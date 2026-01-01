#!/usr/bin/env bash

# Sourced by test_anon_git.sh — not meant to be run directly.
# CONFIG PRIORITY TESTS: precedence among CLI flags, git config anon-git.*,\n# and ANON_GIT_* environment variables.

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
    # ANON_GIT_DRYRUN and ANON_GIT_ENTIREHISTORY are not flagged by
    # check_incompatible (that only looks at CLI-flag-derived *_ARG
    # variables, never at env vars) and are not meant to be: --dry-run and
    # --entire-history are a supported combo (see
    # test_combo_dry_run_entire_history), so setting both env vars together
    # must behave the same way, i.e. preview every commit without rewriting
    # anything. --no-confirm is passed as a flag (not an env var) only to
    # avoid the separate "zero args at all" early-exit that shows help
    # before env vars are even read; it does not affect what's under test.
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

    record_result "$errors" 'envvars ANON_GIT_DRYRUN=1 ANON_GIT_ENTIREHISTORY=1 preview entire history without rewriting'
}

test_combo_env_var_flag_priority() {
    # Command-line flags must win over ANON_GIT_* environment variables
    # (documented priority: flags > env vars > hardcoded defaults).
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

test_flag_env_vars() {
    # ANON_GIT_NAME/EMAIL/DATE must work as priority-3 config (README:
    # "Environment variables"), same as their --name/--email/--date flags.
    local random_index new_commit_hash exit_status commit_info errors=0
    local env_name='Grace Murray' env_email='grace.murray@example.com' env_date='2019-05-05 00:00:00 +0000'

    random_index=$(($(od -An -N2 -tu2 </dev/urandom) % (COMMIT_COUNT - 1)))

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
    # git config anon-git.name/email/date must work as priority-2 config
    # (below flags, above ANON_GIT_* envvars and hardcoded defaults), same as
    # their --name/--email/--date flags.
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

    record_result "$errors" 'git config anon-git.* provides repo-local defaults'
}

test_gitconfig_beats_envvar() {
    # anon-git.name config (priority 2) must win over ANON_GIT_NAME
    # (priority 3), per the documented priority order: repo-local config
    # outranks an inherited/exported envvar.
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
    # anon-git.keepuser (a boolean config key) must behave like --keep-user:
    # git config's true/false/yes/no/on/off/1/0 spellings all normalize to
    # the same '1'/'0' contract as the ANON_GIT_KEEPUSER envvar.
    local before_author after_author exit_status errors=0

    before_author=$(git show -s --format='%an <%ae>' HEAD)
    git config --local anon-git.keepuser yes

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch HEAD >/dev/null 2>&1
    exit_status=$?
    after_author=$(git show -s --format='%an <%ae>' HEAD)

    git config --local --unset anon-git.keepuser

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: anon-git.keepuser=yes run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$after_author" != "$before_author" ]]; then
        printf 'Error: anon-git.keepuser=yes did not preserve author identity\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'anon-git.keepuser config behaves like --keep-user'
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

    record_result "$errors" 'anon-git.keepuser with a non-boolean value fails cleanly'
}

test_gitconfig_catch_incompatible() {
    # anon-git.keepuser=true + anon-git.email configured together must be
    # rejected the same way --keep-user --email is, since reject_incompatible_options
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
    # anon-git.quiet=true must suppress informational output like --quiet,
    # and --verbose must still override it for one run.
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

    record_result "$errors" 'anon-git.quiet config suppresses output; --verbose overrides it'
}

test_flag_env_var_entirehistory() {
    # ANON_GIT_ENTIREHISTORY=1 must behave like --entire-history even
    # without the flag (isolates the env-var path from the flag path
    # already covered by test_entire_history).
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

    record_result "$errors" 'ANON_GIT_ENTIREHISTORY=1 rewrites entire history without the flag'
}

test_flag_env_var_currentbranch() {
    # ANON_GIT_CURRENTBRANCH=1 must rewrite HEAD in place (like
    # --current-branch) instead of creating a new branch.
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

    record_result "$errors" 'ANON_GIT_CURRENTBRANCH=1 rewrites in place without the flag'
}

test_flag_env_var_dryrun() {
    # ANON_GIT_DRYRUN=1 must behave like --dry-run: preview only, no branch
    # created, HEAD untouched. Regression test: the resolve-args line for
    # ANON_GIT_DRYRUN previously only considered the --dry-run flag or the
    # hardcoded default, silently ignoring the environment variable.
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

    record_result "$errors" 'ANON_GIT_DRYRUN=1 previews without rewriting, without the flag'
}

test_flag_verbose_overrides_env_quiet() {
    # --verbose is a CLI-only override that must win over ANON_GIT_QUIET=1,
    # forcing the informational output back on for that one run.
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
