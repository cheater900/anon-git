#!/usr/bin/env bash

set -euo pipefail

# Bumped by hand; no automated release process yet. Not tied to git tags.
ANON_GIT_VERSION='0.1.0'

DEFAULT_NAME='Anon'
DEFAULT_EMAIL='anon@localhost'
DEFAULT_DATE='2008-10-31 00:00:00 +0000'
DEFAULT_KEEPUSER='0'
DEFAULT_KEEPDATE='0'
DEFAULT_KEEPYEAR='0'
DEFAULT_KEEPMONTH='0'
DEFAULT_KEEPDAY='0'
DEFAULT_ENTIREHISTORY='0'
DEFAULT_CURRENTBRANCH='0'
DEFAULT_DRYRUN='0'
DEFAULT_QUIET='0'

# Scratch files cleaned up by the EXIT trap (cleanup_on_exit) below, so a
# kill mid-run (Ctrl-C, CI timeout, ...) can't leave them behind — not just
# the normal success/failure exit paths. Declared here (empty) so the trap
# can safely run even before setup_dryrun/run_filter_repo populate them.
dryrun_file=''
filter_repo_log=''

cleanup_on_exit() {
    if [[ -n "$dryrun_file" && -f "$dryrun_file" ]]; then
        rm -f "$dryrun_file"
    fi
    if [[ -n "$filter_repo_log" && -f "$filter_repo_log" ]]; then
        rm -f "$filter_repo_log"
    fi
}
trap cleanup_on_exit EXIT

# ──────────────────────────────────────────────────────────────────────
# HELP
#
# Defined and handled first so `--help` works even outside a git repository
# or with a dirty working tree; the safety checks that follow this block
# are unchanged, just moved below the help handling.

show_help() {
    cat <<EOF
Anonymizes git commit metadata.

Usage:
  ./anon-git.sh [OPTIONS] [commits]

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
  --no-confirm                    Do not prompt for confirmation
  --no-backup                     Do not create backup branch
  --current-branch                Overwrite current branch instead of creating a copy of it
  --entire-history                Rewrite entire history and not a single commit
  --dry-run                       Show history changes without rewriting it
  --quiet                         Suppress informational output (errors/safety warnings still print)
  --verbose                       Force informational output, overriding --quiet,
                                   ANON_GIT_QUIET, or a repo-local quiet config
  --print-completion [SHELL]      Print a shell completion script (bash, zsh, or fish;
                                   defaults to \$SHELL) and exit
  --install                        Copy this script to ~/.local/bin and/or ~/.bin
                                   (whichever exist) and warn if neither is on \$PATH
  --install-system                 Copy this script system-wide to /usr/bin (via sudo)
  --install-hook                   Install a post-commit hook in the current git repository
                                   that anonymizes each new commit (HEAD only) automatically

Arguments:
  commit(s)               Commit(s) to anonymize (can be: hash, HEAD~3, branch, tag, ...)
                          Required, unless --entire-history is given.
                          If omitted (and --entire-history is not given), this help is shown.
                          If more than one, it should be a commit hash.

Priority (highest to lowest):
  1. Command-line flags (--date, --name, --email, --keep-user, --keep-date, ...)
  2. Repo-local git config (git config anon-git.name, anon-git.email, anon-git.date,
     anon-git.keepuser, anon-git.keepdate, anon-git.keepyear, anon-git.keepmonth,
     anon-git.keepday, anon-git.quiet — --entire-history/--current-branch/--dry-run
     have no config equivalent, flag/envvar only)
  3. Environment variables (ANON_GIT_DATE, ANON_GIT_NAME, ANON_GIT_EMAIL, ANON_GIT_KEEPUSER,
     ANON_GIT_KEEPDATE, ANON_GIT_KEEPYEAR, ANON_GIT_KEEPMONTH, ANON_GIT_KEEPDAY,
     ANON_GIT_ENTIREHISTORY, ANON_GIT_CURRENTBRANCH, ANON_GIT_DRYRUN, ANON_GIT_QUIET)
  4. Hardcoded defaults (${DEFAULT_NAME} <${DEFAULT_EMAIL}>)

Note: --verbose has no ANON_GIT_VERBOSE environment variable or config
      equivalent; it is a CLI-only override that forces informational
      output back on for one run.

Examples:
    # Anonymize current HEAD with defaults
    ./anon-git.sh HEAD

    # Anonymize two commits ago
    ./anon-git.sh HEAD~2

    # Explicit values at specific commit
    ./anon-git.sh --date "2024-01-01 00:00:00 +0000"
                  --name "Jane Doe"
                  --email "jane@anon.dev"
                  8ddf55a

    # Keep real name/email, only change date
    ./anon-git.sh --keep-user --date "2025-06-15T14:20:00Z"

    # Preview what would change before actually rewriting anything
    ./anon-git.sh --dry-run HEAD~2

    # Silence informational output (only errors print)
    ./anon-git.sh --quiet HEAD

    # Force informational output back on, overriding a quiet default
    ./anon-git.sh --verbose HEAD

    # Pin this repo's own defaults instead of passing flags/envvars every time
    git config anon-git.name "Anon"
    git config anon-git.email "anon@localhost"
    git config anon-git.quiet true
    ./anon-git.sh HEAD

    # Anonymize the last 10 commits using shell expansion (works in bash and zsh)
    ./anon-git.sh HEAD~{0..9}

    # Anonymize commits within a specific date range
    git log --format=%H --after='2023-01-01' --before='2024-01-01' | xargs ./anon-git.sh

    # Anonymize commits where the commit author matches a pattern
    git log --format=%H --author='Frederic' | xargs ./anon-git.sh

    # Anonymize commits following the Conventional Commits "fix:" prefix
    git log --format=%H --grep='^fix:' | xargs ./anon-git.sh

    # Install shell completion (shell inferred from \$SHELL if omitted)
    ./anon-git.sh --print-completion bash > ~/.local/share/bash-completion/completions/anon-git.sh
    ./anon-git.sh --print-completion zsh  > "\${fpath[1]}/_anon-git.sh"
    ./anon-git.sh --print-completion fish > ~/.config/fish/completions/anon-git.sh.fish

    # Install this script to ~/.local/bin and/or ~/.bin (whichever exist)
    ./anon-git.sh --install

    # Install this script system-wide to /usr/bin (requires sudo)
    ./anon-git.sh --install-system

    # Install a post-commit hook so every new commit in this repo is
    # auto-anonymized (HEAD only, right after \`git commit\`)
    ./anon-git.sh --install-hook
EOF
    exit 0
}

show_version() {
    printf 'anon-git %s\n' "$ANON_GIT_VERSION"
    exit 0
}

# Internal/undocumented: prints one flag per line (value-taking flags end in
# "="), so shell completion scripts have a single source of truth for the
# flag list instead of hardcoding it (and silently drifting out of sync).
list_flags() {
    cat <<'EOF'
-h
--help
-v
--version
--date=
--name=
--email=
--keep-user
--keep-date
--keep-year
--keep-month
--keep-day
--no-confirm
--no-backup
--current-branch
--entire-history
--dry-run
--quiet
--verbose
--print-completion=
--install
--install-system
--install-hook
EOF
    exit 0
}

# Internal: prints the requested shell's completion script to stdout and
# exits. The completion scripts are static files shipped next to this
# script (see completions/), not generated, so this is just a convenience
# `cat` with shell-name resolution (defaulting to $SHELL) and validation.
print_completion() {
    local shell="$1" script_dir completion_file

    [[ -n "$shell" ]] || shell="${SHELL##*/}"

    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)
    case "$shell" in
    bash) completion_file="${script_dir}/completions/anon-git.bash" ;;
    zsh) completion_file="${script_dir}/completions/_anon-git.sh" ;;
    fish) completion_file="${script_dir}/completions/anon-git.sh.fish" ;;
    *)
        printf 'Error: unsupported shell "%s" (expected bash, zsh, or fish)\n' "$shell" >&2
        exit 1
        ;;
    esac

    if [[ ! -f "$completion_file" ]]; then
        printf 'Error: completion script not found: %s\n' "$completion_file" >&2
        exit 1
    fi

    cat -- "$completion_file"
    exit 0
}

# Internal: absolute path to this script itself, so the install functions
# below can copy it regardless of the relative path (./anon-git.sh, a
# $PATH lookup, ...) it was invoked with.
script_path() {
    local script_dir
    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)
    printf '%s/%s\n' "$script_dir" "$(basename -- "${BASH_SOURCE[0]:-$0}")"
}

# Internal: copies $1 (this script) to $2/anon-git, then warns if $2 is
# not on $PATH. Prints what it did/failed and returns non-zero on failure
# instead of exiting, so install_user can attempt every candidate directory.
install_copy() {
    local src="$1" dir="$2" target="${2}/anon-git"

    if [[ "$target" -ef "$src" ]]; then
        printf 'Already installed: %s\n' "$target"
        return 0
    fi

    if ! cp -- "$src" "$target"; then
        printf 'Error: failed to copy to %s\n' "$target" >&2
        return 1
    fi
    chmod +x "$target"
    printf 'Installed: %s\n' "$target"

    case ":${PATH}:" in
    *":${dir}:"*) ;;
    *)
        printf "Warning: %s is not in your \$PATH.\n" "$dir" >&2
        printf "  Add it, e.g.: export PATH=\"%s:\$PATH\"\n" "$dir" >&2
        ;;
    esac

    return 0
}

# --install: copies this script to ~/.local/bin and/or ~/.bin, whichever of
# the two already exist (neither is created), and warns per-directory if it
# isn't on $PATH.
install_user() {
    local src candidates=("${HOME}/.local/bin" "${HOME}/.bin") dir found=0 failures=0

    src=$(script_path)

    for dir in "${candidates[@]}"; do
        if [[ -d "$dir" ]]; then
            found=1
            install_copy "$src" "$dir" || failures=$((failures + 1))
        fi
    done

    if [[ "$found" -eq 0 ]]; then
        printf 'Error: neither %s nor %s exist. Create one (e.g. mkdir -p %s) and re-run --install.\n' \
            "${candidates[0]}" "${candidates[1]}" "${candidates[0]}" >&2
        exit 1
    fi

    [[ "$failures" -eq 0 ]] && exit 0
    exit 1
}

# --install-system: copies this script to /usr/bin via sudo, for a
# system-wide install available to every user/shell.
install_system() {
    local src target='/usr/bin/anon-git'

    src=$(script_path)

    if [[ "$target" -ef "$src" ]]; then
        printf 'Already installed: %s\n' "$target"
        exit 0
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        printf 'Error: sudo not found; cannot perform a system-wide install.\n' >&2
        exit 1
    fi

    printf 'Installing to %s (requires sudo)...\n' "$target"
    if ! sudo cp -- "$src" "$target"; then
        printf 'Error: failed to copy to %s\n' "$target" >&2
        exit 1
    fi
    sudo chmod 755 "$target"
    printf 'Installed: %s\n' "$target"
    exit 0
}

# Internal: marker embedded in the generated post-commit hook so install_hook
# can recognize (and safely refresh) a hook it created, without clobbering a
# hook the user wrote themselves.
HOOK_MARKER='# Installed by anon-git --install-hook'

# --install-hook: installs a post-commit hook in the current repository's
# .git/hooks/ that re-anonymizes HEAD (the commit that was just made) after
# every `git commit`, using --current-branch so it rewrites in place instead
# of creating a new branch on every commit. Also passes --no-backup: a
# per-commit backup branch would otherwise accumulate one extra branch per
# commit forever (this fires on *every* commit, unlike a manual run); `git
# reflog`/`git reset` still recover the pre-hook state if something goes
# wrong, per the README. Also passes --quiet: without it, every `git commit`
# would print "Anonymizing commit(s): ..." / "Done." on top of git's own
# commit summary.
install_hook() {
    local git_dir hooks_dir hook_file src

    if ! git_dir=$(git rev-parse --git-dir 2>/dev/null); then
        printf 'Error: --install-hook must be run inside a git repository.\n' >&2
        exit 1
    fi
    git_dir=$(cd -- "$git_dir" && pwd)
    hooks_dir="${git_dir}/hooks"
    hook_file="${hooks_dir}/post-commit"

    if [[ -f "$hook_file" ]] && ! grep -qF "$HOOK_MARKER" "$hook_file"; then
        printf 'Error: %s already exists and was not installed by anon-git.\n' "$hook_file" >&2
        printf '  Remove or back it up first, then re-run --install-hook.\n' >&2
        exit 1
    fi

    src=$(script_path)
    mkdir -p "$hooks_dir"
    cat >"$hook_file" <<EOF
#!/usr/bin/env bash
$HOOK_MARKER
#
# Anonymizes the just-created commit (HEAD) after every \`git commit\`.
# --no-backup: this runs on every commit, so a per-commit backup branch
# would accumulate forever; use \`git reflog\`/\`git reset\` to recover if
# needed. --quiet: silences the per-commit "Anonymizing commit(s): ..." /
# "Done." output; drop it (or pass --verbose) if you want that back.
# Regenerate with: $src --install-hook

set -e
"$src" --no-confirm --no-backup --quiet --current-branch HEAD
EOF
    chmod +x "$hook_file"
    printf 'Installed post-commit hook: %s\n' "$hook_file"
    exit 0
}

# ──────────────────────────────────────────────
# EARLY OPTIONS
#
# Handled before any git-repo/safety checks, so --help, --print-completion
# and the --install* flags work even outside a git repository or with a
# dirty working tree.
handle_early_options() {
    [[ $# -eq 0 ]] && show_help

    local args=("$@") i
    for ((i = 0; i < ${#args[@]}; i++)); do
        case "${args[i]}" in
        -h | --help) show_help ;;
        -v | --version) show_version ;;
        --_list-flags) list_flags ;;
        --print-completion) print_completion "${args[i + 1]:-}" ;;
        --install) install_user ;;
        --install-system) install_system ;;
        --install-hook) install_hook ;;
        esac
    done
}

# Internal: dies with a clear message unless run inside a git repository
# with a clean working tree and git-filter-repo available. Split out from
# parse/resolve/rewrite so those can assume a usable repo from this point on.
safety_checks() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        printf 'AnonGit must be run inside a git repository.\n'
        exit 1
    fi

    if ! git diff-index --quiet HEAD -- || ! git diff-files --quiet; then
        printf 'Repository has uncommitted changes. Commit or stash first to prevent losing the changes.\n'
        exit 1
    fi

    if ! command -v git-filter-repo >/dev/null 2>&1 && ! git filter-repo --version >/dev/null 2>&1; then
        printf 'git-filter-repo is required but was not found. See the Pre-requisites section of the README.\n' >&2
        exit 1
    fi
}

# Internal: reads a single boolean repo-local config key (git config
# anon-git.<key>) and prints it normalized to '1'/'0' (matching the
# ANON_GIT_* envvar contract), or prints nothing if the key is unset. A value
# git can't parse as a boolean is treated as a hard error rather than
# silently ignored, since a typo'd repo config should not fail open.
read_git_config_bool() {
    local key="$1" raw
    raw=$(git config --get "$key" 2>/dev/null || true)

    if [[ -z "$raw" ]]; then
        printf ''
        return 0
    fi

    case "$raw" in
    true | yes | on | 1) printf '1' ;;
    false | no | off | 0) printf '0' ;;
    *)
        printf 'Error: git config %s has an invalid boolean value "%s" (expected true/false)\n' "$key" "$raw" >&2
        exit 1
        ;;
    esac
}

# Reads repo-local defaults from `git config anon-git.*` into the GITCONFIG_*
# globals that merge_args_with_defaults consults above ANON_GIT_* envvars
# (repo config wins over an inherited/exported envvar) and below CLI flags
# (see README's "Repo-local config" section). Deliberately scoped to
# name/email/date/keep-*/quiet — the
# settings that make sense to pin per-repo; --entire-history,
# --current-branch and --dry-run stay flag/envvar-only, since a silently
# configured default for any of those would be far more destructive than a
# wrong name or email.
read_git_config() {
    GITCONFIG_NAME=$(git config --get anon-git.name 2>/dev/null || true)
    GITCONFIG_EMAIL=$(git config --get anon-git.email 2>/dev/null || true)
    GITCONFIG_DATE=$(git config --get anon-git.date 2>/dev/null || true)
    GITCONFIG_KEEPUSER=$(read_git_config_bool anon-git.keepuser)
    GITCONFIG_KEEPDATE=$(read_git_config_bool anon-git.keepdate)
    GITCONFIG_KEEPYEAR=$(read_git_config_bool anon-git.keepyear)
    GITCONFIG_KEEPMONTH=$(read_git_config_bool anon-git.keepmonth)
    GITCONFIG_KEEPDAY=$(read_git_config_bool anon-git.keepday)
    GITCONFIG_QUIET=$(read_git_config_bool anon-git.quiet)
}

# Internal: parses "$@" into the *_ARG globals RESOLVE ARGS later merges with
# ANON_GIT_* envvars and the DEFAULT_* fallbacks. Empty string means "not
# provided via flag" throughout the rest of the script.
parse_args() {
    DATE_ARG=""
    NAME_ARG=""
    EMAIL_ARG=""
    KEEPUSER_ARG=""
    KEEPDATE_ARG=""
    KEEPYEAR_ARG=""
    KEEPMONTH_ARG=""
    KEEPDAY_ARG=""
    NOCONFIRM_ARG=""
    NOBACKUP_ARG=""
    DRYRUN_ARG=""
    ENTIREHISTORY_ARG=""
    CURRENTBRANCH_ARG=""
    QUIET_ARG=""
    VERBOSE_ARG=""
    COMMIT_ARG=""
    COMMITS_ARG=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --date)
            [[ $# -ge 2 ]] || {
                printf 'Error: %s requires a value\n' "$1" >&2
                exit 1
            }
            DATE_ARG="$2"
            shift 2
            ;;
        --name)
            [[ $# -ge 2 ]] || {
                printf 'Error: %s requires a value\n' "$1" >&2
                exit 1
            }
            NAME_ARG="$2"
            shift 2
            ;;
        --email)
            [[ $# -ge 2 ]] || {
                printf 'Error: %s requires a value\n' "$1" >&2
                exit 1
            }
            EMAIL_ARG="$2"
            shift 2
            ;;
        --keep-user)
            KEEPUSER_ARG='1'
            shift
            ;;
        --keep-date)
            KEEPDATE_ARG='1'
            shift
            ;;
        --keep-year)
            KEEPYEAR_ARG='1'
            shift
            ;;
        --keep-month)
            KEEPMONTH_ARG='1'
            shift
            ;;
        --keep-day)
            KEEPDAY_ARG='1'
            shift
            ;;
        --no-confirm)
            NOCONFIRM_ARG='1'
            shift
            ;;
        --no-backup)
            NOBACKUP_ARG='1'
            shift
            ;;
        --entire-history)
            ENTIREHISTORY_ARG='1'
            shift
            ;;
        --current-branch)
            CURRENTBRANCH_ARG='1'
            shift
            ;;
        --dry-run)
            DRYRUN_ARG='1'
            shift
            ;;
        --quiet)
            QUIET_ARG='1'
            shift
            ;;
        --verbose)
            VERBOSE_ARG='1'
            shift
            ;;
        -*)
            printf 'Unknown option: %s\n' "$1" >&2
            exit 1
            ;;
        *)
            if ! git rev-parse --quiet --verify "${1}^{commit}" >/dev/null 2>&1; then
                printf 'Error: Commit "%s" does not exist or is not a commit object.\n' "${1}" >&2
                exit 1
            fi
            ref=$(git rev-parse "$1")
            COMMITS_ARG=("${COMMITS_ARG[@]}" "$ref")
            COMMIT_ARG="${COMMITS_ARG[*]}"
            shift
            ;;
        esac
    done
}

# Internal: shared by reject_incompatible_options below to reject a pair of
# mutually-exclusive options once both are non-empty.
check_incompatible() {
    local flag1="$1"
    local flag2="$3"
    local value1="$2"
    local value2="$4"
    if [[ -n "$value1" && -n "$value2" ]]; then
        printf 'Error: %s and %s cannot be used together\n' "$flag1" "$flag2" >&2
        flag_errors=1
    fi
}

# Rejects mutually-exclusive option combinations regardless of whether each
# side was provided via CLI flag, repo-local `git config anon-git.*`, or its
# ANON_GIT_* environment variable equivalent — so e.g.
# `ANON_GIT_KEEP_USER=1 ANON_GIT_NAME=X` and a repo with both `anon-git.keepuser`
# and `anon-git.name` configured are rejected the same way `--keep-user --name X`
# is, instead of silently letting one win. Must run before RESOLVE ARGS
# overwrites these env var names with the fully-resolved value (default
# included), so an unset env var reads as empty and a hardcoded default never
# counts as "provided". Booleans only count as provided when explicitly '1'
# (the "0 or 1" contract validate_bool enforces later); string options count
# as provided whenever non-empty.
reject_incompatible_options() {
    local date_set name_set email_set
    local keepuser_set keepdate_set keepyear_set keepmonth_set keepday_set

    flag_errors=0

    date_set="${DATE_ARG:-${GITCONFIG_DATE:-${ANON_GIT_DATE:-}}}"
    name_set="${NAME_ARG:-${GITCONFIG_NAME:-${ANON_GIT_NAME:-}}}"
    email_set="${EMAIL_ARG:-${GITCONFIG_EMAIL:-${ANON_GIT_EMAIL:-}}}"
    keepuser_set="$KEEPUSER_ARG"
    keepdate_set="$KEEPDATE_ARG"
    keepyear_set="$KEEPYEAR_ARG"
    keepmonth_set="$KEEPMONTH_ARG"
    keepday_set="$KEEPDAY_ARG"
    [[ "${ANON_GIT_KEEPUSER:-}" == '1' ]] && keepuser_set='1'
    [[ "${ANON_GIT_KEEPDATE:-}" == '1' ]] && keepdate_set='1'
    [[ "${ANON_GIT_KEEPYEAR:-}" == '1' ]] && keepyear_set='1'
    [[ "${ANON_GIT_KEEPMONTH:-}" == '1' ]] && keepmonth_set='1'
    [[ "${ANON_GIT_KEEPDAY:-}" == '1' ]] && keepday_set='1'
    [[ "${GITCONFIG_KEEPUSER:-}" == '1' ]] && keepuser_set='1'
    [[ "${GITCONFIG_KEEPDATE:-}" == '1' ]] && keepdate_set='1'
    [[ "${GITCONFIG_KEEPYEAR:-}" == '1' ]] && keepyear_set='1'
    [[ "${GITCONFIG_KEEPMONTH:-}" == '1' ]] && keepmonth_set='1'
    [[ "${GITCONFIG_KEEPDAY:-}" == '1' ]] && keepday_set='1'

    check_incompatible --keep-user "$keepuser_set" --name "$name_set"
    check_incompatible --keep-user "$keepuser_set" --email "$email_set"
    check_incompatible --date "$date_set" --keep-date "$keepdate_set"
    check_incompatible --date "$date_set" --keep-year "$keepyear_set"
    check_incompatible --date "$date_set" --keep-month "$keepmonth_set"
    check_incompatible --date "$date_set" --keep-day "$keepday_set"
    check_incompatible --keep-date "$keepdate_set" --keep-year "$keepyear_set"
    check_incompatible --keep-date "$keepdate_set" --keep-month "$keepmonth_set"
    check_incompatible --keep-date "$keepdate_set" --keep-day "$keepday_set"
    check_incompatible --keep-year "$keepyear_set" --keep-month "$keepmonth_set"
    check_incompatible --keep-year "$keepyear_set" --keep-day "$keepday_set"
    check_incompatible --keep-month "$keepmonth_set" --keep-day "$keepday_set"
    # The commit(s) argument is CLI-only (there is no ANON_GIT_COMMIT env var
    # users are meant to set), so this one stays flag-vs-flag.
    check_incompatible "commit(s) argument" "$COMMIT_ARG" --entire-history "$ENTIREHISTORY_ARG"
    # --verbose is a CLI-only override for ANON_GIT_QUIET/a repo-local quiet
    # config (see merge_args_with_defaults), so this stays flag-vs-flag too:
    # `ANON_GIT_QUIET=1 --verbose` is the intended way to un-silence a quiet
    # default for one run, not a conflict to reject.
    check_incompatible --quiet "$QUIET_ARG" --verbose "$VERBOSE_ARG"

    [[ "$flag_errors" -ne 0 ]] && exit 1
    return 0
}

# Internal: merges flags > repo-local git config > ANON_GIT_* envvars >
# DEFAULT_* fallbacks into the final ANON_GIT_* globals used by everything
# from here on (verbose output, the backup/rewrite logic, and the Python
# commit-callback's environment).
merge_args_with_defaults() {
    DEFAULT_COMMIT=$(git rev-parse HEAD)
    ANON_GIT_DATE="${DATE_ARG:-${GITCONFIG_DATE:-${ANON_GIT_DATE:-${DEFAULT_DATE}}}}"
    ANON_GIT_NAME="${NAME_ARG:-${GITCONFIG_NAME:-${ANON_GIT_NAME:-${DEFAULT_NAME}}}}"
    ANON_GIT_EMAIL="${EMAIL_ARG:-${GITCONFIG_EMAIL:-${ANON_GIT_EMAIL:-${DEFAULT_EMAIL}}}}"
    ANON_GIT_KEEPUSER="${KEEPUSER_ARG:-${GITCONFIG_KEEPUSER:-${ANON_GIT_KEEPUSER:-${DEFAULT_KEEPUSER}}}}"
    ANON_GIT_KEEPDATE="${KEEPDATE_ARG:-${GITCONFIG_KEEPDATE:-${ANON_GIT_KEEPDATE:-${DEFAULT_KEEPDATE}}}}"
    ANON_GIT_KEEPYEAR="${KEEPYEAR_ARG:-${GITCONFIG_KEEPYEAR:-${ANON_GIT_KEEPYEAR:-${DEFAULT_KEEPYEAR}}}}"
    ANON_GIT_KEEPMONTH="${KEEPMONTH_ARG:-${GITCONFIG_KEEPMONTH:-${ANON_GIT_KEEPMONTH:-${DEFAULT_KEEPMONTH}}}}"
    ANON_GIT_KEEPDAY="${KEEPDAY_ARG:-${GITCONFIG_KEEPDAY:-${ANON_GIT_KEEPDAY:-${DEFAULT_KEEPDAY}}}}"
    ANON_GIT_ENTIREHISTORY="${ENTIREHISTORY_ARG:-${ANON_GIT_ENTIREHISTORY:-${DEFAULT_ENTIREHISTORY}}}"
    ANON_GIT_CURRENTBRANCH="${CURRENTBRANCH_ARG:-${ANON_GIT_CURRENTBRANCH:-${DEFAULT_CURRENTBRANCH}}}"
    ANON_GIT_COMMIT="${COMMIT_ARG:-${DEFAULT_COMMIT}}"
    ANON_GIT_DRYRUN="${DRYRUN_ARG:-${ANON_GIT_DRYRUN:-${DEFAULT_DRYRUN}}}"
    ANON_GIT_QUIET="${QUIET_ARG:-${GITCONFIG_QUIET:-${ANON_GIT_QUIET:-${DEFAULT_QUIET}}}}"
    # --verbose always wins, regardless of what set ANON_GIT_QUIET above (flag,
    # repo-local config, envvar, or default): it exists specifically to force
    # output back on.
    if [[ "$VERBOSE_ARG" == '1' ]]; then
        ANON_GIT_QUIET='0'
    fi
}

# Internal: without an explicit commit target or --entire-history there is
# nothing to anonymize; show the help text instead of silently defaulting to
# HEAD (that implicit behavior was surprising, so a target is now required).
require_target() {
    if [[ -z "$COMMIT_ARG" && "$ANON_GIT_ENTIREHISTORY" != '1' ]]; then
        show_help
    fi
}

# Internal: shared by validate_final_options below to enforce the "0 or 1" contract
# every resolved ANON_GIT_* boolean must satisfy, however it was supplied.
validate_bool() {
    local name="$1" value="$2"
    if [[ "$value" != '0' && "$value" != '1' ]]; then
        printf 'Error: %s must resolve to "0" or "1" (got "%s")\n' "$name" "$value" >&2
        exit 1
    fi
}

# Sanity-checks the fully-resolved ANON_GIT_* booleans (flag, envvar, or
# default alike could have produced a bogus value if a stray envvar leaked
# in) before anything acts on them.
validate_final_options() {
    validate_bool ANON_GIT_KEEPUSER "$ANON_GIT_KEEPUSER"
    validate_bool ANON_GIT_KEEPDATE "$ANON_GIT_KEEPDATE"
    validate_bool ANON_GIT_KEEPYEAR "$ANON_GIT_KEEPYEAR"
    validate_bool ANON_GIT_KEEPMONTH "$ANON_GIT_KEEPMONTH"
    validate_bool ANON_GIT_KEEPDAY "$ANON_GIT_KEEPDAY"
    validate_bool ANON_GIT_ENTIREHISTORY "$ANON_GIT_ENTIREHISTORY"
    validate_bool ANON_GIT_CURRENTBRANCH "$ANON_GIT_CURRENTBRANCH"
    validate_bool ANON_GIT_DRYRUN "$ANON_GIT_DRYRUN"
    validate_bool ANON_GIT_QUIET "$ANON_GIT_QUIET"
}

# Prints a short summary of what's about to happen, gated on which flags
# were explicitly passed on the CLI (not the resolved envvar/default value),
# so setting e.g. ANON_GIT_KEEPUSER in your shell profile doesn't spam this
# on every run.
verbose_info() {
    if [[ "$ANON_GIT_QUIET" == '1' ]]; then
        return
    fi
    if [[ -z "$ENTIREHISTORY_ARG" ]]; then
        local short_commit
        short_commit=$(echo "$ANON_GIT_COMMIT" | xargs -n 1 git rev-parse --short | tr '\n' ' ')
        printf 'Anonymizing commit(s): %s\n' "$short_commit"
    fi
    if [[ -n "$ENTIREHISTORY_ARG" ]]; then
        printf 'Anonymizing entire history!\n'
    fi
    if [[ -n "$KEEPUSER_ARG" ]]; then
        printf 'Using identity: %s <%s>\n' "${ANON_GIT_NAME}" "${ANON_GIT_EMAIL}"
    fi
    if [[ -n "$KEEPDATE_ARG" ]]; then
        printf 'Using date: %s\n' "${ANON_GIT_DATE}"
    fi
    if [[ -n "$KEEPYEAR_ARG" ]]; then
        printf 'Using commit date year (anonymizing only month, day, time and tz).\n'
    fi
    if [[ -n "$KEEPMONTH_ARG" ]]; then
        printf 'Using commit date year and month (anonymizing only day, time and tz).\n'
    fi
    if [[ -n "$KEEPDAY_ARG" ]]; then
        printf 'Using commit date year, month and day (anonymizing only time and tz).\n'
    fi
    printf '\n'
}

# Creates a new branch (default) or a backup branch (--current-branch,
# unless --no-backup) before rewriting, so the pre-rewrite history stays
# reachable. No-op under --dry-run, since nothing is rewritten.
backup_branch() {
    local current_branch branch_label timestamp new_branch backup_branch_name switch_target

    current_branch=$(git branch --show-current)
    if [[ -z "$current_branch" && "$ANON_GIT_CURRENTBRANCH" == '1' ]]; then
        printf 'Error: HEAD is detached, so there is no current branch to overwrite. Drop --current-branch or check out a branch first.\n' >&2
        exit 1
    fi
    branch_label="${current_branch:-detached-$(git rev-parse --short HEAD)}"
    # Colon-free timestamp: git ref names may not contain ":" (see
    # git-check-ref-format). Suffixed with PID + $RANDOM rather than
    # sub-second precision (e.g. GNU date's %N) for uniqueness across
    # back-to-back runs within the same second: %N is a GNU coreutils
    # extension stock BSD/macOS date doesn't support, so this stays portable.
    timestamp="$(date +%Y%m%d_%H%M%S)_$$_${RANDOM}"

    if [[ "$ANON_GIT_DRYRUN" != '1' ]]; then
        if [[ "$ANON_GIT_CURRENTBRANCH" != '1' ]]; then
            new_branch="${branch_label}_anonymized_${timestamp}"
            # --quiet: also silences git switch's own "Switched to a new
            # branch '...'" line (git prints it to stderr); the printfs below
            # already say the same thing, so nothing informative is lost.
            switch_target='/dev/stderr'
            if [[ "$ANON_GIT_QUIET" == '1' ]]; then
                switch_target='/dev/null'
            fi
            if ! git switch --create "$new_branch" 2>"$switch_target"; then
                printf 'Error: failed to create branch %s\n' "$new_branch" >&2
                exit 1
            fi
            if [[ "$ANON_GIT_QUIET" != '1' ]]; then
                printf 'Created new branch %s from %s\n' "$new_branch" "$branch_label"
                printf 'Using branch %s to rewrite commits.\n' "$new_branch"
            fi
        elif [[ "$NOBACKUP_ARG" != "1" ]]; then
            backup_branch_name="${branch_label}_backup_${timestamp}"
            if ! git branch "${backup_branch_name}"; then
                printf 'Error: failed to create backup branch %s\n' "$backup_branch_name" >&2
                exit 1
            fi
            if [[ "$ANON_GIT_QUIET" != '1' ]]; then
                printf 'Created backup branch %s from %s\n' "$backup_branch_name" "$branch_label"
                printf 'Using branch %s to rewrite commits\n' "$branch_label"
            fi
        else
            # Not gated by --quiet: this is a data-loss warning, not routine
            # informational output, so it stays visible even when quiet.
            printf 'WARNING! Overwriting existing branch %s without backup!\n' "$branch_label"
        fi
    fi
}

# Prompts for confirmation unless --no-confirm or --dry-run (a dry run
# doesn't touch anything, so there's nothing to confirm).
confirm() {
    if [[ "$NOCONFIRM_ARG" != '1' && "$ANON_GIT_DRYRUN" != '1' ]]; then
        read -p "Continue? (y/N) " -n 1 -r
        printf '\n'
        [[ $REPLY =~ ^[Yy]$ ]] || exit 1
    fi
}

# git-filter-repo stores metadata in .git/filter-repo/ after the first run (to
# speed up certain operations and support things like incremental/incremental
# filtering). When you run it again, it tries to reuse that metadata, but under
# some conditions (particularly if the previous filtering pruned certain
# refs/objects or if the repo state changed in subtle ways), the assumption in the
# code breaks and it hits this assertion.
#
# This a known bug in git-filter-repo that can occur when you run the tool multiple
# times on the same repository (especially if you ran it once successfully, then
# tried again or with slightly different options).
#
# To avoid this bug, we remove cached metadata, which may cause trouble while
# anonymizing the git history, for example, when using the script as git hook.
clean_cache() {
    if [[ -d "$PWD/.git/filter-repo" ]]; then
        rm -rf "$PWD/.git/filter-repo"
    fi
}

# Internal: creates the scratch file the Python commit-callback writes its
# preview to under --dry-run, so run_filter_repo/print_result can share it
# via the ANON_GIT_DRYRUN_FILE envvar. Left empty (no file) otherwise.
# dryrun_file is the global the EXIT trap (cleanup_on_exit) removes.
setup_dryrun() {
    if [[ "${ANON_GIT_DRYRUN}" -eq 1 ]]; then
        dryrun_file=$(mktemp)
    fi
}

# ──────────────────────────────────────────────────────────────────────
# REWRITE LOGIC

# Values are passed to the Python commit-callback via the environment (not
# string-interpolated into the generated source) so that a name, email, or
# date containing a quote or other Python-special character cannot break out
# of a string literal and inject code into the callback.
export_rewrite_env() {
    export ANON_GIT_NAME ANON_GIT_EMAIL ANON_GIT_DATE ANON_GIT_COMMIT
    export ANON_GIT_KEEPUSER ANON_GIT_KEEPDATE ANON_GIT_KEEPYEAR ANON_GIT_KEEPMONTH ANON_GIT_KEEPDAY
    export ANON_GIT_ENTIREHISTORY ANON_GIT_DRYRUN
    export ANON_GIT_DRYRUN_FILE="${dryrun_file}"
    export TZ=UTC
}

# Kept as a plain top-level assignment (not nested in a function): the test
# suite locates this callback by its exact, unindented
# `python_commit_callback="` ... `"` line anchors to check it's valid Python.
python_commit_callback="
import os
import re
from datetime import datetime, timedelta, timezone

name  = os.environ['ANON_GIT_NAME']
email = os.environ['ANON_GIT_EMAIL']
date  = os.environ['ANON_GIT_DATE']
target_commits = [c.encode() for c in os.environ.get('ANON_GIT_COMMIT', '').split()]

keepuser = os.environ['ANON_GIT_KEEPUSER'] == '1'
keepdate = os.environ['ANON_GIT_KEEPDATE'] == '1'
keepyear = os.environ['ANON_GIT_KEEPYEAR'] == '1'
keepmonth = os.environ['ANON_GIT_KEEPMONTH'] == '1'
keepday = os.environ['ANON_GIT_KEEPDAY'] == '1'
entirehistory = os.environ['ANON_GIT_ENTIREHISTORY'] == '1'
dryrun = os.environ['ANON_GIT_DRYRUN'] == '1'
dryrun_file = os.environ.get('ANON_GIT_DRYRUN_FILE', '')

author_name = commit.author_name
author_email = commit.author_email
author_date = commit.author_date
committer_name = commit.committer_name
committer_email = commit.committer_email
committer_date = commit.committer_date

if not entirehistory and commit.original_id not in target_commits:
    return

def parse_git_date(date_bytes):
    # @param   <bytes>              Git date (timestamp followed by timezone, i.e 1770000000 +0000)
    # @returns <datetime.datetime>  Date object

    unix_ts, offset = date_bytes.decode().split()
    sign = 1 if offset.startswith('+') else -1
    offset = offset.replace('+', '').replace('-', '')
    if len(offset) == 4:
        hours   = int(offset[:2])
        minutes = int(offset[2:])
        seconds = 0
    elif len(offset) == 6:
        hours   = int(offset[:2])
        minutes = int(offset[2:4])
        seconds = int(offset[4:])
    else:
        raise ValueError('unsupported timezone format')
    tz_offset = timedelta(hours=hours, minutes=minutes, seconds=seconds)
    tz = timezone(sign * tz_offset)
    ts = float(unix_ts)
    dt = datetime.fromtimestamp(ts, tz=tz)
    return dt

def parse_target_date(date_str):
    # Accept both 'YYYY-MM-DD HH:MM:SS +ZZZZ' and ISO 8601 compact form
    # with a 'T' separator and/or a 'Z'/'+HH:MM' offset with no space
    # before it (e.g. '2025-06-15T14:20:00Z'), normalizing to the
    # space-separated, 4-digit-offset form '%z' below expects.
    normalized = date_str.strip()
    if 'T' in normalized:
        normalized = normalized.replace('T', ' ', 1)
        if normalized.endswith('Z'):
            normalized = normalized[:-1] + '+0000'
        match = re.match(r'^(.*\d{2}:\d{2}:\d{2})([+-]\d{2}:?\d{2})$', normalized)
        if match:
            normalized = '%s %s' % (match.group(1), match.group(2).replace(':', ''))
    return datetime.strptime(normalized, '%Y-%m-%d %H:%M:%S %z')

if not keepuser:
    author_name = name.encode()
    author_email = email.encode()
    committer_name = name.encode()
    committer_email = email.encode()

if not keepdate:
    if keepyear or keepmonth or keepday:
        # Strip the timezone (keeping the calendar date as the committer saw
        # it) and re-anchor to midnight UTC, so only the anonymized fields
        # (time, tz) leak; TZ=UTC above makes naive dt.timestamp() below UTC.
        dt = parse_git_date(commit.author_date)
        dt = dt.replace(tzinfo=None, hour=0, minute=0, second=0, microsecond=0)
        if keepyear or keepmonth:
            dt = dt.replace(day=1)
        if keepyear:
            dt = dt.replace(month=1)
        ts = dt.timestamp()
        offset = '+0000'
    else:
        dt = parse_target_date(date)
        ts = int(dt.timestamp())
        if dt.utcoffset():
            offset_seconds = int(dt.utcoffset().total_seconds())
            offset_sign = '+' if offset_seconds >= 0 else '-'
            offset_abs = abs(offset_seconds)
            offset_hours = offset_abs // 3600
            offset_mins = (offset_abs % 3600) // 60
            offset = '%s%02d%02d' % (offset_sign, offset_hours, offset_mins)
        else:
            offset = '+0000'

    date_encoded = b'%d %s' % (ts, offset.encode())
    author_date = date_encoded
    committer_date = date_encoded

# don't rewrite history, just pretend
if dryrun:
    f = open(dryrun_file, 'a')
    f.write('Commit:')

    an = commit.author_name.decode()
    ae = commit.author_email.decode()
    ad = parse_git_date(commit.author_date).isoformat()
    new_an = author_name.decode()
    new_ae = author_email.decode()
    new_ad = parse_git_date(author_date).isoformat()

    cn = commit.committer_name.decode()
    ce = commit.committer_email.decode()
    cd = parse_git_date(commit.committer_date).isoformat()
    new_cn = committer_name.decode()
    new_ce = committer_email.decode()
    new_cd = parse_git_date(committer_date).isoformat()

    id = commit.original_id.decode()
    msg = commit.message.decode()
    sep = '\n' + '-' * 80 + '\n'

    f.write('%s\n' % id)
    f.write('Author:\t\t%s <%s> -> %s <%s> \n' % (an, ae, new_an, new_ae))
    f.write('Committer:\t%s <%s> -> %s <%s> \n' % (cn, ce, new_cn, new_ce))
    f.write('AuthorDate:\t%s -> %s\n' % (ad, new_ad))
    f.write('CommitterDate:\t%s -> %s\n' % (cd, new_cd))
    f.write('\n')
    f.write(msg)
    f.write(sep)
    f.close()
    return

# actually rewrite history
commit.author_name = author_name
commit.author_email = author_email
commit.author_date = author_date
commit.committer_name = committer_name
commit.committer_email = committer_email
commit.committer_date = committer_date
"

# Runs git-filter-repo with the callback above. filter_repo_log (like
# dryrun_file) is a global the EXIT trap (cleanup_on_exit) removes, on this
# function's failure exit or any later one.
run_filter_repo() {
    filter_repo_log=$(mktemp)
    if ! git filter-repo --force --commit-callback "$python_commit_callback" --refs HEAD >"$filter_repo_log" 2>&1; then
        printf 'Error: git filter-repo failed:\n' >&2
        cat "$filter_repo_log" >&2
        exit 1
    fi
}

# Prints the dry-run preview (via $PAGER, falling back to cat) or the final
# success message. dryrun_file itself is removed by the EXIT trap
# (cleanup_on_exit), not here.
print_result() {
    if [[ "$ANON_GIT_DRYRUN" == '1' && -f "$dryrun_file" ]]; then
        local pager=${PAGER:-cat}
        command "$pager" "$dryrun_file"
    elif [[ "$ANON_GIT_QUIET" != '1' ]]; then
        printf 'Done. History has been rewritten.\n'
    fi
}

# ──────────────────────────────────────────────────────────────────────
# MAIN

main() {
    handle_early_options "$@"
    safety_checks
    read_git_config
    parse_args "$@"
    reject_incompatible_options
    merge_args_with_defaults
    validate_final_options
    require_target
    verbose_info
    confirm
    backup_branch
    clean_cache
    setup_dryrun
    export_rewrite_env
    run_filter_repo
    print_result
}

main "$@"
