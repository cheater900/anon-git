#!/usr/bin/env bash

# Sourced by test_anon_git.sh — not meant to be run directly.
# INSTALL / HOOK TESTS: --install and --install-hook.

test_flag_install_local_bin() {
    # --install must copy the running script into ~/.local/bin when it
    # exists, mark it executable, and warn (on stderr) if that directory
    # isn't on $PATH. Uses a disposable $HOME so this never touches the
    # real ~/.local/bin. --install-system is intentionally not tested here:
    # it needs sudo and a real /usr/bin, and we don't want to run as root
    # or mock it.
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

test_flag_install_bin_fallback() {
    # Falls back to ~/.bin when ~/.local/bin doesn't exist.
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
    # Copies to both ~/.local/bin and ~/.bin when both exist.
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

    record_result "$errors" 'flag --install copies to both ~/.local/bin and ~/.bin when both exist'
}

test_flag_install_path_already_set() {
    # No $PATH warning when the target directory is already on $PATH.
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

    record_result "$errors" "flag --install skips the \$PATH warning when already on \$PATH"
}

test_flag_install_no_target_dir() {
    # Neither ~/.local/bin nor ~/.bin exists: --install must fail cleanly
    # without creating either directory.
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

    record_result "$errors" 'flag --install fails cleanly when neither target directory exists'
}

test_flag_install_idempotent() {
    # Running --install again from the just-installed copy (same path, same
    # inode) should report "Already installed" rather than overwrite it and
    # re-warn about $PATH.
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

    record_result "$errors" 'flag --install is idempotent when re-run from the installed copy'
}

test_flag_uninstall_removes_both_dirs() {
    # --uninstall must remove the script from every candidate directory that
    # actually has a copy (both ~/.local/bin and ~/.bin here), reporting each
    # removal, and leave the (now empty) directories themselves alone.
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

    record_result "$errors" 'flag --uninstall removes the script from both ~/.local/bin and ~/.bin'
}

test_flag_uninstall_skips_missing_dir() {
    # Only ~/.local/bin has a copy; --uninstall must remove that one and not
    # treat the absent ~/.bin copy as a failure.
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

    record_result "$errors" 'flag --uninstall skips a candidate directory with no installed copy'
}

test_flag_uninstall_nothing_installed() {
    # Nothing installed anywhere: --uninstall must succeed (the desired end
    # state is already reached) and say so, rather than treating "not found"
    # as an error the way --install does for "no target directory".
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

    record_result "$errors" 'flag --uninstall with nothing installed succeeds and says so'
}

new_hook_test_repo() {
    # Creates an isolated git repo (separate from the shared $TMP_DIR repo
    # used by the rest of the suite, so hook side effects can't leak into
    # other tests) with one commit and a copy of the script inside it.
    # Prints the repo's absolute path.
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

    record_result "$errors" 'flag --install-hook creates a post-commit hook'
}

test_flag_install_hook_requires_git_repo() {
    # Must live outside $TMP_DIR (which is itself a git repo, see init_repo):
    # `git rev-parse --git-dir` walks up parent directories, so a dir nested
    # inside $TMP_DIR would be treated as being inside that repo and
    # --install-hook would (wrongly) succeed there, polluting the shared
    # suite repo's hooks in the process.
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

    record_result "$errors" 'flag --install-hook requires a git repository'
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

    record_result "$errors" 'flag --install-hook does not overwrite a pre-existing foreign hook'
}

test_flag_install_hook_warns_on_hookspath() {
    # Regression test: git honors core.hooksPath over <git-dir>/hooks when
    # set (common with husky/pre-commit/lefthook), so a hook written to the
    # standard location would silently never fire. --install-hook must warn
    # about this rather than installing silently, but should still succeed
    # (exit 0) and still write the hook file, so it stays regenerable/usable
    # for manual relocation.
    local repo_dir hook_file output exit_status errors=0

    repo_dir=$(new_hook_test_repo)
    hook_file="${repo_dir}/.git/hooks/post-commit"
    (cd "$repo_dir" && git config --local core.hooksPath .husky)

    output=$(cd "$repo_dir" && "./${SCRIPT_NAME}" --install-hook 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --install-hook with core.hooksPath set exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ ! -x "$hook_file" ]]; then
        printf 'Error: %s was not created despite core.hooksPath being set\n' "$hook_file"
        errors=$((errors + 1))
    fi
    if ! grep -qi 'core.hookspath' <<<"$output"; then
        printf 'Error: expected a core.hooksPath warning not found\n'
        errors=$((errors + 1))
    fi
    if ! grep -qF '.husky' <<<"$output"; then
        printf 'Error: warning did not mention the configured hooksPath value\n'
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --install-hook warns when core.hooksPath is set'
}

test_flag_install_hook_no_warning_without_hookspath() {
    # No core.hooksPath warning when it isn't set (the common case) — a
    # sibling regression test to the one above, pinning down the non-noisy
    # default so a future change can't make --install-hook warn on every run.
    local repo_dir output exit_status errors=0

    repo_dir=$(new_hook_test_repo)

    output=$(cd "$repo_dir" && "./${SCRIPT_NAME}" --install-hook 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --install-hook exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if grep -qi 'core.hookspath' <<<"$output"; then
        printf 'Error: unexpected core.hooksPath warning when it is not set\n'
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --install-hook does not warn when core.hooksPath is unset'
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

    record_result "$errors" 'flag --install-hook is idempotent when re-run over its own hook'
}

test_flag_install_hook_anonymizes_next_commit() {
    # The hook must fire after `git commit` and rewrite only the just-made
    # commit (HEAD); earlier history must be left untouched. Also a
    # regression test for the hook accumulating a backup branch per commit
    # (fixed by passing --no-backup): makes two hooked commits and checks
    # the branch count never grows, since the hook fires on every commit.
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

    record_result "$errors" 'flag --install-hook anonymizes only the just-made commit'
}

test_flag_install_hook_quiet() {
    # The generated post-commit hook must pass --quiet, so it doesn't spam
    # "Anonymizing commit(s): ..." / "Done." on every git commit.
    local repo_dir hook_file errors=0

    repo_dir=$(new_hook_test_repo)
    hook_file="${repo_dir}/.git/hooks/post-commit"

    (cd "$repo_dir" && "./${SCRIPT_NAME}" --install-hook >/dev/null 2>&1)

    if ! grep -q -- '--quiet' "$hook_file"; then
        printf 'Error: generated hook does not pass --quiet\n'
        errors=$((errors + 1))
    fi

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --install-hook generates a hook that passes --quiet'
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

    record_result "$errors" 'flag --uninstall-hook removes a hook it installed'
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

    record_result "$errors" 'flag --uninstall-hook requires a git repository'
}

test_flag_uninstall_hook_nothing_installed() {
    # No hook present: --uninstall-hook must succeed (nothing to do) rather
    # than treat "not found" as an error.
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

    record_result "$errors" 'flag --uninstall-hook with no hook installed succeeds and says so'
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

    record_result "$errors" 'flag --uninstall-hook does not remove a pre-existing foreign hook'
}
