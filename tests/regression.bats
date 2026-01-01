#!/usr/bin/env bats

# REGRESSION TESTS: pinned-down edge cases (merge commits, detached HEAD,
# shell injection, EXIT-trap cleanup, filter-repo rerun cache) so a future
# change cannot silently reintroduce them.

load test_helper

# Creates a side branch with one commit, then merges it --no-ff into the
# current branch.
merge_side_branch() {
    local original_branch
    original_branch=$(git branch --show-current)
    git switch -q --create feature
    echo 'feature work' >feature_file.txt
    git add feature_file.txt
    git commit -q -m 'Add feature file'
    git switch -q "$original_branch"
    "$@"
    git merge -q --no-ff -m 'Merge feature branch' feature
}

# Inits an empty repo in $1 holding a copy of the script.
new_repo() {
    git init -q "$1"
    git -C "$1" config --local user.name "Jordan Blake"
    git -C "$1" config --local user.email "jordan.blake@example.com"
    cp "$SCRIPT" "$1/"
    printf 'anon-git.sh\n' >>"$1/.git/info/exclude"
}

file_count() {
    find "$1" -type f | wc -l | tr -d ' '
}

@test "rejects detached HEAD with --current-branch" {
    git checkout -q --detach HEAD
    run ./anon-git.sh --no-confirm --no-backup --current-branch HEAD
    assert_failure
    assert_head_unchanged
    assert_output --partial 'detached'
}

@test "--entire-history handles merge commits" {
    merge_side_branch
    run ./anon-git.sh --no-confirm --no-backup --current-branch --entire-history --name 'Merge Tester'
    assert_success
    assert_equal "$(git log --format='%an' | sort -u)" 'Merge Tester'
}

@test "merge commit by hash keeps topology" {
    # Targeting a merge commit by hash (not --entire-history) must rewrite
    # only its metadata, leaving parent topology, parents' own metadata, and
    # tree/content untouched.
    local parents_before parent1_author_before tree_before
    merge_side_branch
    parents_before=$(git show -s --format='%P' HEAD)
    parent1_author_before=$(git show -s --format='%an <%ae>' HEAD^1)
    tree_before=$(git show -s --format='%T' HEAD)
    run ./anon-git.sh --no-confirm --no-backup --current-branch \
        --name 'Merge Single Tester' --email 'merge.single@example.com' HEAD
    assert_success
    assert_equal "$(git show -s --format='%an <%ae>' HEAD)" 'Merge Single Tester <merge.single@example.com>'
    assert_equal "$(git show -s --format='%P' HEAD)" "$parents_before"
    assert_equal "$(git show -s --format='%T' HEAD)" "$tree_before"
    assert_equal "$(git show -s --format='%an <%ae>' HEAD^1)" "$parent1_author_before"
    git fsck --full
}

add_main_ancestor() {
    echo 'main ancestor work' >main_ancestor_file.txt
    git add main_ancestor_file.txt
    git commit -q -m 'Add main ancestor file'
}

@test "merge ancestor by hash cascades merge parent pointer" {
    # Rewriting an ancestor of a later merge commit must cascade through
    # git-filter-repo (the merge's parent pointer follows the ancestor's new
    # hash), while the merge's tree, parent count, and other parent stay intact.
    local other_parent_before tree_before
    merge_side_branch add_main_ancestor
    other_parent_before=$(git rev-parse HEAD^2)
    tree_before=$(git show -s --format='%T' HEAD)
    run ./anon-git.sh --no-confirm --no-backup --current-branch \
        --name 'Ancestor Tester' --email 'ancestor.tester@example.com' HEAD^1
    assert_success
    assert_equal "$(git show -s --format='%an <%ae>' HEAD^1)" 'Ancestor Tester <ancestor.tester@example.com>'
    assert_equal "$(git show -s --format='%P' HEAD | wc -w | tr -d ' ')" 2
    assert_equal "$(git rev-parse HEAD^2)" "$other_parent_before"
    assert_equal "$(git show -s --format='%T' HEAD)" "$tree_before"
    git fsck --full
}

@test "outside git repo fails cleanly" {
    mkdir "${BATS_TEST_TMPDIR}/norepo"
    cp ./anon-git.sh "${BATS_TEST_TMPDIR}/norepo/"
    cd "${BATS_TEST_TMPDIR}/norepo"
    run --separate-stderr ./anon-git.sh --no-confirm
    assert_failure
    assert_stderr --partial 'git repository'
}

@test "bare repo fails with work tree message" {
    local bare_dir=${BATS_TEST_TMPDIR}/bare
    git clone -q --bare "$REPO" "$bare_dir"
    cd "$bare_dir"
    run --separate-stderr "${REPO}/anon-git.sh" --no-confirm HEAD
    assert_failure
    assert_stderr --partial 'not a bare repository'
}

@test "unset HOME keeps startup working" {
    run env -u HOME ./anon-git.sh --version
    assert_success
}

@test "unborn HEAD fails with clear message" {
    local repo_dir=${BATS_TEST_TMPDIR}/unborn
    new_repo "$repo_dir"
    cd "$repo_dir"
    run ./anon-git.sh --no-confirm HEAD
    assert_failure
    assert_output --partial 'no commits yet'
}

@test "linked worktree run and hook install" {
    # In a linked worktree .git is a file and hooks live in the common dir.
    local wt_dir=${BATS_TEST_TMPDIR}/wt
    git worktree add -q -b wt_branch "$wt_dir"
    cp "$SCRIPT" "$wt_dir/"
    cd "$wt_dir"
    run ./anon-git.sh --no-confirm --no-backup --current-branch --name 'Worktree Run' HEAD
    assert_success
    assert_equal "$(git show -s --format='%an' HEAD)" 'Worktree Run'
    ./anon-git.sh --install-hook
    assert_file_executable "${REPO}/.git/hooks/post-commit"
}

@test "filter-repo cache cleared from subdir" {
    # Run from a subdir, $PWD/.git does not exist; the cache must still go.
    local marker
    marker="$(git rev-parse --absolute-git-dir)/filter-repo/stale_marker"
    mkdir -p "$(dirname "$marker")" subdir
    touch "$marker"
    cd subdir
    PAGER='cat' run ../anon-git.sh --dry-run HEAD
    assert_file_not_exists "$marker"
}

@test "EXIT trap cleans scratch files when killed mid-run" {
    # The EXIT trap (cleanup_on_exit) must remove scratch files even when
    # killed mid-run. The PAGER marks the point where every scratch file
    # exists, then sleeps so the kill lands mid-run; bash runs the trap once
    # the pager returns. A dedicated TMPDIR makes leftovers easy to spot.
    # `exec` in the backgrounded subshell makes $pid the script's own PID.
    local repo_dir=${BATS_TEST_TMPDIR}/trap_kill_repo scratch_tmpdir=${BATS_TEST_TMPDIR}/scratch
    local ready_file=${BATS_TEST_TMPDIR}/trap_kill_ready pid
    new_repo "$repo_dir"
    git -C "$repo_dir" commit -q --allow-empty -m 'Initial commit'
    mkdir "$scratch_tmpdir"
    (cd "$repo_dir" && TMPDIR="$scratch_tmpdir" PAGER="touch '${ready_file}'; sleep 1; :" \
        exec ./anon-git.sh --no-confirm --dry-run --random-day --entire-history >/dev/null 2>&1) &
    pid=$!
    for _ in $(seq 1 100); do
        if [[ -e "$ready_file" ]]; then
            break
        fi
        sleep 0.1
    done
    assert_file_exists "$ready_file"
    assert_equal "$(file_count "$scratch_tmpdir")" 3
    kill -TERM "$pid" || true
    wait "$pid" || true
    assert_equal "$(file_count "$scratch_tmpdir")" 0
}

@test "annotated tag target rewritten" {
    git tag -a -m 'Annotated tag' annotated HEAD
    run ./anon-git.sh --no-confirm --no-backup --current-branch --name 'Tag Target' annotated
    assert_success
    assert_equal "$(git show -s --format='%an' HEAD)" 'Tag Target'
}

@test "dry run keeps signed commit hash" {
    # filter-repo strips signatures, so a dry run that reaches it for real
    # changes the hash even though the callback rewrites nothing.
    local repo_dir=${BATS_TEST_TMPDIR}/signed before
    new_repo "$repo_dir"
    cd "$repo_dir"
    ssh-keygen -q -t ed25519 -N '' -f signing_key
    git config --local gpg.format ssh
    git config --local user.signingkey "${repo_dir}/signing_key"
    printf 'signing_key*\n' >>.git/info/exclude
    git commit -q -S --allow-empty -m 'Signed commit'
    before=$(git rev-parse HEAD)
    PAGER='cat' run ./anon-git.sh --no-confirm --dry-run HEAD
    assert_success
    assert_equal "$(git rev-parse HEAD)" "$before"
}

@test "dry run handles non-UTF-8 metadata" {
    # Commit metadata is raw bytes; an invalid UTF-8 name must not crash the preview.
    local repo_dir=${BATS_TEST_TMPDIR}/non_utf8 commit
    new_repo "$repo_dir"
    cd "$repo_dir"
    commit=$(printf 'tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\nauthor Bad \xff Name <bad@example.com> 1700000000 +0000\ncommitter Bad \xff Name <bad@example.com> 1700000000 +0000\n\nMessage \xfe\n' |
        git hash-object -t commit -w --stdin)
    git reset -q --hard "$commit"
    PAGER='cat' run ./anon-git.sh --dry-run HEAD
    assert_success
    assert_output --partial 'AuthorDate:'
}

@test "consecutive runs avoid filter-repo cache bug" {
    # A second run against the same repo is a known trigger for an upstream
    # git-filter-repo assertion bug unless clean_cache clears its metadata cache first.
    run ./anon-git.sh --no-confirm --no-backup --current-branch --name 'First Run' HEAD
    assert_success
    run ./anon-git.sh --no-confirm --no-backup --current-branch --name 'Second Run' HEAD
    assert_success
    assert_equal "$(git show -s --format='%an' HEAD)" 'Second Run'
}

shell_injection() {
    # $1: --name | --email, $2: format of the stored value, $3: payload
    # prefix, $4: payload suffix
    local marker=${BATS_TEST_TMPDIR}/injection_marker payload
    payload="$3'\"; touch ${marker}; \`touch ${marker}\`; \$(touch ${marker}) #$4"
    run ./anon-git.sh --no-confirm --no-backup --current-branch "$1" "$payload" HEAD
    assert_success
    assert_equal "$(git show -s --format="$2" HEAD)" "$payload"
    assert_file_not_exists "$marker"
}

@test "shell metacharacters in --email not executed" {
    shell_injection --email '%ae' evil '@example.com'
}

@test "shell metacharacters in --name not executed" {
    shell_injection --name '%an' Evil ''
}
