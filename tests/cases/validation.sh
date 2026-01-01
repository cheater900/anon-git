#!/usr/bin/env bash

# Sourced by test_anon_git.sh — not meant to be run directly.
# VALIDATION TESTS: rejecting bad input (incompatible flags, invalid commit
# refs, a dirty tree, malformed dates) and the python-callback syntax check.

test_python_callback_syntax() {
    # Extracts python_commit_callback's contents and checks they're valid
    # Python. Wrapped in a dummy function before compiling since the body
    # uses bare `return`, only legal inside a function -- matching how
    # git-filter-repo itself embeds the callback.
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
    # $@: the incompatible combination to reject -- CLI flags/args and/or
    # single "ANON_GIT_NAME=value" envvar assignments (routed to `env`), in
    # any mix. Covers flag-vs-flag, envvar-vs-envvar, and mixed conflicts
    # with one function, since a conflict must be rejected the same way
    # regardless of which side came from a flag vs. its envvar.
    local before after output exit_status errors=0 envvars=() cli_args=() arg label

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
    output=$(env "${envvars[@]}" ./"${SCRIPT_NAME}" --no-confirm --no-backup "${cli_args[@]}" 2>&1)
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
    if ! grep -q 'cannot be used together' <<<"$output"; then
        printf 'Error: "%s" failed without conflict message (got: %s)\n' "$*" "$output"
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

    record_result "$errors" 'invalid commit ref rejected'
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

    record_result "$errors" 'uncommitted changes rejected'
}

test_flag_missing_value() {
    # $1: --date | --name | --email, $2 (optional): empty value, e.g. ''
    local flag="$1" before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch "$@" 2>&1)
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

    record_result "$errors" "flag with missing value: $flag${2+ (empty)}"
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

    record_result "$errors" 'unknown flag rejected'
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

    record_result "$errors" 'malformed --date rejected safely'
}

test_match_malformed_date_no_branch() {
    # $1 (optional): rejected date, default an out-of-range one
    local date="${1:-2025-13-45 99:00:00 +0000}" branch_before branch_count_before output exit_status errors=0

    branch_before=$(git branch --show-current)
    branch_count_before=$(git branch --list | wc -l)
    output=$(./"${SCRIPT_NAME}" --no-confirm --date "$date" HEAD 2>&1)
    exit_status=$?

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: malformed --date value did not cause failure\n'
        errors=$((errors + 1))
    fi
    if [[ "$(git branch --list | wc -l)" != "$branch_count_before" ]]; then
        printf 'Error: malformed --date left a stray branch\n'
        errors=$((errors + 1))
    fi
    if ! grep -q 'invalid date' <<<"$output"; then
        printf 'Error: expected "invalid date" message not found (got: %s)\n' "$output"
        errors=$((errors + 1))
    fi
    git switch "$branch_before" >/dev/null 2>&1

    record_result "$errors" "malformed --date $date rejected before branch creation"
}

test_match_invalid_identity() {
    # $1: --name | --email, $2: value fast-import can't encode in an ident
    local branch_count_before before output exit_status errors=0

    before=$(git rev-parse HEAD)
    branch_count_before=$(git branch --list | wc -l)
    output=$(./"${SCRIPT_NAME}" --no-confirm "$1" "$2" HEAD 2>&1)
    exit_status=$?

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: %s %q did not fail\n' "$1" "$2"
        errors=$((errors + 1))
    fi
    if [[ "$(git rev-parse HEAD)" != "$before" ]]; then
        printf 'Error: HEAD changed despite invalid %s\n' "$1"
        errors=$((errors + 1))
    fi
    if [[ "$(git branch --list | wc -l)" != "$branch_count_before" ]]; then
        printf 'Error: invalid %s left a stray branch\n' "$1"
        errors=$((errors + 1))
    fi
    if ! grep -q 'must not contain' <<<"$output"; then
        printf 'Error: expected "must not contain" message not found (got: %s)\n' "$output"
        errors=$((errors + 1))
    fi

    record_result "$errors" "invalid identity $1 $(printf '%q' "$2") rejected before branch creation"
}

test_match_unreachable_commit() {
    local original_branch side_branch="unreachable_$$" side_commit before output exit_status errors=0

    original_branch=$(git branch --show-current)
    git switch --create "$side_branch" >/dev/null 2>&1
    git commit -q --allow-empty -m 'Side commit'
    side_commit=$(git rev-parse HEAD)
    git switch "$original_branch" >/dev/null 2>&1

    before=$(git rev-parse HEAD)
    output=$(./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch "$side_commit" 2>&1)
    exit_status=$?

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: unreachable commit target did not fail\n'
        errors=$((errors + 1))
    fi
    if ! grep -q 'not reachable from HEAD' <<<"$output"; then
        printf 'Error: expected "not reachable from HEAD" message not found (got: %s)\n' "$output"
        errors=$((errors + 1))
    fi
    if [[ "$(git rev-parse HEAD)" != "$before" ]]; then
        printf 'Error: HEAD changed despite unreachable target\n'
        errors=$((errors + 1))
    fi
    git branch -D "$side_branch" >/dev/null

    record_result "$errors" 'commit not reachable from HEAD rejected'
}
