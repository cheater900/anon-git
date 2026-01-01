#!/usr/bin/env bats

# FLAG TESTS: individual CLI flags governing how a run behaves
# (branching, backups, dry-run, quiet/verbose, timezone, confirmation).

load test_helper

@test "--current-branch creates backup" {
    local backup_branch
    run ./anon-git.sh --no-confirm --current-branch --name 'Edsger Dijkstra' HEAD
    assert_success
    assert_not_equal "$(git rev-parse HEAD)" "$HEAD_BEFORE"
    backup_branch=$(git branch --format='%(refname:short)' | grep '_backup_' | tail -1)
    assert [ -n "$backup_branch" ]
    assert_equal "$(git rev-parse "$backup_branch")" "$HEAD_BEFORE"
}

dry_run() {
    # $1: PAGER value; may carry arguments, like git's
    PAGER=$1 run ./anon-git.sh --dry-run HEAD
    assert_success
    assert_head_unchanged
    assert_output --partial 'AuthorDate:'
}

@test "--dry-run with PAGER='cat' previews" {
    dry_run cat
}

@test "--dry-run with PAGER=\"cat -u\" previews" {
    dry_run 'cat -u'
}

keep_partial() {
    # $1: --keep-year | --keep-month | --keep-day
    local flag=$1 target old_year old_month old_day
    pick_random_index
    target="HEAD~${PICKED_INDEX}"
    old_year=$(commit_date "$target" '%Y')
    old_month=$(commit_date "$target" '%m')
    old_day=$(commit_date "$target" '%d')
    run ./anon-git.sh --no-confirm --no-backup --current-branch "$flag" "$target"
    assert_success
    assert_equal "$(commit_date "$target" '%Y')" "$old_year"
    if [[ "$flag" == '--keep-year' ]]; then
        return
    fi
    assert_equal "$(commit_date "$target" '%m')" "$old_month"
    if [[ "$flag" == '--keep-month' ]]; then
        return
    fi
    assert_equal "$(commit_date "$target" '%d')" "$old_day"
}

@test "--keep-year keeps year" {
    keep_partial --keep-year
}

@test "--keep-month keeps year, month" {
    keep_partial --keep-month
}

@test "--keep-day keeps year, month, day" {
    keep_partial --keep-day
}

@test "creates new branch by default" {
    # Default (no --current-branch): a fresh "<branch>_anonymized_<timestamp>"
    # branch is created; the original branch/HEAD stays untouched.
    local original_branch
    original_branch=$(git branch --show-current)
    run ./anon-git.sh --no-confirm --name 'John von Neumann' HEAD
    assert_success
    assert_regex "$(anonymized_branch)" "^${original_branch}_anonymized_"
    git switch -q "$original_branch"
    assert_head_unchanged
}

@test "--no-backup skips backup branch" {
    run ./anon-git.sh --no-confirm --no-backup --current-branch --name 'Rosalind Franklin' HEAD
    assert_success
    assert_not_equal "$(git rev-parse HEAD)" "$HEAD_BEFORE"
    assert_equal "$(branch_count)" 1
}

@test "--quiet silences informational output" {
    # Must suppress informational output but still rewrite and exit 0. Uses
    # the default (new-branch) path, not --current-branch --no-backup, since
    # that prints a safety warning --quiet deliberately doesn't suppress.
    local new_branch_name
    run ./anon-git.sh --no-confirm --quiet --name 'Ken Thompson' HEAD
    assert_success
    assert_output ''
    new_branch_name=$(anonymized_branch)
    assert [ -n "$new_branch_name" ]
    assert_equal "$(git show -s --format='%an' "$new_branch_name")" 'Ken Thompson'
}

@test "--strip-timezone alone keeps author, date digits, forces +0000" {
    # Alone, must not change author or date/time digits -- only relabel the
    # offset to +0000 (original is +0530, unambiguously not already UTC).
    local old_author old_date_no_tz
    echo 'strip timezone alone' >strip_tz_alone_file.txt
    git add strip_tz_alone_file.txt
    GIT_AUTHOR_DATE='1600000000 +0530' GIT_COMMITTER_DATE='1600000000 +0530' \
        git commit -q -m 'Strip timezone alone test'
    assert_equal "$(commit_date HEAD '%z')" '+0530'
    old_author=$(commit_author HEAD)
    old_date_no_tz=$(commit_date HEAD '%Y-%m-%d %H:%M:%S')
    run ./anon-git.sh --no-confirm --no-backup --current-branch --strip-timezone HEAD
    assert_success
    assert_equal "$(commit_author HEAD)" "$old_author"
    assert_equal "$(commit_date HEAD '%Y-%m-%d %H:%M:%S')" "$old_date_no_tz"
    assert_equal "$(commit_date HEAD '%z')" '+0000'
}

@test "--strip-timezone --keep-date keeps date digits, forces +0000" {
    # Not the "used alone" case: --keep-date preserves digits, --strip-timezone
    # still forces +0000. Author identity is NOT implied kept (only
    # --keep-date given, not --keep-user), so it falls back to the default.
    local old_date_no_tz
    echo 'strip timezone with keep-date' >strip_tz_keepdate_file.txt
    git add strip_tz_keepdate_file.txt
    GIT_AUTHOR_DATE='1650000000 -0700' GIT_COMMITTER_DATE='1650000000 -0700' \
        git commit -q -m 'Strip timezone with keep-date test'
    assert_equal "$(commit_date HEAD '%z')" '-0700'
    old_date_no_tz=$(commit_date HEAD '%Y-%m-%d %H:%M:%S')
    run ./anon-git.sh --no-confirm --no-backup --current-branch --strip-timezone --keep-date HEAD
    assert_success
    assert_equal "$(commit_author HEAD)" "$DEFAULT_AUTHOR"
    assert_equal "$(commit_date HEAD '%Y-%m-%d %H:%M:%S')" "$old_date_no_tz"
    assert_equal "$(commit_date HEAD '%z')" '+0000'
}

@test "--strip-timezone --date keeps digits, forces +0000" {
    # Must use --date's digits but force +0000, ignoring --date's own offset.
    run ./anon-git.sh --no-confirm --no-backup --current-branch \
        --strip-timezone --date '2025-06-15 14:20:00 +0300' HEAD
    assert_success
    assert_equal "$(git show -s --date=iso --format='%ad' HEAD)" '2025-06-15 14:20:00 +0000'
}

@test "--strip-timezone with other flag resets date to default" {
    # Any other flag alongside --strip-timezone (here --name) breaks the
    # "used alone" contract: date is NOT implicitly preserved, falls through
    # to the default-date path (already +0000).
    run ./anon-git.sh --no-confirm --no-backup --current-branch \
        --strip-timezone --name 'Strip TZ Not Alone' HEAD
    assert_success
    assert_equal "$(commit_author HEAD)" "Strip TZ Not Alone <${DEFAULT_EMAIL}>"
    assert_equal "$(git show -s --date=iso --format='%ad' HEAD)" "$DEFAULT_DATE"
}

@test "confirmation prompt: n aborts, y proceeds" {
    # Without --no-confirm, declining (n) must abort with no changes,
    # accepting (y) must proceed.
    run run_with_tty n ./anon-git.sh --no-backup HEAD
    assert_failure
    assert_head_unchanged
    run run_with_tty y ./anon-git.sh --no-backup --current-branch --name 'Alonzo Church' HEAD
    assert_success
    assert_not_equal "$(git rev-parse HEAD)" "$HEAD_BEFORE"
}

@test "declined confirmation creates no branch" {
    # Regression: confirm() must run before backup_branch() in main().
    # backup_branch() switches to a new branch at the same commit, so
    # checking only `git rev-parse HEAD` can't distinguish a clean decline
    # from a decline-after-branch-switch. Assert on the branch name instead.
    local branch_before
    branch_before=$(git branch --show-current)
    run run_with_tty n ./anon-git.sh HEAD
    assert_equal "$(git branch --show-current)" "$branch_before"
    assert_equal "$(branch_count)" 1
}

@test "confirmation without terminal fails with --no-confirm hint" {
    # Under xargs stdin is /dev/null; without a terminal confirm() must fail
    # with a hint instead of reading stdin.
    run run_without_tty ./anon-git.sh --no-backup --current-branch HEAD </dev/null
    assert_failure
    assert_output --partial '--no-confirm'
    assert_head_unchanged
}

@test "--keep-user --keep-date print \"Not overwriting\", not stale default" {
    # Output must say author/date aren't overwritten, not claim the unused
    # default/env identity or date is "in use".
    run ./anon-git.sh --no-confirm --no-backup --current-branch --keep-user --keep-date HEAD
    assert_success
    assert_output --partial 'Not overwriting user/email.'
    assert_output --partial 'Not overwriting date.'
    refute_output --partial 'Using identity:'
    refute_output --partial 'Using date:'
}
