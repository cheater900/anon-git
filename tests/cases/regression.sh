#!/usr/bin/env bash

# Sourced by test_anon_git.sh — not meant to be run directly.
# REGRESSION TESTS: pinned-down edge cases (merge commits, detached HEAD,
# shell injection, EXIT-trap cleanup, filter-repo rerun cache) so a future
# change cannot silently reintroduce them.

test_match_detached_head_current_branch() {
    local original_branch before_head after_head output exit_status errors=0

    original_branch=$(git branch --show-current)
    before_head=$(git rev-parse HEAD)

    git checkout --detach HEAD >/dev/null 2>&1

    output=$(./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch HEAD 2>&1)
    exit_status=$?
    after_head=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: --current-branch on a detached HEAD did not fail\n'
        errors=$((errors + 1))
    fi
    if [[ "$before_head" != "$after_head" ]]; then
        printf 'Error: HEAD changed despite detached-HEAD guard\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'detached' <<<"$output"; then
        printf 'Error: expected "detached" message not found\n'
        errors=$((errors + 1))
    fi

    git checkout "$original_branch" >/dev/null 2>&1

    record_result "$errors" 'detached HEAD with flag --current-branch rejected'
}

test_match_merge_commit() {
    local original_branch feature_branch exit_status mismatches errors=0

    original_branch=$(git branch --show-current)
    feature_branch="merge_test_$$"

    git switch --create "$feature_branch" >/dev/null 2>&1
    echo 'feature work' >feature_file.txt
    git add feature_file.txt >/dev/null
    git commit -m 'Add feature file' >/dev/null

    git switch "$original_branch" >/dev/null 2>&1
    git merge --no-ff -m 'Merge feature branch' "$feature_branch" >/dev/null 2>&1

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --entire-history --name 'Merge Tester' >/dev/null 2>&1
    exit_status=$?

    mismatches=$(git log --format='%an' | grep --invert-match --count '^Merge Tester$')

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --entire-history on history with a merge commit exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$mismatches" -ne 0 ]]; then
        printf 'Error: --entire-history left %s commit(s) unrewritten around the merge commit\n' "$mismatches"
        errors=$((errors + 1))
    fi

    git branch -D "$feature_branch" >/dev/null 2>&1

    record_result "$errors" 'flag --entire-history handles merge commits'
}

test_match_merge_commit_single_target() {
    # Targeting a merge commit by hash (not --entire-history) must rewrite
    # only its metadata, leaving parent topology, parents' own metadata, and
    # tree/content untouched. Complements test_match_merge_commit.
    local original_branch feature_branch parent1_before parent2_before
    local parent1_author_before merge_hash tree_before exit_status
    local new_merge_author parents_after tree_after parent1_author_after
    local errors=0

    original_branch=$(git branch --show-current)
    feature_branch="merge_single_test_$$"

    git switch --create "$feature_branch" >/dev/null 2>&1
    echo 'feature work' >feature_single_file.txt
    git add feature_single_file.txt >/dev/null
    git commit -m 'Add feature single file' >/dev/null

    git switch "$original_branch" >/dev/null 2>&1
    git merge --no-ff -m 'Merge feature branch (single target)' "$feature_branch" >/dev/null 2>&1

    merge_hash=$(git rev-parse HEAD)
    parent1_before=$(git rev-parse HEAD^1)
    parent2_before=$(git rev-parse HEAD^2)
    parent1_author_before=$(git show -s --format='%an <%ae>' "$parent1_before")
    tree_before=$(git show -s --format='%T' "$merge_hash")

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch \
        --name 'Merge Single Tester' --email 'merge.single@example.com' "$merge_hash" >/dev/null 2>&1
    exit_status=$?

    new_merge_author=$(git show -s --format='%an <%ae>' HEAD)
    parents_after=$(git show -s --format='%P' HEAD)
    tree_after=$(git show -s --format='%T' HEAD)
    parent1_author_after=$(git show -s --format='%an <%ae>' "$parent1_before" 2>/dev/null)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: anonymizing a merge commit by hash exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$new_merge_author" != 'Merge Single Tester <merge.single@example.com>' ]]; then
        printf 'Error: targeted merge commit was not anonymized (got "%s")\n' "$new_merge_author"
        errors=$((errors + 1))
    fi
    if [[ "$parents_after" != "${parent1_before} ${parent2_before}" ]]; then
        printf 'Error: merge commit parents changed despite not being rewrite targets\n'
        errors=$((errors + 1))
    fi
    if [[ "$tree_after" != "$tree_before" ]]; then
        printf 'Error: merge commit tree/content drifted from a metadata-only rewrite\n'
        errors=$((errors + 1))
    fi
    if [[ "$parent1_author_after" != "$parent1_author_before" ]]; then
        printf 'Error: a parent commit was unexpectedly rewritten\n'
        errors=$((errors + 1))
    fi
    if ! git fsck --full >/dev/null 2>&1; then
        printf 'Error: git fsck reported a corrupt repository after the rewrite\n'
        errors=$((errors + 1))
    fi

    git branch -D "$feature_branch" >/dev/null 2>&1

    record_result "$errors" 'merge commit by hash (single-commit mode) keeps topology'
}

test_match_merge_commit_ancestor_only() {
    # Rewriting an ancestor of a later merge commit must cascade through
    # git-filter-repo (the merge's parent pointer follows the ancestor's new
    # hash), while the merge's tree, parent count, and other parent stay intact.
    local original_branch feature_branch other_parent_before ancestor_hash
    local tree_before exit_status new_ancestor_author merge_parent_count
    local other_parent_after tree_after errors=0

    original_branch=$(git branch --show-current)
    feature_branch="merge_ancestor_test_$$"

    git switch --create "$feature_branch" >/dev/null 2>&1
    echo 'feature work' >feature_ancestor_file.txt
    git add feature_ancestor_file.txt >/dev/null
    git commit -m 'Add feature ancestor file' >/dev/null
    other_parent_before=$(git rev-parse HEAD)

    git switch "$original_branch" >/dev/null 2>&1
    echo 'main ancestor work' >main_ancestor_file.txt
    git add main_ancestor_file.txt >/dev/null
    git commit -m 'Add main ancestor file' >/dev/null
    ancestor_hash=$(git rev-parse HEAD)

    git merge --no-ff -m 'Merge feature branch (ancestor target)' "$feature_branch" >/dev/null 2>&1
    tree_before=$(git show -s --format='%T' HEAD)

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch \
        --name 'Ancestor Tester' --email 'ancestor.tester@example.com' "$ancestor_hash" >/dev/null 2>&1
    exit_status=$?

    new_ancestor_author=$(git show -s --format='%an <%ae>' HEAD^1)
    merge_parent_count=$(git show -s --format='%P' HEAD | wc -w)
    other_parent_after=$(git rev-parse HEAD^2)
    tree_after=$(git show -s --format='%T' HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: anonymizing a merge ancestor by hash exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$new_ancestor_author" != 'Ancestor Tester <ancestor.tester@example.com>' ]]; then
        printf 'Error: targeted ancestor commit was not anonymized (got "%s")\n' "$new_ancestor_author"
        errors=$((errors + 1))
    fi
    if [[ "$merge_parent_count" -ne 2 ]]; then
        printf 'Error: merge commit lost its two-parent topology after an ancestor rewrite (got %s parent(s))\n' "$merge_parent_count"
        errors=$((errors + 1))
    fi
    if [[ "$other_parent_after" != "$other_parent_before" ]]; then
        printf 'Error: the other (non-rewritten) branch of the merge was unexpectedly re-hashed\n'
        errors=$((errors + 1))
    fi
    if [[ "$tree_after" != "$tree_before" ]]; then
        printf 'Error: merge commit tree/content drifted after an ancestor-only rewrite\n'
        errors=$((errors + 1))
    fi
    if ! git fsck --full >/dev/null 2>&1; then
        printf 'Error: git fsck reported a corrupt repository after the rewrite\n'
        errors=$((errors + 1))
    fi

    git branch -D "$feature_branch" >/dev/null 2>&1

    record_result "$errors" 'merge-commit ancestor by hash cascades merge parent pointer'
}

test_match_outside_git_repo() {
    local no_repo_dir output exit_status errors=0

    no_repo_dir=$(mktemp -d /tmp/anon_git_test_norepo.XXXXXX)
    cp "$SCRIPT" "$no_repo_dir/"
    chmod +x "${no_repo_dir}/${SCRIPT_NAME}"

    output=$(cd "$no_repo_dir" && "./${SCRIPT_NAME}" --no-confirm 2>&1)
    exit_status=$?

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: running outside a git repository did not fail\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'git repository' <<<"$output"; then
        printf 'Error: expected "git repository" message not found\n'
        errors=$((errors + 1))
    fi

    rm -rf "$no_repo_dir"

    record_result "$errors" 'outside git repo fails cleanly'
}

test_match_clean_cache_from_subdir() {
    # Run from a subdir, $PWD/.git does not exist; the cache must still go.
    local marker errors=0

    marker="$(git rev-parse --absolute-git-dir)/filter-repo/stale_marker"
    mkdir -p "$(dirname "$marker")"
    touch "$marker"
    mkdir -p subdir
    (cd subdir && PAGER="cat" ../"${SCRIPT_NAME}" --dry-run HEAD >/dev/null 2>&1)
    rmdir subdir

    if [[ -e "$marker" ]]; then
        printf 'Error: filter-repo cache not cleared when run from subdir\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'filter-repo cache cleared from subdir'
}

test_match_trap_cleanup_on_kill() {
    # The EXIT trap (cleanup_on_exit) must remove scratch files even when
    # killed mid-run. Uses a large repo (gives filter-repo time to run) and a
    # dedicated TMPDIR to spot leftovers easily. `exec` in the backgrounded
    # subshell makes $pid the script's own PID. If the run finishes before
    # the kill lands, the check is inconclusive and skipped, not errored.
    local repo_dir scratch_tmpdir pid i caught_mid_run leftover errors=0

    repo_dir=$(mktemp -d "${TMP_DIR}/trap_kill_repo.XXXXXX")
    (
        cd "$repo_dir" || exit 1
        git init >/dev/null
        git config --local user.name "Jordan Blake"
        git config --local user.email "jordan.blake@example.com"
        for i in $(seq 1 500); do
            echo "file ${i}" >"file_${i}.txt"
            git add "file_${i}.txt" >/dev/null
            git commit -q -m "Add file_${i}.txt"
        done
    )
    cp "$SCRIPT" "$repo_dir/"
    chmod +x "${repo_dir}/${SCRIPT_NAME}"

    scratch_tmpdir=$(mktemp -d "${TMP_DIR}/trap_kill_tmpdir.XXXXXX")

    (cd "$repo_dir" && TMPDIR="$scratch_tmpdir" PAGER=cat exec "./${SCRIPT_NAME}" --no-confirm --dry-run --entire-history >/dev/null 2>&1) &
    pid=$!

    caught_mid_run=0
    for i in $(seq 1 200); do
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        if [[ -n "$(find "$scratch_tmpdir" -type f 2>/dev/null)" ]]; then
            caught_mid_run=1
            break
        fi
        sleep 0.01
    done

    if [[ "$caught_mid_run" -eq 1 ]]; then
        kill -TERM "$pid" 2>/dev/null
    fi
    wait "$pid" 2>/dev/null

    if [[ "$caught_mid_run" -eq 0 ]]; then
        printf 'SKIP EXIT trap cleanup on kill: could not catch the run in progress\n'
    else
        leftover=$(find "$scratch_tmpdir" -type f 2>/dev/null | wc -l)
        if [[ "$leftover" -ne 0 ]]; then
            printf 'Error: %s scratch file(s) left behind after killing the script mid-run\n' "$leftover"
            errors=$((errors + 1))
        fi
        record_result "$errors" 'EXIT trap cleans scratch files when killed mid-run'
    fi

    rm -rf "$repo_dir" "$scratch_tmpdir"
}

test_match_annotated_tag() {
    local tag_name="annotated_$$" exit_status new_author errors=0

    git tag -a -m 'Annotated tag' "$tag_name" HEAD
    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --name 'Tag Target' "$tag_name" >/dev/null 2>&1
    exit_status=$?
    new_author=$(git show -s --format='%an' HEAD)
    git tag -d "$tag_name" >/dev/null

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: annotated tag target exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$new_author" != 'Tag Target' ]]; then
        printf 'Error: annotated tag target not rewritten (author "%s")\n' "$new_author"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'annotated tag target rewritten'
}

test_match_dry_run_keeps_signed_commit() {
    # filter-repo strips signatures, so a dry run that reaches it for real
    # changes the hash even though the callback rewrites nothing.
    local repo_dir before after exit_status errors=0

    repo_dir=$(mktemp -d "${TMP_DIR}/signed_repo.XXXXXX")
    (
        cd "$repo_dir" || exit 1
        ssh-keygen -q -t ed25519 -N '' -f signing_key
        git init >/dev/null
        git config --local user.name "Jordan Blake"
        git config --local user.email "jordan.blake@example.com"
        git config --local gpg.format ssh
        git config --local user.signingkey "${repo_dir}/signing_key"
        printf 'signing_key*\n' >.git/info/exclude
        git commit -q -S --allow-empty -m 'Signed commit'
    )
    cp "$SCRIPT" "$repo_dir/"
    printf '%s\n' "$SCRIPT_NAME" >>"${repo_dir}/.git/info/exclude"

    before=$(git -C "$repo_dir" rev-parse HEAD)
    (cd "$repo_dir" && PAGER="cat" "./${SCRIPT_NAME}" --no-confirm --dry-run HEAD >/dev/null 2>&1)
    exit_status=$?
    after=$(git -C "$repo_dir" rev-parse HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --dry-run on signed commit exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: --dry-run rewrote signed commit %s -> %s\n' "$before" "$after"
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"
    record_result "$errors" 'dry run keeps signed commit hash'
}

test_match_dry_run_non_utf8() {
    # Commit metadata is raw bytes; an invalid UTF-8 name must not crash the preview.
    local repo_dir commit output exit_status errors=0

    repo_dir=$(mktemp -d "${TMP_DIR}/non_utf8_repo.XXXXXX")
    git -C "$repo_dir" init >/dev/null
    commit=$(printf 'tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\nauthor Bad \xff Name <bad@example.com> 1700000000 +0000\ncommitter Bad \xff Name <bad@example.com> 1700000000 +0000\n\nMessage \xfe\n' |
        git -C "$repo_dir" hash-object -t commit -w --stdin)
    git -C "$repo_dir" reset -q --hard "$commit"
    cp "$SCRIPT" "$repo_dir/"
    printf '%s\n' "$SCRIPT_NAME" >>"${repo_dir}/.git/info/exclude"

    output=$(cd "$repo_dir" && PAGER="cat" "./${SCRIPT_NAME}" --dry-run HEAD 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --dry-run on non-UTF-8 commit exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if ! grep -q 'AuthorDate:' <<<"$output"; then
        printf 'Error: --dry-run on non-UTF-8 commit printed no preview\n'
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"
    record_result "$errors" 'dry run handles non-UTF-8 metadata'
}

test_match_rerun_cache() {
    # A second run against the same repo is a known trigger for an upstream
    # git-filter-repo assertion bug unless clean_cache clears its metadata cache first.
    local first_exit second_exit new_author errors=0

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --name 'First Run' HEAD >/dev/null 2>&1
    first_exit=$?
    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --name 'Second Run' HEAD >/dev/null 2>&1
    second_exit=$?
    new_author=$(git show -s --format='%an' HEAD)

    if [[ "$first_exit" -ne 0 ]]; then
        printf 'Error: first run exited with status %s\n' "$first_exit"
        errors=$((errors + 1))
    fi
    if [[ "$second_exit" -ne 0 ]]; then
        printf 'Error: second (back-to-back) run exited with status %s\n' "$second_exit"
        errors=$((errors + 1))
    fi
    if [[ "$new_author" != 'Second Run' ]]; then
        printf 'Error: second run did not take effect (got author "%s")\n' "$new_author"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'consecutive runs avoid filter-repo cache bug'
}

test_match_shell_injection_email() {
    local marker payload commit_email exit_status errors=0

    marker="${TMP_DIR}/injection_marker_email"
    rm -f "$marker"
    payload="evil'\"; touch ${marker}; \`touch ${marker}\`; \$(touch ${marker}) #@example.com"

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --email "$payload" HEAD >/dev/null 2>&1
    exit_status=$?
    commit_email=$(git show -s --format='%ae' HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: run with shell-metacharacter --email exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$commit_email" != "$payload" ]]; then
        printf 'Error: email was not stored literally (got "%s")\n' "$commit_email"
        errors=$((errors + 1))
    fi
    if [[ -e "$marker" ]]; then
        printf 'Error: shell metacharacters in --email were executed (marker file created)\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'shell metacharacters in --email not executed'
}

test_match_shell_injection_name() {
    local marker payload commit_name exit_status errors=0

    marker="${TMP_DIR}/injection_marker_name"
    rm -f "$marker"
    payload="Evil'\"; touch ${marker}; \`touch ${marker}\`; \$(touch ${marker}) #"

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --name "$payload" HEAD >/dev/null 2>&1
    exit_status=$?
    commit_name=$(git show -s --format='%an' HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: run with shell-metacharacter --name exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$commit_name" != "$payload" ]]; then
        printf 'Error: author name was not stored literally (got "%s")\n' "$commit_name"
        errors=$((errors + 1))
    fi
    if [[ -e "$marker" ]]; then
        printf 'Error: shell metacharacters in --name were executed (marker file created)\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'shell metacharacters in --name not executed'
}
