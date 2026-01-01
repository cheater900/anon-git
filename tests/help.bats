#!/usr/bin/env bats

# HELP / VERSION TESTS: --help, --version, and the default-to-help paths.

load test_helper

@test "--help shows usage" {
    run ./anon-git.sh --help
    assert_success
    assert_output --partial 'Usage:'
}

@test "--version and -v print version" {
    # Handled in handle_early_options, before safety checks, so it must work
    # even outside a repository and print a version string.
    local no_repo_dir=${BATS_TEST_TMPDIR}/norepo
    run ./anon-git.sh --version
    assert_success
    assert_output --regexp '^anon-git [0-9]+\.[0-9]+\.[0-9]+$'
    run ./anon-git.sh -v
    assert_success
    assert_output --regexp '^anon-git [0-9]+\.[0-9]+\.[0-9]+$'
    # Mirrors "outside git repo fails cleanly" (regression.bats).
    mkdir "$no_repo_dir"
    cp ./anon-git.sh "$no_repo_dir/"
    cd "$no_repo_dir"
    run ./anon-git.sh --version
    assert_success
}

@test "no args in dirty repo shows help" {
    # A bare invocation shows help before safety checks run, so an unstaged
    # change shouldn't be a hard failure. Modifies a tracked file (not an
    # untracked one) since the guard being bypassed only checks
    # diff-index/diff-files.
    echo 'uncommitted change' >>file_1.txt
    run ./anon-git.sh
    assert_success
    assert_head_unchanged
    assert_output --partial 'Usage:'
}

@test "no target shows help" {
    # Without a commit target or --entire-history, shows help instead of
    # defaulting to HEAD.
    run ./anon-git.sh
    assert_success
    assert_head_unchanged
    assert_output --partial 'Usage:'
}

@test "--dry-run without target shows help" {
    # --dry-run alone isn't a target; must fall through to help, not preview HEAD.
    PAGER='cat' run ./anon-git.sh --dry-run
    assert_success
    assert_head_unchanged
    assert_output --partial 'Usage:'
}
