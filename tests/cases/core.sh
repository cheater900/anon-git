#!/usr/bin/env bash

# Sourced by test-anon-git.sh — not meant to be run directly.
# CORE / INTEGRATION TESTS: rewriting multiple commits or the entire history in one run.

test_multiple_commits() {
    local h1 h2 exit_status a1 a2 errors=0

    h1=$(git rev-parse HEAD~1)
    h2=$(git rev-parse HEAD~3)

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --name 'Donald Knuth' --email 'donald.knuth@example.com' "$h1" "$h2" >/dev/null 2>&1
    exit_status=$?

    a1=$(git show -s --format='%an <%ae>' HEAD~1)
    a2=$(git show -s --format='%an <%ae>' HEAD~3)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: multi-commit run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$a1" != 'Donald Knuth <donald.knuth@example.com>' ]]; then
        printf 'Error: first target commit not anonymized\n'
        errors=$((errors + 1))
    fi
    if [[ "$a2" != 'Donald Knuth <donald.knuth@example.com>' ]]; then
        printf 'Error: second target commit not anonymized\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'multiple commits in one run'
}

test_entire_history() {
    local exit_status mismatches errors=0

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --entire-history >/dev/null 2>&1
    exit_status=$?

    mismatches=$(git log --format='%an <%ae>' | grep --invert-match --count "^${DEFAULT_NAME} <${DEFAULT_EMAIL}>\$")

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --entire-history exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$mismatches" -ne 0 ]]; then
        printf 'Error: --entire-history left %s commit(s) with a non-default author\n' "$mismatches"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --entire-history'
}
