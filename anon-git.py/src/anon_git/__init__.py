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
import tty
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from importlib import resources
from typing import NamedTuple

import git_filter_repo as fr

VERSION = "0.1.0"

DEFAULT_NAME = "Anon"
DEFAULT_EMAIL = "anon@localhost"
DEFAULT_DATE = "2008-10-31 00:00:00 +0000"

# Options taking a value; each has a --flag, git config and ANON_GIT_* envvar.
VALUE_OPTIONS = ["NAME", "EMAIL", "DATE"]

# Boolean options: each has a flag (KEEPUSER <-> --keep-user, see
# flag_option), an ANON_GIT_<OPT> envvar and a default of "0". CONFIG_BOOLS
# also read git config anon-git.<opt>; the rest would be too destructive as
# a silent repo default.
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
# Order matches anon-git.sh's --_list-flags.
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
    "--current-branch",
    "--entire-history",
    "--dry-run",
    "--quiet",
    "--verbose",
]
FLAGS_HOOK = ["--install-hook", "--uninstall-hook"]
# Value-taking flags end in "=". Single source of truth for --_list-flags.
FLAGS = [
    "-h",
    "--help",
    "-v",
    "--version",
    *(f"{flag}=" for flag in FLAGS_VALUE),
    *FLAGS_BOOL,
    "--print-completion=",
    *FLAGS_HOOK,
]
# Shell-version flags that copy the script around; uv owns installs here.
FLAGS_DROPPED = ["--install", "--install-system", "--uninstall"]

# fast-import can't store these in an ident.
IDENT_FORBIDDEN_CHARS = "<>\n"

# Calendar unit each --random-* flag keeps; the rest is randomized.
KEPT_YEAR = "year"
KEPT_MONTH = "month"
KEPT_DAY = "day"

# New/backup branch names: "<branch><suffix><timestamp>".
BRANCH_SUFFIX_ANONYMIZED = "_anonymized_"
BRANCH_SUFFIX_BACKUP = "_backup_"
# Same range as bash's $RANDOM, which anon-git.sh uses for the same suffix.
BRANCH_RANDOM_RANGE = 32768

PREVIEW_SEPARATOR = "-" * 80

# Marks hooks this tool generated, so install_hook can refresh them without
# clobbering a hook the user wrote. Same marker as the shell version.
HOOK_MARKER = "# Installed by anon-git --install-hook"

COMPLETION_FILES = {
    "bash": "anon-git.bash",
    "zsh": "_anon-git",
    "fish": "anon-git.fish",
}

ERROR_NOT_A_COMMIT = 'Error: Commit "{rev}" does not exist or is not a commit object.'

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


class HistoryCommit(NamedTuple):
    hash: str
    epoch: int
    offset: str
    parents: list


# One commit placed in a calendar-unit bucket; sorts by (epoch, index).
class BucketMember(NamedTuple):
    epoch: int
    index: int
    hash: str
    is_target: bool


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
    cli_flags: dict


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
        if arg in FLAGS_VALUE:
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


# --install-hook: re-anonymizes HEAD in place after every commit, with
# --no-backup (would accumulate one branch per commit) and --quiet. Calls
# this exact interpreter, never whatever `anon-git` is first on $PATH.
def require_work_tree_for(flag):
    if not git_ok("rev-parse", "--show-toplevel"):
        fail(f"Error: {flag} must be run inside a git repository.")


def install_hook():
    require_work_tree_for("--install-hook")
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
    require_work_tree_for("--uninstall-hook")
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


# Returns (git exit status, value). Status 1 means the key is unset.
def git_config_get(key, *flags):
    result = subprocess.run(["git", "config", *flags, "--get", key], capture_output=True, text=True)
    return result.returncode, result.stdout.rstrip("\n")


def config_key(opt):
    return f"anon-git.{opt.lower()}"


# Reads git config anon-git.<key> as "1"/"0", or "" if unset. Parsed by git
# itself (--type=bool), so "True", "YES" or a valueless key mean what git
# says. An unparseable value is a hard error: a typo must not fail open.
def read_git_config_bool(key):
    status, value = git_config_get(key, "--type=bool")
    if status == 1:
        return ""
    if status != 0:
        fail(
            f'Error: git config {key} has an invalid boolean value "{git_config_get(key)[1]}" '
            "(expected true/false)"
        )
    return "1" if value == "true" else "0"


def read_git_config():
    config = {}
    for opt in VALUE_OPTIONS:
        status, value = git_config_get(config_key(opt))
        config[opt] = value if status == 0 else ""
    for opt in CONFIG_BOOLS:
        config[opt] = read_git_config_bool(config_key(opt))
    return config


def read_env(environ):
    return {opt: environ.get(f"ANON_GIT_{opt}", "") for opt in (*VALUE_OPTIONS, *BOOLS)}


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
            fail(ERROR_NOT_A_COMMIT.format(rev=rev))
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
            fail(ERROR_NOT_A_COMMIT.format(rev=rev))
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
    date_flags += [
        flag
        for flag in FLAGS_BOOL
        if flag_option(flag) in GROUP_DATE and bool_set(sources, flag_option(flag))
    ]
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
    defaults.update(dict.fromkeys(BOOLS, "0"))
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
        cli_flags=args,
        **{opt.lower(): resolved[opt] == "1" for opt in BOOLS},
    )


# ──────────────────────────────────────────────────────────────────────
# DATES


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


# Wall-clock date/time in the commit's own offset, labeled UTC: the output is
# +0000, so bucket bounds must be these digits read as UTC.
def local_datetime(epoch, offset):
    return parse_git_date(f"{epoch} {offset}".encode()).replace(tzinfo=timezone.utc)


def utc_git_date(epoch):
    return b"%d +0000" % epoch


# ──────────────────────────────────────────────────────────────────────
# VALIDATION


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
        if any(char in value for char in IDENT_FORBIDDEN_CHARS):
            fail(f'Error: {field} must not contain "<", ">" or a newline (got "{value}")')


# --current-branch rewrites the checked-out branch, so there must be one.
def require_branch_to_overwrite(opts):
    if opts.currentbranch and not git("branch", "--show-current"):
        fail(
            "Error: HEAD is detached, so there is no current branch to overwrite. "
            "Drop --current-branch or check out a branch first."
        )


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
        if opts.cli_flags.get(opt):
            print(message)
    print()


# Reads one key from the terminal, not stdin: under xargs stdin is /dev/null.
# Skipped for --no-confirm or --dry-run (nothing is touched either way).
def confirm(opts):
    if opts.noconfirm or opts.dryrun:
        return
    try:
        terminal = open("/dev/tty", "r+b", buffering=0)  # noqa: SIM115 -- closed by `with` below
    except OSError:
        fail("Error: no terminal to ask for confirmation; pass --no-confirm.")
    with terminal:
        terminal.write(b"Continue? (y/N) ")
        saved = termios.tcgetattr(terminal)
        single_key = list(saved)
        single_key[tty.LFLAG] &= ~termios.ICANON
        termios.tcsetattr(terminal, termios.TCSANOW, single_key)
        try:
            reply = terminal.read(1)
        finally:
            termios.tcsetattr(terminal, termios.TCSANOW, saved)
    print()
    if reply not in (b"y", b"Y"):
        fail("Aborted.")


# Creates a new branch (default) or a backup branch (--current-branch, unless
# --no-backup) so pre-rewrite history stays reachable. No-op under --dry-run.
def backup_branch(opts):
    if opts.dryrun:
        return
    current_branch = git("branch", "--show-current")
    branch_label = current_branch or f"detached-{git('rev-parse', '--short', 'HEAD')}"
    # Colon-free (git ref names disallow ":"); PID + random suffix for
    # uniqueness within the same second.
    timestamp = (
        f"{time.strftime('%Y%m%d_%H%M%S')}_{os.getpid()}_{random.randrange(BRANCH_RANDOM_RANGE)}"
    )
    if not opts.currentbranch:
        new_branch = f"{branch_label}{BRANCH_SUFFIX_ANONYMIZED}{timestamp}"
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
    backup_branch_name = f"{branch_label}{BRANCH_SUFFIX_BACKUP}{timestamp}"
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
# calendar unit kept.
def bucket_bounds(dt, kept_unit):
    if kept_unit == KEPT_YEAR:
        start = datetime(dt.year, 1, 1, tzinfo=timezone.utc)
        end = datetime(dt.year, 12, 31, 23, 59, 59, tzinfo=timezone.utc)
        return (dt.year,), int(start.timestamp()), int(end.timestamp())
    if kept_unit == KEPT_MONTH:
        start = datetime(dt.year, dt.month, 1, tzinfo=timezone.utc)
        if dt.month == 12:
            next_month_start = datetime(dt.year + 1, 1, 1, tzinfo=timezone.utc)
        else:
            next_month_start = datetime(dt.year, dt.month + 1, 1, tzinfo=timezone.utc)
        end = next_month_start - timedelta(seconds=1)
        return (dt.year, dt.month), int(start.timestamp()), int(end.timestamp())
    start = datetime(dt.year, dt.month, dt.day, tzinfo=timezone.utc)
    end = start + timedelta(days=1, seconds=-1)
    return (dt.year, dt.month, dt.day), int(start.timestamp()), int(end.timestamp())


# Real neighbors are parents and children: across a merge, the commit next
# in log order can sit on another branch.
def find_anchors(history, targets):
    anchors = set()
    for commit in history:
        if commit.hash in targets:
            anchors.update(commit.parents)
        elif any(parent in targets for parent in commit.parents):
            anchors.add(commit.hash)
    return anchors


# Groups targets and anchors by the calendar unit each must stay in: the
# commit's local unit (what `git log` shows, as --keep-* uses); an anchor
# also bounds targets whose bucket holds its real instant. Returns
# [(sorted members, (start epoch, end epoch))].
def bucket_members(history, targets, kept_unit, entire):
    anchors = find_anchors(history, targets)
    buckets = defaultdict(list)
    bounds = {}
    for index, commit in enumerate(history):
        is_target = entire or commit.hash in targets
        if not is_target and commit.hash not in anchors:
            continue
        keys = {bucket_bounds(local_datetime(commit.epoch, commit.offset), kept_unit)}
        if not is_target:
            real_instant = datetime.fromtimestamp(commit.epoch, tz=timezone.utc)
            keys.add(bucket_bounds(real_instant, kept_unit))
        for key, start, end in keys:
            buckets[key].append(BucketMember(commit.epoch, index, commit.hash, is_target))
            bounds[key] = (start, end)
    return [(sorted(members), bounds[key]) for key, members in buckets.items()]


# count sorted random epochs in [lower, upper], kept within the bucket.
def pick_epochs(lower, upper, bucket, count, rng):
    bucket_start, bucket_end = bucket
    if upper < lower:
        # No room between anchors, or an anchor outside the bucket. Share the
        # nearest in-bucket timestamp: git allows identical dates, the
        # calendar unit must not change.
        return [min(max(lower - 1, bucket_start), bucket_end)] * count
    if count <= upper - lower + 1:
        return sorted(rng.sample(range(lower, upper + 1), count))
    return sorted(rng.randint(lower, upper) for _ in range(count))


# One random epoch per target, {hash: epoch}. history: [HistoryCommit],
# oldest first, parents before children; the history index breaks epoch
# ties so a parent sorts before its same-second child. Each run of targets
# between two anchors gets sorted epochs strictly between them.
def compute_random_dates(history, targets, kept_unit, entire, rng=None):
    rng = rng or random.SystemRandom()
    picked = {}
    for members, bucket in bucket_members(history, targets, kept_unit, entire):
        bucket_start, bucket_end = bucket
        i = 0
        lower = bucket_start
        while i < len(members):
            if not members[i].is_target:
                lower = max(members[i].epoch + 1, bucket_start)
                i += 1
                continue
            run_start = i
            while i < len(members) and members[i].is_target:
                i += 1
            run = members[run_start:i]
            upper = min(members[i].epoch - 1, bucket_end) if i < len(members) else bucket_end
            epochs = pick_epochs(lower, upper, bucket, len(run), rng)
            for member, epoch in zip(run, epochs, strict=True):
                picked[member.hash] = epoch
    return picked


def read_history():
    log = git(
        "log", "--reverse", "--topo-order", "--date=format:%z", "--format=%H %at %ad %P", "HEAD"
    )
    history = []
    for line in log.splitlines():
        commit_hash, epoch, offset, *parents = line.split()
        history.append(HistoryCommit(commit_hash, int(epoch), offset, parents))
    return history


def kept_calendar_unit(opts):
    if opts.randommonth:
        return KEPT_YEAR
    if opts.randomday:
        return KEPT_MONTH
    if opts.randomtime:
        return KEPT_DAY
    return None


# {hash: epoch} for --random-*, or None when dates aren't randomized.
def random_dates_for(opts):
    kept_unit = None if opts.keepdate else kept_calendar_unit(opts)
    if kept_unit is None:
        return None
    return compute_random_dates(read_history(), set(opts.commits), kept_unit, opts.entirehistory)


# ──────────────────────────────────────────────────────────────────────
# REWRITE


def target_date_bytes(opts, commit, random_dates):
    if random_dates is not None:
        epoch = random_dates.get(commit.original_id.decode())
        if epoch is None:
            raise SystemExit(
                f"anon-git: no precomputed random date for commit {commit.original_id.decode()}"
            )
        return utc_git_date(epoch)
    if opts.keepyear or opts.keepmonth or opts.keepday:
        # Keep the calendar date as seen, re-anchored to midnight UTC, so
        # only time/tz leak.
        dt = parse_git_date(commit.author_date).replace(hour=0, minute=0, second=0, microsecond=0)
        if opts.keepyear or opts.keepmonth:
            dt = dt.replace(day=1)
        if opts.keepyear:
            dt = dt.replace(month=1)
        return utc_git_date(as_utc_epoch(dt))
    dt = parse_target_date(opts.date)
    if opts.striptimezone:
        return utc_git_date(as_utc_epoch(dt))
    offset_seconds = int(dt.utcoffset().total_seconds())
    sign = "+" if offset_seconds >= 0 else "-"
    hours, minutes = divmod(abs(offset_seconds) // 60, 60)
    return b"%d %s%02d%02d" % (int(dt.timestamp()), sign.encode(), hours, minutes)


# Commit metadata is raw bytes with no guaranteed encoding.
def decode_metadata(raw):
    return raw.decode(errors="replace")


def git_date_iso(git_date):
    return parse_git_date(git_date).isoformat()


def ident(name, email):
    return f"{decode_metadata(name)} <{decode_metadata(email)}>"


def preview_entry(commit, new):
    author = ident(commit.author_name, commit.author_email)
    new_author = ident(new["author_name"], new["author_email"])
    committer = ident(commit.committer_name, commit.committer_email)
    new_committer = ident(new["committer_name"], new["committer_email"])
    return (
        f"Commit:{commit.original_id.decode()}\n"
        f"Author:\t\t{author} -> {new_author} \n"
        f"Committer:\t{committer} -> {new_committer} \n"
        f"AuthorDate:\t{git_date_iso(commit.author_date)} -> {git_date_iso(new['author_date'])}\n"
        f"CommitterDate:\t{git_date_iso(commit.committer_date)} -> "
        f"{git_date_iso(new['committer_date'])}\n"
        "\n"
        f"{decode_metadata(commit.message)}"
        f"\n{PREVIEW_SEPARATOR}\n"
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
                new[field] = utc_git_date(as_utc_epoch(parse_git_date(getattr(commit, field))))
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
    require_branch_to_overwrite(opts)
    verbose_info(opts)
    confirm(opts)
    backup_branch(opts)
    clean_cache()
    preview = []
    run_filter_repo(opts, make_commit_callback(opts, random_dates_for(opts), preview))
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
