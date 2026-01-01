#!/usr/bin/env bash

# Loaded by every tests/*.bats file. Each test starts in $REPO, a fresh copy
# of setup_suite.bash's template repo, so one test's leftovers can't cascade
# into the next.

bats_require_minimum_version 1.5.0
bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT_NAME=anon-git.sh
SCRIPT=${SCRIPT_DIR}/${SCRIPT_NAME}
COMMIT_COUNT=20
TEST_USER_NAME='Jordan Blake'
TEST_USER_EMAIL='jordan.blake@example.com'

setup() {
    REPO=${BATS_TEST_TMPDIR}/repo
    cp -a "$REPO_TEMPLATE" "$REPO"
    cd "$REPO" || return 1
    # The copy's file stat info differs from the index; refresh so git
    # doesn't report the tree as dirty.
    git update-index -q --refresh
    HEAD_BEFORE=$(git rev-parse HEAD)
}

# Inits an empty repo in $1 holding an untracked, git-excluded copy of the
# script.
new_repo() {
    git init -q "$1"
    git -C "$1" config --local user.name "$TEST_USER_NAME"
    git -C "$1" config --local user.email "$TEST_USER_EMAIL"
    cp "$SCRIPT" "$1/"
    printf '%s\n' "$SCRIPT_NAME" >>"$1/.git/info/exclude"
}

# Copies the script to a dir outside any git repo and cds there.
cd_outside_repo() {
    mkdir "${BATS_TEST_TMPDIR}/norepo"
    cp "$SCRIPT" "${BATS_TEST_TMPDIR}/norepo/"
    cd "${BATS_TEST_TMPDIR}/norepo" || return
}

assert_head_unchanged() {
    assert_equal "$(git rev-parse HEAD)" "$HEAD_BEFORE"
}

branch_count() {
    git branch --list | wc -l | tr -d ' '
}

# Prints the newest "<branch>_anonymized_*" branch, created by a run without
# --current-branch.
anonymized_branch() {
    git branch --format='%(refname:short)' | grep "_anonymized_" | tail -1 || true
}

pick_random_index() {
    # Sets PICKED_INDEX to a random HEAD~N target; set TEST_RANDOM_INDEX to
    # replay it. Bats prints a test's output only when it fails.
    PICKED_INDEX=${TEST_RANDOM_INDEX:-$(($(od -An -N2 -tu2 </dev/urandom) % (COMMIT_COUNT - 1)))}
    echo "target HEAD~${PICKED_INDEX}, replay with TEST_RANDOM_INDEX=${PICKED_INDEX}"
}

# Prints a commit's author date in strftime format.
commit_date() {
    # $1: commit, $2: strftime format
    git show -s --date=format:"$2" --format='%ad' "$1"
}

# Rewrites a random HEAD~N with $@ and checks only that commit changed, as
# the flags ask.
assert_rewrite() {
    # $@: flags to pass through (--name, --email, --date, --keep-user, --keep-date)
    local expected_name=$DEFAULT_NAME expected_email=$DEFAULT_EMAIL expected_date=$DEFAULT_DATE
    local keep_user=$DEFAULT_KEEPUSER keep_date=$DEFAULT_KEEPDATE args=("$@")
    local commit_format='%an <%aE> (%ai) %cn <%cE> (%ci)' target old_user old_date old_others
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --date)
            expected_date=$2
            shift 2
            ;;
        --name)
            expected_name=$2
            shift 2
            ;;
        --email)
            expected_email=$2
            shift 2
            ;;
        --keep-user)
            keep_user=1
            shift
            ;;
        --keep-date)
            keep_date=1
            shift
            ;;
        *)
            fail "unexpected argument in assert_rewrite: $1"
            ;;
        esac
    done
    pick_random_index
    target="HEAD~${PICKED_INDEX}"
    old_user=$(git show -s --format='%an <%ae> %cn <%ce>' "$target")
    old_date=$(git show -s --format='%ai %ci' "$target")
    # Every other commit, to verify only the target changes.
    old_others=$(git log --format="$commit_format" | sed "$((PICKED_INDEX + 1))d")
    run ./anon-git.sh --no-confirm --no-backup "${args[@]}" "$target"
    assert_success
    if [[ "$keep_user" == '1' ]]; then
        assert_equal "$(git show -s --format='%an <%ae> %cn <%ce>' "$target")" "$old_user"
    else
        assert_equal "$(git show -s --format='%an <%ae>' "$target")" "${expected_name} <${expected_email}>"
        assert_equal "$(git show -s --format='%cn <%ce>' "$target")" "${expected_name} <${expected_email}>"
    fi
    if [[ "$keep_date" == '1' ]]; then
        assert_equal "$(git show -s --format='%ai %ci' "$target")" "$old_date"
    else
        assert_equal "$(git show -s --format='%ai' "$target")" "$expected_date"
        assert_equal "$(git show -s --format='%ci' "$target")" "$expected_date"
    fi
    assert_equal "$(git log --format="$commit_format" | sed "$((PICKED_INDEX + 1))d")" "$old_others"
}

# Runs anon-git.sh with $@ and checks it rejects them as conflicting,
# leaving HEAD alone. "ANON_GIT_*=value" args are routed to `env`, so one
# helper covers flag-vs-flag, envvar-vs-envvar, and mixed conflicts.
assert_incompatible() {
    local arg envvars=() cli_args=()
    for arg in "$@"; do
        if [[ "$arg" == ANON_GIT_*=* ]]; then
            envvars+=("$arg")
        else
            cli_args+=("$arg")
        fi
    done
    run env "${envvars[@]}" ./anon-git.sh --no-confirm --no-backup "${cli_args[@]}"
    assert_failure
    assert_head_unchanged
    assert_output --partial 'cannot be used together'
}

# Extracts a "name=\"...\"" multi-line string assignment from the script,
# without its first/last lines.
extract_script_block() {
    # $1: variable name, e.g. python_commit_callback
    sed -n "/^$1=\"\$/,/^\"\$/p" "$SCRIPT" | sed -e '1d' -e '$d'
}

run_with_tty() {
    # $1: keystrokes typed into the terminal, rest: command. confirm() reads
    # /dev/tty, not stdin, so a pipe can't answer it; a pty can.
    python3 -c '
import os, pty, sys
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[2], sys.argv[2:])
os.write(fd, sys.argv[1].encode())
while True:
    try:
        if not os.read(fd, 1024):
            break
    except OSError:
        break
sys.exit(os.waitstatus_to_exitcode(os.waitpid(pid, 0)[1]))
' "$@"
}

run_without_tty() {
    # New session: no controlling terminal, so /dev/tty can't be opened.
    python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@"
}
