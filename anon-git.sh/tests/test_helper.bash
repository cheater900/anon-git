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

# The user's own ANON_GIT_*, pager or global git config must not leak in.
unset PAGER "${!ANON_GIT_@}"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

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

pick_random_index() {
    # Sets PICKED_INDEX to a random HEAD~N target; set TEST_RANDOM_INDEX to
    # replay it. Bats prints a test's output only when it fails.
    PICKED_INDEX=${TEST_RANDOM_INDEX:-$(($(od -An -N2 -tu2 </dev/urandom) % (COMMIT_COUNT - 1)))}
    echo "target HEAD~${PICKED_INDEX}, replay with TEST_RANDOM_INDEX=${PICKED_INDEX}"
}

# Prints a commit's "name <email>" author.
commit_author() {
    git show -s --format='%an <%ae>' "$1"
}

# Prints the distinct "name <email>" authors in HEAD's history.
history_authors() {
    git log --format='%an <%ae>' | sort -u
}

# Prints a commit's author date in strftime format.
commit_date() {
    # $1: commit, $2: strftime format
    git show -s --date=format:"$2" --format='%ad' "$1"
}

# Extracts a "name=\"...\"" multi-line string assignment from the script,
# without its first/last lines.
extract_script_block() {
    # $1: variable name, e.g. python_commit_callback
    sed -n "/^$1=\"\$/,/^\"\$/p" "$SCRIPT" | sed -e '1d' -e '$d'
}
