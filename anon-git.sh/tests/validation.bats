#!/usr/bin/env bats

# VALIDATION TESTS: rejecting bad input (incompatible flags, invalid commit
# refs, a dirty tree, malformed dates) and the python-callback syntax check.

load test_helper

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

@test "python commit callback syntax valid" {
    # Wrapped in a dummy function before compiling since the body uses bare
    # `return`, only legal inside a function -- matching how
    # git-filter-repo itself embeds the callback.
    local python_code check_file
    python_code=$(extract_script_block python_commit_callback)
    assert [ -n "$python_code" ]
    check_file=${BATS_TEST_TMPDIR}/python_commit_callback_check.py
    {
        printf 'def _commit_callback(commit, metadata):\n'
        printf '%s\n' "    ${python_code//$'\n'/$'\n    '}"
    } >"$check_file"
    run python3 -m py_compile "$check_file"
    assert_success
}

@test "rejects --date with --keep-date" {
    assert_incompatible --date '2020-01-01 00:00:00 +0000' --keep-date
}

@test "rejects --date with --keep-year" {
    assert_incompatible --date '2020-01-01 00:00:00 +0000' --keep-year
}

@test "rejects --keep-user with --name" {
    assert_incompatible --keep-user --name 'Nobody'
}

@test "rejects --keep-user with --email" {
    assert_incompatible --keep-user --email 'nobody@example.com'
}

@test "rejects --keep-year with --keep-month" {
    assert_incompatible --keep-year --keep-month
}

@test "rejects --keep-year with --keep-day" {
    assert_incompatible --keep-year --keep-day
}

@test "rejects --keep-month with --keep-day" {
    assert_incompatible --keep-month --keep-day
}

@test "rejects --entire-history with commit" {
    assert_incompatible --entire-history HEAD
}

# random-time/day/month: only one at a time, none with --keep-* (both
# families dictate a fill strategy), none with an explicit --date.
@test "rejects --random-day with --keep-day" {
    assert_incompatible --random-day --keep-day
}

@test "rejects --random-time with --keep-year" {
    assert_incompatible --random-time --keep-year
}

@test "rejects --random-month with --keep-month" {
    assert_incompatible --random-month --keep-month
}

@test "rejects --keep-date with --random-time" {
    assert_incompatible --keep-date --random-time
}

@test "rejects --random-time with --random-day" {
    assert_incompatible --random-time --random-day
}

@test "rejects --random-day with --random-month" {
    assert_incompatible --random-day --random-month
}

@test "rejects --random-time with --random-month" {
    assert_incompatible --random-time --random-month
}

@test "rejects --date with --random-month" {
    assert_incompatible --date '2020-01-01 00:00:00 +0000' --random-month
}

# Same combinations via their ANON_GIT_* envvar equivalents (--entire-history
# has none: no ANON_GIT_COMMIT envvar exists, so it's flag-only).
@test "rejects ANON_GIT_DATE with ANON_GIT_KEEPDATE" {
    assert_incompatible 'ANON_GIT_DATE=2020-01-01 00:00:00 +0000' ANON_GIT_KEEPDATE=1
}

@test "rejects ANON_GIT_DATE with ANON_GIT_KEEPYEAR" {
    assert_incompatible 'ANON_GIT_DATE=2020-01-01 00:00:00 +0000' ANON_GIT_KEEPYEAR=1
}

@test "rejects ANON_GIT_KEEPUSER with ANON_GIT_NAME" {
    assert_incompatible ANON_GIT_KEEPUSER=1 ANON_GIT_NAME=Nobody
}

@test "rejects ANON_GIT_KEEPUSER with ANON_GIT_EMAIL" {
    assert_incompatible ANON_GIT_KEEPUSER=1 ANON_GIT_EMAIL=nobody@example.com
}

@test "rejects ANON_GIT_KEEPYEAR with ANON_GIT_KEEPMONTH" {
    assert_incompatible ANON_GIT_KEEPYEAR=1 ANON_GIT_KEEPMONTH=1
}

@test "rejects ANON_GIT_KEEPYEAR with ANON_GIT_KEEPDAY" {
    assert_incompatible ANON_GIT_KEEPYEAR=1 ANON_GIT_KEEPDAY=1
}

@test "rejects ANON_GIT_KEEPMONTH with ANON_GIT_KEEPDAY" {
    assert_incompatible ANON_GIT_KEEPMONTH=1 ANON_GIT_KEEPDAY=1
}

@test "rejects ANON_GIT_RANDOMDAY with ANON_GIT_KEEPDAY" {
    assert_incompatible ANON_GIT_RANDOMDAY=1 ANON_GIT_KEEPDAY=1
}

@test "rejects ANON_GIT_RANDOMTIME with ANON_GIT_RANDOMMONTH" {
    assert_incompatible ANON_GIT_RANDOMTIME=1 ANON_GIT_RANDOMMONTH=1
}

@test "rejects --quiet with --verbose" {
    run ./anon-git.sh --no-confirm --no-backup --quiet --verbose HEAD
    assert_failure
    assert_head_unchanged
}

@test "rejects invalid commit ref" {
    run ./anon-git.sh --no-confirm --no-backup deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
    assert_failure
    assert_head_unchanged
    assert_output --partial 'does not exist'
}

@test "rejects uncommitted changes" {
    echo 'dirty' >>file_1.txt
    run ./anon-git.sh --no-confirm --no-backup
    assert_failure
    assert_head_unchanged
}

missing_value() {
    # $@: --date | --name | --email, optionally followed by an empty value
    run ./anon-git.sh --no-confirm --no-backup --current-branch "$@"
    assert_failure
    assert_head_unchanged
    assert_output --partial 'requires a value'
}

@test "rejects --date without value" {
    missing_value --date
}

@test "rejects --name without value" {
    missing_value --name
}

@test "rejects --email without value" {
    missing_value --email
}

@test "rejects empty --name" {
    missing_value --name ''
}

@test "rejects empty --date" {
    missing_value --date ''
}

@test "rejects unknown flag" {
    run ./anon-git.sh --no-confirm --no-backup --bogus-flag HEAD
    assert_failure
    assert_head_unchanged
    assert_output --partial 'Unknown option'
}

@test "rejects malformed --date safely" {
    run ./anon-git.sh --no-confirm --no-backup --current-branch --date 'not-a-real-date' HEAD
    assert_failure
    assert_head_unchanged
    assert_output --regexp '[Ee]rror'
}

malformed_date_no_branch() {
    # $1: rejected date
    run ./anon-git.sh --no-confirm --date "$1" HEAD
    assert_failure
    assert_equal "$(branch_count)" 1
    assert_output --partial 'invalid date'
}

@test "rejects out-of-range --date before branch creation" {
    malformed_date_no_branch '2025-13-45 99:00:00 +0000'
}

@test "rejects pre-1970 --date before branch creation" {
    malformed_date_no_branch '1960-01-01 00:00:00 +0000'
}

invalid_identity() {
    # $1: --name | --email, $2: value fast-import can't encode in an ident
    run ./anon-git.sh --no-confirm "$1" "$2" HEAD
    assert_failure
    assert_head_unchanged
    assert_equal "$(branch_count)" 1
    assert_output --partial 'must not contain'
}

@test "rejects --name with angle brackets before branch creation" {
    invalid_identity --name 'Ev<il>'
}

@test "rejects --email with angle bracket before branch creation" {
    invalid_identity --email 'a>b@example.com'
}

@test "rejects --name with newline before branch creation" {
    invalid_identity --name $'Line\nBreak'
}

@test "rejects commit not reachable from HEAD" {
    local original_branch side_commit
    original_branch=$(git branch --show-current)
    git switch -q --create side
    git commit -q --allow-empty -m 'Side commit'
    side_commit=$(git rev-parse HEAD)
    git switch -q "$original_branch"
    run ./anon-git.sh --no-confirm --no-backup --current-branch "$side_commit"
    assert_failure
    assert_output --partial 'not reachable from HEAD'
    assert_head_unchanged
}
