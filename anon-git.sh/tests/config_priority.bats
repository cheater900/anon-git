#!/usr/bin/env bats

# CONFIG PRIORITY TESTS: precedence among CLI flags, git config anon-git.*,
# and ANON_GIT_* environment variables.

load test_helper

@test "--dry-run --entire-history without PAGER previews all, no rewrite" {
    run ./anon-git.sh --dry-run --entire-history
    assert_success
    assert_head_unchanged
    assert_equal "$(grep -c '^Commit:' <<<"$output")" "$COMMIT_COUNT"
}

@test "ANON_GIT_DRYRUN=1 ANON_GIT_ENTIREHISTORY=1 preview all, no rewrite" {
    # check_incompatible only looks at CLI-flag *_ARG variables, not envvars,
    # so both env vars together must still preview everything without
    # rewriting. --no-confirm is passed as a flag only to avoid the "zero
    # args" early-exit to help.
    PAGER='cat' ANON_GIT_DRYRUN=1 ANON_GIT_ENTIREHISTORY=1 run ./anon-git.sh --no-confirm
    assert_success
    assert_head_unchanged
    assert_equal "$(grep -c '^Commit:' <<<"$output")" "$COMMIT_COUNT"
}

@test "--name overrides ANON_GIT_NAME" {
    # Documented priority: flags > envvars > defaults.
    ANON_GIT_NAME='Ignored Env Name' run ./anon-git.sh --no-confirm --no-backup --current-branch --name 'Flag Wins' HEAD
    assert_success
    assert_equal "$(git show -s --format='%an' HEAD)" 'Flag Wins'
    run git show -s --pretty=fuller HEAD
    refute_output --partial 'Ignored Env Name'
}

@test "flag overrides envvar of same group" {
    # A flag overrides envvars of the same group instead of conflicting.
    local original_author
    original_author=$(git show -s --format='%an' HEAD)
    ANON_GIT_NAME='Env Name' run ./anon-git.sh --no-confirm --no-backup --current-branch --keep-user HEAD
    assert_success
    assert_equal "$(git show -s --format='%an' HEAD)" "$original_author"
    ANON_GIT_KEEPDATE=1 run ./anon-git.sh --no-confirm --no-backup --current-branch \
        --date '2021-02-03 04:05:06 +0000' HEAD
    assert_success
    assert_equal "$(git show -s --format='%ai' HEAD)" '2021-02-03 04:05:06 +0000'
}

@test "ANON_GIT_* envvars overwrite defaults" {
    # ANON_GIT_NAME/EMAIL/DATE work as priority-3 config, same as
    # --name/--email/--date.
    pick_random_index
    ANON_GIT_NAME='Grace Murray' ANON_GIT_EMAIL='grace.murray@example.com' ANON_GIT_DATE='2019-05-05 00:00:00 +0000' \
        run ./anon-git.sh --no-confirm --no-backup --current-branch "HEAD~${PICKED_INDEX}"
    assert_success
    assert_equal "$(commit_author "HEAD~${PICKED_INDEX}")" 'Grace Murray <grace.murray@example.com>'
    assert_equal "$(git show -s --format='%ai' "HEAD~${PICKED_INDEX}")" '2019-05-05 00:00:00 +0000'
}

@test "git config anon-git.* sets repo-local defaults" {
    # anon-git.name/email/date work as priority-2 config (below flags, above
    # envvars and defaults).
    git config --local anon-git.name 'Barbara McClintock'
    git config --local anon-git.email 'barbara.mcclintock@example.com'
    git config --local anon-git.date '2018-08-08 00:00:00 +0000'
    run ./anon-git.sh --no-confirm --no-backup --current-branch HEAD
    assert_success
    assert_equal "$(commit_author HEAD)" 'Barbara McClintock <barbara.mcclintock@example.com>'
    assert_equal "$(git show -s --format='%ai' HEAD)" '2018-08-08 00:00:00 +0000'
}

@test "anon-git.name config overrides ANON_GIT_NAME" {
    # anon-git.name (priority 2) must win over ANON_GIT_NAME (priority 3).
    git config --local anon-git.name 'Config Wins'
    ANON_GIT_NAME='Envvar Loses' run ./anon-git.sh --no-confirm --no-backup --current-branch HEAD
    assert_success
    assert_equal "$(git show -s --format='%an' HEAD)" 'Config Wins'
    run git show -s --pretty=fuller HEAD
    refute_output --partial 'Envvar Loses'
}

@test "--name overrides anon-git.name config" {
    # --name (priority 1) must win over anon-git.name config (priority 2).
    git config --local anon-git.name 'Config Loses'
    run ./anon-git.sh --no-confirm --no-backup --current-branch --name 'Flag Wins' HEAD
    assert_success
    assert_equal "$(git show -s --format='%an' HEAD)" 'Flag Wins'
}

keepuser_bool() {
    # $1: spelling. Any git bool spelling (any case) must normalize like
    # --keep-user.
    local before_author
    before_author=$(commit_author HEAD)
    git config --local anon-git.keepuser "$1"
    run ./anon-git.sh --no-confirm --no-backup --current-branch HEAD
    assert_success
    assert_equal "$(commit_author HEAD)" "$before_author"
}

@test "anon-git.keepuser=yes acts as --keep-user" {
    keepuser_bool yes
}

@test "anon-git.keepuser=YES acts as --keep-user" {
    keepuser_bool YES
}

@test "anon-git.keepuser=True acts as --keep-user" {
    keepuser_bool True
}

@test "non-boolean anon-git.keepuser fails cleanly" {
    git config --local anon-git.keepuser bogus
    run ./anon-git.sh --no-confirm --no-backup HEAD
    assert_failure
    assert_head_unchanged
    assert_output --partial 'invalid boolean value'
}

@test "rejects anon-git.keepuser with anon-git.email config" {
    # Must be rejected the same way --keep-user --email is:
    # reject_incompatible_options folds GITCONFIG_* into the same "_set"
    # checks as flags/envvars.
    git config --local anon-git.keepuser true
    git config --local anon-git.email 'nobody@example.com'
    run ./anon-git.sh --no-confirm --no-backup HEAD
    assert_failure
    assert_head_unchanged
}

@test "anon-git.quiet config silences output, --verbose overrides" {
    local original_branch
    original_branch=$(git branch --show-current)
    git config --local anon-git.quiet true
    run ./anon-git.sh --no-confirm --name 'Grace Hopper Quiet' HEAD
    assert_success
    assert_output ''
    git switch -q "$original_branch"
    run ./anon-git.sh --no-confirm --verbose --name 'Grace Hopper Verbose' HEAD
    assert_output --partial 'Anonymizing commit'
}

@test "ANON_GIT_ENTIREHISTORY=1 rewrites all commits without flag" {
    # Isolates the envvar path from --entire-history's flag path.
    ANON_GIT_ENTIREHISTORY=1 run ./anon-git.sh --no-confirm --no-backup --current-branch
    assert_success
    assert_equal "$(history_authors)" "$DEFAULT_AUTHOR"
}

@test "rejects ANON_GIT_ENTIREHISTORY=1 with commit" {
    ANON_GIT_ENTIREHISTORY=1 run ./anon-git.sh --no-confirm --no-backup --current-branch HEAD
    assert_failure
    assert_output --partial 'cannot be used together'
    assert_head_unchanged
}

@test "ANON_GIT_CURRENTBRANCH=1 rewrites in place without flag" {
    # Must rewrite HEAD in place (like --current-branch), not on a new branch.
    local branch_before
    branch_before=$(git branch --show-current)
    ANON_GIT_CURRENTBRANCH=1 run ./anon-git.sh --no-confirm --no-backup --name 'Barbara Liskov' HEAD
    assert_success
    assert_not_equal "$(git rev-parse HEAD)" "$HEAD_BEFORE"
    assert_equal "$(git branch --show-current)" "$branch_before"
}

@test "ANON_GIT_DRYRUN=1 previews without flag, no rewrite" {
    # Must behave like --dry-run: preview only, no branch, HEAD untouched.
    # Regression: the resolve-args line previously ignored this envvar.
    PAGER='cat' ANON_GIT_DRYRUN=1 run ./anon-git.sh HEAD
    assert_success
    assert_head_unchanged
    assert_equal "$(branch_count)" 1
    assert_output --partial 'AuthorDate:'
}

@test "--verbose overrides ANON_GIT_QUIET=1" {
    ANON_GIT_QUIET=1 run ./anon-git.sh --no-confirm --no-backup --current-branch --verbose --name 'Dennis Ritchie' HEAD
    assert_success
    assert_output --partial 'Anonymizing commit'
}

@test "rejects invalid ANON_GIT_KEEPUSER value" {
    ANON_GIT_KEEPUSER=yes run ./anon-git.sh --no-confirm --no-backup --current-branch HEAD
    assert_failure
    assert_output --partial 'must resolve to "0" or "1"'
    assert_head_unchanged
}
