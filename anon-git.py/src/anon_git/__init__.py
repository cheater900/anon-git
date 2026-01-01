"""Anonymizes git commit metadata.

Python port of anon-git.sh: same flags, messages and exit codes. Function
names mirror the shell implementation so the two can be audited side by side.
The rewrite runs in-process through the git_filter_repo library.
"""

import os
import sys
from importlib import resources

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
        elif arg in FLAGS_DROPPED:
            dropped_install_flag(arg)
        i += 1


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    handle_early_options(argv)
