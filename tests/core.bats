#!/usr/bin/env bats

# CORE / INTEGRATION TESTS: single target with each identity/date flag mix,
# multiple commits or entire history in one run.

load test_helper

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
    assert_equal "$(git show -s --format='%an <%ae>' HEAD~1)" 'Donald Knuth <donald.knuth@example.com>'
    assert_equal "$(git show -s --format='%an <%ae>' HEAD~3)" 'Donald Knuth <donald.knuth@example.com>'
}

@test "--entire-history rewrites all commits" {
    run ./anon-git.sh --no-confirm --no-backup --current-branch --entire-history
    assert_success
    assert_equal "$(git log --format='%an <%ae>' | sort -u)" "${DEFAULT_NAME} <${DEFAULT_EMAIL}>"
}
