"""Fixed values: defaults, option and flag tables, names."""

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


# C0/C1 control characters except tab and newline, shown as \xNN: a cloned
# repo's commit metadata must not drive the terminal (escape sequences).
CONTROL_ESCAPES = {
    code: f"\\x{code:02x}" for code in (*range(0x20), *range(0x7F, 0xA0)) if chr(code) not in "\t\n"
}


# Marks hooks this tool generated, so install_hook can refresh them without
# clobbering a hook the user wrote. Same marker as the shell version.
HOOK_MARKER = "# Installed by anon-git --install-hook"


COMPLETION_FILES = {
    "bash": "anon-git.bash",
    "zsh": "_anon-git",
    "fish": "anon-git.fish",
}


ERROR_NOT_A_COMMIT = 'Error: Commit "{rev}" does not exist or is not a commit object.'
