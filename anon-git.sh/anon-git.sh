#!/usr/bin/env bash

set -euo pipefail

# Bumped by hand; not tied to git tags.
ANON_GIT_VERSION='0.1.0'

DEFAULT_NAME='Anon'
DEFAULT_EMAIL='anon@localhost'
DEFAULT_DATE='2008-10-31 00:00:00 +0000'
# Bool defaults are read indirectly (${!def}), see BOOLS below.
# shellcheck disable=SC2034
{
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
}

# Boolean options: each has a flag (KEEPUSER <-> --keep-user, see
# flag_option), an ANON_GIT_<OPT> envvar and a DEFAULT_<OPT>. CONFIG_BOOLS
# also read git config anon-git.<opt>.
CONFIG_BOOLS=(KEEPUSER KEEPDATE KEEPYEAR KEEPMONTH KEEPDAY RANDOMTIME RANDOMDAY RANDOMMONTH STRIPTIMEZONE QUIET)
BOOLS=("${CONFIG_BOOLS[@]}" ENTIREHISTORY CURRENTBRANCH DRYRUN)

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

# Internal: sets the variable named $1 to a new scratch file. The name is
# stored before the file exists: with `x=$(mktemp)` a kill between file
# creation and assignment would leave a file the EXIT trap can't see.
make_scratch_file() {
    local path
    path=$(mktemp -u)
    printf -v "$1" '%s' "$path"
    # umask 077: the file holds pre-anonymization names, emails and messages.
    (
        set -C
        umask 077
        : >"$path"
    )
}

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
    ./anon-git.sh \$(git log --format=%H --after='2023-01-01' --before='2024-01-01')

    # Anonymize commits where the commit author matches a pattern
    ./anon-git.sh \$(git log --format=%H --author='Frederic')

    # Anonymize commits following the Conventional Commits "fix:" prefix
    ./anon-git.sh \$(git log --format=%H --grep='^fix:')

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

# Where --install/--install-system put completions/, since an installed
# copy has none next to it.
# ${HOME:-}: an unset HOME must not break runs that never install.
USER_DATA_DIR="${HOME:-}/.local/share/anon-git"
SYSTEM_DATA_DIR='/usr/share/anon-git'

# Internal: completion scripts are static files shipped in completions/,
# not generated; this resolves the shell name (defaulting to $SHELL) and
# cats the matching file, from a checkout or an installed copy.
print_completion() {
    local shell="$1" script_dir completions_dir completion_file

    [[ -n "$shell" ]] || shell="${SHELL##*/}"

    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)
    for completions_dir in "${script_dir}/completions" "${USER_DATA_DIR}/completions" "${SYSTEM_DATA_DIR}/completions"; do
        if [[ -d "$completions_dir" ]]; then
            break
        fi
    done
    case "$shell" in
    bash) completion_file="${completions_dir}/anon-git.bash" ;;
    zsh) completion_file="${completions_dir}/_anon-git.sh" ;;
    fish) completion_file="${completions_dir}/anon-git.sh.fish" ;;
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

    # Absent when run from an installed copy; that install already has them.
    if [[ -d "$(dirname -- "$src")/completions" ]]; then
        mkdir -p "$USER_DATA_DIR"
        if cp -R -- "$(dirname -- "$src")/completions" "$USER_DATA_DIR/"; then
            printf 'Installed: %s/completions\n' "$USER_DATA_DIR"
        else
            failures=$((failures + 1))
        fi
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

    if [[ -d "$(dirname -- "$src")/completions" ]]; then
        sudo mkdir -p "$SYSTEM_DATA_DIR"
        sudo cp -R -- "$(dirname -- "$src")/completions" "$SYSTEM_DATA_DIR/"
        printf 'Installed: %s/completions\n' "$SYSTEM_DATA_DIR"
    fi
    exit 0
}

# Marks hooks this script generated, so install_hook can refresh them
# without clobbering a hook the user wrote themselves.
HOOK_MARKER='# Installed by anon-git --install-hook'

# Internal: prints the absolute post-commit hook path git actually runs.
# `--git-path hooks` honors core.hooksPath and resolves to the common dir in
# a linked worktree; a relative result is relative to the top-level dir.
hook_file_path() {
    local top hooks_dir

    top=$(git rev-parse --show-toplevel)
    hooks_dir=$(git -C "$top" rev-parse --git-path hooks)
    if [[ "$hooks_dir" != /* ]]; then
        hooks_dir="${top}/${hooks_dir}"
    fi
    printf '%s/post-commit\n' "$hooks_dir"
}

# Internal: true if $1 is a regular file carrying HOOK_MARKER. A symlink is
# never ours: writing through it would overwrite its target (e.g. a copy of
# this script, which contains the marker text).
hook_is_ours() {
    [[ ! -L "$1" && -f "$1" ]] && grep -qF "$HOOK_MARKER" "$1"
}

# --install-hook: installs a post-commit hook that re-anonymizes HEAD in
# place after every commit, with --no-backup (would accumulate one branch
# per commit) and --quiet.
install_hook() {
    local hook_file src

    if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
        printf 'Error: --install-hook must be run inside a git repository.\n' >&2
        exit 1
    fi
    hook_file=$(hook_file_path)

    if [[ -e "$hook_file" || -L "$hook_file" ]] && ! hook_is_ours "$hook_file"; then
        printf 'Error: %s already exists and was not installed by anon-git.\n' "$hook_file" >&2
        printf '  Remove or back it up first, then re-run --install-hook.\n' >&2
        exit 1
    fi

    src=$(script_path)
    mkdir -p "$(dirname -- "$hook_file")"
    cat >"$hook_file" <<EOF
#!/usr/bin/env bash
$HOOK_MARKER
#
# Anonymizes the just-created commit (HEAD) after every \`git commit\`.
# --no-backup avoids accumulating a branch per commit (use \`git reflog\`/
# \`git reset\` to recover). --quiet drops the per-commit output; pass
# --verbose to bring it back. Regenerate with: $src --install-hook

set -e
anon_git=$(printf '%q' "$src")
EOF
    cat >>"$hook_file" <<'EOF'

# The script this hook calls is gone (moved, or --uninstall): say so instead
# of failing every commit with a bare "No such file".
if [[ ! -x "$anon_git" ]]; then
    printf 'anon-git: %s missing, not anonymized; re-run --install-hook.\n' "$anon_git" >&2
    exit 0
fi

# Rewriting HEAD mid-sequence would derail the rebase/cherry-pick/revert.
for state in rebase-merge rebase-apply sequencer CHERRY_PICK_HEAD REVERT_HEAD; do
    if [[ -e "$(git rev-parse --git-path "$state")" ]]; then
        printf 'anon-git: %s in progress, commit not anonymized.\n' "$state" >&2
        exit 0
    fi
done

# A partial commit (git add -p, git commit <path>) leaves a dirty tree,
# which anon-git refuses; stash it around the run. Only pop what this push
# saved: it saves nothing for e.g. a dirty submodule, and popping would then
# apply an older, unrelated stash.
stashed=0
if ! git diff-index --quiet HEAD -- || ! git diff-files --quiet; then
    stash_before=$(git rev-parse --quiet --verify refs/stash || true)
    git stash push --quiet
    if [[ "$(git rev-parse --quiet --verify refs/stash || true)" != "$stash_before" ]]; then
        stashed=1
    fi
fi
status=0
"$anon_git" --no-confirm --no-backup --quiet --current-branch HEAD || status=$?
if [[ "$stashed" -eq 1 ]]; then
    git stash pop --quiet --index
fi
exit "$status"
EOF
    chmod +x "$hook_file"
    printf 'Installed post-commit hook: %s\n' "$hook_file"
    exit 0
}

# Internal: removes $1/anon-git if present. Unlike install_copy, a missing
# target is not a failure -- uninstalling is idempotent.
# Internal: true if $1 is a copy of this script, so --uninstall never deletes
# an unrelated file that happens to share the name.
is_anon_git() {
    grep -q "^ANON_GIT_VERSION=" "$1" 2>/dev/null
}

uninstall_copy() {
    local dir="$1" target="${1}/anon-git"

    if [[ ! -e "$target" ]]; then
        return 0
    fi

    if ! is_anon_git "$target"; then
        printf 'Error: %s is not anon-git; refusing to remove it.\n' "$target" >&2
        return 1
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

    if [[ -e "$USER_DATA_DIR" ]]; then
        found=1
        if rm -rf -- "$USER_DATA_DIR"; then
            printf 'Removed: %s\n' "$USER_DATA_DIR"
        else
            failures=$((failures + 1))
        fi
    fi

    if [[ -e "$system_target" ]]; then
        found=1
        if ! is_anon_git "$system_target"; then
            printf 'Error: %s is not anon-git; refusing to remove it.\n' "$system_target" >&2
            failures=$((failures + 1))
        elif ! command -v sudo >/dev/null 2>&1; then
            printf 'Error: sudo not found; cannot remove %s\n' "$system_target" >&2
            failures=$((failures + 1))
        elif ! sudo rm -f -- "$system_target"; then
            printf 'Error: failed to remove %s\n' "$system_target" >&2
            failures=$((failures + 1))
        else
            printf 'Removed: %s\n' "$system_target"
        fi
    fi

    if [[ -e "$SYSTEM_DATA_DIR" ]] && command -v sudo >/dev/null 2>&1; then
        found=1
        if sudo rm -rf -- "$SYSTEM_DATA_DIR"; then
            printf 'Removed: %s\n' "$SYSTEM_DATA_DIR"
        else
            failures=$((failures + 1))
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
    local hook_file

    if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
        printf 'Error: --uninstall-hook must be run inside a git repository.\n' >&2
        exit 1
    fi
    hook_file=$(hook_file_path)

    if [[ ! -e "$hook_file" && ! -L "$hook_file" ]]; then
        printf 'No post-commit hook installed at %s\n' "$hook_file"
        exit 0
    fi

    if ! hook_is_ours "$hook_file"; then
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
        # Skip the value, so `--name --install` doesn't run the installer.
        --date | --name | --email) i=$((i + 1)) ;;
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
        printf 'AnonGit must be run inside a git repository.\n' >&2
        exit 1
    fi

    # Bare repo or inside .git: the dirty-tree check below would misreport.
    if [[ "$(git rev-parse --is-inside-work-tree)" != 'true' ]]; then
        printf 'Error: AnonGit must be run inside a work tree (not a bare repository or .git directory).\n' >&2
        exit 1
    fi

    if ! git rev-parse --quiet --verify HEAD >/dev/null; then
        printf 'Error: repository has no commits yet; nothing to anonymize.\n' >&2
        exit 1
    fi

    if ! git diff-index --quiet HEAD -- || ! git diff-files --quiet; then
        printf 'Repository has uncommitted changes. Commit or stash first to prevent losing the changes.\n' >&2
        exit 1
    fi

    if ! command -v git-filter-repo >/dev/null 2>&1 && ! git filter-repo --version >/dev/null 2>&1; then
        printf 'git-filter-repo is required but was not found. See the Pre-requisites section of the README.\n' >&2
        exit 1
    fi
}

# Internal: reads git config anon-git.<key>, normalized to '1'/'0', or
# prints nothing if unset. Parsed by git itself (--type=bool), so "True",
# "YES" or a valueless key mean what git says. An unparseable value is a
# hard error rather than silently ignored, since a typo'd config shouldn't
# fail open.
read_git_config_bool() {
    local key="$1" value status=0
    value=$(git config --type=bool --get "$key" 2>/dev/null) || status=$?

    # Exit 1: key unset.
    if [[ "$status" -eq 1 ]]; then
        return 0
    fi
    if [[ "$status" -ne 0 ]]; then
        printf 'Error: git config %s has an invalid boolean value "%s" (expected true/false)\n' \
            "$key" "$(git config --get "$key")" >&2
        exit 1
    fi
    if [[ "$value" == 'true' ]]; then
        printf '1'
        return 0
    fi
    printf '0'
}

# Reads `git config anon-git.*` into the GITCONFIG_* globals, ranked above
# envvars and below flags. Excludes --entire-history/--current-branch/
# --dry-run: a silent default for those would be too destructive.
read_git_config() {
    local opt key value

    GITCONFIG_NAME=$(git config --get anon-git.name 2>/dev/null || true)
    GITCONFIG_EMAIL=$(git config --get anon-git.email 2>/dev/null || true)
    GITCONFIG_DATE=$(git config --get anon-git.date 2>/dev/null || true)
    for opt in "${CONFIG_BOOLS[@]}"; do
        key="anon-git.$(to_lower "$opt")"
        # Plain assignment, so an invalid value's exit 1 aborts the script.
        value=$(read_git_config_bool "$key")
        printf -v "GITCONFIG_${opt}" '%s' "$value"
    done
}

to_lower() {
    tr '[:upper:]' '[:lower:]' <<<"$1"
}

# Internal: maps a flag to its option name: --keep-user -> KEEPUSER.
flag_option() {
    local opt="${1#--}"
    tr '[:lower:]' '[:upper:]' <<<"${opt//-/}"
}

# Internal: parses "$@" into the *_ARG globals, later merged with ANON_GIT_*
# envvars and DEFAULT_* fallbacks. Empty string means "not provided via flag".
parse_args() {
    local opt ref

    for opt in DATE NAME EMAIL "${BOOLS[@]}" NOCONFIRM NOBACKUP VERBOSE COMMIT; do
        printf -v "${opt}_ARG" '%s' ''
    done
    COMMITS_ARG=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --date | --name | --email)
            # Empty would silently fall back to the default identity/date.
            [[ $# -ge 2 && -n "$2" ]] || {
                printf 'Error: %s requires a value\n' "$1" >&2
                exit 1
            }
            printf -v "$(flag_option "$1")_ARG" '%s' "$2"
            shift 2
            ;;
        --keep-user | --keep-date | --keep-year | --keep-month | --keep-day | \
            --random-time | --random-day | --random-month | --strip-timezone | \
            --no-confirm | --no-backup | --entire-history | --current-branch | \
            --dry-run | --quiet | --verbose)
            printf -v "$(flag_option "$1")_ARG" '%s' '1'
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
            # ^{commit} peels annotated tags, whose own hash never matches a commit.
            ref=$(git rev-parse "${1}^{commit}")
            COMMITS_ARG+=("$ref")
            COMMIT_ARG="${COMMITS_ARG[*]}"
            shift
            ;;
        esac
    done
}

# Internal: prints '1' if bool option $1 is on from any source.
bool_set() {
    local arg="${1}_ARG" cfg="GITCONFIG_${1}" env="ANON_GIT_${1}"
    if [[ -n "${!arg}" || "${!cfg:-}" == '1' || "${!env:-}" == '1' ]]; then
        printf '1'
    fi
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

# Options that decide the same thing (identity, date) form a group; the
# highest-priority source setting any member owns the whole group, so e.g.
# ANON_GIT_DATE doesn't conflict with --keep-date: lower sources' members are
# cleared before the conflict checks and the merge. Bool '0' doesn't count.
drop_overridden_sources() {
    local group suffix source var owner
    local groups=('NAME EMAIL KEEPUSER' 'DATE KEEPDATE KEEPYEAR KEEPMONTH KEEPDAY RANDOMTIME RANDOMDAY RANDOMMONTH')

    for group in "${groups[@]}"; do
        owner=''
        for source in ARG GITCONFIG ANON_GIT; do
            for suffix in $group; do
                var=$(source_var "$source" "$suffix")
                if [[ -n "${!var:-}" && "${!var:-}" != '0' ]]; then
                    owner="$source"
                    break 2
                fi
            done
        done
        for source in ARG GITCONFIG ANON_GIT; do
            if [[ -z "$owner" || "$source" == "$owner" ]]; then
                continue
            fi
            for suffix in $group; do
                printf -v "$(source_var "$source" "$suffix")" '%s' ''
            done
        done
    done
}

# Internal: name of the variable holding option $2 (e.g. DATE) from source
# $1 (ARG = CLI flag, GITCONFIG = repo config, ANON_GIT = envvar).
source_var() {
    if [[ "$1" == 'ARG' ]]; then
        printf '%s_ARG' "$2"
        return
    fi
    printf '%s_%s' "$1" "$2"
}

# Rejects mutually-exclusive options regardless of whether each side came
# from a CLI flag, repo-local config, or its envvar. Must run before
# merge_args_with_defaults overwrites these envvar names with the
# fully-resolved value, so an unset envvar still reads as empty.
reject_incompatible_options() {
    local date_set name_set email_set keepuser_set entirehistory_set flag joined
    local date_flags=()

    flag_errors=0

    date_set="${DATE_ARG:-${GITCONFIG_DATE:-${ANON_GIT_DATE:-}}}"
    name_set="${NAME_ARG:-${GITCONFIG_NAME:-${ANON_GIT_NAME:-}}}"
    email_set="${EMAIL_ARG:-${GITCONFIG_EMAIL:-${ANON_GIT_EMAIL:-}}}"
    keepuser_set=$(bool_set KEEPUSER)
    entirehistory_set=$(bool_set ENTIREHISTORY)

    check_incompatible --keep-user "$keepuser_set" --name "$name_set"
    check_incompatible --keep-user "$keepuser_set" --email "$email_set"
    # --date, --keep-* and --random-* each decide the whole date: one at most.
    if [[ -n "$date_set" ]]; then
        date_flags+=(--date)
    fi
    for flag in --keep-date --keep-year --keep-month --keep-day --random-time --random-day --random-month; do
        if [[ -n "$(bool_set "$(flag_option "$flag")")" ]]; then
            date_flags+=("$flag")
        fi
    done
    if [[ ${#date_flags[@]} -gt 1 ]]; then
        joined=$(printf '%s and ' "${date_flags[@]}")
        printf 'Error: %s cannot be used together\n' "${joined% and }" >&2
        flag_errors=1
    fi
    # CLI-only: no ANON_GIT_COMMIT envvar exists.
    check_incompatible "commit(s) argument" "$COMMIT_ARG" --entire-history "$entirehistory_set"
    # Only the two flags conflict: --verbose over ANON_GIT_QUIET=1 or
    # anon-git.quiet is the intended way to un-silence a quiet default.
    check_incompatible --quiet "$QUIET_ARG" --verbose "$VERBOSE_ARG"

    [[ "$flag_errors" -ne 0 ]] && exit 1
    return 0
}

# Internal: merges flags > repo-local git config > ANON_GIT_* envvars >
# DEFAULT_* fallbacks into the final ANON_GIT_* globals used from here on.
merge_args_with_defaults() {
    local opt arg cfg env def

    DEFAULT_COMMIT=$(git rev-parse HEAD)
    ANON_GIT_DATE="${DATE_ARG:-${GITCONFIG_DATE:-${ANON_GIT_DATE:-${DEFAULT_DATE}}}}"
    ANON_GIT_NAME="${NAME_ARG:-${GITCONFIG_NAME:-${ANON_GIT_NAME:-${DEFAULT_NAME}}}}"
    ANON_GIT_EMAIL="${EMAIL_ARG:-${GITCONFIG_EMAIL:-${ANON_GIT_EMAIL:-${DEFAULT_EMAIL}}}}"
    for opt in "${BOOLS[@]}"; do
        arg="${opt}_ARG" cfg="GITCONFIG_${opt}" env="ANON_GIT_${opt}" def="DEFAULT_${opt}"
        printf -v "$env" '%s' "${!arg:-${!cfg:-${!env:-${!def}}}}"
    done
    ANON_GIT_COMMIT="${COMMIT_ARG:-${DEFAULT_COMMIT}}"
    # --verbose always wins over whatever set ANON_GIT_QUIET above.
    if [[ "$VERBOSE_ARG" == '1' ]]; then
        ANON_GIT_QUIET='0'
    fi
}

# Internal: --strip-timezone alone implicitly behaves like --keep-user
# --keep-date for that run (the python commit-callback still does the
# offset rewrite). Any other CLI flag opts back into normal precedence.
# Only the *_ARG (CLI-only) globals count -- repo config/envvars don't.
# shellcheck disable=SC2034 # ANON_GIT_* are exported indirectly.
apply_strip_timezone_alone() {
    local opt arg

    if [[ "$STRIPTIMEZONE_ARG" != '1' ]]; then
        return
    fi
    for opt in DATE NAME EMAIL KEEPUSER KEEPDATE KEEPYEAR KEEPMONTH KEEPDAY RANDOMTIME RANDOMDAY RANDOMMONTH; do
        arg="${opt}_ARG"
        if [[ -n "${!arg}" ]]; then
            return
        fi
    done
    ANON_GIT_KEEPUSER='1'
    ANON_GIT_KEEPDATE='1'
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
    local opt env

    for opt in "${BOOLS[@]}"; do
        env="ANON_GIT_${opt}"
        validate_bool "$env" "${!env}"
    done
}

# Only HEAD's history is rewritten (--refs HEAD), so any other target would
# silently stay untouched.
require_reachable() {
    local commit
    for commit in ${COMMITS_ARG[@]+"${COMMITS_ARG[@]}"}; do
        if ! git merge-base --is-ancestor "$commit" HEAD; then
            printf 'Error: commit %s is not reachable from HEAD; check out a branch containing it first.\n' \
                "$(git rev-parse --short "$commit")" >&2
            exit 1
        fi
    done
}

# --current-branch rewrites the checked-out branch, so there must be one.
# Checked before confirm, so nothing waits for a "y" that can't be acted on.
require_branch_to_overwrite() {
    if [[ "$ANON_GIT_CURRENTBRANCH" == '1' && -z "$(git branch --show-current)" ]]; then
        printf 'Error: HEAD is detached, so there is no current branch to overwrite. Drop --current-branch or check out a branch first.\n' >&2
        exit 1
    fi
}

# Pre-1970 is rejected: git writes the negative timestamp, but fsck (and
# so most hosts on push) rejects the commit as badDate.
validate_date() {
    if ! ANON_GIT_DATE="$ANON_GIT_DATE" python3 -c "${python_parse_target_date}
import os
assert parse_target_date(os.environ['ANON_GIT_DATE']).timestamp() >= 0" 2>/dev/null; then
        printf 'Error: invalid date "%s" (expected e.g. "2025-03-10 13:37:00 +0000", not before 1970)\n' "$ANON_GIT_DATE" >&2
        exit 1
    fi
}

# fast-import aborts mid-rewrite on an ident with <, > or a newline, after
# the new/backup branch already exists; reject it before anything runs.
validate_identity() {
    local field value
    if [[ "$ANON_GIT_KEEPUSER" == '1' ]]; then
        return
    fi
    for field in NAME EMAIL; do
        value="ANON_GIT_${field}"
        if [[ "${!value}" == *[$'<>\n']* ]]; then
            printf 'Error: %s must not contain "<", ">" or a newline (got "%s")\n' "$(to_lower "$field")" "${!value}" >&2
            exit 1
        fi
    done
}

# Prints a summary, gated on flags explicitly passed on the CLI (not the
# resolved envvar/default), so e.g. ANON_GIT_KEEPUSER in a shell profile
# doesn't spam this on every run.
verbose_info() {
    if [[ "$ANON_GIT_QUIET" == '1' ]]; then
        return
    fi
    if [[ "$ANON_GIT_ENTIREHISTORY" != '1' ]]; then
        local short_commit
        short_commit=$(echo "$ANON_GIT_COMMIT" | xargs -n 1 git rev-parse --short | tr '\n' ' ')
        printf 'Anonymizing commit(s): %s\n' "$short_commit"
    fi
    if [[ "$ANON_GIT_ENTIREHISTORY" == '1' ]]; then
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
            printf 'WARNING! Overwriting existing branch %s without backup!\n' "$branch_label" >&2
        fi
    fi
}

# Skipped for --no-confirm or --dry-run (nothing is touched either way).
# Reads the terminal, not stdin: under xargs stdin is /dev/null.
confirm() {
    if [[ "$NOCONFIRM_ARG" == '1' || "$ANON_GIT_DRYRUN" == '1' ]]; then
        return
    fi
    if ! : </dev/tty 2>/dev/null; then
        printf 'Error: no terminal to ask for confirmation; pass --no-confirm.\n' >&2
        exit 1
    fi
    read -p "Continue? (y/N) " -n 1 -r </dev/tty
    printf '\n'
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        printf 'Aborted.\n' >&2
        exit 1
    fi
}

# git-filter-repo caches metadata in .git/filter-repo/ to reuse across runs,
# but reusing it after certain repo state changes hits a known assertion bug
# in the tool. Removing it forces a clean run each time.
clean_cache() {
    rm -rf -- "$(git rev-parse --git-dir)/filter-repo"
}

# Internal: creates the scratch file the Python commit-callback writes its
# --dry-run preview to (shared via ANON_GIT_DRYRUN_FILE). Removed by the
# EXIT trap (cleanup_on_exit).
setup_dryrun() {
    if [[ "$ANON_GIT_DRYRUN" == '1' ]]; then
        make_scratch_file dryrun_file
    fi
}

# ──────────────────────────────────────────────────────────────────────
# REWRITE LOGIC

# Passed via environment rather than string-interpolated into the generated
# source, so a name/email/date with a quote or other Python-special
# character can't break out of a string literal and inject code.
export_rewrite_env() {
    local opt

    export ANON_GIT_NAME ANON_GIT_EMAIL ANON_GIT_DATE ANON_GIT_COMMIT
    for opt in "${BOOLS[@]}"; do
        export "ANON_GIT_${opt}"
    done
    export ANON_GIT_RANDOM_DATES_FILE="${random_dates_file}"
    export ANON_GIT_DRYRUN_FILE="${dryrun_file}"
    export TZ=UTC
}

# Precomputes one random timestamp per target commit for --random-time/-day/
# -month: reads full history from stdin, oldest first ("<hash> <epoch>
# <offset> [parents...]"), tags each commit target/anchor (a parent or child
# of a target)/ignored, buckets by the commit's local calendar unit (what
# `git log` shows, as --keep-* uses), and assigns each bucket's runs random
# timestamps bounded by their nearest anchor, preserving relative order.
# Prints "<hash> <epoch> +0000" lines, targets only. Kept as a plain
# top-level assignment: the test suite locates it by its exact, unindented
# `python_compute_random_dates="` ... `"` line anchors.
python_compute_random_dates="
import os
import random
import sys

# OS entropy: Mersenne Twister output is recoverable from enough samples.
rng = random.SystemRandom()
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

def local_datetime(epoch, offset):
    # Wall-clock date/time in the commit's own offset, labeled UTC: the
    # output is +0000, so bucket bounds must be these digits read as UTC.
    sign = -1 if offset.startswith('-') else 1
    seconds = sign * (int(offset[1:3]) * 3600 + int(offset[3:5]) * 60)
    return datetime.fromtimestamp(epoch + seconds, tz=timezone.utc)

history = []
for line in sys.stdin:
    fields = line.split()
    if not fields:
        continue
    history.append((fields[0], int(fields[1]), fields[2], fields[3:]))

# Real neighbors are parents and children: across a merge, the commit next
# in log order can sit on another branch.
anchors = set()
for commit_hash, _epoch, _offset, parents in history:
    if commit_hash in target_hashes:
        anchors.update(parents)
    elif any(parent in target_hashes for parent in parents):
        anchors.add(commit_hash)

if entirehistory:
    roles = ['target'] * len(history)
else:
    roles = []
    for commit_hash, _epoch, _offset, _parents in history:
        if commit_hash in target_hashes:
            roles.append('target')
        elif commit_hash in anchors:
            roles.append('anchor')
        else:
            roles.append('skip')

buckets = defaultdict(list)
bounds = {}

# History index breaks epoch ties, so a parent sorts before its same-second child.
for index, ((commit_hash, epoch, offset, _parents), role) in enumerate(zip(history, roles)):
    if role == 'skip':
        continue
    keys = {bucket_bounds(local_datetime(epoch, offset))}
    if role == 'anchor':
        # Also bound targets whose bucket holds this anchor's real instant.
        keys.add(bucket_bounds(datetime.fromtimestamp(epoch, tz=timezone.utc)))
    for key, start, end in keys:
        buckets[key].append((epoch, index, commit_hash, role))
        bounds[key] = (start, end)

for key, members in buckets.items():
    bucket_start, bucket_end = bounds[key]
    members.sort()

    i = 0
    member_count = len(members)
    lower = bucket_start
    while i < member_count:
        epoch, _index, commit_hash, role = members[i]
        if role == 'anchor':
            lower = max(epoch + 1, bucket_start)
            i += 1
            continue
        run_start = i
        while i < member_count and members[i][3] == 'target':
            i += 1
        run = members[run_start:i]
        upper = min(members[i][0] - 1, bucket_end) if i < member_count else bucket_end
        count = len(run)
        span = upper - lower
        if span < 0:
            # No room between anchors (e.g. two real commits one second
            # apart with a target sandwiched between), or an anchor outside
            # the bucket. Share the nearest in-bucket timestamp -- git allows
            # identical dates, the calendar unit must not change.
            picks = [min(max(lower - 1, bucket_start), bucket_end)] * count
        elif count <= span + 1:
            picks = sorted(rng.sample(range(lower, upper + 1), count))
        else:
            picks = sorted(rng.randint(lower, upper) for _ in range(count))
        for (_original_epoch, _member_index, member_hash, _role), new_epoch in zip(run, picks):
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

    make_scratch_file random_dates_file

    if ! git log --reverse --topo-order --date=format:%z --format='%H %at %ad %P' HEAD |
        ANON_GIT_RANDOMTIME="$ANON_GIT_RANDOMTIME" ANON_GIT_RANDOMDAY="$ANON_GIT_RANDOMDAY" ANON_GIT_RANDOMMONTH="$ANON_GIT_RANDOMMONTH" \
            ANON_GIT_ENTIREHISTORY="$ANON_GIT_ENTIREHISTORY" ANON_GIT_TARGET_COMMITS="$ANON_GIT_COMMIT" \
            python3 -c "$python_compute_random_dates" >"$random_dates_file"; then
        printf 'Error: failed to compute randomized commit dates\n' >&2
        exit 1
    fi
}

# Prepended to python_commit_callback, and run alone by validate_date so a
# malformed date fails before anything is touched.
python_parse_target_date="
import re
from datetime import datetime

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
"

# Kept as a plain top-level assignment (not nested in a function): the test
# suite locates this callback by its exact, unindented
# `python_commit_callback="` ... `"` line anchors to check it's valid Python.
python_commit_callback="
import os
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

# Loaded once: filter-repo wraps this body in a function, so without
# \`global\` the dict would be local and the file re-read per commit.
global RANDOM_DATES
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
    # Metadata is raw bytes with no guaranteed encoding.
    an = commit.author_name.decode(errors='replace')
    ae = commit.author_email.decode(errors='replace')
    ad = parse_git_date(commit.author_date).isoformat()
    new_an = author_name.decode(errors='replace')
    new_ae = author_email.decode(errors='replace')
    new_ad = parse_git_date(author_date).isoformat()

    cn = commit.committer_name.decode(errors='replace')
    ce = commit.committer_email.decode(errors='replace')
    cd = parse_git_date(commit.committer_date).isoformat()
    new_cn = committer_name.decode(errors='replace')
    new_ce = committer_email.decode(errors='replace')
    new_cd = parse_git_date(committer_date).isoformat()

    commit_id = commit.original_id.decode()
    msg = commit.message.decode(errors='replace')
    sep = '\n' + '-' * 80 + '\n'

    with open(dryrun_file, 'a', encoding='utf-8') as f:
        f.write('Commit:')
        f.write('%s\n' % commit_id)
        f.write('Author:\t\t%s <%s> -> %s <%s> \n' % (an, ae, new_an, new_ae))
        f.write('Committer:\t%s <%s> -> %s <%s> \n' % (cn, ce, new_cn, new_ce))
        f.write('AuthorDate:\t%s -> %s\n' % (ad, new_ad))
        f.write('CommitterDate:\t%s -> %s\n' % (cd, new_cd))
        f.write('\n')
        f.write(msg)
        f.write(sep)
    return

commit.author_name = author_name
commit.author_email = author_email
commit.author_date = author_date
commit.committer_name = committer_name
commit.committer_email = committer_email
commit.committer_date = committer_date
"

# filter_repo_log is a global the EXIT trap (cleanup_on_exit) removes.
# --dry-run is forwarded: without it filter-repo still rewrites history even
# when the callback changes nothing (e.g. signed commits lose their signature).
run_filter_repo() {
    local dryrun_args=()
    if [[ "$ANON_GIT_DRYRUN" == '1' ]]; then
        dryrun_args=(--dry-run)
    fi
    make_scratch_file filter_repo_log
    if ! git filter-repo --force ${dryrun_args[@]+"${dryrun_args[@]}"} --commit-callback "${python_parse_target_date}${python_commit_callback}" --refs HEAD >"$filter_repo_log" 2>&1; then
        printf 'Error: git filter-repo failed:\n' >&2
        cat "$filter_repo_log" >&2
        exit 1
    fi
}

# dryrun_file is removed by the EXIT trap (cleanup_on_exit), not here.
print_result() {
    if [[ "$ANON_GIT_DRYRUN" == '1' && -f "$dryrun_file" ]]; then
        # Through sh, like git, so PAGER may carry arguments ("less -R").
        sh -c "${PAGER:-cat} \"\$1\"" sh "$dryrun_file"
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
    drop_overridden_sources
    reject_incompatible_options
    merge_args_with_defaults
    apply_strip_timezone_alone
    validate_final_options
    require_target
    validate_date
    validate_identity
    require_reachable
    require_branch_to_overwrite
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

# Skipped when sourced, so the test suite can read DEFAULT_* directly.
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main "$@"
fi
