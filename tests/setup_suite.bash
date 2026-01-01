#!/usr/bin/env bash

# Runs once per `bats` invocation, before any test file. Builds the template
# repo every test copies (see setup in test_helper.bash) and reads the
# script's DEFAULT_* values.

script_default() {
    # $1: option name. Prints DEFAULT_$1, read by sourcing the script in a
    # subshell (main is skipped when sourced).
    bash -c 'source "$1" && printf "%s" "${!2}"' _ "$SCRIPT" "DEFAULT_$1"
}

setup_suite() {
    local i
    export SCRIPT_DIR SCRIPT_NAME=anon-git.sh SCRIPT COMMIT_COUNT=20 REPO_TEMPLATE
    SCRIPT_DIR=$(realpath "${BATS_TEST_DIRNAME}/..")
    SCRIPT=${SCRIPT_DIR}/${SCRIPT_NAME}
    export DEFAULT_DATE DEFAULT_NAME DEFAULT_EMAIL DEFAULT_KEEPUSER DEFAULT_KEEPDATE
    DEFAULT_DATE=$(script_default DATE)
    DEFAULT_NAME=$(script_default NAME)
    DEFAULT_EMAIL=$(script_default EMAIL)
    DEFAULT_KEEPUSER=$(script_default KEEPUSER)
    DEFAULT_KEEPDATE=$(script_default KEEPDATE)
    REPO_TEMPLATE=${BATS_SUITE_TMPDIR}/template
    mkdir "$REPO_TEMPLATE"
    cd "$REPO_TEMPLATE" || return 1
    git init -q
    git config --local user.name "Jordan Blake"
    git config --local user.email "jordan.blake@example.com"
    for i in $(seq 1 "$COMMIT_COUNT"); do
        echo "This is file $i" >"file_${i}.txt"
        git add "file_${i}.txt"
        git commit -q -m "Add file file_${i}.txt"
    done
    # Untracked, like the old harness: tests run ./anon-git.sh from the repo.
    cp "$SCRIPT" .
    chmod +x "./${SCRIPT_NAME}"
}
