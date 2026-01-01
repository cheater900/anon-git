#!/usr/bin/env bats

# CORE / INTEGRATION TESTS: single target with each identity/date flag mix,
# multiple commits or entire history in one run.

load test_helper

# Prints identity and dates of every commit except HEAD~$1.
commits_except() {
    git log --format='%an <%aE> (%ai) %cn <%cE> (%ci)' | sed "$(($1 + 1))d"
}

# Rewrites a random HEAD~N with $@ and checks only that commit changed, as
# the flags ask.
assert_rewrite() {
    # $@: flags to pass through (--name, --email, --date, --keep-user, --keep-date)
    local expected_name=$DEFAULT_NAME expected_email=$DEFAULT_EMAIL expected_date=$DEFAULT_DATE
    local keep_user=$DEFAULT_KEEPUSER keep_date=$DEFAULT_KEEPDATE args=("$@")
    local target old_user old_date untouched_commits
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --date)
            expected_date=$2
            shift 2
            ;;
        --name)
            expected_name=$2
            shift 2
            ;;
        --email)
            expected_email=$2
            shift 2
            ;;
        --keep-user)
            keep_user=1
            shift
            ;;
        --keep-date)
            keep_date=1
            shift
            ;;
        *)
            fail "unexpected argument in assert_rewrite: $1"
            ;;
        esac
    done
    pick_random_index
    target="HEAD~${PICKED_INDEX}"
    old_user=$(git show -s --format='%an <%ae> %cn <%ce>' "$target")
    old_date=$(git show -s --format='%ai %ci' "$target")
    untouched_commits=$(commits_except "$PICKED_INDEX")
    run ./anon-git.sh --no-confirm --no-backup "${args[@]}" "$target"
    assert_success
    if [[ "$keep_user" == '1' ]]; then
        assert_equal "$(git show -s --format='%an <%ae> %cn <%ce>' "$target")" "$old_user"
    else
        assert_equal "$(commit_author "$target")" "${expected_name} <${expected_email}>"
        assert_equal "$(git show -s --format='%cn <%ce>' "$target")" "${expected_name} <${expected_email}>"
    fi
    if [[ "$keep_date" == '1' ]]; then
        assert_equal "$(git show -s --format='%ai %ci' "$target")" "$old_date"
    else
        assert_equal "$(git show -s --format='%ai' "$target")" "$expected_date"
        assert_equal "$(git show -s --format='%ci' "$target")" "$expected_date"
    fi
    assert_equal "$(commits_except "$PICKED_INDEX")" "$untouched_commits"
}

@test "defaults rewrite target" {
    assert_rewrite
}

@test "--name rewrites target" {
    assert_rewrite --name 'Grace Hopper'
}

@test "--name --email rewrite target" {
    assert_rewrite --name 'Alan Turing' --email 'alan.turing@example.com'
}

@test "--name --email --date rewrite target" {
    assert_rewrite --name 'Ada Lovelace' --email 'ada.lovelace@example.com' --date '2020-01-01 00:03:03 +0000'
}

@test "--name --date rewrite target" {
    assert_rewrite --name 'Katherine Johnson' --date '2020-01-01 00:04:04 +0000'
}

@test "--email rewrites target" {
    assert_rewrite --email 'margaret.hamilton@example.com'
}

@test "--email --date rewrite target" {
    assert_rewrite --email 'barbara.liskov@example.com' --date '2020-10-31 00:06:06 +0000'
}

@test "--date rewrites target" {
    assert_rewrite --date '2020-01-01 00:07:07 +0000'
}

@test "--keep-date keeps date" {
    assert_rewrite --keep-date
}

@test "--keep-date --name keeps date" {
    assert_rewrite --keep-date --name 'Radia Perlman'
}

@test "--keep-date --name --email keeps date" {
    assert_rewrite --keep-date --name 'Hedy Lamarr' --email 'hedy.lamarr@example.com'
}

@test "--keep-user keeps user" {
    assert_rewrite --keep-user
}

@test "--keep-user --date keeps user" {
    assert_rewrite --keep-user --date '2020-01-01 00:10:10 +0000'
}

@test "multiple commits per run" {
    run ./anon-git.sh --no-confirm --no-backup --current-branch --name 'Donald Knuth' --email 'donald.knuth@example.com' HEAD~1 HEAD~3
    assert_success
    assert_equal "$(commit_author HEAD~1)" 'Donald Knuth <donald.knuth@example.com>'
    assert_equal "$(commit_author HEAD~3)" 'Donald Knuth <donald.knuth@example.com>'
}

@test "--entire-history rewrites all commits" {
    run ./anon-git.sh --no-confirm --no-backup --current-branch --entire-history
    assert_success
    assert_equal "$(history_authors)" "$DEFAULT_AUTHOR"
}
