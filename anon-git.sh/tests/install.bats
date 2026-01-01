#!/usr/bin/env bats

# INSTALL / HOOK TESTS: --install, --uninstall, --install-hook and
# --uninstall-hook. Installs go to a disposable $HOME, so they never touch
# the real ~/.local/bin; --install-system isn't tested: it needs sudo and a
# real /usr/bin. Hooks go into the per-test $REPO.

load test_helper

HOOK_FILE=.git/hooks/post-commit
FOREIGN_SCRIPT=$'#!/bin/sh\necho foreign'

# Writes an executable non-anon-git script to $1.
write_foreign_script() {
    printf '%s\n' "$FOREIGN_SCRIPT" >"$1"
    chmod +x "$1"
}

# Creates $FAKE_HOME with subdirs $@ (e.g. .local/bin .bin).
make_fake_home() {
    local dir
    FAKE_HOME=${BATS_TEST_TMPDIR}/home
    mkdir -p "$FAKE_HOME"
    for dir in "$@"; do
        mkdir -p "${FAKE_HOME}/${dir}"
    done
}

# Runs $@ with $FAKE_HOME as $HOME and a $PATH without its bin dirs.
run_installer() {
    run env HOME="$FAKE_HOME" PATH=/usr/bin:/bin "$@"
}

@test "--install copies to ~/.local/bin" {
    make_fake_home .local/bin
    run_installer ./anon-git.sh --install
    assert_success
    assert_file_executable "${FAKE_HOME}/.local/bin/anon-git"
    assert_files_equal "${FAKE_HOME}/.local/bin/anon-git" ./anon-git.sh
    assert_output --partial "is not in your \$PATH"
}

@test "--install ships completions for installed copy" {
    # The installed copy has no completions/ next to it; --install must ship
    # them so --print-completion still works, and --uninstall drop them.
    local src_dir=${BATS_TEST_TMPDIR}/src
    make_fake_home .local/bin
    mkdir "$src_dir"
    cp "$SCRIPT" "$src_dir/"
    cp -R "${SCRIPT_DIR}/completions" "$src_dir/"
    run_installer "${src_dir}/anon-git.sh" --install
    assert_success
    HOME=$FAKE_HOME run "${FAKE_HOME}/.local/bin/anon-git" --print-completion bash
    assert_success
    assert_output --regexp 'complete -F _anon_git_completion anon-git$'
    run_installer "${src_dir}/anon-git.sh" --uninstall
    assert_file_not_exists "${FAKE_HOME}/.local/share/anon-git"
}

@test "--install as --name value not run" {
    make_fake_home .local/bin
    HOME=$FAKE_HOME PAGER='cat' run ./anon-git.sh --dry-run --name --install HEAD
    assert_file_not_exists "${FAKE_HOME}/.local/bin/anon-git"
}

@test "--install falls back to ~/.bin" {
    make_fake_home .bin
    run_installer ./anon-git.sh --install
    assert_success
    assert_file_executable "${FAKE_HOME}/.bin/anon-git"
    assert_dir_not_exists "${FAKE_HOME}/.local/bin"
}

@test "--install copies to ~/.local/bin and ~/.bin when both exist" {
    make_fake_home .local/bin .bin
    run_installer ./anon-git.sh --install
    assert_success
    assert_file_executable "${FAKE_HOME}/.local/bin/anon-git"
    assert_file_executable "${FAKE_HOME}/.bin/anon-git"
}

@test "--install skips \$PATH warning when already on \$PATH" {
    make_fake_home .local/bin
    run env HOME="$FAKE_HOME" PATH="${FAKE_HOME}/.local/bin:/usr/bin:/bin" ./anon-git.sh --install
    assert_success
    refute_output --partial "is not in your \$PATH"
}

@test "--install fails cleanly without target dir" {
    # Must fail cleanly without creating either directory.
    make_fake_home
    run_installer ./anon-git.sh --install
    assert_failure
    assert_dir_not_exists "${FAKE_HOME}/.local/bin"
    assert_dir_not_exists "${FAKE_HOME}/.bin"
    assert_output --partial 'neither'
}

@test "--install idempotent when re-run from installed copy" {
    # Re-running from the just-installed copy (same path, same inode) should
    # report "Already installed" rather than overwrite and re-warn.
    make_fake_home .local/bin
    run_installer ./anon-git.sh --install
    assert_success
    run_installer "${FAKE_HOME}/.local/bin/anon-git" --install
    assert_success
    assert_output --partial 'Already installed'
}

@test "--uninstall removes script from ~/.local/bin and ~/.bin" {
    # Must report each removal and leave the (now empty) directories alone.
    make_fake_home .local/bin .bin
    run_installer ./anon-git.sh --install
    run_installer ./anon-git.sh --uninstall
    assert_success
    assert_file_not_exists "${FAKE_HOME}/.local/bin/anon-git"
    assert_file_not_exists "${FAKE_HOME}/.bin/anon-git"
    assert_output --partial "${FAKE_HOME}/.local/bin/anon-git"
    assert_output --partial "${FAKE_HOME}/.bin/anon-git"
}

@test "--uninstall keeps foreign file" {
    make_fake_home .local/bin
    write_foreign_script "${FAKE_HOME}/.local/bin/anon-git"
    run_installer ./anon-git.sh --uninstall
    assert_failure
    assert_file_exists "${FAKE_HOME}/.local/bin/anon-git"
    assert_output --partial 'not anon-git'
}

@test "--uninstall skips dir without installed copy" {
    # Must not treat the absent ~/.bin copy as a failure.
    make_fake_home .local/bin
    run_installer ./anon-git.sh --install
    run_installer ./anon-git.sh --uninstall
    assert_success
    assert_file_not_exists "${FAKE_HOME}/.local/bin/anon-git"
}

@test "--uninstall with nothing installed succeeds, reports it" {
    # Must succeed and say so, unlike --install's "no target directory" error.
    make_fake_home
    run_installer ./anon-git.sh --uninstall
    assert_success
    assert_output --partial 'not installed'
}

@test "--install-hook creates post-commit hook" {
    run ./anon-git.sh --install-hook
    assert_success
    assert_file_executable "$HOOK_FILE"
    assert_file_contains "$HOOK_FILE" 'Installed by anon-git'
    run cat "$HOOK_FILE"
    assert_output --partial "${REPO}/anon-git.sh"
    # Without --no-backup a backup branch would accumulate per commit.
    assert_output --partial '--no-backup'
}

@test "--install-hook requires git repo" {
    cd_outside_repo
    run ./anon-git.sh --install-hook
    assert_failure
    assert_output --partial 'git repository'
}

@test "--install-hook keeps foreign hook" {
    write_foreign_script "$HOOK_FILE"
    run ./anon-git.sh --install-hook
    assert_failure
    assert_equal "$(cat "$HOOK_FILE")" "$FOREIGN_SCRIPT"
    assert_output --partial 'already exists'
}

hook_flag_refuses_symlink() {
    # $1: --install-hook | --uninstall-hook. The link target carries the
    # marker (like a copy of anon-git.sh does); it must still be left alone.
    local target=${BATS_TEST_TMPDIR}/shared-hook
    local content=$'#!/bin/sh\n# Installed by anon-git --install-hook'
    printf '%s\n' "$content" >"$target"
    ln -s "$target" "$HOOK_FILE"
    run ./anon-git.sh "$1"
    assert_failure
    assert_equal "$(cat "$target")" "$content"
    assert_link_exists "$HOOK_FILE"
}

@test "--install-hook refuses symlinked hook" {
    hook_flag_refuses_symlink --install-hook
}

@test "--uninstall-hook refuses symlinked hook" {
    hook_flag_refuses_symlink --uninstall-hook
}

@test "--install-hook refuses dangling symlink" {
    local target=${BATS_TEST_TMPDIR}/missing
    ln -s "$target" "$HOOK_FILE"
    run ./anon-git.sh --install-hook
    assert_failure
    assert_file_not_exists "$target"
}

@test "--install-hook installs into core.hooksPath" {
    # git runs hooks from core.hooksPath when set, so the hook must land there.
    git config --local core.hooksPath .husky
    run ./anon-git.sh --install-hook
    assert_success
    assert_file_executable "${REPO}/.husky/post-commit"
    assert_file_not_exists "$HOOK_FILE"
}

@test "--install-hook anonymizes partial commit, keeps changes" {
    # A partial commit leaves unstaged and staged changes behind; the hook
    # must still anonymize HEAD and restore both.
    ./anon-git.sh --install-hook
    echo 'staged' >staged.txt
    echo 'committed' >committed.txt
    git add staged.txt committed.txt
    echo 'unstaged' >>file_1.txt
    git commit -q -m 'Partial commit' committed.txt
    assert_equal "$(commit_author HEAD)" "$DEFAULT_AUTHOR"
    assert_equal "$(git diff --name-only)" 'file_1.txt'
    assert_equal "$(git diff --cached --name-only)" 'staged.txt'
}

@test "--install-hook keeps unrelated stash when push saves nothing" {
    # Dirty submodule content: diff-files reports it, stash push saves
    # nothing, so the hook must not pop the older stash.
    local sub=${BATS_TEST_TMPDIR}/sub
    new_repo "$sub"
    git -C "$sub" commit -q --allow-empty -m sub
    git -c protocol.file.allow=always submodule add -q "$sub" sub
    git commit -q -m 'Add submodule'
    echo 'stashed' >>file_1.txt
    git stash push -q
    ./anon-git.sh --install-hook
    echo 'new' >sub/new.txt
    git -C sub add new.txt
    git commit -q --allow-empty -m 'Commit with dirty submodule' 2>/dev/null
    assert_equal "$(git stash list | wc -l | tr -d ' ')" 1
    assert_equal "$(git diff --name-only -- file_1.txt)" ''
}

@test "--install-hook with moved script explains, lets commit through" {
    ./anon-git.sh --install-hook
    mv ./anon-git.sh "${BATS_TEST_TMPDIR}/"
    run --separate-stderr git commit -q --allow-empty -m 'after move'
    assert_success
    assert_stderr --partial "${REPO}/anon-git.sh missing, not anonymized"
    assert_equal "$(git log -1 --format=%s)" 'after move'
}

@test "--install-hook works from path with shell metacharacters" {
    # Script path with shell metacharacters must survive into the hook.
    local odd_dir="${REPO}/odd \"\$dir\`"
    mkdir -p "$odd_dir"
    mv ./anon-git.sh "$odd_dir/"
    printf 'odd*\n' >>.git/info/exclude
    "${odd_dir}/anon-git.sh" --install-hook
    git commit -q --allow-empty -m 'Hooked commit'
    assert_equal "$(git show -s --format='%an' HEAD)" "$DEFAULT_NAME"
}

@test "--install-hook skips rebase" {
    ./anon-git.sh --install-hook
    run git rebase -q --force-rebase HEAD~1
    assert_success
    assert_not_equal "$(git show -s --format='%an' HEAD)" "$DEFAULT_NAME"
    assert_dir_not_exists .git/rebase-merge
    refute_output --partial 'Error'
}

@test "--install-hook idempotent over own hook" {
    run ./anon-git.sh --install-hook
    assert_success
    run ./anon-git.sh --install-hook
    assert_success
    assert_file_executable "$HOOK_FILE"
}

@test "--install-hook anonymizes only new commit" {
    # Must rewrite only the just-made commit (HEAD), leaving earlier history
    # untouched. Also checks two hooked commits don't grow the branch count
    # (regression for a backup branch accumulating per commit).
    local prior_commit i
    prior_commit=$(git show -s --pretty=fuller --date=iso HEAD)
    ./anon-git.sh --install-hook
    for i in 21 22; do
        echo "This is file ${i}" >"file_${i}.txt"
        git add "file_${i}.txt"
        git commit -q -m "Add file_${i}.txt"
    done
    assert_equal "$(commit_author HEAD)" "$DEFAULT_AUTHOR"
    assert_equal "$(git show -s --format='%ai' HEAD)" "$DEFAULT_DATE"
    assert_equal "$(git show -s --pretty=fuller --date=iso "$HEAD_BEFORE")" "$prior_commit"
    assert_equal "$(branch_count)" 1
}

@test "--install-hook generates hook passing --quiet" {
    # Must not spam output on every git commit.
    ./anon-git.sh --install-hook
    # Not assert_file_contains: its grep reads "--quiet" as an option.
    run cat "$HOOK_FILE"
    assert_output --partial '--quiet'
}

@test "--uninstall-hook removes own hook" {
    ./anon-git.sh --install-hook
    run ./anon-git.sh --uninstall-hook
    assert_success
    assert_file_not_exists "$HOOK_FILE"
    assert_output --partial 'Removed post-commit hook'
}

@test "--uninstall-hook requires git repo" {
    cd_outside_repo
    run ./anon-git.sh --uninstall-hook
    assert_failure
    assert_output --partial 'git repository'
}

@test "--uninstall-hook without hook succeeds, reports it" {
    # Must succeed rather than treat "not found" as an error.
    run ./anon-git.sh --uninstall-hook
    assert_success
    assert_output --partial 'No post-commit hook installed'
}

@test "--uninstall-hook keeps foreign hook" {
    write_foreign_script "$HOOK_FILE"
    run ./anon-git.sh --uninstall-hook
    assert_failure
    assert_equal "$(cat "$HOOK_FILE")" "$FOREIGN_SCRIPT"
    assert_output --partial 'not installed by anon-git'
}
