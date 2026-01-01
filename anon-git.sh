#!/usr/bin/env bash

set -euo pipefail

# Bumped by hand; not tied to git tags.
ANON_GIT_VERSION='0.1.0'

DEFAULT_NAME='Anon'
DEFAULT_EMAIL='anon@localhost'
DEFAULT_DATE='2008-10-31 00:00:00 +0000'
DEFAULT_KEEPUSER='0'
DEFAULT_KEEPDATE='0'
DEFAULT_KEEPYEAR='0'
DEFAULT_KEEPMONTH='0'
DEFAULT_KEEPDAY='0'
DEFAULT_RANDOMTIME='0'
DEFAULT_RANDOMDAY='0'
DEFAULT_RANDOMMONTH='0'
DEFAULT_STRIPTIMEZONE='0'
DEFAULT_ENTIREHISTORY='0'
DEFAULT_CURRENTBRANCH='0'
DEFAULT_DRYRUN='0'
DEFAULT_QUIET='0'

# Scratch files removed by the EXIT trap (cleanup_on_exit) so a kill mid-run
# doesn't leave them behind. Declared empty so the trap is safe before
# setup_dryrun/run_filter_repo populate them.
dryrun_file=''
filter_repo_log=''
random_dates_file=''

cleanup_on_exit() {
    if [[ -n "$dryrun_file" && -f "$dryrun_file" ]]; then
        rm -f "$dryrun_file"
    fi
    if [[ -n "$filter_repo_log" && -f "$filter_repo_log" ]]; then
        rm -f "$filter_repo_log"
    fi
    if [[ -n "$random_dates_file" && -f "$random_dates_file" ]]; then
        rm -f "$random_dates_file"
    fi
}
trap cleanup_on_exit EXIT

# ──────────────────────────────────────────────────────────────────────
# HELP
#
# Defined first so `--help` works even outside a git repo or with a dirty
# working tree.

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
                                   defaults to \$SHELL) and exit
  --install                        Copy this script to ~/.local/bin and/or ~/.bin
                                   (whichever exist) and warn if neither is on \$PATH
  --install-system                 Copy this script system-wide to /usr/bin (via sudo)
  --install-hook                   Install a post-commit hook in the current git repository
                                   that anonymizes each new commit (HEAD only) automatically
  --uninstall                      Remove this script from ~/.local/bin, ~/.bin, and
                                   /usr/bin (wherever --install/--install-system put it)
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

    # Keep the commit year, randomize month/day/time; commits keep their
    # relative order (a later commit never lands earlier than an earlier one)
    ./anon-git.sh --random-month --entire-history

    # Used alone: keep author and date/time as-is, only force the timezone
    # offset to UTC+0000 (hides where the committer is, keeps everything else)
    ./anon-git.sh --strip-timezone HEAD

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

    # Remove this script from wherever --install/--install-system put it
    ./anon-git.sh --uninstall

    # Remove the post-commit hook installed by --install-hook
    ./anon-git.sh --uninstall-hook
EOF
    exit 0
}

show_version() {
    printf 'anon-git %s\n' "$ANON_GIT_VERSION"
    exit 0
}

# Internal/undocumented: single source of truth for the flag list, so
# completion scripts don't hardcode it and drift out of sync. Value-taking
# flags end in "=".
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
--random-time
--random-day
--random-month
--strip-timezone
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
--uninstall
--uninstall-hook
EOF
    exit 0
}

# Internal: completion scripts are static files shipped in completions/,
# not generated; this resolves the shell name (defaulting to $SHELL) and
# cats the matching file.
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

# Internal: resolves to an absolute path regardless of how the script was
# invoked (./anon-git.sh, a $PATH lookup, ...), for the install functions below.
script_path() {
    local script_dir
    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)
    printf '%s/%s\n' "$script_dir" "$(basename -- "${BASH_SOURCE[0]:-$0}")"
}

# Internal: copies $1 to $2/anon-git, warns if $2 isn't on $PATH. Returns
# non-zero instead of exiting, so install_user can try every candidate dir.
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

# --install: copies to ~/.local/bin and/or ~/.bin, whichever already exist
# (neither is created).
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

# Marks hooks this script generated, so install_hook can refresh them
# without clobbering a hook the user wrote themselves.
HOOK_MARKER='# Installed by anon-git --install-hook'

# --install-hook: installs a post-commit hook that re-anonymizes HEAD in
# place after every commit, with --no-backup (would accumulate one branch
# per commit) and --quiet. Warns but still installs if core.hooksPath is
# set, since git would look there instead and the hook would never fire.
install_hook() {
    local git_dir hooks_dir hook_file src hooks_path

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

    # Still installs at the standard location so it stays idempotent and the
    # file is there for manual relocation.
    hooks_path=$(git config --get core.hooksPath 2>/dev/null || true)
    if [[ -n "$hooks_path" ]]; then
        printf 'Warning: core.hooksPath is set to "%s"; git looks there for hooks, not %s.\n' "$hooks_path" "$hooks_dir" >&2
        printf '  This hook will not fire until you either unset core.hooksPath or\n' >&2
        printf '  move/symlink %s into "%s" yourself.\n' "$hook_file" "$hooks_path" >&2
    fi

    src=$(script_path)
    mkdir -p "$hooks_dir"
    cat >"$hook_file" <<EOF
#!/usr/bin/env bash
$HOOK_MARKER
#
# Anonymizes the just-created commit (HEAD) after every \`git commit\`.
# --no-backup avoids accumulating a branch per commit (use \`git reflog\`/
# \`git reset\` to recover). --quiet drops the per-commit output; pass
# --verbose to bring it back. Regenerate with: $src --install-hook

set -e
"$src" --no-confirm --no-backup --quiet --current-branch HEAD
EOF
    chmod +x "$hook_file"
    printf 'Installed post-commit hook: %s\n' "$hook_file"
    exit 0
}

# Internal: removes $1/anon-git if present. Unlike install_copy, a missing
# target is not a failure -- uninstalling is idempotent.
uninstall_copy() {
    local dir="$1" target="${1}/anon-git"

    if [[ ! -e "$target" ]]; then
        return 0
    fi

    if ! rm -f -- "$target"; then
        printf 'Error: failed to remove %s\n' "$target" >&2
        return 1
    fi
    printf 'Removed: %s\n' "$target"
    return 0
}

# --uninstall: removes this script from every location --install/
# --install-system may have copied it to. Finding nothing installed is not
# an error; only an actual removal failure is.
uninstall_all() {
    local candidates=("${HOME}/.local/bin" "${HOME}/.bin") dir found=0 failures=0
    local system_target='/usr/bin/anon-git'

    for dir in "${candidates[@]}"; do
        if [[ -e "${dir}/anon-git" ]]; then
            found=1
            uninstall_copy "$dir" || failures=$((failures + 1))
        fi
    done

    if [[ -e "$system_target" ]]; then
        found=1
        if ! command -v sudo >/dev/null 2>&1; then
            printf 'Error: sudo not found; cannot remove %s\n' "$system_target" >&2
            failures=$((failures + 1))
        elif ! sudo rm -f -- "$system_target"; then
            printf 'Error: failed to remove %s\n' "$system_target" >&2
            failures=$((failures + 1))
        else
            printf 'Removed: %s\n' "$system_target"
        fi
    fi

    if [[ "$found" -eq 0 ]]; then
        printf 'anon-git is not installed in ~/.local/bin, ~/.bin, or /usr/bin.\n'
        exit 0
    fi

    [[ "$failures" -eq 0 ]] && exit 0
    exit 1
}

# --uninstall-hook: guarded by the same HOOK_MARKER check install_hook uses,
# so a hook this script didn't create is never touched.
uninstall_hook() {
    local git_dir hooks_dir hook_file

    if ! git_dir=$(git rev-parse --git-dir 2>/dev/null); then
        printf 'Error: --uninstall-hook must be run inside a git repository.\n' >&2
        exit 1
    fi
    git_dir=$(cd -- "$git_dir" && pwd)
    hooks_dir="${git_dir}/hooks"
    hook_file="${hooks_dir}/post-commit"

    if [[ ! -f "$hook_file" ]]; then
        printf 'No post-commit hook installed at %s\n' "$hook_file"
        exit 0
    fi

    if ! grep -qF "$HOOK_MARKER" "$hook_file"; then
        printf 'Error: %s was not installed by anon-git; refusing to remove it.\n' "$hook_file" >&2
        printf '  Remove it yourself if you are sure.\n' >&2
        exit 1
    fi

    if ! rm -f -- "$hook_file"; then
        printf 'Error: failed to remove %s\n' "$hook_file" >&2
        exit 1
    fi
    printf 'Removed post-commit hook: %s\n' "$hook_file"
    exit 0
}

# ──────────────────────────────────────────────
# EARLY OPTIONS
#
# Handled before any git-repo/safety checks, so these work even outside a
# git repository or with a dirty working tree.
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
        --uninstall) uninstall_all ;;
        --uninstall-hook) uninstall_hook ;;
        esac
    done
}

# Internal: dies unless inside a git repo with a clean working tree and
# git-filter-repo available. Everything after this can assume a usable repo.
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

# Internal: reads git config anon-git.<key>, normalized to '1'/'0', or
# prints nothing if unset. An unparseable value is a hard error rather than
# silently ignored, since a typo'd config shouldn't fail open.
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

# Reads `git config anon-git.*` into the GITCONFIG_* globals, ranked above
# envvars and below flags. Excludes --entire-history/--current-branch/
# --dry-run: a silent default for those would be too destructive.
read_git_config() {
    GITCONFIG_NAME=$(git config --get anon-git.name 2>/dev/null || true)
    GITCONFIG_EMAIL=$(git config --get anon-git.email 2>/dev/null || true)
    GITCONFIG_DATE=$(git config --get anon-git.date 2>/dev/null || true)
    GITCONFIG_KEEPUSER=$(read_git_config_bool anon-git.keepuser)
    GITCONFIG_KEEPDATE=$(read_git_config_bool anon-git.keepdate)
    GITCONFIG_KEEPYEAR=$(read_git_config_bool anon-git.keepyear)
    GITCONFIG_KEEPMONTH=$(read_git_config_bool anon-git.keepmonth)
    GITCONFIG_KEEPDAY=$(read_git_config_bool anon-git.keepday)
    GITCONFIG_RANDOMTIME=$(read_git_config_bool anon-git.randomtime)
    GITCONFIG_RANDOMDAY=$(read_git_config_bool anon-git.randomday)
    GITCONFIG_RANDOMMONTH=$(read_git_config_bool anon-git.randommonth)
    GITCONFIG_STRIPTIMEZONE=$(read_git_config_bool anon-git.striptimezone)
    GITCONFIG_QUIET=$(read_git_config_bool anon-git.quiet)
}

# Internal: parses "$@" into the *_ARG globals, later merged with ANON_GIT_*
# envvars and DEFAULT_* fallbacks. Empty string means "not provided via flag".
parse_args() {
    DATE_ARG=""
    NAME_ARG=""
    EMAIL_ARG=""
    KEEPUSER_ARG=""
    KEEPDATE_ARG=""
    KEEPYEAR_ARG=""
    KEEPMONTH_ARG=""
    KEEPDAY_ARG=""
    RANDOMTIME_ARG=""
    RANDOMDAY_ARG=""
    RANDOMMONTH_ARG=""
    STRIPTIMEZONE_ARG=""
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
        --random-time)
            RANDOMTIME_ARG='1'
            shift
            ;;
        --random-day)
            RANDOMDAY_ARG='1'
            shift
            ;;
        --random-month)
            RANDOMMONTH_ARG='1'
            shift
            ;;
        --strip-timezone)
            STRIPTIMEZONE_ARG='1'
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

# Rejects mutually-exclusive options regardless of whether each side came
# from a CLI flag, repo-local config, or its envvar. Must run before
# merge_args_with_defaults overwrites these envvar names with the
# fully-resolved value, so an unset envvar still reads as empty.
reject_incompatible_options() {
    local date_set name_set email_set
    local keepuser_set keepdate_set keepyear_set keepmonth_set keepday_set
    local randomtime_set randomday_set randommonth_set

    flag_errors=0

    date_set="${DATE_ARG:-${GITCONFIG_DATE:-${ANON_GIT_DATE:-}}}"
    name_set="${NAME_ARG:-${GITCONFIG_NAME:-${ANON_GIT_NAME:-}}}"
    email_set="${EMAIL_ARG:-${GITCONFIG_EMAIL:-${ANON_GIT_EMAIL:-}}}"
    keepuser_set="$KEEPUSER_ARG"
    keepdate_set="$KEEPDATE_ARG"
    keepyear_set="$KEEPYEAR_ARG"
    keepmonth_set="$KEEPMONTH_ARG"
    keepday_set="$KEEPDAY_ARG"
    randomtime_set="$RANDOMTIME_ARG"
    randomday_set="$RANDOMDAY_ARG"
    randommonth_set="$RANDOMMONTH_ARG"
    [[ "${ANON_GIT_KEEPUSER:-}" == '1' ]] && keepuser_set='1'
    [[ "${ANON_GIT_KEEPDATE:-}" == '1' ]] && keepdate_set='1'
    [[ "${ANON_GIT_KEEPYEAR:-}" == '1' ]] && keepyear_set='1'
    [[ "${ANON_GIT_KEEPMONTH:-}" == '1' ]] && keepmonth_set='1'
    [[ "${ANON_GIT_KEEPDAY:-}" == '1' ]] && keepday_set='1'
    [[ "${ANON_GIT_RANDOMTIME:-}" == '1' ]] && randomtime_set='1'
    [[ "${ANON_GIT_RANDOMDAY:-}" == '1' ]] && randomday_set='1'
    [[ "${ANON_GIT_RANDOMMONTH:-}" == '1' ]] && randommonth_set='1'
    [[ "${GITCONFIG_KEEPUSER:-}" == '1' ]] && keepuser_set='1'
    [[ "${GITCONFIG_KEEPDATE:-}" == '1' ]] && keepdate_set='1'
    [[ "${GITCONFIG_KEEPYEAR:-}" == '1' ]] && keepyear_set='1'
    [[ "${GITCONFIG_KEEPMONTH:-}" == '1' ]] && keepmonth_set='1'
    [[ "${GITCONFIG_KEEPDAY:-}" == '1' ]] && keepday_set='1'
    [[ "${GITCONFIG_RANDOMTIME:-}" == '1' ]] && randomtime_set='1'
    [[ "${GITCONFIG_RANDOMDAY:-}" == '1' ]] && randomday_set='1'
    [[ "${GITCONFIG_RANDOMMONTH:-}" == '1' ]] && randommonth_set='1'

    check_incompatible --keep-user "$keepuser_set" --name "$name_set"
    check_incompatible --keep-user "$keepuser_set" --email "$email_set"
    check_incompatible --date "$date_set" --keep-date "$keepdate_set"
    check_incompatible --date "$date_set" --keep-year "$keepyear_set"
    check_incompatible --date "$date_set" --keep-month "$keepmonth_set"
    check_incompatible --date "$date_set" --keep-day "$keepday_set"
    check_incompatible --date "$date_set" --random-time "$randomtime_set"
    check_incompatible --date "$date_set" --random-day "$randomday_set"
    check_incompatible --date "$date_set" --random-month "$randommonth_set"
    check_incompatible --keep-date "$keepdate_set" --keep-year "$keepyear_set"
    check_incompatible --keep-date "$keepdate_set" --keep-month "$keepmonth_set"
    check_incompatible --keep-date "$keepdate_set" --keep-day "$keepday_set"
    check_incompatible --keep-date "$keepdate_set" --random-time "$randomtime_set"
    check_incompatible --keep-date "$keepdate_set" --random-day "$randomday_set"
    check_incompatible --keep-date "$keepdate_set" --random-month "$randommonth_set"
    check_incompatible --keep-year "$keepyear_set" --keep-month "$keepmonth_set"
    check_incompatible --keep-year "$keepyear_set" --keep-day "$keepday_set"
    check_incompatible --keep-month "$keepmonth_set" --keep-day "$keepday_set"
    # random-* and keep-year/-month/-day both dictate a fill strategy (zero
    # vs. random) for the unkept fields, so cross-pairing is a real conflict.
    check_incompatible --keep-year "$keepyear_set" --random-time "$randomtime_set"
    check_incompatible --keep-year "$keepyear_set" --random-day "$randomday_set"
    check_incompatible --keep-year "$keepyear_set" --random-month "$randommonth_set"
    check_incompatible --keep-month "$keepmonth_set" --random-time "$randomtime_set"
    check_incompatible --keep-month "$keepmonth_set" --random-day "$randomday_set"
    check_incompatible --keep-month "$keepmonth_set" --random-month "$randommonth_set"
    check_incompatible --keep-day "$keepday_set" --random-time "$randomtime_set"
    check_incompatible --keep-day "$keepday_set" --random-day "$randomday_set"
    check_incompatible --keep-day "$keepday_set" --random-month "$randommonth_set"
    # Three granularities of the same thing: only one at a time.
    check_incompatible --random-time "$randomtime_set" --random-day "$randomday_set"
    check_incompatible --random-time "$randomtime_set" --random-month "$randommonth_set"
    check_incompatible --random-day "$randomday_set" --random-month "$randommonth_set"
    # CLI-only: no ANON_GIT_COMMIT envvar exists.
    check_incompatible "commit(s) argument" "$COMMIT_ARG" --entire-history "$ENTIREHISTORY_ARG"
    # Not a real conflict: `ANON_GIT_QUIET=1 --verbose` is the intended way to
    # un-silence a quiet default for one run.
    check_incompatible --quiet "$QUIET_ARG" --verbose "$VERBOSE_ARG"

    [[ "$flag_errors" -ne 0 ]] && exit 1
    return 0
}

# Internal: merges flags > repo-local git config > ANON_GIT_* envvars >
# DEFAULT_* fallbacks into the final ANON_GIT_* globals used from here on.
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
    ANON_GIT_RANDOMTIME="${RANDOMTIME_ARG:-${GITCONFIG_RANDOMTIME:-${ANON_GIT_RANDOMTIME:-${DEFAULT_RANDOMTIME}}}}"
    ANON_GIT_RANDOMDAY="${RANDOMDAY_ARG:-${GITCONFIG_RANDOMDAY:-${ANON_GIT_RANDOMDAY:-${DEFAULT_RANDOMDAY}}}}"
    ANON_GIT_RANDOMMONTH="${RANDOMMONTH_ARG:-${GITCONFIG_RANDOMMONTH:-${ANON_GIT_RANDOMMONTH:-${DEFAULT_RANDOMMONTH}}}}"
    ANON_GIT_STRIPTIMEZONE="${STRIPTIMEZONE_ARG:-${GITCONFIG_STRIPTIMEZONE:-${ANON_GIT_STRIPTIMEZONE:-${DEFAULT_STRIPTIMEZONE}}}}"
    ANON_GIT_ENTIREHISTORY="${ENTIREHISTORY_ARG:-${ANON_GIT_ENTIREHISTORY:-${DEFAULT_ENTIREHISTORY}}}"
    ANON_GIT_CURRENTBRANCH="${CURRENTBRANCH_ARG:-${ANON_GIT_CURRENTBRANCH:-${DEFAULT_CURRENTBRANCH}}}"
    ANON_GIT_COMMIT="${COMMIT_ARG:-${DEFAULT_COMMIT}}"
    ANON_GIT_DRYRUN="${DRYRUN_ARG:-${ANON_GIT_DRYRUN:-${DEFAULT_DRYRUN}}}"
    ANON_GIT_QUIET="${QUIET_ARG:-${GITCONFIG_QUIET:-${ANON_GIT_QUIET:-${DEFAULT_QUIET}}}}"
    # --verbose always wins over whatever set ANON_GIT_QUIET above.
    if [[ "$VERBOSE_ARG" == '1' ]]; then
        ANON_GIT_QUIET='0'
    fi
}

# Internal: --strip-timezone alone implicitly behaves like --keep-user
# --keep-date for that run (the python commit-callback still does the
# offset rewrite). Any other CLI flag opts back into normal precedence.
# Only the *_ARG (CLI-only) globals count -- repo config/envvars don't.
apply_strip_timezone_alone() {
    if [[ "$STRIPTIMEZONE_ARG" == '1' && -z "$DATE_ARG" && -z "$NAME_ARG" && -z "$EMAIL_ARG" &&
        -z "$KEEPUSER_ARG" && -z "$KEEPDATE_ARG" &&
        -z "$KEEPYEAR_ARG" && -z "$KEEPMONTH_ARG" && -z "$KEEPDAY_ARG" &&
        -z "$RANDOMTIME_ARG" && -z "$RANDOMDAY_ARG" && -z "$RANDOMMONTH_ARG" ]]; then
        ANON_GIT_KEEPUSER='1'
        ANON_GIT_KEEPDATE='1'
    fi
}

# Internal: without a commit target or --entire-history, show help instead
# of silently defaulting to HEAD.
require_target() {
    if [[ -z "$COMMIT_ARG" && "$ANON_GIT_ENTIREHISTORY" != '1' ]]; then
        show_help
    fi
}

validate_bool() {
    local name="$1" value="$2"
    if [[ "$value" != '0' && "$value" != '1' ]]; then
        printf 'Error: %s must resolve to "0" or "1" (got "%s")\n' "$name" "$value" >&2
        exit 1
    fi
}

# Sanity-checks the resolved ANON_GIT_* booleans (a stray envvar could have
# produced a bogus value) before anything acts on them.
validate_final_options() {
    validate_bool ANON_GIT_KEEPUSER "$ANON_GIT_KEEPUSER"
    validate_bool ANON_GIT_KEEPDATE "$ANON_GIT_KEEPDATE"
    validate_bool ANON_GIT_KEEPYEAR "$ANON_GIT_KEEPYEAR"
    validate_bool ANON_GIT_KEEPMONTH "$ANON_GIT_KEEPMONTH"
    validate_bool ANON_GIT_KEEPDAY "$ANON_GIT_KEEPDAY"
    validate_bool ANON_GIT_RANDOMTIME "$ANON_GIT_RANDOMTIME"
    validate_bool ANON_GIT_RANDOMDAY "$ANON_GIT_RANDOMDAY"
    validate_bool ANON_GIT_RANDOMMONTH "$ANON_GIT_RANDOMMONTH"
    validate_bool ANON_GIT_STRIPTIMEZONE "$ANON_GIT_STRIPTIMEZONE"
    validate_bool ANON_GIT_ENTIREHISTORY "$ANON_GIT_ENTIREHISTORY"
    validate_bool ANON_GIT_CURRENTBRANCH "$ANON_GIT_CURRENTBRANCH"
    validate_bool ANON_GIT_DRYRUN "$ANON_GIT_DRYRUN"
    validate_bool ANON_GIT_QUIET "$ANON_GIT_QUIET"
}

# Prints a summary, gated on flags explicitly passed on the CLI (not the
# resolved envvar/default), so e.g. ANON_GIT_KEEPUSER in a shell profile
# doesn't spam this on every run.
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
        printf 'Not overwriting user/email.\n'
    fi
    if [[ -n "$KEEPDATE_ARG" ]]; then
        printf 'Not overwriting date.\n'
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
    if [[ -n "$RANDOMTIME_ARG" ]]; then
        printf 'Randomizing time only (keeping commit date year, month and day), preserving relative commit order.\n'
    fi
    if [[ -n "$RANDOMDAY_ARG" ]]; then
        printf 'Randomizing day and time (keeping commit date year and month), preserving relative commit order.\n'
    fi
    if [[ -n "$RANDOMMONTH_ARG" ]]; then
        printf 'Randomizing month, day and time (keeping commit date year), preserving relative commit order.\n'
    fi
    if [[ -n "$STRIPTIMEZONE_ARG" ]]; then
        printf 'Forcing timezone offset to UTC+0000 (date/time digits unchanged).\n'
    fi
    printf '\n'
}

# Creates a new branch (default) or a backup branch (--current-branch,
# unless --no-backup) so pre-rewrite history stays reachable. No-op under
# --dry-run.
backup_branch() {
    local current_branch branch_label timestamp new_branch backup_branch_name switch_target

    current_branch=$(git branch --show-current)
    if [[ -z "$current_branch" && "$ANON_GIT_CURRENTBRANCH" == '1' ]]; then
        printf 'Error: HEAD is detached, so there is no current branch to overwrite. Drop --current-branch or check out a branch first.\n' >&2
        exit 1
    fi
    branch_label="${current_branch:-detached-$(git rev-parse --short HEAD)}"
    # Colon-free (git ref names disallow ":"); PID + $RANDOM suffix for
    # uniqueness within the same second, avoiding GNU-only date %N.
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

# Skipped for --no-confirm or --dry-run (nothing is touched either way).
confirm() {
    if [[ "$NOCONFIRM_ARG" != '1' && "$ANON_GIT_DRYRUN" != '1' ]]; then
        read -p "Continue? (y/N) " -n 1 -r
        printf '\n'
        [[ $REPLY =~ ^[Yy]$ ]] || exit 1
    fi
}

# git-filter-repo caches metadata in .git/filter-repo/ to reuse across runs,
# but reusing it after certain repo state changes hits a known assertion bug
# in the tool. Removing it forces a clean run each time.
clean_cache() {
    if [[ -d "$PWD/.git/filter-repo" ]]; then
        rm -rf "$PWD/.git/filter-repo"
    fi
}

# Internal: creates the scratch file the Python commit-callback writes its
# --dry-run preview to (shared via ANON_GIT_DRYRUN_FILE). Removed by the
# EXIT trap (cleanup_on_exit).
setup_dryrun() {
    if [[ "${ANON_GIT_DRYRUN}" -eq 1 ]]; then
        dryrun_file=$(mktemp)
    fi
}

# ──────────────────────────────────────────────────────────────────────
# REWRITE LOGIC

# Passed via environment rather than string-interpolated into the generated
# source, so a name/email/date with a quote or other Python-special
# character can't break out of a string literal and inject code.
export_rewrite_env() {
    export ANON_GIT_NAME ANON_GIT_EMAIL ANON_GIT_DATE ANON_GIT_COMMIT
    export ANON_GIT_KEEPUSER ANON_GIT_KEEPDATE ANON_GIT_KEEPYEAR ANON_GIT_KEEPMONTH ANON_GIT_KEEPDAY
    export ANON_GIT_RANDOMTIME ANON_GIT_RANDOMDAY ANON_GIT_RANDOMMONTH
    export ANON_GIT_RANDOM_DATES_FILE="${random_dates_file}"
    export ANON_GIT_STRIPTIMEZONE
    export ANON_GIT_ENTIREHISTORY ANON_GIT_DRYRUN
    export ANON_GIT_DRYRUN_FILE="${dryrun_file}"
    export TZ=UTC
}

# Precomputes one random timestamp per target commit for --random-time/-day/
# -month: reads full history from stdin (oldest to newest), tags each commit
# target/anchor/ignored, buckets by the fixed calendar unit, and assigns each
# bucket's runs random timestamps bounded by their nearest anchor, preserving
# relative order. Prints "<hash> <epoch> +0000" lines, targets only. Kept as
# a plain top-level assignment: the test suite locates it by its exact,
# unindented `python_compute_random_dates="` ... `"` line anchors.
python_compute_random_dates="
import os
import random
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

granularity = 'time-of-day'
if os.environ.get('ANON_GIT_RANDOMMONTH') == '1':
    granularity = 'month'
elif os.environ.get('ANON_GIT_RANDOMDAY') == '1':
    granularity = 'day-of-month'

entirehistory = os.environ.get('ANON_GIT_ENTIREHISTORY') == '1'
target_hashes = set(os.environ.get('ANON_GIT_TARGET_COMMITS', '').split())

def bucket_bounds(dt):
    # dt: UTC-aware original commit date. Returns (bucket key, start epoch, end epoch).
    if granularity == 'month':
        key = (dt.year,)
        start = datetime(dt.year, 1, 1, tzinfo=timezone.utc)
        end = datetime(dt.year, 12, 31, 23, 59, 59, tzinfo=timezone.utc)
    elif granularity == 'day-of-month':
        key = (dt.year, dt.month)
        start = datetime(dt.year, dt.month, 1, tzinfo=timezone.utc)
        if dt.month == 12:
            next_month_start = datetime(dt.year + 1, 1, 1, tzinfo=timezone.utc)
        else:
            next_month_start = datetime(dt.year, dt.month + 1, 1, tzinfo=timezone.utc)
        end = next_month_start - timedelta(seconds=1)
    else:
        key = (dt.year, dt.month, dt.day)
        start = datetime(dt.year, dt.month, dt.day, tzinfo=timezone.utc)
        end = start + timedelta(hours=23, minutes=59, seconds=59)
    return key, int(start.timestamp()), int(end.timestamp())

history = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    commit_hash, epoch_str = line.split()
    history.append((commit_hash, int(epoch_str)))

if entirehistory:
    roles = ['target'] * len(history)
else:
    roles = []
    for i, (commit_hash, _epoch) in enumerate(history):
        if commit_hash in target_hashes:
            roles.append('target')
        else:
            before_is_target = i > 0 and history[i - 1][0] in target_hashes
            after_is_target = i + 1 < len(history) and history[i + 1][0] in target_hashes
            roles.append('anchor' if (before_is_target or after_is_target) else 'skip')

buckets = defaultdict(list)
bounds = {}

for (commit_hash, epoch), role in zip(history, roles):
    if role == 'skip':
        continue
    dt = datetime.fromtimestamp(epoch, tz=timezone.utc)
    key, start, end = bucket_bounds(dt)
    buckets[key].append((epoch, commit_hash, role))
    bounds[key] = (start, end)

for key, members in buckets.items():
    bucket_start, bucket_end = bounds[key]
    members.sort()

    i = 0
    member_count = len(members)
    lower = bucket_start
    while i < member_count:
        epoch, commit_hash, role = members[i]
        if role == 'anchor':
            lower = epoch + 1
            i += 1
            continue
        run_start = i
        while i < member_count and members[i][2] == 'target':
            i += 1
        run = members[run_start:i]
        upper = members[i][0] - 1 if i < member_count else bucket_end
        count = len(run)
        span = upper - lower
        if span < 0:
            # No room between anchors (e.g. two real commits one second
            # apart with a target sandwiched between). Fall back to a shared
            # timestamp -- git allows identical author dates.
            picks = [lower] * count
        elif count <= span + 1:
            picks = sorted(random.sample(range(lower, upper + 1), count))
        else:
            picks = sorted(random.randint(lower, upper) for _ in range(count))
        for (_original_epoch, member_hash, _role), new_epoch in zip(run, picks):
            print('%s %d +0000' % (member_hash, new_epoch))
"

# Internal: only runs for --random-time/-day/-month. Feeds
# python_compute_random_dates the full history plus which commits are
# targets, producing the lookup file python_commit_callback reads
# (ANON_GIT_RANDOM_DATES_FILE). Removed by the EXIT trap (cleanup_on_exit).
setup_random_dates() {
    if [[ "$ANON_GIT_RANDOMTIME" != '1' && "$ANON_GIT_RANDOMDAY" != '1' && "$ANON_GIT_RANDOMMONTH" != '1' ]]; then
        return
    fi

    random_dates_file=$(mktemp)

    if ! git log --reverse --format='%H %at' HEAD |
        ANON_GIT_RANDOMTIME="$ANON_GIT_RANDOMTIME" ANON_GIT_RANDOMDAY="$ANON_GIT_RANDOMDAY" ANON_GIT_RANDOMMONTH="$ANON_GIT_RANDOMMONTH" \
            ANON_GIT_ENTIREHISTORY="$ANON_GIT_ENTIREHISTORY" ANON_GIT_TARGET_COMMITS="$ANON_GIT_COMMIT" \
            python3 -c "$python_compute_random_dates" >"$random_dates_file"; then
        printf 'Error: failed to compute randomized commit dates\n' >&2
        exit 1
    fi
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
randomtime = os.environ['ANON_GIT_RANDOMTIME'] == '1'
randomday = os.environ['ANON_GIT_RANDOMDAY'] == '1'
randommonth = os.environ['ANON_GIT_RANDOMMONTH'] == '1'
striptimezone = os.environ['ANON_GIT_STRIPTIMEZONE'] == '1'
entirehistory = os.environ['ANON_GIT_ENTIREHISTORY'] == '1'
dryrun = os.environ['ANON_GIT_DRYRUN'] == '1'
dryrun_file = os.environ.get('ANON_GIT_DRYRUN_FILE', '')

# Loaded once: module-level state persists across every commit-callback
# invocation within this filter-repo run, so no need to re-read per commit.
if 'RANDOM_DATES' not in globals():
    RANDOM_DATES = {}
    random_dates_file = os.environ.get('ANON_GIT_RANDOM_DATES_FILE', '')
    if random_dates_file:
        with open(random_dates_file, 'rb') as random_dates_fh:
            for random_dates_line in random_dates_fh:
                random_dates_parts = random_dates_line.split()
                if len(random_dates_parts) == 3:
                    RANDOM_DATES[random_dates_parts[0]] = b'%s %s' % (random_dates_parts[1], random_dates_parts[2])

author_name = commit.author_name
author_email = commit.author_email
author_date = commit.author_date
committer_name = commit.committer_name
committer_email = commit.committer_email
committer_date = commit.committer_date

if not entirehistory and commit.original_id not in target_commits:
    return

def parse_git_date(date_bytes):
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
    # Also accepts ISO 8601 compact form (e.g. '2025-06-15T14:20:00Z'),
    # normalized to the space-separated, 4-digit-offset form '%z' expects.
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
    if randomtime or randomday or randommonth:
        # setup_random_dates already computed this commit's randomized date;
        # just look it up by commit hash.
        random_date = RANDOM_DATES.get(commit.original_id)
        if random_date is None:
            raise SystemExit(
                'anon-git: no precomputed random date for commit %s' % commit.original_id.decode()
            )
        dt = parse_git_date(random_date)
        ts = int(dt.timestamp())
        offset = '+0000'
    elif keepyear or keepmonth or keepday:
        # Strip the timezone (keeping the calendar date as seen) and
        # re-anchor to midnight UTC, so only time/tz leak. TZ=UTC above
        # makes the naive dt.timestamp() below UTC.
        dt = parse_git_date(commit.author_date)
        dt = dt.replace(tzinfo=None, hour=0, minute=0, second=0, microsecond=0)
        if keepyear or keepmonth:
            dt = dt.replace(day=1)
        if keepyear:
            dt = dt.replace(month=1)
        ts = dt.timestamp()
        offset = '+0000'
    elif striptimezone:
        # Keep the date/time digits from --date, relabel (not convert) the
        # offset to +0000 -- same reinterpret-as-UTC trick as above, without
        # zeroing the smaller fields.
        dt = parse_target_date(date)
        dt = dt.replace(tzinfo=None)
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
elif striptimezone:
    # --keep-date leaves digits untouched, but --strip-timezone still relabels
    # each field's offset to +0000, computed per author/committer
    # independently (they can differ, e.g. after a rebase).
    author_dt = parse_git_date(commit.author_date).replace(tzinfo=None)
    author_date = b'%d +0000' % (int(author_dt.timestamp()),)
    committer_dt = parse_git_date(commit.committer_date).replace(tzinfo=None)
    committer_date = b'%d +0000' % (int(committer_dt.timestamp()),)

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

commit.author_name = author_name
commit.author_email = author_email
commit.author_date = author_date
commit.committer_name = committer_name
commit.committer_email = committer_email
commit.committer_date = committer_date
"

# filter_repo_log is a global the EXIT trap (cleanup_on_exit) removes.
run_filter_repo() {
    filter_repo_log=$(mktemp)
    if ! git filter-repo --force --commit-callback "$python_commit_callback" --refs HEAD >"$filter_repo_log" 2>&1; then
        printf 'Error: git filter-repo failed:\n' >&2
        cat "$filter_repo_log" >&2
        exit 1
    fi
}

# dryrun_file is removed by the EXIT trap (cleanup_on_exit), not here.
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
    apply_strip_timezone_alone
    validate_final_options
    require_target
    verbose_info
    confirm
    backup_branch
    clean_cache
    setup_dryrun
    setup_random_dates
    export_rewrite_env
    run_filter_repo
    print_result
}

main "$@"
