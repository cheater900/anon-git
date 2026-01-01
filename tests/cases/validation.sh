#!/usr/bin/env bash

# Sourced by test-anon-git.sh — not meant to be run directly.
# VALIDATION TESTS: rejecting bad input (incompatible flags, invalid commit refs,\n# a dirty tree, malformed dates) and the python-callback syntax sanity check.

test_python_callback_syntax() {
    # anon-git.sh assigns the git-filter-repo commit callback to a shell
    # variable, python_commit_callback="...". Extract its contents (via a
    # regex address range, since the value spans many lines) and check that
    # it's syntactically valid Python. The body uses bare `return` statements,
    # which are only legal inside a function, so wrap it in a dummy one before
    # compiling — matching how git-filter-repo itself embeds the callback.
    local raw_block python_code check_file output exit_status errors=0

    raw_block=$(sed -n '/^python_commit_callback="$/,/^"$/p' "$SCRIPT")
    python_code=$(sed -e '1d' -e '$d' <<<"$raw_block")

    if [[ -z "$python_code" ]]; then
        printf 'Error: could not extract python_commit_callback contents from %s\n' "$SCRIPT_NAME"
        errors=$((errors + 1))
    fi

    check_file="${TMP_DIR}/python_commit_callback_check.py"
    {
        printf 'def _commit_callback(commit, metadata):\n'
        printf '%s\n' "    ${python_code//$'\n'/$'\n    '}"
    } >"$check_file"

    output=$(python3 -m py_compile "$check_file" 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: python_commit_callback has a syntax error:\n%s\n' "$output"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'python commit callback syntax'
}

test_catch_incompatible() {
    # @param $@  the incompatible combination to reject: CLI flags/args
    #            (--foo, HEAD, ...) and/or ANON_GIT_*=value envvar
    #            assignments, in any mix. Each envvar assignment must be a
    #            single "ANON_GIT_NAME=value" argument (not split across
    #            two), since it's routed to `env` rather than the script.
    #            This covers flag-vs-flag (the classic case), envvar-vs-
    #            envvar, and mixed flag-vs-envvar conflicts with one
    #            function, since anon-git.sh is meant to reject an
    #            incompatible combination the same way regardless of
    #            whether each side came from a flag or its env var.
    local before after exit_status errors=0 envvars=() cli_args=() arg label

    for arg in "$@"; do
        if [[ "$arg" == ANON_GIT_*=* ]]; then
            envvars+=("$arg")
        else
            cli_args+=("$arg")
        fi
    done
    label='catch incompatible'
    [[ -n "${envvars[*]}" ]] && label="${label} ${envvars[*]}"
    [[ -n "${cli_args[*]}" ]] && label="${label} ${cli_args[*]}"
    [[ "$label" == 'catch incompatible' ]] && label="${label} (defaults)"

    before=$(git rev-parse HEAD)
    env "${envvars[@]}" ./"${SCRIPT_NAME}" --no-confirm --no-backup "${cli_args[@]}" >/dev/null 2>&1
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: "%s" did not fail as expected\n' "$*"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite incompatible "%s"\n' "$*"
        errors=$((errors + 1))
    fi

    record_result "$errors" "$label"
}

test_catch_invalid_commit() {
    local before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(./"${SCRIPT_NAME}" --no-confirm --no-backup deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: invalid commit ref did not cause failure\n'
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite invalid commit ref\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'does not exist' <<<"$output"; then
        printf 'Error: expected "does not exist" message not found\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'invalid commit ref'
}

test_catch_uncommitted_changes() {
    local before after exit_status errors=0

    echo 'dirty' >>file_1.txt
    before=$(git rev-parse HEAD)
    ./"${SCRIPT_NAME}" --no-confirm --no-backup >/dev/null 2>&1
    exit_status=$?
    after=$(git rev-parse HEAD)
    git checkout -- file_1.txt

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: script proceeded despite uncommitted changes\n'
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: HEAD changed despite uncommitted-changes guard\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'uncommitted changes guard'
}

test_flag_missing_value() {
    # @param $1  flag under test: --date | --name | --email
    local flag="$1" before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch "$flag" 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: %s with no value did not fail as expected\n' "$flag"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite %s missing its value\n' "$flag"
        errors=$((errors + 1))
    fi
    if ! grep -qi 'requires a value' <<<"$output"; then
        printf 'Error: expected "requires a value" message not found\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" "flag with missing value: $flag"
}

test_flag_unknown() {
    local before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(./"${SCRIPT_NAME}" --no-confirm --no-backup --bogus-flag HEAD 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: unknown flag did not cause failure\n'
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite unknown flag\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'unknown option' <<<"$output"; then
        printf 'Error: expected "Unknown option" message not found\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'unknown flag'
}

test_catch_incompatible_quiet_verbose() {
    local before after exit_status errors=0

    before=$(git rev-parse HEAD)
    ./"${SCRIPT_NAME}" --no-confirm --no-backup --quiet --verbose HEAD >/dev/null 2>&1
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: --quiet --verbose did not fail as expected\n'
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite incompatible --quiet --verbose\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'catch incompatible --quiet --verbose'
}

test_match_malformed_date() {
    local before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --date 'not-a-real-date' HEAD 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: malformed --date value did not cause failure\n'
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite malformed --date value\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'error' <<<"$output"; then
        printf 'Error: expected an error message for malformed --date\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'malformed --date value is rejected safely'
}
