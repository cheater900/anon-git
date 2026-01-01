"""Anonymizes git commit metadata.

Python port of anon-git.sh: same flags, messages and exit codes. Function
names mirror the shell implementation so the two can be audited side by side.
The rewrite runs in-process through the git_filter_repo library.
"""

import os
import random
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import termios
import time
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from importlib import resources

import git_filter_repo as fr

VERSION = "0.1.0"

DEFAULT_NAME = "Anon"
DEFAULT_EMAIL = "anon@localhost"
DEFAULT_DATE = "2008-10-31 00:00:00 +0000"

# Value-taking flags end in "=". Single source of truth for --_list-flags.
FLAGS = [
    "-h",
    "--help",
    "-v",
    "--version",
    "--date=",
    "--name=",
    "--email=",
    "--keep-user",
    "--keep-date",
    "--keep-year",
    "--keep-month",
    "--keep-day",
    "--random-time",
    "--random-day",
    "--random-month",
    "--strip-timezone",
    "--no-confirm",
    "--no-backup",
    "--current-branch",
    "--entire-history",
    "--dry-run",
    "--quiet",
    "--verbose",
    "--print-completion=",
    "--install-hook",
    "--uninstall-hook",
]

# Shell-version flags that copy the script around; uv owns installs here.
FLAGS_DROPPED = ["--install", "--install-system", "--uninstall"]

# Boolean options: each has a flag (KEEPUSER <-> --keep-user, see
# flag_option), an ANON_GIT_<OPT> envvar and a default of "0". CONFIG_BOOLS
# also read git config anon-git.<opt>.
CONFIG_BOOLS = [
    "KEEPUSER",
    "KEEPDATE",
    "KEEPYEAR",
    "KEEPMONTH",
    "KEEPDAY",
    "RANDOMTIME",
    "RANDOMDAY",
    "RANDOMMONTH",
    "STRIPTIMEZONE",
    "QUIET",
]
BOOLS = [*CONFIG_BOOLS, "ENTIREHISTORY", "CURRENTBRANCH", "DRYRUN"]

# Options that decide the same thing; the highest-priority source setting any
# member owns the whole group (see drop_overridden_sources).
GROUP_IDENTITY = ["NAME", "EMAIL", "KEEPUSER"]
GROUP_DATE = [
    "DATE",
    "KEEPDATE",
    "KEEPYEAR",
    "KEEPMONTH",
    "KEEPDAY",
    "RANDOMTIME",
    "RANDOMDAY",
    "RANDOMMONTH",
]

# Highest priority first: CLI flag, repo git config, ANON_GIT_* envvar.
SOURCES = ["ARG", "GITCONFIG", "ANON_GIT"]

FLAGS_VALUE = ["--date", "--name", "--email"]
FLAGS_BOOL = [
    "--keep-user",
    "--keep-date",
    "--keep-year",
    "--keep-month",
    "--keep-day",
    "--random-time",
    "--random-day",
    "--random-month",
    "--strip-timezone",
    "--no-confirm",
    "--no-backup",
    "--entire-history",
    "--current-branch",
    "--dry-run",
    "--quiet",
    "--verbose",
]
FLAGS_DATE = [
    "--keep-date",
    "--keep-year",
    "--keep-month",
    "--keep-day",
    "--random-time",
    "--random-day",
    "--random-month",
]

# Marks hooks this tool generated, so install_hook can refresh them without
# clobbering a hook the user wrote. Same marker as the shell version.
HOOK_MARKER = "# Installed by anon-git --install-hook"

COMPLETION_FILES = {
    "bash": "anon-git.bash",
    "zsh": "_anon-git",
    "fish": "anon-git.fish",
}

HELP = """Anonymizes git commit metadata.

Usage:
  anon-git [OPTIONS] [commits]

Options:
  -h, --help                      Show this help message and exit
  -v, --version                   Show version and exit
  --date        ISO Date          Date to use (example: "2025-03-10 13:37:00 +0000")
  --name        "Full name"       Name to use for author & committer
  --email       "Email address"   Email to use for author & committer
  --keep-user                     Do not change user name or author
  --keep-date                     Do not change date
  --keep-year                     Do not change commit year
  --keep-month                    Do not change commit month (and year)
  --keep-day                      Do not change commit day (and year and month)
  --random-time                   Keep commit date year, month and day; replace the time
                                   with a random one, ordered to match the original
                                   relative commit order (never touches the year)
  --random-day                    Keep commit date year and month; replace day and time
                                   with random values, ordered to match the original
                                   relative commit order (never touches the year)
  --random-month                  Keep commit date year; replace month, day and time
                                   with random values, ordered to match the original
                                   relative commit order (never touches the year)
  --strip-timezone                Force the timezone offset to UTC+0000 without changing
                                   the date/time digits. Used with no other option, also
                                   leaves author and date/time untouched (only the offset
                                   changes); combined with other options, those take their
                                   normal effect and the resulting offset is still forced
                                   to +0000
  --no-confirm                    Do not prompt for confirmation
  --no-backup                     Do not create backup branch
  --current-branch                Overwrite current branch instead of creating a copy of it
  --entire-history                Rewrite entire history and not a single commit
  --dry-run                       Show history changes without rewriting it
  --quiet                         Suppress informational output (errors/safety warnings still print)
  --verbose                       Force informational output, overriding --quiet,
                                   ANON_GIT_QUIET, or a repo-local quiet config
  --print-completion [SHELL]      Print a shell completion script (bash, zsh, or fish;
                                   defaults to $SHELL) and exit
  --install-hook                   Install a post-commit hook in the current git repository
                                   that anonymizes each new commit (HEAD only) automatically
  --uninstall-hook                 Remove the post-commit hook installed by --install-hook

Arguments:
  commit(s)               Commit(s) to anonymize (can be: hash, HEAD~3, branch, tag, ...)
                          Required, unless --entire-history is given.
                          If omitted (and --entire-history is not given), this help is shown.
                          If more than one, it should be a commit hash.

Priority (highest to lowest):
  1. Command-line flags (--date, --name, --email, --keep-user, --keep-date, ...)
  2. Repo-local git config (git config anon-git.name, anon-git.email, anon-git.date,
     anon-git.keepuser, anon-git.keepdate, anon-git.keepyear, anon-git.keepmonth,
     anon-git.keepday, anon-git.randomtime, anon-git.randomday, anon-git.randommonth,
     anon-git.striptimezone, anon-git.quiet;
     --entire-history/--current-branch/--dry-run have no config equivalent, flag/envvar only)
  3. Environment variables (ANON_GIT_DATE, ANON_GIT_NAME, ANON_GIT_EMAIL, ANON_GIT_KEEPUSER,
     ANON_GIT_KEEPDATE, ANON_GIT_KEEPYEAR, ANON_GIT_KEEPMONTH, ANON_GIT_KEEPDAY,
     ANON_GIT_RANDOMTIME, ANON_GIT_RANDOMDAY, ANON_GIT_RANDOMMONTH,
     ANON_GIT_STRIPTIMEZONE, ANON_GIT_ENTIREHISTORY, ANON_GIT_CURRENTBRANCH,
     ANON_GIT_DRYRUN, ANON_GIT_QUIET)
  4. Hardcoded defaults ({DEFAULT_NAME} <{DEFAULT_EMAIL}>)

Note: --verbose has no ANON_GIT_VERBOSE environment variable or config
      equivalent; it is a CLI-only override that forces informational
      output back on for one run.

Examples:
    # Anonymize current HEAD with defaults
    anon-git HEAD

    # Anonymize two commits ago
    anon-git HEAD~2

    # Explicit values at specific commit
    anon-git --date "2024-01-01 00:00:00 +0000"
             --name "Jane Doe"
             --email "jane@anon.dev"
             8ddf55a

    # Keep real name/email, only change date
    anon-git --keep-user --date "2025-06-15T14:20:00Z"

    # Keep the commit year, randomize month/day/time; commits keep their
    # relative order (a later commit never lands earlier than an earlier one)
    anon-git --random-month --entire-history

    # Used alone: keep author and date/time as-is, only force the timezone
    # offset to UTC+0000 (hides where the committer is, keeps everything else)
    anon-git --strip-timezone HEAD

    # Preview what would change before actually rewriting anything
    anon-git --dry-run HEAD~2

    # Silence informational output (only errors print)
    anon-git --quiet HEAD

    # Force informational output back on, overriding a quiet default
    anon-git --verbose HEAD

    # Pin this repo's own defaults instead of passing flags/envvars every time
    git config anon-git.name "Anon"
    git config anon-git.email "anon@localhost"
    git config anon-git.quiet true
    anon-git HEAD

    # Anonymize the last 10 commits using shell expansion (works in bash and zsh)
    anon-git HEAD~{{0..9}}

    # Anonymize commits within a specific date range
    anon-git $(git log --format=%H --after='2023-01-01' --before='2024-01-01')

    # Anonymize commits where the commit author matches a pattern
    anon-git $(git log --format=%H --author='Frederic')

    # Anonymize commits following the Conventional Commits "fix:" prefix
    anon-git $(git log --format=%H --grep='^fix:')

    # Install shell completion (shell inferred from $SHELL if omitted)
    anon-git --print-completion bash > ~/.local/share/bash-completion/completions/anon-git
    anon-git --print-completion zsh  > "${{fpath[1]}}/_anon-git"
    anon-git --print-completion fish > ~/.config/fish/completions/anon-git.fish

    # Install a post-commit hook so every new commit in this repo is
    # auto-anonymized (HEAD only, right after `git commit`)
    anon-git --install-hook

    # Remove the post-commit hook installed by --install-hook
    anon-git --uninstall-hook"""


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def show_help():
    print(HELP.format(DEFAULT_NAME=DEFAULT_NAME, DEFAULT_EMAIL=DEFAULT_EMAIL))
    sys.exit(0)


def show_version():
    print(f"anon-git {VERSION}")
    sys.exit(0)


def list_flags():
    print("\n".join(FLAGS))
    sys.exit(0)


def print_completion(shell):
    shell = shell or os.path.basename(os.environ.get("SHELL", ""))
    if shell not in COMPLETION_FILES:
        fail(f'Error: unsupported shell "{shell}" (expected bash, zsh, or fish)')
    completion = resources.files("anon_git") / "completions" / COMPLETION_FILES[shell]
    sys.stdout.write(completion.read_text())
    sys.exit(0)


def dropped_install_flag(flag):
    fail(
        f"Error: {flag} is not supported by the Python implementation.\n"
        "  Install: uv tool install ./anon-git.py\n"
        "  Remove:  uv tool uninstall anon-git"
    )


# Handled before any git-repo/safety checks, so these work even outside a
# git repository or with a dirty working tree.
def handle_early_options(argv):
    if not argv:
        show_help()
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("--date", "--name", "--email"):
            # Skip the value, so `--name --help` uses "--help" as the name.
            i += 1
        elif arg in ("-h", "--help"):
            show_help()
        elif arg in ("-v", "--version"):
            show_version()
        elif arg == "--_list-flags":
            list_flags()
        elif arg == "--print-completion":
            print_completion(argv[i + 1] if i + 1 < len(argv) else "")
        elif arg == "--install-hook":
            install_hook()
        elif arg == "--uninstall-hook":
            uninstall_hook()
        elif arg in FLAGS_DROPPED:
            dropped_install_flag(arg)
        i += 1


@dataclass(frozen=True)
class Options:
    name: str
    email: str
    date: str
    commits: list
    keepuser: bool
    keepdate: bool
    keepyear: bool
    keepmonth: bool
    keepday: bool
    randomtime: bool
    randomday: bool
    randommonth: bool
    striptimezone: bool
    entirehistory: bool
    currentbranch: bool
    dryrun: bool
    quiet: bool
    # CLI-only, never read from config/envvars.
    noconfirm: bool
    nobackup: bool
    # Flags given on the CLI, for messages gated on explicit flags.
    args: dict


# ──────────────────────────────────────────────────────────────────────
# GIT


def git(*args):
    """Runs git with list args (never a shell) and returns stripped stdout."""
    result = subprocess.run(["git", *args], capture_output=True, text=True, check=True)
    return result.stdout.rstrip("\n")


def git_ok(*args):
    return subprocess.run(["git", *args], capture_output=True).returncode == 0


# ──────────────────────────────────────────────────────────────────────
# HOOKS


# The post-commit hook path git actually runs. `--git-path hooks` honors
# core.hooksPath and resolves to the common dir in a linked worktree; a
# relative result is relative to the top-level dir.
def hook_file_path():
    top = git("rev-parse", "--show-toplevel")
    hooks_dir = git("-C", top, "rev-parse", "--git-path", "hooks")
    return os.path.join(top, hooks_dir, "post-commit")


# A symlink is never ours: writing through it would overwrite its target
# (e.g. a copy of anon-git.sh, which contains the marker text).
def hook_is_ours(hook_file):
    if os.path.islink(hook_file) or not os.path.isfile(hook_file):
        return False
    with open(hook_file, encoding="utf-8", errors="replace") as fh:
        return HOOK_MARKER in fh.read()


HOOK_BODY = """
# The install this hook calls is gone (e.g. `uv tool uninstall anon-git`):
# say so instead of failing every commit with a bare "No such file".
if [[ ! -x "${anon_git[0]}" ]]; then
    printf 'anon-git: %s missing, not anonymized; re-run --install-hook.\\n' "${anon_git[0]}" >&2
    exit 0
fi

# Rewriting HEAD mid-sequence would derail the rebase/cherry-pick/revert.
for state in rebase-merge rebase-apply sequencer CHERRY_PICK_HEAD REVERT_HEAD; do
    if [[ -e "$(git rev-parse --git-path "$state")" ]]; then
        printf 'anon-git: %s in progress, commit not anonymized.\\n' "$state" >&2
        exit 0
    fi
done

# A partial commit (git add -p, git commit <path>) leaves a dirty tree,
# which anon-git refuses; stash it around the run.
stashed=0
if ! git diff-index --quiet HEAD -- || ! git diff-files --quiet; then
    git stash push --quiet
    stashed=1
fi
status=0
"${anon_git[@]}" --no-confirm --no-backup --quiet --current-branch HEAD || status=$?
if [[ "$stashed" -eq 1 ]]; then
    git stash pop --quiet --index
fi
exit "$status"
"""


# --install-hook: re-anonymizes HEAD in place after every commit, with
# --no-backup (would accumulate one branch per commit) and --quiet. Calls
# this exact interpreter, never whatever `anon-git` is first on $PATH.
def install_hook():
    if not git_ok("rev-parse", "--show-toplevel"):
        fail("Error: --install-hook must be run inside a git repository.")
    hook_file = hook_file_path()
    if os.path.lexists(hook_file) and not hook_is_ours(hook_file):
        fail(
            f"Error: {hook_file} already exists and was not installed by anon-git.\n"
            "  Remove or back it up first, then re-run --install-hook."
        )
    os.makedirs(os.path.dirname(hook_file), exist_ok=True)
    with open(hook_file, "w", encoding="utf-8") as fh:
        fh.write(
            "#!/usr/bin/env bash\n"
            f"{HOOK_MARKER}\n"
            "#\n"
            "# Anonymizes the just-created commit (HEAD) after every `git commit`.\n"
            "# --no-backup avoids accumulating a branch per commit (use `git reflog`/\n"
            "# `git reset` to recover). --quiet drops the per-commit output; pass\n"
            "# --verbose to bring it back. Regenerate with: anon-git --install-hook\n"
            "\n"
            "set -e\n"
            f"anon_git=({shlex.quote(sys.executable)} -m anon_git)\n"
            f"{HOOK_BODY}"
        )
    os.chmod(hook_file, 0o755)
    print(f"Installed post-commit hook: {hook_file}")
    sys.exit(0)


# --uninstall-hook: guarded by the same HOOK_MARKER check install_hook uses,
# so a hook this tool didn't create is never touched.
def uninstall_hook():
    if not git_ok("rev-parse", "--show-toplevel"):
        fail("Error: --uninstall-hook must be run inside a git repository.")
    hook_file = hook_file_path()
    if not os.path.lexists(hook_file):
        print(f"No post-commit hook installed at {hook_file}")
        sys.exit(0)
    if not hook_is_ours(hook_file):
        fail(
            f"Error: {hook_file} was not installed by anon-git; refusing to remove it.\n"
            "  Remove it yourself if you are sure."
        )
    os.remove(hook_file)
    print(f"Removed post-commit hook: {hook_file}")
    sys.exit(0)


# ──────────────────────────────────────────────────────────────────────
# OPTIONS


# Dies unless inside a git repo with a clean working tree. Everything after
# this can assume a usable repo.
def safety_checks():
    if not git_ok("rev-parse", "--git-dir"):
        fail("AnonGit must be run inside a git repository.")
    # Bare repo or inside .git: the dirty-tree check below would misreport.
    if git("rev-parse", "--is-inside-work-tree") != "true":
        fail(
            "Error: AnonGit must be run inside a work tree "
            "(not a bare repository or .git directory)."
        )
    if not git_ok("rev-parse", "--quiet", "--verify", "HEAD"):
        fail("Error: repository has no commits yet; nothing to anonymize.")
    if not git_ok("diff-index", "--quiet", "HEAD", "--") or not git_ok("diff-files", "--quiet"):
        fail(
            "Repository has uncommitted changes. "
            "Commit or stash first to prevent losing the changes."
        )


# Reads git config anon-git.<key> as "1"/"0", or "" if unset. Parsed by git
# itself (--type=bool), so "True", "YES" or a valueless key mean what git
# says. An unparseable value is a hard error: a typo must not fail open.
def read_git_config_bool(key):
    result = subprocess.run(
        ["git", "config", "--type=bool", "--get", key], capture_output=True, text=True
    )
    if result.returncode == 1:
        return ""
    if result.returncode != 0:
        raw = subprocess.run(["git", "config", "--get", key], capture_output=True, text=True)
        fail(
            f'Error: git config {key} has an invalid boolean value "{raw.stdout.strip()}" '
            "(expected true/false)"
        )
    return "1" if result.stdout.strip() == "true" else "0"


# Excludes ENTIREHISTORY/CURRENTBRANCH/DRYRUN: a silent default for those
# would be too destructive.
def read_git_config():
    config = {}
    for opt in ("NAME", "EMAIL", "DATE"):
        result = subprocess.run(
            ["git", "config", "--get", f"anon-git.{opt.lower()}"], capture_output=True, text=True
        )
        config[opt] = result.stdout.rstrip("\n") if result.returncode == 0 else ""
    for opt in CONFIG_BOOLS:
        config[opt] = read_git_config_bool(f"anon-git.{opt.lower()}")
    return config


def read_env(environ):
    return {opt: environ.get(f"ANON_GIT_{opt}", "") for opt in ("NAME", "EMAIL", "DATE", *BOOLS)}


# --keep-user -> KEEPUSER.
def flag_option(flag):
    return flag.lstrip("-").replace("-", "").upper()


# Resolves revisions to commit hashes in one git process, so passing
# `$(git log --format=%H)` doesn't spawn one per commit. ^{commit} peels
# annotated tags, whose own hash never matches a commit.
def resolve_commits(revs):
    # A newline would split one revision into two batch lines.
    for rev in revs:
        if "\n" in rev:
            fail(f'Error: Commit "{rev}" does not exist or is not a commit object.')
    batch = subprocess.run(
        ["git", "cat-file", "--batch-check=%(objectname) %(objecttype)"],
        input="".join(f"{rev}^{{commit}}\n" for rev in revs),
        capture_output=True,
        text=True,
        check=True,
    )
    commits = []
    for rev, line in zip(revs, batch.stdout.splitlines(), strict=True):
        commit, kind = line.rsplit(" ", 1)
        if kind != "commit":
            fail(f'Error: Commit "{rev}" does not exist or is not a commit object.')
        commits.append(commit)
    return commits


# Parses argv into ({option: value} for given flags, [resolved commit hashes]).
def parse_args(argv):
    args = {}
    revs = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in FLAGS_VALUE:
            # Empty would silently fall back to the default identity/date.
            if i + 1 >= len(argv) or not argv[i + 1]:
                fail(f"Error: {arg} requires a value")
            args[flag_option(arg)] = argv[i + 1]
            i += 2
            continue
        if arg in FLAGS_BOOL:
            args[flag_option(arg)] = "1"
        elif arg.startswith("-"):
            fail(f"Unknown option: {arg}")
        else:
            revs.append(arg)
        i += 1
    return args, resolve_commits(revs) if revs else []


def is_on(value):
    return value not in ("", "0")


# The highest-priority source setting any member of a group owns the whole
# group: lower sources' members are cleared, so e.g. ANON_GIT_DATE doesn't
# conflict with --keep-date. Bool "0" doesn't count.
def drop_overridden_sources(sources):
    for group in (GROUP_IDENTITY, GROUP_DATE):
        owner = next(
            (s for s in SOURCES if any(is_on(sources[s].get(opt, "")) for opt in group)), None
        )
        if owner is None:
            continue
        for source in SOURCES:
            if source == owner:
                continue
            for opt in group:
                sources[source][opt] = ""
    return sources


def first_set(sources, opt):
    return next((sources[s][opt] for s in SOURCES if sources[s].get(opt)), "")


def bool_set(sources, opt):
    return (
        bool(sources["ARG"].get(opt))
        or sources["GITCONFIG"].get(opt) == "1"
        or sources["ANON_GIT"].get(opt) == "1"
    )


# Mutually-exclusive options, wherever each side came from. Returns error
# messages instead of exiting, so every conflict is reported at once.
def reject_incompatible_options(sources, commits):
    errors = []
    args = sources["ARG"]
    keepuser = bool_set(sources, "KEEPUSER")
    for flag in ("--name", "--email"):
        if keepuser and first_set(sources, flag_option(flag)):
            errors.append(f"Error: --keep-user and {flag} cannot be used together")
    # --date, --keep-* and --random-* each decide the whole date: one at most.
    date_flags = ["--date"] if first_set(sources, "DATE") else []
    date_flags += [flag for flag in FLAGS_DATE if bool_set(sources, flag_option(flag))]
    if len(date_flags) > 1:
        errors.append(f"Error: {' and '.join(date_flags)} cannot be used together")
    if commits and bool_set(sources, "ENTIREHISTORY"):
        errors.append("Error: commit(s) argument and --entire-history cannot be used together")
    # Only the two flags conflict: --verbose over ANON_GIT_QUIET=1 or
    # anon-git.quiet is the intended way to un-silence a quiet default.
    if args.get("QUIET") and args.get("VERBOSE"):
        errors.append("Error: --quiet and --verbose cannot be used together")
    return errors


# Flags > repo-local git config > ANON_GIT_* envvars > defaults.
def merge_args_with_defaults(sources):
    defaults = {"NAME": DEFAULT_NAME, "EMAIL": DEFAULT_EMAIL, "DATE": DEFAULT_DATE}
    defaults.update({opt: "0" for opt in BOOLS})
    resolved = {opt: first_set(sources, opt) or default for opt, default in defaults.items()}
    # --verbose always wins over whatever set QUIET above.
    if sources["ARG"].get("VERBOSE") == "1":
        resolved["QUIET"] = "0"
    return resolved


# --strip-timezone alone implicitly behaves like --keep-user --keep-date
# (the callback still rewrites the offset). Any other identity/date CLI flag
# opts back into normal precedence; config/envvars don't count.
def apply_strip_timezone_alone(args, resolved):
    if args.get("STRIPTIMEZONE") != "1":
        return resolved
    if any(args.get(opt) for opt in GROUP_IDENTITY + GROUP_DATE):
        return resolved
    return {**resolved, "KEEPUSER": "1", "KEEPDATE": "1"}


# A stray envvar could produce a bogus value; check before anything acts on it.
def validate_final_options(resolved):
    for opt in BOOLS:
        if resolved[opt] not in ("0", "1"):
            fail(f'Error: ANON_GIT_{opt} must resolve to "0" or "1" (got "{resolved[opt]}")')


def build_options(argv, environ):
    args, commits = parse_args(argv)
    sources = drop_overridden_sources(
        {"ARG": dict(args), "GITCONFIG": read_git_config(), "ANON_GIT": read_env(environ)}
    )
    errors = reject_incompatible_options(sources, commits)
    if errors:
        fail("\n".join(errors))
    resolved = apply_strip_timezone_alone(args, merge_args_with_defaults(sources))
    validate_final_options(resolved)
    return Options(
        name=resolved["NAME"],
        email=resolved["EMAIL"],
        date=resolved["DATE"],
        commits=commits,
        noconfirm=args.get("NOCONFIRM") == "1",
        nobackup=args.get("NOBACKUP") == "1",
        args=args,
        **{opt.lower(): resolved[opt] == "1" for opt in BOOLS},
    )


# ──────────────────────────────────────────────────────────────────────
# VALIDATION


def parse_target_date(date_str):
    # Also accepts ISO 8601 compact form (e.g. '2025-06-15T14:20:00Z'),
    # normalized to the space-separated, 4-digit-offset form '%z' expects.
    normalized = date_str.strip()
    if "T" in normalized:
        normalized = normalized.replace("T", " ", 1)
        if normalized.endswith("Z"):
            normalized = normalized[:-1] + "+0000"
        match = re.match(r"^(.*\d{2}:\d{2}:\d{2})([+-]\d{2}:?\d{2})$", normalized)
        if match:
            normalized = f"{match.group(1)} {match.group(2).replace(':', '')}"
    return datetime.strptime(normalized, "%Y-%m-%d %H:%M:%S %z")


# Without a commit target or --entire-history, show help instead of silently
# defaulting to HEAD.
def require_target(opts):
    if not opts.commits and not opts.entirehistory:
        show_help()


# Pre-1970 is rejected: git writes the negative timestamp, but fsck (and so
# most hosts on push) rejects the commit as badDate.
def validate_date(opts):
    try:
        valid = parse_target_date(opts.date).timestamp() >= 0
    except ValueError:
        valid = False
    if not valid:
        fail(
            f'Error: invalid date "{opts.date}" '
            '(expected e.g. "2025-03-10 13:37:00 +0000", not before 1970)'
        )


# fast-import aborts mid-rewrite on an ident with <, > or a newline, after
# the new/backup branch already exists; reject it before anything runs.
def validate_identity(opts):
    if opts.keepuser:
        return
    for field, value in (("name", opts.name), ("email", opts.email)):
        if any(char in value for char in "<>\n"):
            fail(f'Error: {field} must not contain "<", ">" or a newline (got "{value}")')


# Only HEAD's history is rewritten (--refs HEAD), so any other target would
# silently stay untouched.
def require_reachable(opts):
    if not opts.commits:
        return
    reachable = set(git("rev-list", "HEAD").splitlines())
    for commit in opts.commits:
        if commit not in reachable:
            fail(
                f"Error: commit {git('rev-parse', '--short', commit)} is not reachable "
                "from HEAD; check out a branch containing it first."
            )


# ──────────────────────────────────────────────────────────────────────
# RUN


# Gated on flags explicitly passed on the CLI (not the resolved value), so
# e.g. ANON_GIT_KEEPUSER in a shell profile doesn't spam this on every run.
def verbose_info(opts):
    if opts.quiet:
        return
    if opts.entirehistory:
        print("Anonymizing entire history!")
    else:
        # One rev-parse for the repo's abbrev length, not one per commit.
        length = len(git("rev-parse", "--short", opts.commits[0]))
        shorts = [commit[:length] for commit in opts.commits]
        print(f"Anonymizing commit(s): {' '.join(shorts)} ")
    messages = {
        "KEEPUSER": "Not overwriting user/email.",
        "KEEPDATE": "Not overwriting date.",
        "KEEPYEAR": "Using commit date year (anonymizing only month, day, time and tz).",
        "KEEPMONTH": "Using commit date year and month (anonymizing only day, time and tz).",
        "KEEPDAY": "Using commit date year, month and day (anonymizing only time and tz).",
        "RANDOMTIME": "Randomizing time only (keeping commit date year, month and day), "
        "preserving relative commit order.",
        "RANDOMDAY": "Randomizing day and time (keeping commit date year and month), "
        "preserving relative commit order.",
        "RANDOMMONTH": "Randomizing month, day and time (keeping commit date year), "
        "preserving relative commit order.",
        "STRIPTIMEZONE": "Forcing timezone offset to UTC+0000 (date/time digits unchanged).",
    }
    for opt, message in messages.items():
        if opts.args.get(opt):
            print(message)
    print()


# Reads one key from the terminal, not stdin: under xargs stdin is /dev/null.
# Skipped for --no-confirm or --dry-run (nothing is touched either way).
def confirm(opts):
    if opts.noconfirm or opts.dryrun:
        return
    try:
        tty = open("/dev/tty", "r+b", buffering=0)  # noqa: SIM115 -- closed by the `with` below
    except OSError:
        fail("Error: no terminal to ask for confirmation; pass --no-confirm.")
    with tty:
        tty.write(b"Continue? (y/N) ")
        saved = termios.tcgetattr(tty)
        raw = list(saved)
        raw[3] &= ~termios.ICANON
        termios.tcsetattr(tty, termios.TCSANOW, raw)
        try:
            reply = tty.read(1)
        finally:
            termios.tcsetattr(tty, termios.TCSANOW, saved)
    print()
    if reply not in (b"y", b"Y"):
        fail("Aborted.")


# Creates a new branch (default) or a backup branch (--current-branch, unless
# --no-backup) so pre-rewrite history stays reachable. No-op under --dry-run.
def backup_branch(opts):
    current_branch = git("branch", "--show-current")
    if not current_branch and opts.currentbranch:
        fail(
            "Error: HEAD is detached, so there is no current branch to overwrite. "
            "Drop --current-branch or check out a branch first."
        )
    if opts.dryrun:
        return
    branch_label = current_branch or f"detached-{git('rev-parse', '--short', 'HEAD')}"
    # Colon-free (git ref names disallow ":"); PID + random suffix for
    # uniqueness within the same second.
    timestamp = f"{time.strftime('%Y%m%d_%H%M%S')}_{os.getpid()}_{random.randrange(32768)}"
    if not opts.currentbranch:
        new_branch = f"{branch_label}_anonymized_{timestamp}"
        # --quiet also silences git's own "Switched to a new branch" line.
        stderr = subprocess.DEVNULL if opts.quiet else None
        if subprocess.run(["git", "switch", "--create", new_branch], stderr=stderr).returncode:
            fail(f"Error: failed to create branch {new_branch}")
        if not opts.quiet:
            print(f"Created new branch {new_branch} from {branch_label}")
            print(f"Using branch {new_branch} to rewrite commits.")
        return
    if opts.nobackup:
        # Not gated by --quiet: a data-loss warning, not routine output.
        print(
            f"WARNING! Overwriting existing branch {branch_label} without backup!", file=sys.stderr
        )
        return
    backup_branch_name = f"{branch_label}_backup_{timestamp}"
    if subprocess.run(["git", "branch", backup_branch_name]).returncode:
        fail(f"Error: failed to create backup branch {backup_branch_name}")
    if not opts.quiet:
        print(f"Created backup branch {backup_branch_name} from {branch_label}")
        print(f"Using branch {branch_label} to rewrite commits")


# git-filter-repo caches metadata in .git/filter-repo/; reusing it after
# certain repo state changes hits a known assertion bug in the tool.
def clean_cache():
    cache = os.path.join(git("rev-parse", "--git-dir"), "filter-repo")
    if os.path.isdir(cache):
        shutil.rmtree(cache)


# ──────────────────────────────────────────────────────────────────────
# RANDOM DATES


# dt: UTC-labeled date. Returns (bucket key, start epoch, end epoch) of the
# calendar unit --random-* keeps.
def bucket_bounds(dt, granularity):
    if granularity == "month":
        start = datetime(dt.year, 1, 1, tzinfo=timezone.utc)
        end = datetime(dt.year, 12, 31, 23, 59, 59, tzinfo=timezone.utc)
        return (dt.year,), int(start.timestamp()), int(end.timestamp())
    if granularity == "day-of-month":
        start = datetime(dt.year, dt.month, 1, tzinfo=timezone.utc)
        if dt.month == 12:
            next_month_start = datetime(dt.year + 1, 1, 1, tzinfo=timezone.utc)
        else:
            next_month_start = datetime(dt.year, dt.month + 1, 1, tzinfo=timezone.utc)
        end = next_month_start - timedelta(seconds=1)
        return (dt.year, dt.month), int(start.timestamp()), int(end.timestamp())
    start = datetime(dt.year, dt.month, dt.day, tzinfo=timezone.utc)
    end = start + timedelta(hours=23, minutes=59, seconds=59)
    return (dt.year, dt.month, dt.day), int(start.timestamp()), int(end.timestamp())


# Wall-clock date/time in the commit's own offset, labeled UTC: the output is
# +0000, so bucket bounds must be these digits read as UTC.
def local_datetime(epoch, offset):
    sign = -1 if offset.startswith("-") else 1
    seconds = sign * (int(offset[1:3]) * 3600 + int(offset[3:5]) * 60)
    return datetime.fromtimestamp(epoch + seconds, tz=timezone.utc)


# One random epoch per target. history: [(hash, epoch, offset, parents)],
# oldest first, parents before children. Tags each commit target/anchor (a
# parent or child of a target)/skip, buckets by the commit's local calendar
# unit (what `git log` shows, as --keep-* uses), and gives each bucket's runs
# of targets sorted random epochs bounded by their nearest anchor.
def compute_random_dates(history, targets, granularity, entire, rng=None):
    rng = rng or random.SystemRandom()
    # Real neighbors are parents and children: across a merge, the commit
    # next in log order can sit on another branch.
    anchors = set()
    for commit_hash, _epoch, _offset, parents in history:
        if commit_hash in targets:
            anchors.update(parents)
        elif any(parent in targets for parent in parents):
            anchors.add(commit_hash)
    buckets = defaultdict(list)
    bounds = {}
    # History index breaks epoch ties, so a parent sorts before its
    # same-second child.
    for index, (commit_hash, epoch, offset, _parents) in enumerate(history):
        if entire or commit_hash in targets:
            role = "target"
        elif commit_hash in anchors:
            role = "anchor"
        else:
            continue
        keys = {bucket_bounds(local_datetime(epoch, offset), granularity)}
        if role == "anchor":
            # Also bound targets whose bucket holds this anchor's real instant.
            keys.add(bucket_bounds(datetime.fromtimestamp(epoch, tz=timezone.utc), granularity))
        for key, start, end in keys:
            buckets[key].append((epoch, index, commit_hash, role))
            bounds[key] = (start, end)
    picked = {}
    for key, members in buckets.items():
        bucket_start, bucket_end = bounds[key]
        members.sort()
        i = 0
        lower = bucket_start
        while i < len(members):
            epoch, _index, _hash, role = members[i]
            if role == "anchor":
                lower = max(epoch + 1, bucket_start)
                i += 1
                continue
            run_start = i
            while i < len(members) and members[i][3] == "target":
                i += 1
            run = members[run_start:i]
            upper = min(members[i][0] - 1, bucket_end) if i < len(members) else bucket_end
            if upper < lower:
                # No room between anchors, or an anchor outside the bucket.
                # Share the nearest in-bucket timestamp: git allows identical
                # dates, the calendar unit must not change.
                picks = [min(max(lower - 1, bucket_start), bucket_end)] * len(run)
            elif len(run) <= upper - lower + 1:
                picks = sorted(rng.sample(range(lower, upper + 1), len(run)))
            else:
                picks = sorted(rng.randint(lower, upper) for _ in run)
            for (_epoch, _index, member_hash, _role), new_epoch in zip(run, picks, strict=True):
                picked[member_hash] = new_epoch
    return picked


def read_history():
    log = git(
        "log", "--reverse", "--topo-order", "--date=format:%z", "--format=%H %at %ad %P", "HEAD"
    )
    history = []
    for line in log.splitlines():
        fields = line.split()
        history.append((fields[0], int(fields[1]), fields[2], fields[3:]))
    return history


def random_granularity(opts):
    if opts.randommonth:
        return "month"
    if opts.randomday:
        return "day-of-month"
    if opts.randomtime:
        return "time-of-day"
    return None


# ──────────────────────────────────────────────────────────────────────
# REWRITE


def parse_git_date(date_bytes):
    unix_ts, offset = date_bytes.decode().split()
    sign = 1 if offset.startswith("+") else -1
    offset = offset.lstrip("+-")
    if len(offset) not in (4, 6):
        raise ValueError("unsupported timezone format")
    tz_offset = timedelta(
        hours=int(offset[:2]), minutes=int(offset[2:4]), seconds=int(offset[4:] or 0)
    )
    return datetime.fromtimestamp(float(unix_ts), tz=timezone(sign * tz_offset))


# Same digits, relabeled (not converted) as UTC.
def as_utc_epoch(dt):
    return int(dt.replace(tzinfo=timezone.utc).timestamp())


def target_date_bytes(opts, commit, random_dates):
    if random_dates is not None:
        epoch = random_dates.get(commit.original_id.decode())
        if epoch is None:
            raise SystemExit(
                f"anon-git: no precomputed random date for commit {commit.original_id.decode()}"
            )
        return b"%d +0000" % epoch
    if opts.keepyear or opts.keepmonth or opts.keepday:
        # Keep the calendar date as seen, re-anchored to midnight UTC, so
        # only time/tz leak.
        dt = parse_git_date(commit.author_date).replace(hour=0, minute=0, second=0, microsecond=0)
        if opts.keepyear or opts.keepmonth:
            dt = dt.replace(day=1)
        if opts.keepyear:
            dt = dt.replace(month=1)
        return b"%d +0000" % as_utc_epoch(dt)
    dt = parse_target_date(opts.date)
    if opts.striptimezone:
        return b"%d +0000" % as_utc_epoch(dt)
    offset_seconds = int(dt.utcoffset().total_seconds())
    sign = "+" if offset_seconds >= 0 else "-"
    hours, minutes = divmod(abs(offset_seconds) // 60, 60)
    return b"%d %s%02d%02d" % (int(dt.timestamp()), sign.encode(), hours, minutes)


def preview_entry(commit, new):
    def text(raw):
        # Metadata is raw bytes with no guaranteed encoding.
        return raw.decode(errors="replace")

    def iso(raw):
        return parse_git_date(raw).isoformat()

    return (
        f"Commit:{commit.original_id.decode()}\n"
        f"Author:\t\t{text(commit.author_name)} <{text(commit.author_email)}> -> "
        f"{text(new['author_name'])} <{text(new['author_email'])}> \n"
        f"Committer:\t{text(commit.committer_name)} <{text(commit.committer_email)}> -> "
        f"{text(new['committer_name'])} <{text(new['committer_email'])}> \n"
        f"AuthorDate:\t{iso(commit.author_date)} -> {iso(new['author_date'])}\n"
        f"CommitterDate:\t{iso(commit.committer_date)} -> {iso(new['committer_date'])}\n"
        "\n"
        f"{text(commit.message)}"
        f"\n{'-' * 80}\n"
    )


# Returns the filter-repo commit callback. Under --dry-run it appends a
# preview entry to `preview` instead of changing the commit.
def make_commit_callback(opts, random_dates, preview):
    targets = {commit.encode() for commit in opts.commits}

    def callback(commit, _metadata):
        if not opts.entirehistory and commit.original_id not in targets:
            return
        new = {
            "author_name": commit.author_name,
            "author_email": commit.author_email,
            "author_date": commit.author_date,
            "committer_name": commit.committer_name,
            "committer_email": commit.committer_email,
            "committer_date": commit.committer_date,
        }
        if not opts.keepuser:
            for field in ("author_name", "committer_name"):
                new[field] = opts.name.encode()
            for field in ("author_email", "committer_email"):
                new[field] = opts.email.encode()
        if not opts.keepdate:
            new["author_date"] = new["committer_date"] = target_date_bytes(
                opts, commit, random_dates
            )
        elif opts.striptimezone:
            # Digits untouched, each offset relabeled to +0000 independently
            # (author and committer can differ, e.g. after a rebase).
            for field in ("author_date", "committer_date"):
                new[field] = b"%d +0000" % as_utc_epoch(parse_git_date(getattr(commit, field)))
        if opts.dryrun:
            preview.append(preview_entry(commit, new))
            return
        for field, value in new.items():
            setattr(commit, field, value)

    return callback


# Runs filter-repo in-process. Its output, and that of the fast-export/
# fast-import children it spawns, goes to an unnamed temp file (fds 1/2
# redirected), shown only on failure. --dry-run is forwarded: without it
# filter-repo still rewrites history even when the callback changes nothing
# (e.g. signed commits lose their signature).
def run_filter_repo(opts, callback):
    filter_args = fr.FilteringOptions.parse_args(
        ["--force", "--refs", "HEAD", *(["--dry-run"] if opts.dryrun else [])]
    )
    with tempfile.TemporaryFile() as log:
        sys.stdout.flush()
        sys.stderr.flush()
        saved = os.dup(1), os.dup(2)
        os.dup2(log.fileno(), 1)
        os.dup2(log.fileno(), 2)
        error = None
        try:
            fr.RepoFilter(filter_args, commit_callback=callback).run()
        except SystemExit as exc:
            error = exc
        finally:
            sys.stdout.flush()
            sys.stderr.flush()
            os.dup2(saved[0], 1)
            os.dup2(saved[1], 2)
            os.close(saved[0])
            os.close(saved[1])
        if error is None or error.code in (None, 0):
            return
        log.seek(0)
        print("Error: git filter-repo failed:", file=sys.stderr)
        sys.stderr.write(log.read().decode(errors="replace"))
        # filter-repo exits with either a message or a bare status code.
        if isinstance(error.code, str):
            print(error.code, file=sys.stderr)
        sys.exit(1)


def print_result(opts, preview):
    if not opts.dryrun:
        if not opts.quiet:
            print("Done. History has been rewritten.")
        return
    # Through sh, like git, so PAGER may carry arguments ("less -R").
    sys.stdout.flush()
    subprocess.run(
        ["sh", "-c", os.environ.get("PAGER") or "cat"], input="".join(preview), text=True
    )


# ──────────────────────────────────────────────────────────────────────
# MAIN


def run(argv):
    handle_early_options(argv)
    safety_checks()
    opts = build_options(argv, os.environ)
    require_target(opts)
    validate_date(opts)
    validate_identity(opts)
    require_reachable(opts)
    verbose_info(opts)
    confirm(opts)
    backup_branch(opts)
    clean_cache()
    granularity = None if opts.keepdate else random_granularity(opts)
    random_dates = None
    if granularity:
        random_dates = compute_random_dates(
            read_history(), set(opts.commits), granularity, opts.entirehistory
        )
    preview = []
    run_filter_repo(opts, make_commit_callback(opts, random_dates, preview))
    print_result(opts, preview)


def main(argv=None):
    # Keeps stdout and stderr lines in order when both go to one pipe.
    sys.stdout.reconfigure(line_buffering=True)
    try:
        run(sys.argv[1:] if argv is None else argv)
    except subprocess.CalledProcessError as exc:
        fail(f"Error: {shlex.join(exc.cmd)} failed: {(exc.stderr or '').strip()}")
    except KeyboardInterrupt:
        # Ctrl-C mid-run: a backup/new branch may already exist; say so
        # instead of dumping a traceback.
        fail("\nInterrupted. Check `git branch` and `git reflog` before re-running.")
