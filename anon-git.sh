#!/usr/bin/env bash

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────
# HELP
#
# Defined and handled first so `--help` works even outside a git repository
# or with a dirty working tree; the safety checks that follow this block
# are unchanged, just moved below the help handling.

DEFAULT_NAME='Anon'
DEFAULT_EMAIL='anon@localhost'

show_help() {
    cat <<EOF
Anonymizes git commit metadata.

Usage:
  ./anon-git.sh [OPTIONS] [commits]

Options:
  -h, --help                      Show this help message and exit
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
  --print-completion [SHELL]      Print a shell completion script (bash, zsh, or fish;
                                   defaults to \$SHELL) and exit

Arguments:
  commit(s)               Commit(s) to anonymize (can be: hash, HEAD~3, branch, tag, ...)
                          Required, unless --entire-history is given.
                          If omitted (and --entire-history is not given), this help is shown.
                          If more than one, it should be a commit hash.

Priority (highest to lowest):
  1. Command-line flags (--date, --name, --email, --keep-user, --keep-date, ...)
  2. Environment variables (ANON_GIT_DATE, ANON_GIT_NAME, ANON_GIT_EMAIL, ANON_GIT_KEEPUSER,
     ANON_GIT_KEEPDATE, ANON_GIT_KEEPYEAR, ANON_GIT_KEEPMONTH, ANON_GIT_KEEPDAY)
  3. Hardcoded defaults (${DEFAULT_NAME} <${DEFAULT_EMAIL}>)

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
EOF
    exit 0
}

# Internal/undocumented: prints one flag per line (value-taking flags end in
# "="), so shell completion scripts have a single source of truth for the
# flag list instead of hardcoding it (and silently drifting out of sync).
list_flags() {
    cat <<'EOF'
-h
--help
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
--print-completion=
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

[[ $# -eq 0 ]] && show_help

args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[i]}" in
    -h | --help) show_help ;;
    --_list-flags) list_flags ;;
    --print-completion) print_completion "${args[i + 1]:-}" ;;
    esac
done

# ──────────────────────────────────────────────
# SAFETY CHECKS

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

# ──────────────────────────────────────────────
# DEFAULTS

DEFAULT_DATE='2008-10-31 00:00:00 +0000'
DEFAULT_KEEPUSER='0'
DEFAULT_KEEPDATE='0'
DEFAULT_KEEPYEAR='0'
DEFAULT_KEEPMONTH='0'
DEFAULT_KEEPDAY='0'
DEFAULT_ENTIREHISTORY='0'
DEFAULT_CURRENTBRANCH='0'
DEFAULT_DRYRUN='0'
DEFAULT_COMMIT=$(git rev-parse HEAD)

# ──────────────────────────────────────────────────────────────────────
# PARSE ARGUMENTS

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

# ──────────────────────────────────────────────
# VALIDATE ARGS

flag_errors=0
check_incompatible() {
    local flag1="$1"
    local flag2="$3"
    local value1="$2"
    local value2="$4"
    if [[ -n "$value1" && -n "$value2" ]]; then
        printf 'Error: flags %s and %s cannot be used together\n' "$flag1" "$flag2" >&2
        flag_errors=1
    fi
}

check_incompatible --keep-user "$KEEPUSER_ARG" --name "$NAME_ARG"
check_incompatible --keep-user "$KEEPUSER_ARG" --email "$EMAIL_ARG"
check_incompatible --date "$DATE_ARG" --keep-date "$KEEPDATE_ARG"
check_incompatible --date "$DATE_ARG" --keep-year "$KEEPYEAR_ARG"
check_incompatible --date "$DATE_ARG" --keep-month "$KEEPMONTH_ARG"
check_incompatible --date "$DATE_ARG" --keep-day "$KEEPDAY_ARG"
check_incompatible --keep-date "$KEEPDATE_ARG" --keep-year "$KEEPYEAR_ARG"
check_incompatible --keep-date "$KEEPDATE_ARG" --keep-month "$KEEPMONTH_ARG"
check_incompatible --keep-date "$KEEPDATE_ARG" --keep-day "$KEEPDAY_ARG"
check_incompatible --keep-year "$KEEPYEAR_ARG" --keep-month "$KEEPMONTH_ARG"
check_incompatible --keep-year "$KEEPYEAR_ARG" --keep-day "$KEEPDAY_ARG"
check_incompatible --keep-month "$KEEPMONTH_ARG" --keep-day "$KEEPDAY_ARG"
check_incompatible "commit(s) argument" "$COMMIT_ARG" --entire-history "$ENTIREHISTORY_ARG"

[[ "$flag_errors" -ne 0 ]] && exit 1

# ──────────────────────────────────────────────
# RESOLVE ARGS

ANON_GIT_DATE="${DATE_ARG:-${ANON_GIT_DATE:-${DEFAULT_DATE}}}"
ANON_GIT_NAME="${NAME_ARG:-${ANON_GIT_NAME:-${DEFAULT_NAME}}}"
ANON_GIT_EMAIL="${EMAIL_ARG:-${ANON_GIT_EMAIL:-${DEFAULT_EMAIL}}}"
ANON_GIT_KEEPUSER="${KEEPUSER_ARG:-${ANON_GIT_KEEPUSER:-${DEFAULT_KEEPUSER}}}"
ANON_GIT_KEEPDATE="${KEEPDATE_ARG:-${ANON_GIT_KEEPDATE:-${DEFAULT_KEEPDATE}}}"
ANON_GIT_KEEPYEAR="${KEEPYEAR_ARG:-${ANON_GIT_KEEPYEAR:-${DEFAULT_KEEPYEAR}}}"
ANON_GIT_KEEPMONTH="${KEEPMONTH_ARG:-${ANON_GIT_KEEPMONTH:-${DEFAULT_KEEPMONTH}}}"
ANON_GIT_KEEPDAY="${KEEPDAY_ARG:-${ANON_GIT_KEEPDAY:-${DEFAULT_KEEPDAY}}}"
ANON_GIT_ENTIREHISTORY="${ENTIREHISTORY_ARG:-${ANON_GIT_ENTIREHISTORY:-${DEFAULT_ENTIREHISTORY}}}"
ANON_GIT_CURRENTBRANCH="${CURRENTBRANCH_ARG:-${ANON_GIT_CURRENTBRANCH:-${DEFAULT_CURRENTBRANCH}}}"
ANON_GIT_COMMIT="${COMMIT_ARG:-${DEFAULT_COMMIT}}"
ANON_GIT_DRYRUN="${DRYRUN_ARG:-${DEFAULT_DRYRUN}}"

# ──────────────────────────────────────────────
# DEFAULT: SHOW HELP WHEN NO TARGET IS GIVEN
#
# Without an explicit commit target or --entire-history there is nothing to
# anonymize; show the help text instead of silently defaulting to HEAD (that
# implicit behavior was surprising, so a target is now required).
if [[ -z "$COMMIT_ARG" && "$ANON_GIT_ENTIREHISTORY" != '1' ]]; then
    show_help
fi

# ──────────────────────────────────────────────
# VALIDATE RESOLVED VALUES

validate_bool() {
    local name="$1" value="$2"
    if [[ "$value" != '0' && "$value" != '1' ]]; then
        printf 'Error: %s must resolve to "0" or "1" (got "%s")\n' "$name" "$value" >&2
        exit 1
    fi
}

validate_bool ANON_GIT_KEEPUSER "$ANON_GIT_KEEPUSER"
validate_bool ANON_GIT_KEEPDATE "$ANON_GIT_KEEPDATE"
validate_bool ANON_GIT_KEEPYEAR "$ANON_GIT_KEEPYEAR"
validate_bool ANON_GIT_KEEPMONTH "$ANON_GIT_KEEPMONTH"
validate_bool ANON_GIT_KEEPDAY "$ANON_GIT_KEEPDAY"
validate_bool ANON_GIT_ENTIREHISTORY "$ANON_GIT_ENTIREHISTORY"
validate_bool ANON_GIT_CURRENTBRANCH "$ANON_GIT_CURRENTBRANCH"
validate_bool ANON_GIT_DRYRUN "$ANON_GIT_DRYRUN"

# ──────────────────────────────────────────────────────────────────────
# VERBOSE INFO

if [[ -z "$ENTIREHISTORY_ARG" ]]; then
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

# ──────────────────────────────────────────────────────────────────────
# BACKUP BRANCH

current_branch=$(git branch --show-current)
if [[ -z "$current_branch" && "$ANON_GIT_CURRENTBRANCH" == '1' ]]; then
    printf 'Error: HEAD is detached, so there is no current branch to overwrite. Drop --current-branch or check out a branch first.\n' >&2
    exit 1
fi
branch_label="${current_branch:-detached-$(git rev-parse --short HEAD)}"
# Colon-free timestamp: git ref names may not contain ":" (see git-check-ref-format).
timestamp=$(date +%Y%m%d_%H%M%S_%N)

if [[ "$ANON_GIT_DRYRUN" != '1' ]]; then
    if [[ "$ANON_GIT_CURRENTBRANCH" != '1' ]]; then
        new_branch="${branch_label}_anonymized_${timestamp}"
        if ! git switch --create "$new_branch"; then
            printf 'Error: failed to create branch %s\n' "$new_branch" >&2
            exit 1
        fi
        printf 'Created new branch %s from %s\n' "$new_branch" "$branch_label"
        printf 'Using branch %s to rewrite commits.\n' "$new_branch"
    elif [[ "$NOBACKUP_ARG" != "1" ]]; then
        backup_branch="${branch_label}_backup_${timestamp}"
        if ! git branch "${backup_branch}"; then
            printf 'Error: failed to create backup branch %s\n' "$backup_branch" >&2
            exit 1
        fi
        printf 'Created backup branch %s from %s\n' "$backup_branch" "$branch_label"
        printf 'Using branch %s to rewrite commits\n' "$branch_label"
    else
        printf 'WARNING! Overwriting existing branch %s without backup!\n' "$branch_label"
    fi
fi

# ──────────────────────────────────────────────────────────────────────
# CONFIRMATION

if [[ "$NOCONFIRM_ARG" != '1' && "$ANON_GIT_DRYRUN" != '1' ]]; then
    read -p "Continue? (y/N) " -n 1 -r
    printf '\n'
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

# ──────────────────────────────────────────────────────────────────────
# CLEAN CACHE

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
if [[ -d "$PWD/.git/filter-repo" ]]; then
    rm -rf "$PWD/.git/filter-repo"
fi

# ──────────────────────────────────────────────────────────────────────
# DRYRUN

dryrun_file=''
if [[ "${ANON_GIT_DRYRUN}" -eq 1 ]]; then
    dryrun_file=$(mktemp)
fi

# ──────────────────────────────────────────────────────────────────────
# REWRITE LOGIC

# Values are passed to the Python commit-callback via the environment (not
# string-interpolated into the generated source) so that a name, email, or
# date containing a quote or other Python-special character cannot break out
# of a string literal and inject code into the callback.
export ANON_GIT_NAME ANON_GIT_EMAIL ANON_GIT_DATE ANON_GIT_COMMIT
export ANON_GIT_KEEPUSER ANON_GIT_KEEPDATE ANON_GIT_KEEPYEAR ANON_GIT_KEEPMONTH ANON_GIT_KEEPDAY
export ANON_GIT_ENTIREHISTORY ANON_GIT_DRYRUN
export ANON_GIT_DRYRUN_FILE="${dryrun_file}"
export TZ=UTC

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

anon_git_main() {
    git filter-repo --force --commit-callback "$python_commit_callback" --refs HEAD
}

filter_repo_log=$(mktemp)
if ! anon_git_main >"$filter_repo_log" 2>&1; then
    printf 'Error: git filter-repo failed:\n' >&2
    cat "$filter_repo_log" >&2
    rm -f "$filter_repo_log"
    [[ -n "$dryrun_file" ]] && rm -f "$dryrun_file"
    exit 1
fi
rm -f "$filter_repo_log"

# Preview output using pager defined by $PAGER. Falls back to cat.
if [[ "$ANON_GIT_DRYRUN" == '1' && -f "$dryrun_file" ]]; then
    pager=${PAGER:-cat}
    command "$pager" "$dryrun_file"
    rm -f "$dryrun_file"
else
    printf 'Done. History has been rewritten.\n'
fi
