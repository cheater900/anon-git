#!/usr/bin/env bash

# Sourced by test_anon_git.sh — not meant to be run directly.
# FLAG TESTS: individual CLI flags governing how a run behaves
# (branching, backups, dry-run, quiet/verbose, timezone, confirmation).

test_flag_current_branch_backup() {
    local before_head after_head exit_status backup_branch errors=0

    before_head=$(git rev-parse HEAD)

    ./"${SCRIPT_NAME}" --no-confirm --current-branch --name 'Edsger Dijkstra' HEAD >/dev/null 2>&1
    exit_status=$?
    after_head=$(git rev-parse HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --current-branch run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$after_head" == "$before_head" ]]; then
        printf 'Error: current branch HEAD did not change\n'
        errors=$((errors + 1))
    fi

    backup_branch=$(git branch --format='%(refname:short)' | grep '_backup_' | tail -1)
    if [[ -z "$backup_branch" ]]; then
        printf 'Error: no backup branch was created\n'
        errors=$((errors + 1))
    elif [[ "$(git rev-parse "$backup_branch")" != "$before_head" ]]; then
        printf 'Error: backup branch does not point at pre-rewrite HEAD\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'creates backup with flag --current-branch'
}

test_flag_dry_run() {
    local before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(PAGER="cat" ./"${SCRIPT_NAME}" --dry-run HEAD 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --dry-run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: --dry-run modified HEAD\n'
        errors=$((errors + 1))
    fi
    if ! grep -q 'AuthorDate:' <<<"$output"; then
        printf 'Error: --dry-run output missing expected preview content\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag dry-run'
}

test_flag_keep_partial() {
    # $1: --keep-year | --keep-month | --keep-day
    local flag="$1" random_index commit_hash old_year old_month old_day
    local new_commit_hash new_year new_month new_day exit_status errors=0

    random_index=$(($(od -An -N2 -tu2 </dev/urandom) % (COMMIT_COUNT - 1)))
    commit_hash=$(git rev-parse "HEAD~${random_index}")
    old_year=$(git show -s --date=format:'%Y' --format='%ad' "$commit_hash")
    old_month=$(git show -s --date=format:'%m' --format='%ad' "$commit_hash")
    old_day=$(git show -s --date=format:'%d' --format='%ad' "$commit_hash")

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch "$flag" "HEAD~${random_index}" >/dev/null 2>&1
    exit_status=$?

    new_commit_hash=$(git rev-parse "HEAD~${random_index}")
    new_year=$(git show -s --date=format:'%Y' --format='%ad' "$new_commit_hash")
    new_month=$(git show -s --date=format:'%m' --format='%ad' "$new_commit_hash")
    new_day=$(git show -s --date=format:'%d' --format='%ad' "$new_commit_hash")

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: %s exited with status %s\n' "$flag" "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$new_year" != "$old_year" ]]; then
        printf 'Error: %s did not preserve year\n' "$flag"
        errors=$((errors + 1))
    fi
    if [[ "$flag" == '--keep-month' || "$flag" == '--keep-day' ]]; then
        if [[ "$new_month" != "$old_month" ]]; then
            printf 'Error: %s did not preserve month\n' "$flag"
            errors=$((errors + 1))
        fi
    fi
    if [[ "$flag" == '--keep-day' ]]; then
        if [[ "$new_day" != "$old_day" ]]; then
            printf 'Error: %s did not preserve day\n' "$flag"
            errors=$((errors + 1))
        fi
    fi

    record_result "$errors" "flag $flag"
}

test_flag_new_branch() {
    # Default (no --current-branch): a fresh "<branch>_anonymized_<timestamp>"
    # branch is created; the original branch/HEAD stays untouched.
    local original_branch before_head exit_status new_branch_name errors=0

    original_branch=$(git branch --show-current)
    before_head=$(git rev-parse HEAD)

    ./"${SCRIPT_NAME}" --no-confirm --name 'John von Neumann' HEAD >/dev/null 2>&1
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: default run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi

    new_branch_name=$(git branch --format='%(refname:short)' | grep "^${original_branch}_anonymized_" | tail -1)
    if [[ -z "$new_branch_name" ]]; then
        printf 'Error: expected a new "%s_anonymized_*" branch to be created\n' "$original_branch"
        errors=$((errors + 1))
    fi

    git switch "$original_branch" >/dev/null 2>&1
    if [[ "$(git rev-parse HEAD)" != "$before_head" ]]; then
        printf 'Error: original branch was modified by the default (new-branch) run\n'
        errors=$((errors + 1))
    fi

    [[ -n "$new_branch_name" ]] && git branch -D "$new_branch_name" >/dev/null 2>&1

    record_result "$errors" 'it creates new branch by default'
}

test_flag_no_backup() {
    # Compares counts rather than asserting zero: an earlier test may have
    # already left a backup branch in the shared test repo.
    local before_head after_head exit_status before_count after_count errors=0

    before_head=$(git rev-parse HEAD)
    before_count=$(git branch --format='%(refname:short)' | grep -c '_backup_')

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --name 'Rosalind Franklin' HEAD >/dev/null 2>&1
    exit_status=$?
    after_head=$(git rev-parse HEAD)
    after_count=$(git branch --format='%(refname:short)' | grep -c '_backup_')

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --no-backup run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$after_head" == "$before_head" ]]; then
        printf 'Error: current branch HEAD did not change\n'
        errors=$((errors + 1))
    fi
    if [[ "$after_count" -ne "$before_count" ]]; then
        printf 'Error: --no-backup created a new backup branch (before=%s, after=%s)\n' "$before_count" "$after_count"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --no-backup skips backup branch'
}

test_flag_quiet() {
    # Must suppress informational output but still rewrite and exit 0. Uses
    # the default (new-branch) path, not --current-branch --no-backup, since
    # that prints a safety warning --quiet deliberately doesn't suppress.
    local original_branch new_branch_name output exit_status errors=0

    original_branch=$(git branch --show-current)

    output=$(./"${SCRIPT_NAME}" --no-confirm --quiet --name 'Ken Thompson' HEAD 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --quiet run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ -n "$output" ]]; then
        printf 'Error: --quiet produced output: %s\n' "$output"
        errors=$((errors + 1))
    fi

    new_branch_name=$(git branch --format='%(refname:short)' | grep "^${original_branch}_anonymized_" | tail -1)
    if [[ -z "$new_branch_name" ]]; then
        printf 'Error: --quiet did not still rewrite the commit onto a new branch\n'
        errors=$((errors + 1))
    elif [[ "$(git show -s --format='%an' "$new_branch_name")" != 'Ken Thompson' ]]; then
        printf 'Error: --quiet did not still rewrite the commit\n'
        errors=$((errors + 1))
    fi

    git switch "$original_branch" >/dev/null 2>&1
    [[ -n "$new_branch_name" ]] && git branch -D "$new_branch_name" >/dev/null 2>&1

    record_result "$errors" 'flag --quiet suppresses informational output'
}

test_flag_strip_timezone_alone() {
    # Alone, must not change author or date/time digits -- only relabel the
    # offset to +0000 (original is +0530, unambiguously not already UTC).
    local commit_hash old_author old_date_no_tz old_offset exit_status
    local new_commit_hash new_author new_date_no_tz new_offset errors=0

    echo 'strip timezone alone' >strip_tz_alone_file.txt
    git add strip_tz_alone_file.txt >/dev/null
    GIT_AUTHOR_DATE='1600000000 +0530' GIT_COMMITTER_DATE='1600000000 +0530' \
        git commit -m 'Strip timezone alone test' >/dev/null
    commit_hash=$(git rev-parse HEAD)

    old_author=$(git show -s --format='%an <%ae>' "$commit_hash")
    old_date_no_tz=$(git show -s --date=format:'%Y-%m-%d %H:%M:%S' --format='%ad' "$commit_hash")
    old_offset=$(git show -s --date=format:'%z' --format='%ad' "$commit_hash")

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --strip-timezone "$commit_hash" >/dev/null 2>&1
    exit_status=$?

    new_commit_hash=$(git rev-parse HEAD)
    new_author=$(git show -s --format='%an <%ae>' "$new_commit_hash")
    new_date_no_tz=$(git show -s --date=format:'%Y-%m-%d %H:%M:%S' --format='%ad' "$new_commit_hash")
    new_offset=$(git show -s --date=format:'%z' --format='%ad' "$new_commit_hash")

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --strip-timezone (alone) exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$old_offset" == '+0000' ]]; then
        printf 'Error: test setup bug: commit already had a +0000 offset\n'
        errors=$((errors + 1))
    fi
    if [[ "$new_author" != "$old_author" ]]; then
        printf 'Error: --strip-timezone (alone) changed author identity (%s -> %s)\n' "$old_author" "$new_author"
        errors=$((errors + 1))
    fi
    if [[ "$new_date_no_tz" != "$old_date_no_tz" ]]; then
        printf 'Error: --strip-timezone (alone) changed the date/time digits (%s -> %s)\n' "$old_date_no_tz" "$new_date_no_tz"
        errors=$((errors + 1))
    fi
    if [[ "$new_offset" != '+0000' ]]; then
        printf 'Error: --strip-timezone (alone) did not force the offset to +0000 (got %s)\n' "$new_offset"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --strip-timezone alone preserves author/date, forces UTC+0000'
}

test_flag_strip_timezone_with_keep_date() {
    # Not the "used alone" case: --keep-date preserves digits, --strip-timezone
    # still forces +0000. Author identity is NOT implied kept (only
    # --keep-date given, not --keep-user), so it falls back to the default.
    local old_date_no_tz old_offset exit_status
    local new_author new_date_no_tz new_offset errors=0

    echo 'strip timezone with keep-date' >strip_tz_keepdate_file.txt
    git add strip_tz_keepdate_file.txt >/dev/null
    GIT_AUTHOR_DATE='1650000000 -0700' GIT_COMMITTER_DATE='1650000000 -0700' \
        git commit -m 'Strip timezone with keep-date test' >/dev/null

    old_date_no_tz=$(git show -s --date=format:'%Y-%m-%d %H:%M:%S' --format='%ad' HEAD)
    old_offset=$(git show -s --date=format:'%z' --format='%ad' HEAD)

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --strip-timezone --keep-date HEAD >/dev/null 2>&1
    exit_status=$?

    new_author=$(git show -s --format='%an <%ae>' HEAD)
    new_date_no_tz=$(git show -s --date=format:'%Y-%m-%d %H:%M:%S' --format='%ad' HEAD)
    new_offset=$(git show -s --date=format:'%z' --format='%ad' HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --strip-timezone --keep-date exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$old_offset" == '+0000' ]]; then
        printf 'Error: test setup bug: commit already had a +0000 offset\n'
        errors=$((errors + 1))
    fi
    if [[ "$new_author" != "${DEFAULT_NAME} <${DEFAULT_EMAIL}>" ]]; then
        printf 'Error: --strip-timezone --keep-date unexpectedly preserved author identity (got %s)\n' "$new_author"
        errors=$((errors + 1))
    fi
    if [[ "$new_date_no_tz" != "$old_date_no_tz" ]]; then
        printf 'Error: --strip-timezone --keep-date changed the date/time digits (%s -> %s)\n' "$old_date_no_tz" "$new_date_no_tz"
        errors=$((errors + 1))
    fi
    if [[ "$new_offset" != '+0000' ]]; then
        printf 'Error: --strip-timezone --keep-date did not force the offset to +0000 (got %s)\n' "$new_offset"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --strip-timezone + --keep-date preserves date digits, forces UTC+0000'
}

test_flag_strip_timezone_with_date_arg() {
    # Must use --date's digits but force +0000, ignoring --date's own offset.
    local exit_status new_date errors=0

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch \
        --strip-timezone --date '2025-06-15 14:20:00 +0300' HEAD >/dev/null 2>&1
    exit_status=$?

    new_date=$(git show -s --date=iso --format='%ad' HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --strip-timezone --date exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$new_date" != '2025-06-15 14:20:00 +0000' ]]; then
        printf 'Error: --strip-timezone --date did not keep digits with a +0000 offset (got %s)\n' "$new_date"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --strip-timezone + --date keeps digits, forces UTC+0000'
}

test_flag_strip_timezone_not_alone_resets_date() {
    # Any other flag alongside --strip-timezone (here --name) breaks the
    # "used alone" contract: date is NOT implicitly preserved, falls through
    # to the default-date path (already +0000).
    local exit_status new_author new_date errors=0

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch \
        --strip-timezone --name 'Strip TZ Not Alone' HEAD >/dev/null 2>&1
    exit_status=$?

    new_author=$(git show -s --format='%an <%ae>' HEAD)
    new_date=$(git show -s --date=iso --format='%ad' HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --strip-timezone --name exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$new_author" != "Strip TZ Not Alone <${DEFAULT_EMAIL}>" ]]; then
        printf 'Error: --strip-timezone --name did not change author as expected (got %s)\n' "$new_author"
        errors=$((errors + 1))
    fi
    if [[ "$new_date" != "$DEFAULT_DATE" ]]; then
        printf 'Error: --strip-timezone with another flag unexpectedly preserved the original date (got %s, expected default %s)\n' "$new_date" "$DEFAULT_DATE"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --strip-timezone + another flag is not "alone": date resets to default'
}

test_flag_no_confirm() {
    # Without it, declining (n) must abort with no changes, accepting (y) must proceed.
    local before after exit_status errors=0

    before=$(git rev-parse HEAD)
    echo 'n' | ./"${SCRIPT_NAME}" --no-backup HEAD >/dev/null 2>&1
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: declining the confirmation prompt (n) did not abort\n'
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite declining the confirmation prompt\n'
        errors=$((errors + 1))
    fi

    before=$(git rev-parse HEAD)
    echo 'y' | ./"${SCRIPT_NAME}" --no-backup --current-branch --name 'Alonzo Church' HEAD >/dev/null 2>&1
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: accepting the confirmation prompt (y) did not succeed\n'
        errors=$((errors + 1))
    fi
    if [[ "$after" == "$before" ]]; then
        printf 'Error: accepting the confirmation prompt (y) did not rewrite HEAD\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --no-confirm skips confirmation prompt'
}

test_noconfirm_executes_first() {
    # Regression: confirm() must run before backup_branch() in main().
    # backup_branch() switches to a new branch at the same commit, so
    # checking only `git rev-parse HEAD` can't distinguish a clean decline
    # from a decline-after-branch-switch. Assert on the branch name instead.
    local branch_before branch_after branch_count_before branch_count_after errors=0

    branch_before=$(git branch --show-current)
    branch_count_before=$(git branch --list | wc -l)

    echo 'n' | ./"${SCRIPT_NAME}" HEAD >/dev/null 2>&1

    branch_after=$(git branch --show-current)
    branch_count_after=$(git branch --list | wc -l)

    if [[ "$branch_after" != "$branch_before" ]]; then
        printf 'Error: declining the confirmation prompt left a different branch checked out (%s -> %s)\n' \
            "$branch_before" "$branch_after"
        errors=$((errors + 1))
    fi
    if [[ "$branch_count_after" != "$branch_count_before" ]]; then
        printf 'Error: declining the confirmation prompt still created a branch (%s -> %s branches)\n' \
            "$branch_count_before" "$branch_count_after"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'declining the confirmation prompt creates no branch'
}

test_flag_keep_user_keep_date_verbose_message() {
    # Output must say author/date aren't overwritten, not claim the unused
    # default/env identity or date is "in use".
    local output exit_status errors=0

    output=$(./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --keep-user --keep-date HEAD 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --keep-user --keep-date run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if ! grep -q 'Not overwriting user/email\.' <<<"$output"; then
        printf 'Error: --keep-user did not print "Not overwriting user/email." (got: %s)\n' "$output"
        errors=$((errors + 1))
    fi
    if ! grep -q 'Not overwriting date\.' <<<"$output"; then
        printf 'Error: --keep-date did not print "Not overwriting date." (got: %s)\n' "$output"
        errors=$((errors + 1))
    fi
    if grep -q 'Using identity:' <<<"$output"; then
        printf 'Error: --keep-user still printed the stale "Using identity: ..." message\n'
        errors=$((errors + 1))
    fi
    if grep -q 'Using date:' <<<"$output"; then
        printf 'Error: --keep-date still printed the stale "Using date: ..." message\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flags --keep-user --keep-date print "Not overwriting ..." instead of the stale default'
}
