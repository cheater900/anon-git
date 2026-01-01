#!/usr/bin/env bash

# Sourced by test_anon_git.sh — not meant to be run directly.
# INSTALL / HOOK TESTS: --install and --install-hook.

test_flag_install_local_bin() {
    # Uses a disposable $HOME so this never touches the real ~/.local/bin.
    # --install-system isn't tested: it needs sudo and a real /usr/bin.
    local fake_home target output exit_status errors=0

    fake_home=$(mktemp -d "${TMP_DIR}/fake_home.XXXXXX")
    mkdir -p "${fake_home}/.local/bin"
    target="${fake_home}/.local/bin/anon-git"

    output=$(HOME="$fake_home" PATH="/usr/bin:/bin" ./"${SCRIPT_NAME}" --install 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --install exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ ! -x "$target" ]]; then
        printf 'Error: %s was not created or is not executable\n' "$target"
        errors=$((errors + 1))
    fi
    if ! cmp -s "$target" "./${SCRIPT_NAME}"; then
        printf 'Error: installed copy at %s does not match the source script\n' "$target"
        errors=$((errors + 1))
    fi
    if ! grep -qi "not in your \$PATH" <<<"$output"; then
        printf "Error: expected a \$PATH warning when %s/.local/bin is not on \$PATH\n" "$fake_home"
        errors=$((errors + 1))
    fi

    rm -rf "$fake_home"

    record_result "$errors" 'flag --install copies to ~/.local/bin'
}

test_flag_install_print_completion() {
    # The installed copy has no completions/ next to it; --install must ship
    # them so --print-completion still works, and --uninstall drop them.
    local fake_home src_dir output exit_status errors=0

    fake_home=$(mktemp -d "${TMP_DIR}/fake_home.XXXXXX")
    src_dir=$(mktemp -d "${TMP_DIR}/src.XXXXXX")
    mkdir -p "${fake_home}/.local/bin"
    cp "$SCRIPT" "$src_dir/"
    cp -R "${SCRIPT_DIR}/completions" "$src_dir/"

    HOME="$fake_home" PATH="/usr/bin:/bin" "${src_dir}/${SCRIPT_NAME}" --install >/dev/null 2>&1
    output=$(HOME="$fake_home" "${fake_home}/.local/bin/anon-git" --print-completion bash 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: installed --print-completion exited with status %s: %s\n' "$exit_status" "$output"
        errors=$((errors + 1))
    fi
    if ! grep -q 'complete -F _anon_git_completion anon-git$' <<<"$output"; then
        printf 'Error: bash completion does not bind installed name anon-git\n'
        errors=$((errors + 1))
    fi

    HOME="$fake_home" PATH="/usr/bin:/bin" "${src_dir}/${SCRIPT_NAME}" --uninstall >/dev/null 2>&1
    if [[ -e "${fake_home}/.local/share/anon-git" ]]; then
        printf 'Error: --uninstall left installed completions behind\n'
        errors=$((errors + 1))
    fi

    rm -rf "$fake_home" "$src_dir"

    record_result "$errors" 'flag --install ships completions for installed copy'
}

test_flag_install_as_flag_value() {
    local fake_home errors=0

    fake_home=$(mktemp -d "${TMP_DIR}/fake_home.XXXXXX")
    mkdir -p "${fake_home}/.local/bin"

    HOME="$fake_home" PAGER="cat" ./"${SCRIPT_NAME}" --dry-run --name --install HEAD >/dev/null 2>&1

    if [[ -e "${fake_home}/.local/bin/anon-git" ]]; then
        printf 'Error: --install given as --name value ran the installer\n'
        errors=$((errors + 1))
    fi

    rm -rf "$fake_home"

    record_result "$errors" '--install as --name value not run'
}

test_flag_install_bin_fallback() {
    local fake_home target exit_status errors=0

    fake_home=$(mktemp -d "${TMP_DIR}/fake_home.XXXXXX")
    mkdir -p "${fake_home}/.bin"
    target="${fake_home}/.bin/anon-git"

    HOME="$fake_home" PATH="/usr/bin:/bin" ./"${SCRIPT_NAME}" --install >/dev/null 2>&1
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --install exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ ! -x "$target" ]]; then
        printf 'Error: %s was not created or is not executable\n' "$target"
        errors=$((errors + 1))
    fi
    if [[ -e "${fake_home}/.local/bin" ]]; then
        printf 'Error: --install created ~/.local/bin even though it did not exist\n'
        errors=$((errors + 1))
    fi

    rm -rf "$fake_home"

    record_result "$errors" 'flag --install falls back to ~/.bin'
}

test_flag_install_both_dirs() {
    local fake_home local_target bin_target exit_status errors=0

    fake_home=$(mktemp -d "${TMP_DIR}/fake_home.XXXXXX")
    mkdir -p "${fake_home}/.local/bin" "${fake_home}/.bin"
    local_target="${fake_home}/.local/bin/anon-git"
    bin_target="${fake_home}/.bin/anon-git"

    HOME="$fake_home" PATH="/usr/bin:/bin" ./"${SCRIPT_NAME}" --install >/dev/null 2>&1
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --install exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ ! -x "$local_target" ]]; then
        printf 'Error: %s was not created\n' "$local_target"
        errors=$((errors + 1))
    fi
    if [[ ! -x "$bin_target" ]]; then
        printf 'Error: %s was not created\n' "$bin_target"
        errors=$((errors + 1))
    fi

    rm -rf "$fake_home"

    record_result "$errors" 'flag --install copies to ~/.local/bin and ~/.bin when both exist'
}

test_flag_install_path_already_set() {
    local fake_home output exit_status errors=0

    fake_home=$(mktemp -d "${TMP_DIR}/fake_home.XXXXXX")
    mkdir -p "${fake_home}/.local/bin"

    output=$(HOME="$fake_home" PATH="${fake_home}/.local/bin:/usr/bin:/bin" ./"${SCRIPT_NAME}" --install 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --install exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if grep -qi "not in your \$PATH" <<<"$output"; then
        printf "Error: unexpected \$PATH warning when the directory is already on \$PATH\n"
        errors=$((errors + 1))
    fi

    rm -rf "$fake_home"

    record_result "$errors" "flag --install skips \$PATH warning when already on \$PATH"
}

test_flag_install_no_target_dir() {
    # Must fail cleanly without creating either directory.
    local fake_home output exit_status errors=0

    fake_home=$(mktemp -d "${TMP_DIR}/fake_home.XXXXXX")

    output=$(HOME="$fake_home" PATH="/usr/bin:/bin" ./"${SCRIPT_NAME}" --install 2>&1)
    exit_status=$?

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: --install with no target directory did not fail as expected\n'
        errors=$((errors + 1))
    fi
    if [[ -e "${fake_home}/.local/bin" || -e "${fake_home}/.bin" ]]; then
        printf 'Error: --install created a directory that did not previously exist\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'neither' <<<"$output"; then
        printf 'Error: expected an explanatory error message when no target directory exists\n'
        errors=$((errors + 1))
    fi

    rm -rf "$fake_home"

    record_result "$errors" 'flag --install fails cleanly without target dir'
}

test_flag_install_idempotent() {
    # Re-running from the just-installed copy (same path, same inode) should
    # report "Already installed" rather than overwrite and re-warn.
    local fake_home target first_exit second_output second_exit errors=0

    fake_home=$(mktemp -d "${TMP_DIR}/fake_home.XXXXXX")
    mkdir -p "${fake_home}/.local/bin"
    target="${fake_home}/.local/bin/anon-git"

    HOME="$fake_home" PATH="/usr/bin:/bin" ./"${SCRIPT_NAME}" --install >/dev/null 2>&1
    first_exit=$?
    second_output=$(HOME="$fake_home" PATH="/usr/bin:/bin" "$target" --install 2>&1)
    second_exit=$?

    if [[ "$first_exit" -ne 0 ]]; then
        printf 'Error: initial --install exited with status %s\n' "$first_exit"
        errors=$((errors + 1))
    fi
    if [[ "$second_exit" -ne 0 ]]; then
        printf 'Error: re-running --install from the installed copy exited with status %s\n' "$second_exit"
        errors=$((errors + 1))
    fi
    if ! grep -qi 'already installed' <<<"$second_output"; then
        printf 'Error: re-running --install from the installed copy did not report "Already installed"\n'
        errors=$((errors + 1))
    fi

    rm -rf "$fake_home"

    record_result "$errors" 'flag --install idempotent when re-run from installed copy'
}

test_flag_uninstall_removes_both_dirs() {
    # Must report each removal and leave the (now empty) directories alone.
    local fake_home local_target bin_target output exit_status errors=0

    fake_home=$(mktemp -d "${TMP_DIR}/fake_home.XXXXXX")
    mkdir -p "${fake_home}/.local/bin" "${fake_home}/.bin"
    local_target="${fake_home}/.local/bin/anon-git"
    bin_target="${fake_home}/.bin/anon-git"

    HOME="$fake_home" PATH="/usr/bin:/bin" ./"${SCRIPT_NAME}" --install >/dev/null 2>&1

    output=$(HOME="$fake_home" PATH="/usr/bin:/bin" ./"${SCRIPT_NAME}" --uninstall 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --uninstall exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ -e "$local_target" ]]; then
        printf 'Error: %s was not removed\n' "$local_target"
        errors=$((errors + 1))
    fi
    if [[ -e "$bin_target" ]]; then
        printf 'Error: %s was not removed\n' "$bin_target"
        errors=$((errors + 1))
    fi
    if ! grep -qF "$local_target" <<<"$output" || ! grep -qF "$bin_target" <<<"$output"; then
        printf 'Error: --uninstall did not report removing both copies (got: %s)\n' "$output"
        errors=$((errors + 1))
    fi

    rm -rf "$fake_home"

    record_result "$errors" 'flag --uninstall removes script from ~/.local/bin and ~/.bin'
}

test_flag_uninstall_keeps_foreign_file() {
    local fake_home target output exit_status errors=0

    fake_home=$(mktemp -d "${TMP_DIR}/fake_home.XXXXXX")
    mkdir -p "${fake_home}/.local/bin"
    target="${fake_home}/.local/bin/anon-git"
    printf '#!/bin/sh\necho foreign\n' >"$target"

    output=$(HOME="$fake_home" PATH="/usr/bin:/bin" ./"${SCRIPT_NAME}" --uninstall 2>&1)
    exit_status=$?

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: --uninstall over foreign file did not fail\n'
        errors=$((errors + 1))
    fi
    if [[ ! -e "$target" ]]; then
        printf 'Error: --uninstall removed foreign file %s\n' "$target"
        errors=$((errors + 1))
    fi
    if ! grep -q 'not anon-git' <<<"$output"; then
        printf 'Error: expected "not anon-git" message not found (got: %s)\n' "$output"
        errors=$((errors + 1))
    fi

    rm -rf "$fake_home"

    record_result "$errors" 'flag --uninstall keeps foreign file'
}

test_flag_uninstall_skips_missing_dir() {
    # Must not treat the absent ~/.bin copy as a failure.
    local fake_home target exit_status errors=0

    fake_home=$(mktemp -d "${TMP_DIR}/fake_home.XXXXXX")
    mkdir -p "${fake_home}/.local/bin"
    target="${fake_home}/.local/bin/anon-git"

    HOME="$fake_home" PATH="/usr/bin:/bin" ./"${SCRIPT_NAME}" --install >/dev/null 2>&1

    HOME="$fake_home" PATH="/usr/bin:/bin" ./"${SCRIPT_NAME}" --uninstall >/dev/null 2>&1
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --uninstall exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ -e "$target" ]]; then
        printf 'Error: %s was not removed\n' "$target"
        errors=$((errors + 1))
    fi

    rm -rf "$fake_home"

    record_result "$errors" 'flag --uninstall skips dir without installed copy'
}

test_flag_uninstall_nothing_installed() {
    # Must succeed and say so, unlike --install's "no target directory" error.
    local fake_home output exit_status errors=0

    fake_home=$(mktemp -d "${TMP_DIR}/fake_home.XXXXXX")

    output=$(HOME="$fake_home" PATH="/usr/bin:/bin" ./"${SCRIPT_NAME}" --uninstall 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --uninstall with nothing installed exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if ! grep -qi 'not installed' <<<"$output"; then
        printf 'Error: expected a "not installed" message not found\n'
        errors=$((errors + 1))
    fi

    rm -rf "$fake_home"

    record_result "$errors" 'flag --uninstall with nothing installed succeeds, reports it'
}

new_hook_test_repo() {
    # Isolated from the shared $TMP_DIR repo so hook side effects can't leak
    # into other tests. Prints the repo's absolute path.
    local repo_dir

    repo_dir=$(mktemp -d "${TMP_DIR}/hook_repo.XXXXXX")
    (
        cd "$repo_dir" || exit 1
        git init >/dev/null
        git config --local user.name "Jordan Blake"
        git config --local user.email "jordan.blake@example.com"
        cp "$SCRIPT" .
        chmod +x "./${SCRIPT_NAME}"
        echo "This is file 1" >file_1.txt
        git add file_1.txt >/dev/null
        git commit -m "Add file_1.txt" >/dev/null
    )

    printf '%s\n' "$repo_dir"
}

test_flag_install_hook_creates_hook() {
    local repo_dir hook_file output exit_status errors=0

    repo_dir=$(new_hook_test_repo)
    hook_file="${repo_dir}/.git/hooks/post-commit"

    output=$(cd "$repo_dir" && "./${SCRIPT_NAME}" --install-hook 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --install-hook exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ ! -x "$hook_file" ]]; then
        printf 'Error: %s was not created or is not executable\n' "$hook_file"
        errors=$((errors + 1))
    fi
    if ! grep -q 'Installed by anon-git' "$hook_file"; then
        printf 'Error: hook file does not contain the anon-git marker\n'
        errors=$((errors + 1))
    fi
    if ! grep -qF "${repo_dir}/${SCRIPT_NAME}" "$hook_file"; then
        printf 'Error: hook file does not invoke the script by its absolute path\n'
        errors=$((errors + 1))
    fi
    if ! grep -q -- '--no-backup' "$hook_file"; then
        printf 'Error: hook file does not pass --no-backup (would accumulate a backup branch per commit)\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'installed post-commit hook' <<<"$output"; then
        printf 'Error: expected confirmation message not found in output\n'
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --install-hook creates post-commit hook'
}

test_flag_install_hook_requires_git_repo() {
    # Must live outside $TMP_DIR (itself a git repo): `git rev-parse --git-dir`
    # walks up parents, so nesting inside it would wrongly succeed and
    # pollute the shared suite repo's hooks.
    local no_repo_dir output exit_status errors=0

    no_repo_dir=$(mktemp -d /tmp/anon_git_test_hook_norepo.XXXXXX)
    cp "$SCRIPT" "$no_repo_dir/"
    chmod +x "${no_repo_dir}/${SCRIPT_NAME}"

    output=$(cd "$no_repo_dir" && "./${SCRIPT_NAME}" --install-hook 2>&1)
    exit_status=$?

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: --install-hook outside a git repository did not fail\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'git repository' <<<"$output"; then
        printf 'Error: expected "git repository" message not found\n'
        errors=$((errors + 1))
    fi

    rm -rf "$no_repo_dir"

    record_result "$errors" 'flag --install-hook requires git repo'
}

test_flag_install_hook_preserves_foreign_hook() {
    local repo_dir hook_file original output exit_status errors=0

    repo_dir=$(new_hook_test_repo)
    hook_file="${repo_dir}/.git/hooks/post-commit"
    printf '#!/bin/sh\necho foreign\n' >"$hook_file"
    chmod +x "$hook_file"
    original=$(cat "$hook_file")

    output=$(cd "$repo_dir" && "./${SCRIPT_NAME}" --install-hook 2>&1)
    exit_status=$?

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: --install-hook did not fail over a pre-existing foreign hook\n'
        errors=$((errors + 1))
    fi
    if [[ "$(cat "$hook_file")" != "$original" ]]; then
        printf 'Error: pre-existing foreign hook was overwritten\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'already exists' <<<"$output"; then
        printf 'Error: expected an "already exists" message not found\n'
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --install-hook keeps foreign hook'
}

test_flag_install_hook_honors_hookspath() {
    # git runs hooks from core.hooksPath when set, so the hook must land there.
    local repo_dir hook_file output exit_status errors=0

    repo_dir=$(new_hook_test_repo)
    hook_file="${repo_dir}/.husky/post-commit"
    (cd "$repo_dir" && git config --local core.hooksPath .husky)

    output=$(cd "$repo_dir" && "./${SCRIPT_NAME}" --install-hook 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --install-hook with core.hooksPath set exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ ! -x "$hook_file" ]]; then
        printf 'Error: %s was not created\n' "$hook_file"
        errors=$((errors + 1))
    fi
    if [[ -e "${repo_dir}/.git/hooks/post-commit" ]]; then
        printf 'Error: hook written to .git/hooks despite core.hooksPath\n'
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --install-hook installs into core.hooksPath'
}

test_flag_install_hook_partial_commit() {
    # A partial commit leaves unstaged and staged changes behind; the hook
    # must still anonymize HEAD and restore both.
    local repo_dir author unstaged staged errors=0

    repo_dir=$(new_hook_test_repo)
    (
        cd "$repo_dir" || exit 1
        "./${SCRIPT_NAME}" --install-hook >/dev/null 2>&1
        echo 'staged' >staged.txt
        echo 'committed' >committed.txt
        git add staged.txt committed.txt
        echo 'unstaged' >>file_1.txt
        git commit -m 'Partial commit' committed.txt >/dev/null 2>&1
    )
    author=$(git -C "$repo_dir" show -s --format='%an <%ae>' HEAD)
    unstaged=$(git -C "$repo_dir" diff --name-only)
    staged=$(git -C "$repo_dir" diff --cached --name-only)

    if [[ "$author" != "${DEFAULT_NAME} <${DEFAULT_EMAIL}>" ]]; then
        printf 'Error: partial commit not anonymized (author "%s")\n' "$author"
        errors=$((errors + 1))
    fi
    if [[ "$unstaged" != 'file_1.txt' ]]; then
        printf 'Error: unstaged change lost (got "%s")\n' "$unstaged"
        errors=$((errors + 1))
    fi
    if [[ "$staged" != 'staged.txt' ]]; then
        printf 'Error: staged change lost (got "%s")\n' "$staged"
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --install-hook anonymizes partial commit, keeps changes'
}

test_flag_install_hook_special_path() {
    # Script path with shell metacharacters must survive into the hook.
    local repo_dir odd_dir author errors=0

    repo_dir=$(new_hook_test_repo)
    odd_dir="${repo_dir}/odd \"\$dir\`"
    mkdir -p "$odd_dir"
    mv "${repo_dir}/${SCRIPT_NAME}" "$odd_dir/"
    printf 'odd*\n' >>"${repo_dir}/.git/info/exclude"
    (
        cd "$repo_dir" || exit 1
        "${odd_dir}/${SCRIPT_NAME}" --install-hook >/dev/null 2>&1
        git commit -q --allow-empty -m 'Hooked commit' 2>/dev/null
    )
    author=$(git -C "$repo_dir" show -s --format='%an' HEAD)

    if [[ "$author" != "$DEFAULT_NAME" ]]; then
        printf 'Error: hook from odd path did not anonymize (author "%s")\n' "$author"
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --install-hook works from path with shell metacharacters'
}

test_flag_install_hook_skips_rebase() {
    local repo_dir output exit_status errors=0

    repo_dir=$(new_hook_test_repo)
    output=$(
        cd "$repo_dir" || exit 1
        echo 'file 2' >file_2.txt
        git add file_2.txt
        git commit -q -m 'Add file_2.txt'
        "./${SCRIPT_NAME}" --install-hook >/dev/null 2>&1
        git rebase -q --force-rebase HEAD~1 2>&1
    )
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: rebase with hook installed exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$(git -C "$repo_dir" show -s --format='%an' HEAD)" == "$DEFAULT_NAME" ]]; then
        printf 'Error: hook rewrote HEAD mid-rebase\n'
        errors=$((errors + 1))
    fi
    if [[ -d "${repo_dir}/.git/rebase-merge" ]]; then
        printf 'Error: rebase left in progress\n'
        errors=$((errors + 1))
    fi
    if grep -q 'Error' <<<"$output"; then
        printf 'Error: hook failed during rebase: %s\n' "$output"
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --install-hook skips rebase'
}

test_flag_install_hook_idempotent() {
    local repo_dir hook_file first_exit second_exit errors=0

    repo_dir=$(new_hook_test_repo)
    hook_file="${repo_dir}/.git/hooks/post-commit"

    (cd "$repo_dir" && "./${SCRIPT_NAME}" --install-hook >/dev/null 2>&1)
    first_exit=$?
    (cd "$repo_dir" && "./${SCRIPT_NAME}" --install-hook >/dev/null 2>&1)
    second_exit=$?

    if [[ "$first_exit" -ne 0 ]]; then
        printf 'Error: initial --install-hook exited with status %s\n' "$first_exit"
        errors=$((errors + 1))
    fi
    if [[ "$second_exit" -ne 0 ]]; then
        printf 'Error: re-running --install-hook over its own hook exited with status %s\n' "$second_exit"
        errors=$((errors + 1))
    fi
    if [[ ! -x "$hook_file" ]]; then
        printf 'Error: %s missing after re-install\n' "$hook_file"
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --install-hook idempotent over own hook'
}

test_flag_install_hook_anonymizes_next_commit() {
    # Must rewrite only the just-made commit (HEAD), leaving earlier history
    # untouched. Also checks two hooked commits don't grow the branch count
    # (regression for a backup branch accumulating per commit).
    local repo_dir prior_hash prior_commit new_commit errors=0
    local branch_count_before branch_count_after

    repo_dir=$(new_hook_test_repo)
    prior_hash=$(cd "$repo_dir" && git rev-parse HEAD)
    prior_commit=$(cd "$repo_dir" && git show --pretty=fuller --no-patch --date=iso "$prior_hash")

    (cd "$repo_dir" && "./${SCRIPT_NAME}" --install-hook >/dev/null 2>&1)
    branch_count_before=$(cd "$repo_dir" && git branch --list | wc -l)

    for i in 2 3; do
        (
            cd "$repo_dir" || exit 1
            echo "This is file ${i}" >"file_${i}.txt"
            git add "file_${i}.txt" >/dev/null
            git commit -m "Add file_${i}.txt" >/dev/null 2>&1
        )
    done

    new_commit=$(cd "$repo_dir" && git show --pretty=fuller --no-patch --date=iso HEAD)
    branch_count_after=$(cd "$repo_dir" && git branch --list | wc -l)

    if ! grep -q "^Author:\s\+${DEFAULT_NAME} <${DEFAULT_EMAIL}>" <<<"$new_commit"; then
        printf 'Error: new commit author was not anonymized by the hook\n'
        errors=$((errors + 1))
    fi
    if ! grep -q "^AuthorDate:\s\+${DEFAULT_DATE}" <<<"$new_commit"; then
        printf 'Error: new commit date was not anonymized by the hook\n'
        errors=$((errors + 1))
    fi
    if [[ "$(cd "$repo_dir" && git show --pretty=fuller --no-patch --date=iso "$prior_hash" 2>/dev/null)" != "$prior_commit" ]]; then
        printf 'Error: the hook modified the earlier commit, which should have been left untouched\n'
        errors=$((errors + 1))
    fi
    if [[ "$branch_count_after" != "$branch_count_before" ]]; then
        printf 'Error: hooked commits accumulated backup branches (%s -> %s branches for 2 commits)\n' \
            "$branch_count_before" "$branch_count_after"
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --install-hook anonymizes only new commit'
}

test_flag_install_hook_quiet() {
    # Must not spam output on every git commit.
    local repo_dir hook_file errors=0

    repo_dir=$(new_hook_test_repo)
    hook_file="${repo_dir}/.git/hooks/post-commit"

    (cd "$repo_dir" && "./${SCRIPT_NAME}" --install-hook >/dev/null 2>&1)

    if ! grep -q -- '--quiet' "$hook_file"; then
        printf 'Error: generated hook does not pass --quiet\n'
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --install-hook generates hook passing --quiet'
}

test_flag_uninstall_hook_removes_hook() {
    local repo_dir hook_file output exit_status errors=0

    repo_dir=$(new_hook_test_repo)
    hook_file="${repo_dir}/.git/hooks/post-commit"

    (cd "$repo_dir" && "./${SCRIPT_NAME}" --install-hook >/dev/null 2>&1)

    output=$(cd "$repo_dir" && "./${SCRIPT_NAME}" --uninstall-hook 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --uninstall-hook exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ -e "$hook_file" ]]; then
        printf 'Error: %s was not removed\n' "$hook_file"
        errors=$((errors + 1))
    fi
    if ! grep -qi 'removed post-commit hook' <<<"$output"; then
        printf 'Error: expected confirmation message not found in output\n'
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --uninstall-hook removes own hook'
}

test_flag_uninstall_hook_requires_git_repo() {
    local no_repo_dir output exit_status errors=0

    no_repo_dir=$(mktemp -d /tmp/anon_git_test_uninstall_hook_norepo.XXXXXX)
    cp "$SCRIPT" "$no_repo_dir/"
    chmod +x "${no_repo_dir}/${SCRIPT_NAME}"

    output=$(cd "$no_repo_dir" && "./${SCRIPT_NAME}" --uninstall-hook 2>&1)
    exit_status=$?

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: --uninstall-hook outside a git repository did not fail\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'git repository' <<<"$output"; then
        printf 'Error: expected "git repository" message not found\n'
        errors=$((errors + 1))
    fi

    rm -rf "$no_repo_dir"

    record_result "$errors" 'flag --uninstall-hook requires git repo'
}

test_flag_uninstall_hook_nothing_installed() {
    # Must succeed rather than treat "not found" as an error.
    local repo_dir output exit_status errors=0

    repo_dir=$(new_hook_test_repo)

    output=$(cd "$repo_dir" && "./${SCRIPT_NAME}" --uninstall-hook 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --uninstall-hook with no hook installed exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if ! grep -qi 'no post-commit hook installed' <<<"$output"; then
        printf 'Error: expected a "no post-commit hook installed" message not found\n'
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --uninstall-hook without hook succeeds, reports it'
}

test_flag_uninstall_hook_preserves_foreign_hook() {
    local repo_dir hook_file original output exit_status errors=0

    repo_dir=$(new_hook_test_repo)
    hook_file="${repo_dir}/.git/hooks/post-commit"
    printf '#!/bin/sh\necho foreign\n' >"$hook_file"
    chmod +x "$hook_file"
    original=$(cat "$hook_file")

    output=$(cd "$repo_dir" && "./${SCRIPT_NAME}" --uninstall-hook 2>&1)
    exit_status=$?

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: --uninstall-hook did not fail over a pre-existing foreign hook\n'
        errors=$((errors + 1))
    fi
    if [[ "$(cat "$hook_file")" != "$original" ]]; then
        printf 'Error: pre-existing foreign hook was removed/overwritten\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'not installed by anon-git' <<<"$output"; then
        printf 'Error: expected a "not installed by anon-git" message not found\n'
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --uninstall-hook keeps foreign hook'
}
