#!/usr/bin/env bash

# Runs once per `bats` invocation, before any test file. Builds the template
# repo every test copies (see setup in test_helper.bash) and reads the
# script's DEFAULT_* values.

# shellcheck source=tests/test_helper.bash
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.bash"

setup_suite() {
    local i
    export DEFAULT_DATE DEFAULT_NAME DEFAULT_EMAIL DEFAULT_KEEPUSER DEFAULT_KEEPDATE
    DEFAULT_DATE=$(script_var DEFAULT_DATE)
    DEFAULT_NAME=$(script_var DEFAULT_NAME)
    DEFAULT_EMAIL=$(script_var DEFAULT_EMAIL)
    DEFAULT_KEEPUSER=$(script_var DEFAULT_KEEPUSER)
    DEFAULT_KEEPDATE=$(script_var DEFAULT_KEEPDATE)
    export DEFAULT_AUTHOR="${DEFAULT_NAME} <${DEFAULT_EMAIL}>"
    export REPO_TEMPLATE=${BATS_SUITE_TMPDIR}/template
    new_repo "$REPO_TEMPLATE"
    for ((i = 1; i <= COMMIT_COUNT; i++)); do
        echo "This is file $i" >"${REPO_TEMPLATE}/file_${i}.txt"
        git -C "$REPO_TEMPLATE" add "file_${i}.txt"
        git -C "$REPO_TEMPLATE" commit -q -m "Add file file_${i}.txt"
    done
}
