#!/usr/bin/env bash

# Sourced by test_anon_git.sh — not meant to be run directly.
# CONFIG PRIORITY TESTS: precedence among CLI flags, git config anon-git.*,
# and ANON_GIT_* environment variables.

test_combo_dry_run_entire_history() {
    local before after output exit_status preview_count errors=0

    before=$(git rev-parse HEAD)
    output=$(PAGER="cat" ./"${SCRIPT_NAME}" --dry-run --entire-history 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)
    preview_count=$(grep -c '^Commit:' <<<"$output")

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --dry-run --entire-history exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: --dry-run --entire-history modified HEAD\n'
        errors=$((errors + 1))
    fi
    if [[ "$preview_count" -ne "$COMMIT_COUNT" ]]; then
        printf 'Error: expected %s commits previewed, got %s\n' "$COMMIT_COUNT" "$preview_count"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flags --dry-run --entire-history'
}

test_combo_env_var_dry_run_entire_history() {
    # check_incompatible only looks at CLI-flag *_ARG variables, not envvars,
    # so both env vars together must still preview everything without
    # rewriting (same as test_combo_dry_run_entire_history). --no-confirm is
    # passed as a flag only to avoid the "zero args" early-exit to help.
    local before after output exit_status preview_count errors=0

    before=$(git rev-parse HEAD)
    output=$(PAGER="cat" ANON_GIT_DRYRUN=1 ANON_GIT_ENTIREHISTORY=1 ./"${SCRIPT_NAME}" --no-confirm 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)
    preview_count=$(grep -c '^Commit:' <<<"$output")

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: ANON_GIT_DRYRUN=1 ANON_GIT_ENTIREHISTORY=1 run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: ANON_GIT_DRYRUN=1 ANON_GIT_ENTIREHISTORY=1 modified HEAD\n'
        errors=$((errors + 1))
    fi
    if [[ "$preview_count" -ne "$COMMIT_COUNT" ]]; then
        printf 'Error: expected %s commits previewed, got %s\n' "$COMMIT_COUNT" "$preview_count"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'envvars ANON_GIT_DRYRUN=1 ANON_GIT_ENTIREHISTORY=1 preview history, no rewrite'
}

test_combo_env_var_flag_priority() {
    # Documented priority: flags > envvars > defaults.
    local exit_status commit_info errors=0
    local env_name='Ignored Env Name' flag_name='Flag Wins'

    ANON_GIT_NAME="$env_name" ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --name "$flag_name" HEAD >/dev/null 2>&1
    exit_status=$?

    commit_info=$(git show --pretty=fuller --no-patch HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --name + ANON_GIT_NAME run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if ! grep -q "^Author:\s\+${flag_name} <" <<<"$commit_info"; then
        printf 'Error: --name flag did not take priority over ANON_GIT_NAME\n'
        errors=$((errors + 1))
    fi
    grep -qF "$env_name" <<<"$commit_info" && {
        printf 'Error: ANON_GIT_NAME leaked through despite --name flag\n'
        errors=$((errors + 1))
    }

    record_result "$errors" 'flag --name overrides ANON_GIT_NAME'
}

test_flag_overrides_env_group() {
    # A flag overrides envvars of the same group instead of conflicting.
    local original_author output exit_status errors=0

    original_author=$(git show -s --format='%an' HEAD)
    output=$(ANON_GIT_NAME='Env Name' ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --keep-user HEAD 2>&1)
    exit_status=$?
    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --keep-user with ANON_GIT_NAME failed: %s\n' "$output"
        errors=$((errors + 1))
    fi
    if [[ "$(git show -s --format='%an' HEAD)" != "$original_author" ]]; then
        printf 'Error: --keep-user did not override ANON_GIT_NAME\n'
        errors=$((errors + 1))
    fi

    output=$(ANON_GIT_KEEPDATE=1 ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch \
        --date '2021-02-03 04:05:06 +0000' HEAD 2>&1)
    exit_status=$?
    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --date with ANON_GIT_KEEPDATE=1 failed: %s\n' "$output"
        errors=$((errors + 1))
    fi
    if [[ "$(git show -s --format='%ai' HEAD)" != '2021-02-03 04:05:06 +0000' ]]; then
        printf 'Error: --date did not override ANON_GIT_KEEPDATE=1\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag overrides envvar of same group'
}

test_flag_env_vars() {
    # ANON_GIT_NAME/EMAIL/DATE work as priority-3 config, same as
    # --name/--email/--date.
    local random_index new_commit_hash exit_status commit_info errors=0
    local env_name='Grace Murray' env_email='grace.murray@example.com' env_date='2019-05-05 00:00:00 +0000'

    pick_random_index
    random_index=$PICKED_INDEX

    ANON_GIT_NAME="$env_name" ANON_GIT_EMAIL="$env_email" ANON_GIT_DATE="$env_date" \
        ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch "HEAD~${random_index}" >/dev/null 2>&1
    exit_status=$?

    new_commit_hash=$(git rev-parse "HEAD~${random_index}")
    commit_info=$(git show --pretty=fuller --no-patch --date=iso "$new_commit_hash")

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: ANON_GIT_* env-var run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if ! grep -q "^Author:\s\+${env_name} <${env_email}>" <<<"$commit_info"; then
        printf 'Error: ANON_GIT_NAME/ANON_GIT_EMAIL not respected\n'
        errors=$((errors + 1))
    fi
    if ! grep -q "^AuthorDate:\s\+${env_date}" <<<"$commit_info"; then
        printf 'Error: ANON_GIT_DATE not respected\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'ANON_GIT_* envvars overwrite defaults'
}

test_gitconfig_defaults() {
    # anon-git.name/email/date work as priority-2 config (below flags, above
    # envvars and defaults).
    local cfg_name='Barbara McClintock' cfg_email='barbara.mcclintock@example.com'
    local cfg_date='2018-08-08 00:00:00 +0000'
    local exit_status commit_info errors=0

    git config --local anon-git.name "$cfg_name"
    git config --local anon-git.email "$cfg_email"
    git config --local anon-git.date "$cfg_date"

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch HEAD >/dev/null 2>&1
    exit_status=$?
    commit_info=$(git show --pretty=fuller --no-patch --date=iso HEAD)

    git config --local --unset anon-git.name
    git config --local --unset anon-git.email
    git config --local --unset anon-git.date

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: git config anon-git.* run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if ! grep -q "^Author:\s\+${cfg_name} <${cfg_email}>" <<<"$commit_info"; then
        printf 'Error: git config anon-git.name/anon-git.email not respected\n'
        errors=$((errors + 1))
    fi
    if ! grep -q "^AuthorDate:\s\+${cfg_date}" <<<"$commit_info"; then
        printf 'Error: git config anon-git.date not respected\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'git config anon-git.* sets repo-local defaults'
}

test_gitconfig_beats_envvar() {
    # anon-git.name (priority 2) must win over ANON_GIT_NAME (priority 3).
    local cfg_name='Config Wins' env_name='Envvar Loses'
    local exit_status commit_info errors=0

    git config --local anon-git.name "$cfg_name"

    ANON_GIT_NAME="$env_name" ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch HEAD >/dev/null 2>&1
    exit_status=$?
    commit_info=$(git show --pretty=fuller --no-patch HEAD)

    git config --local --unset anon-git.name

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: ANON_GIT_NAME + anon-git.name run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if ! grep -q "^Author:\s\+${cfg_name} <" <<<"$commit_info"; then
        printf 'Error: anon-git.name config did not take priority over ANON_GIT_NAME\n'
        errors=$((errors + 1))
    fi
    grep -qF "$env_name" <<<"$commit_info" && {
        printf 'Error: ANON_GIT_NAME leaked through despite anon-git.name config\n'
        errors=$((errors + 1))
    }

    record_result "$errors" 'anon-git.name config overrides ANON_GIT_NAME envvar'
}

test_gitconfig_flag_priority() {
    # --name (priority 1) must win over anon-git.name config (priority 2).
    local cfg_name='Config Loses' flag_name='Flag Wins'
    local exit_status commit_info errors=0

    git config --local anon-git.name "$cfg_name"

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --name "$flag_name" HEAD >/dev/null 2>&1
    exit_status=$?
    commit_info=$(git show --pretty=fuller --no-patch HEAD)

    git config --local --unset anon-git.name

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --name + anon-git.name config run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if ! grep -q "^Author:\s\+${flag_name} <" <<<"$commit_info"; then
        printf 'Error: --name flag did not take priority over anon-git.name config\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --name overrides anon-git.name config'
}

test_gitconfig_keepuser_bool() {
    # $1 (optional): spelling, default yes. Any git bool spelling (any case)
    # must normalize like --keep-user.
    local value="${1:-yes}" before_author after_author exit_status errors=0

    before_author=$(git show -s --format='%an <%ae>' HEAD)
    git config --local anon-git.keepuser "$value"

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch HEAD >/dev/null 2>&1
    exit_status=$?
    after_author=$(git show -s --format='%an <%ae>' HEAD)

    git config --local --unset anon-git.keepuser

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: anon-git.keepuser=%s run exited with status %s\n' "$value" "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$after_author" != "$before_author" ]]; then
        printf 'Error: anon-git.keepuser=%s did not preserve author identity\n' "$value"
        errors=$((errors + 1))
    fi

    record_result "$errors" "anon-git.keepuser=$value config acts as --keep-user"
}

test_gitconfig_invalid_bool() {
    local before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    git config --local anon-git.keepuser bogus

    output=$(./"${SCRIPT_NAME}" --no-confirm --no-backup HEAD 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    git config --local --unset anon-git.keepuser

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: anon-git.keepuser=bogus did not fail as expected\n'
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite invalid anon-git.keepuser value\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'invalid boolean value' <<<"$output"; then
        printf 'Error: expected "invalid boolean value" message not found\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'non-boolean anon-git.keepuser fails cleanly'
}

test_gitconfig_catch_incompatible() {
    # Must be rejected the same way --keep-user --email is: reject_incompatible_options
    # folds GITCONFIG_* into the same "_set" checks as flags/envvars.
    local before after exit_status errors=0

    git config --local anon-git.keepuser true
    git config --local anon-git.email 'nobody@example.com'

    before=$(git rev-parse HEAD)
    ./"${SCRIPT_NAME}" --no-confirm --no-backup HEAD >/dev/null 2>&1
    exit_status=$?
    after=$(git rev-parse HEAD)

    git config --local --unset anon-git.keepuser
    git config --local --unset anon-git.email

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: anon-git.keepuser=true + anon-git.email did not fail as expected\n'
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite incompatible git config\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'catch incompatible anon-git.keepuser + anon-git.email config'
}

test_gitconfig_quiet() {
    # Must suppress output like --quiet; --verbose must still override for one run.
    local original_branch new_branch_name output exit_status errors=0

    git config --local anon-git.quiet true

    original_branch=$(git branch --show-current)
    output=$(./"${SCRIPT_NAME}" --no-confirm --name 'Grace Hopper Quiet' HEAD 2>&1)
    exit_status=$?

    new_branch_name=$(git branch --format='%(refname:short)' | grep "^${original_branch}_anonymized_" | tail -1)
    git switch "$original_branch" >/dev/null 2>&1
    [[ -n "$new_branch_name" ]] && git branch -D "$new_branch_name" >/dev/null 2>&1

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: anon-git.quiet=true run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ -n "$output" ]]; then
        printf 'Error: anon-git.quiet=true produced output: %s\n' "$output"
        errors=$((errors + 1))
    fi

    output=$(./"${SCRIPT_NAME}" --no-confirm --verbose --name 'Grace Hopper Verbose' HEAD 2>&1)
    new_branch_name=$(git branch --format='%(refname:short)' | grep "^${original_branch}_anonymized_" | tail -1)
    git switch "$original_branch" >/dev/null 2>&1
    [[ -n "$new_branch_name" ]] && git branch -D "$new_branch_name" >/dev/null 2>&1

    git config --local --unset anon-git.quiet

    if ! grep -q 'Anonymizing commit' <<<"$output"; then
        printf 'Error: --verbose did not override anon-git.quiet=true\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'anon-git.quiet config suppresses output; --verbose overrides'
}

test_flag_env_var_entirehistory() {
    # Must behave like --entire-history without the flag (isolates the
    # envvar path from test_entire_history's flag path).
    local exit_status mismatches errors=0

    ANON_GIT_ENTIREHISTORY=1 ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch >/dev/null 2>&1
    exit_status=$?

    mismatches=$(git log --format='%an <%ae>' | grep --invert-match --count "^${DEFAULT_NAME} <${DEFAULT_EMAIL}>\$")

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: ANON_GIT_ENTIREHISTORY=1 run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$mismatches" -ne 0 ]]; then
        printf 'Error: ANON_GIT_ENTIREHISTORY=1 left %s commit(s) with a non-default author\n' "$mismatches"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'ANON_GIT_ENTIREHISTORY=1 rewrites entire history without flag'
}

test_catch_env_var_entirehistory_with_commit() {
    local before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(ANON_GIT_ENTIREHISTORY=1 ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch HEAD 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: ANON_GIT_ENTIREHISTORY=1 with commit argument did not fail\n'
        errors=$((errors + 1))
    fi
    if ! grep -q 'cannot be used together' <<<"$output"; then
        printf 'Error: expected "cannot be used together" message not found\n'
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: HEAD changed despite conflict\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'ANON_GIT_ENTIREHISTORY=1 with commit argument rejected'
}

test_flag_env_var_currentbranch() {
    # Must rewrite HEAD in place (like --current-branch), not on a new branch.
    local before_head after_head branch_before branch_after exit_status errors=0

    before_head=$(git rev-parse HEAD)
    branch_before=$(git branch --show-current)

    ANON_GIT_CURRENTBRANCH=1 ./"${SCRIPT_NAME}" --no-confirm --no-backup --name 'Barbara Liskov' HEAD >/dev/null 2>&1
    exit_status=$?

    after_head=$(git rev-parse HEAD)
    branch_after=$(git branch --show-current)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: ANON_GIT_CURRENTBRANCH=1 run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$after_head" == "$before_head" ]]; then
        printf 'Error: ANON_GIT_CURRENTBRANCH=1 did not rewrite HEAD\n'
        errors=$((errors + 1))
    fi
    if [[ "$branch_after" != "$branch_before" ]]; then
        printf 'Error: ANON_GIT_CURRENTBRANCH=1 switched to a new branch instead of rewriting in place\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'ANON_GIT_CURRENTBRANCH=1 rewrites in place without flag'
}

test_flag_env_var_dryrun() {
    # Must behave like --dry-run: preview only, no branch, HEAD untouched.
    # Regression: the resolve-args line previously ignored this envvar.
    local before after branches_before branches_after output exit_status errors=0

    before=$(git rev-parse HEAD)
    branches_before=$(git branch --format='%(refname:short)' | sort)

    output=$(PAGER="cat" ANON_GIT_DRYRUN=1 ./"${SCRIPT_NAME}" HEAD 2>&1)
    exit_status=$?

    after=$(git rev-parse HEAD)
    branches_after=$(git branch --format='%(refname:short)' | sort)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: ANON_GIT_DRYRUN=1 run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: ANON_GIT_DRYRUN=1 modified HEAD\n'
        errors=$((errors + 1))
    fi
    if [[ "$branches_before" != "$branches_after" ]]; then
        printf 'Error: ANON_GIT_DRYRUN=1 created a new branch instead of only previewing\n'
        errors=$((errors + 1))
    fi
    if ! grep -q 'AuthorDate:' <<<"$output"; then
        printf 'Error: ANON_GIT_DRYRUN=1 output missing expected preview content\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'ANON_GIT_DRYRUN=1 previews without flag, no rewrite'
}

test_flag_verbose_overrides_env_quiet() {
    # Must win over ANON_GIT_QUIET=1, forcing output back on for one run.
    local output exit_status errors=0

    output=$(ANON_GIT_QUIET=1 ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --verbose --name 'Dennis Ritchie' HEAD 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --verbose run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if ! grep -q 'Anonymizing commit' <<<"$output"; then
        printf 'Error: --verbose did not override ANON_GIT_QUIET=1\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --verbose overrides ANON_GIT_QUIET=1'
}
