#!/usr/bin/env bash

# Sourced by test-anon-git.sh — not meant to be run directly.
# HELP / VERSION TESTS: --help, --version, and the default-to-help paths.

test_show_help() {
    local output exit_status errors=0

    output=$(./"${SCRIPT_NAME}" --help 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --help exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if ! grep -q 'Usage:' <<<"$output"; then
        printf 'Error: --help output missing usage text\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'show --help'
}

test_show_version() {
    # --version/-v are handled in handle_early_options, before any git-repo
    # safety checks, so they must work even outside a repository (same as
    # --help) and must print a non-empty version string.
    local no_repo_dir output exit_status errors=0

    output=$(./"${SCRIPT_NAME}" --version 2>&1)
    exit_status=$?
    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --version exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if ! grep -qE '^anon-git [0-9]+\.[0-9]+\.[0-9]+$' <<<"$output"; then
        printf 'Error: --version output did not match "anon-git X.Y.Z" (got "%s")\n' "$output"
        errors=$((errors + 1))
    fi

    output=$(./"${SCRIPT_NAME}" -v 2>&1)
    exit_status=$?
    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: -v exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if ! grep -qE '^anon-git [0-9]+\.[0-9]+\.[0-9]+$' <<<"$output"; then
        printf 'Error: -v output did not match "anon-git X.Y.Z" (got "%s")\n' "$output"
        errors=$((errors + 1))
    fi

    # Must not require a git repository (mirrors test_match_outside_git_repo).
    no_repo_dir=$(mktemp -d /tmp/anon_git_test_version_norepo.XXXXXX)
    cp "$SCRIPT" "$no_repo_dir/"
    chmod +x "${no_repo_dir}/${SCRIPT_NAME}"
    output=$(cd "$no_repo_dir" && "./${SCRIPT_NAME}" --version 2>&1)
    exit_status=$?
    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --version outside a git repository exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    rm -rf "$no_repo_dir"

    record_result "$errors" 'show --version / -v'
}

test_show_help_inside_dirty_repo() {
    # A bare invocation (no args) should show help unconditionally, before
    # any safety checks run — an unstaged change to a tracked file should
    # not turn it into a hard failure, since there's nothing here for the
    # script to do or lose. Modifies an existing tracked file (rather than
    # adding an untracked one) since the uncommitted-changes guard this is
    # meant to bypass only looks at diff-index/diff-files, not untracked
    # files.
    local tracked_file before after output exit_status errors=0

    tracked_file='file_1.txt'
    echo 'uncommitted change' >>"$tracked_file"

    before=$(git rev-parse HEAD)
    output=$(./"${SCRIPT_NAME}" 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: bare invocation in a dirty repo exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: bare invocation in a dirty repo modified HEAD\n'
        errors=$((errors + 1))
    fi
    if ! grep -q 'Usage:' <<<"$output"; then
        printf 'Error: bare invocation in a dirty repo did not show help\n'
        errors=$((errors + 1))
    fi

    git checkout -- "$tracked_file"

    record_result "$errors" 'show help inside dirty repo (no args)'
}

test_match_default_shows_help() {
    # Default behavior: without an explicit commit target or --entire-history,
    # the script shows help instead of silently defaulting to HEAD.
    local before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(./"${SCRIPT_NAME}" 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: bare invocation (no target) exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: bare invocation (no target) modified HEAD\n'
        errors=$((errors + 1))
    fi
    if ! grep -q 'Usage:' <<<"$output"; then
        printf 'Error: bare invocation (no target) did not show help\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'no commit target will show help by default'
}

test_match_dry_run_without_target_shows_help() {
    # --dry-run alone doesn't count as a target; without an explicit commit or
    # --entire-history it must still fall through to the help text, not
    # silently preview HEAD.
    local before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(PAGER="cat" ./"${SCRIPT_NAME}" --dry-run 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --dry-run without a target exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: --dry-run without a target modified HEAD\n'
        errors=$((errors + 1))
    fi
    if ! grep -q 'Usage:' <<<"$output"; then
        printf 'Error: --dry-run without a target did not show help\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --dry-run without a target still shows help'
}
