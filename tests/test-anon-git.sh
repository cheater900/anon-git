#!/usr/bin/env bash

# Assume anonymize-git-commit.sh is in the parent directory
SCRIPT_DIR=$(realpath "$(dirname "$0")/..")
SCRIPT_NAME=anon-git.sh
SCRIPT=${SCRIPT_DIR}/${SCRIPT_NAME}

# Create temp dir to work on
TMP_DIR=$(mktemp -d /tmp/anon_git_test.XXXXXX)
cd "$TMP_DIR" || exit 1
cp "$SCRIPT" .
chmod +x "./${SCRIPT_NAME}"

cleanup() {
    cd - >/dev/null 2>&1 || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Global variables shared among functions

COMMIT_COUNT=20
CURRENT_TEST_INDEX=0
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_ERRORS=0

DEFAULT_DATE=$(grep '^DEFAULT_DATE=' "$SCRIPT" | sed -e "s/DEFAULT_DATE='//" -e "s/'\$//")
DEFAULT_NAME=$(grep '^DEFAULT_NAME=' "$SCRIPT" | sed -e "s/DEFAULT_NAME='//" -e "s/'\$//")
DEFAULT_EMAIL=$(grep '^DEFAULT_EMAIL=' "$SCRIPT" | sed -e "s/DEFAULT_EMAIL='//" -e "s/'\$//")
DEFAULT_KEEPUSER=$(grep '^DEFAULT_KEEPUSER=' "$SCRIPT" | sed -e "s/DEFAULT_KEEPUSER='//" -e "s/'\$//")
DEFAULT_KEEPDATE=$(grep '^DEFAULT_KEEPDATE=' "$SCRIPT" | sed -e "s/DEFAULT_KEEPDATE='//" -e "s/'\$//")

# ──────────────────────────────────────────────────────────────────────

init_repo() {
    git init >/dev/null
    git config --local user.name "Jordan Blake"
    git config --local user.email "jordan.blake@example.com"
    for i in $(seq 1 "$COMMIT_COUNT"); do
        filename="file_${i}.txt"
        echo "This is file $i" >"$filename"
        git add "$filename" >/dev/null
        git commit -m "Add file $filename" >/dev/null
    done
}

test_script() {
    # @param $@  flags to pass through to the script (--name, --email, --date, --keep-user, --keep-date)
    local expected_name expected_email expected_date keep_user keep_date args label
    local expected_author random_index commit_hash commit_format original_branch
    local script_exit new_commit_hash OLD_AUTHOR OLD_DATE OLD_COMMITS
    local NEW_AUTHOR NEW_DATE NEW_COMMITS NEW_COMMIT
    local author_matches committer_matches author_date_matches committer_date_matches errors
    local flags=() arg

    for arg in "$@"; do
        [[ "$arg" == -* ]] && flags+=("$arg")
    done
    label="args ${flags[*]:-(defaults)}"

    expected_name="${DEFAULT_NAME}"
    expected_email="${DEFAULT_EMAIL}"
    expected_date="${DEFAULT_DATE}"
    keep_user="${DEFAULT_KEEPUSER}"
    keep_date="${DEFAULT_KEEPDATE}"

    args=(--no-confirm --no-backup)
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --date)
            expected_date="$2"
            args=("${args[@]}" --date "$2")
            shift 2
            ;;
        --name)
            expected_name="$2"
            args=("${args[@]}" --name "$2")
            shift 2
            ;;
        --email)
            expected_email="$2"
            args=("${args[@]}" --email "$2")
            shift 2
            ;;
        --keep-user)
            keep_user='1'
            args=("${args[@]}" --keep-user)
            shift
            ;;
        --keep-date)
            keep_date='1'
            args=("${args[@]}" --keep-date)
            shift
            ;;
        *)
            printf 'Unexpected argument in test_script\n'
            exit 1
            ;;
        esac
    done
    expected_author="${expected_name} <${expected_email}>"

    # Pick random commit
    random_index=$(($(od -An -N2 -tu2 </dev/urandom) % (COMMIT_COUNT - 1)))

    # store old logs (except commit to be modified)
    commit_hash=$(git rev-parse "HEAD~${random_index}")
    commit_format='%H %an <%aE> (%ai) %cn <%cE> (%ci)'
    OLD_AUTHOR=$(git show --format='%an <%ae> %cn <%ce>' "$commit_hash")
    OLD_DATE=$(git show --format='%ai %ci' "$commit_hash")
    OLD_COMMITS=$(git log --format="$commit_format" | grep --invert-match "$commit_hash" | sed 's/^[0-9a-f]\+//')

    # Store current branch because the script by default will create a new one
    original_branch=$(git branch --show-current)

    # Run script
    ./${SCRIPT_NAME} "${args[@]}" "HEAD~${random_index}" >/dev/null 2>&1
    script_exit=$?

    # store new logs (except modified commit)
    new_commit_hash=$(git rev-parse "HEAD~${random_index}")

    # store new logs for comparison
    NEW_AUTHOR=$(git show --format='%an <%ae> %cn <%ce>' "$new_commit_hash")
    NEW_DATE=$(git show --format='%ai %ci' "$new_commit_hash")
    NEW_COMMITS=$(git log --format="$commit_format" | grep --invert-match "$new_commit_hash" | sed 's/^[0-9a-f]\+//')
    NEW_COMMIT=$(git show --pretty=fuller --no-patch --date=iso "$new_commit_hash")

    # Check results

    ## Real values
    author_matches=$(grep --count "^Author:\s\+${expected_author}" <<<"$NEW_COMMIT")
    committer_matches=$(grep --count "^Commit:\s\+${expected_author}" <<<"$NEW_COMMIT")
    author_date_matches=$(grep --count "^AuthorDate:\s\+${expected_date}" <<<"$NEW_COMMIT")
    committer_date_matches=$(grep --count "^CommitDate:\s\+${expected_date}" <<<"$NEW_COMMIT")

    # check for errors
    errors=0

    # exit status check
    if [[ "$script_exit" -ne 0 ]]; then
        printf 'Error: script exited with status %s\n' "$script_exit"
        errors=$((errors + 1))
    fi

    # author & committer check
    if [[ "$keep_user" != '1' && "$author_matches" -ne 1 ]]; then
        printf 'Error: author name & email not overwritten\n'
        errors=$((errors + 1))
    fi
    if [[ "$keep_user" != '1' && "$committer_matches" -ne 1 ]]; then
        printf 'Error: committer name & email not overwritten\n'
        errors=$((errors + 1))
    fi
    if [[ "$keep_user" == '1' && "$NEW_AUTHOR" != "$OLD_AUTHOR" ]]; then
        printf 'Error: flag --keep-user not respected\n'
        errors=$((errors + 1))
    fi

    # date check
    if [[ "$keep_date" != '1' && "$author_date_matches" -ne 1 ]]; then
        printf 'Error: author date not overwritten\n'
        errors=$((errors + 1))
    fi
    if [[ "$keep_date" != '1' && "$committer_date_matches" -ne 1 ]]; then
        printf 'Error: committer date not overwritten\n'
        errors=$((errors + 1))
    fi
    if [[ "$keep_date" == '1' && "$NEW_DATE" != "$OLD_DATE" ]]; then
        printf 'Error: flag --keep-date not respected\n'
        errors=$((errors + 1))
    fi

    # other commits check
    if [[ "$OLD_COMMITS" != "$NEW_COMMITS" ]]; then
        printf 'Error: other commits were affected!\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" "$label"

    # switch to original branch
    git switch "$original_branch" >/dev/null 2>&1
}

record_result() {
    # @param $1  number of errors found by the caller
    # @param $2  short label describing the test, for the summary line
    local errors="$1" label="$2" status
    CURRENT_TEST_INDEX=$((CURRENT_TEST_INDEX + 1))
    if [[ "$errors" -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        status='✅'
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        status='❌'
    fi
    TOTAL_ERRORS=$((TOTAL_ERRORS + errors))
    printf '%s Test %02d » test %s\n' "$status" "$CURRENT_TEST_INDEX" "$label"
}

test_python_callback_syntax() {
    # anon-git.sh assigns the git-filter-repo commit callback to a shell
    # variable, python_commit_callback="...". Extract its contents (via a
    # regex address range, since the value spans many lines) and check that
    # it's syntactically valid Python. The body uses bare `return` statements,
    # which are only legal inside a function, so wrap it in a dummy one before
    # compiling — matching how git-filter-repo itself embeds the callback.
    local raw_block python_code check_file output exit_status errors=0

    raw_block=$(sed -n '/^python_commit_callback="$/,/^"$/p' "$SCRIPT")
    python_code=$(sed -e '1d' -e '$d' <<<"$raw_block")

    if [[ -z "$python_code" ]]; then
        printf 'Error: could not extract python_commit_callback contents from %s\n' "$SCRIPT_NAME"
        errors=$((errors + 1))
    fi

    check_file="${TMP_DIR}/python_commit_callback_check.py"
    {
        printf 'def _commit_callback(commit, metadata):\n'
        printf '%s\n' "    ${python_code//$'\n'/$'\n    '}"
    } >"$check_file"

    output=$(python3 -m py_compile "$check_file" 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: python_commit_callback has a syntax error:\n%s\n' "$output"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'python commit callback syntax'
}

# ──────────────────────────────────────────────────────────────────────
# INTEGRATION TESTS

test_multiple_commits() {
    local h1 h2 exit_status a1 a2 errors=0

    h1=$(git rev-parse HEAD~1)
    h2=$(git rev-parse HEAD~3)

    ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --name 'Donald Knuth' --email 'donald.knuth@example.com' "$h1" "$h2" >/dev/null 2>&1
    exit_status=$?

    a1=$(git show -s --format='%an <%ae>' HEAD~1)
    a2=$(git show -s --format='%an <%ae>' HEAD~3)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: multi-commit run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$a1" != 'Donald Knuth <donald.knuth@example.com>' ]]; then
        printf 'Error: first target commit not anonymized\n'
        errors=$((errors + 1))
    fi
    if [[ "$a2" != 'Donald Knuth <donald.knuth@example.com>' ]]; then
        printf 'Error: second target commit not anonymized\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'multiple commits in one run'
}

test_entire_history() {
    local exit_status mismatches errors=0

    ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --entire-history >/dev/null 2>&1
    exit_status=$?

    mismatches=$(git log --format='%an <%ae>' | grep --invert-match --count "^${DEFAULT_NAME} <${DEFAULT_EMAIL}>\$")

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --entire-history exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$mismatches" -ne 0 ]]; then
        printf 'Error: --entire-history left %s commit(s) with a non-default author\n' "$mismatches"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --entire-history'
}

# ──────────────────────────────────────────────────────────────────────
# UNIT TESTS (alphabetical order)

test_catch_incompatible_flags() {
    # @param $@  the incompatible combination of flags/args to reject
    local before after exit_status errors=0 flags=() arg label

    for arg in "$@"; do
        [[ "${flags[0]}" == "--entire-history" ]] && flags+=("$arg")
        [[ "$arg" == -* ]] && flags+=("$arg")
    done
    label="catch incompatible args ${flags[*]:-(defaults)}"

    before=$(git rev-parse HEAD)
    ./${SCRIPT_NAME} --no-confirm --no-backup "$@" >/dev/null 2>&1
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: flags "%s" did not fail as expected\n' "$*"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite incompatible flags "%s"\n' "$*"
        errors=$((errors + 1))
    fi

    record_result "$errors" "$label"
}

test_catch_invalid_commit() {
    local before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(./${SCRIPT_NAME} --no-confirm --no-backup deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: invalid commit ref did not cause failure\n'
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite invalid commit ref\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'does not exist' <<<"$output"; then
        printf 'Error: expected "does not exist" message not found\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'invalid commit ref'
}

test_catch_uncommitted_changes() {
    local before after exit_status errors=0

    echo 'dirty' >>file_1.txt
    before=$(git rev-parse HEAD)
    ./${SCRIPT_NAME} --no-confirm --no-backup >/dev/null 2>&1
    exit_status=$?
    after=$(git rev-parse HEAD)
    git checkout -- file_1.txt

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: script proceeded despite uncommitted changes\n'
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: HEAD changed despite uncommitted-changes guard\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'uncommitted changes guard'
}

# ──────────────────────────────────────────────────────────────────────
# COMBINATION TESTS (alphabetical order)

test_combo_dry_run_entire_history() {
    local before after output exit_status preview_count errors=0

    before=$(git rev-parse HEAD)
    output=$(PAGER="cat" ./${SCRIPT_NAME} --dry-run --entire-history 2>&1)
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

test_combo_env_var_flag_priority() {
    # Command-line flags must win over ANON_GIT_* environment variables
    # (documented priority: flags > env vars > hardcoded defaults).
    local exit_status commit_info errors=0
    local env_name='Ignored Env Name' flag_name='Flag Wins'

    ANON_GIT_NAME="$env_name" ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --name "$flag_name" HEAD >/dev/null 2>&1
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

test_flag_current_branch_backup() {
    local before_head after_head exit_status backup_branch errors=0

    before_head=$(git rev-parse HEAD)

    ./${SCRIPT_NAME} --no-confirm --current-branch --name 'Edsger Dijkstra' HEAD >/dev/null 2>&1
    exit_status=$?
    after_head=$(git rev-parse HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --current-branch run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$after_head" == "$before_head" ]]; then
        printf 'Error: current branch HEAD did not change\n'
        errors=$((errors + 1))
    fi

    backup_branch=$(git branch --format='%(refname:short)' | grep '_backup_' | tail -1)
    if [[ -z "$backup_branch" ]]; then
        printf 'Error: no backup branch was created\n'
        errors=$((errors + 1))
    elif [[ "$(git rev-parse "$backup_branch")" != "$before_head" ]]; then
        printf 'Error: backup branch does not point at pre-rewrite HEAD\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'creates backup with flag --current-branch'
}

test_flag_dry_run() {
    local before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(PAGER="cat" ./${SCRIPT_NAME} --dry-run HEAD 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --dry-run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: --dry-run modified HEAD\n'
        errors=$((errors + 1))
    fi
    if ! grep -q 'AuthorDate:' <<<"$output"; then
        printf 'Error: --dry-run output missing expected preview content\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag dry-run'
}

test_flag_env_vars() {
    # ANON_GIT_NAME/EMAIL/DATE must work as priority-2 config (README:
    # "Environment variables"), same as their --name/--email/--date flags.
    local random_index commit_hash new_commit_hash exit_status commit_info errors=0
    local env_name='Grace Murray' env_email='grace.murray@example.com' env_date='2019-05-05 00:00:00 +0000'

    random_index=$(($(od -An -N2 -tu2 </dev/urandom) % (COMMIT_COUNT - 1)))
    commit_hash=$(git rev-parse "HEAD~${random_index}")

    ANON_GIT_NAME="$env_name" ANON_GIT_EMAIL="$env_email" ANON_GIT_DATE="$env_date" \
        ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch "HEAD~${random_index}" >/dev/null 2>&1
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

test_flag_env_var_entirehistory() {
    # ANON_GIT_ENTIREHISTORY=1 must behave like --entire-history even
    # without the flag (isolates the env-var path from the flag path
    # already covered by test_entire_history).
    local exit_status mismatches errors=0

    ANON_GIT_ENTIREHISTORY=1 ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch >/dev/null 2>&1
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

    ANON_GIT_CURRENTBRANCH=1 ./${SCRIPT_NAME} --no-confirm --no-backup --name 'Barbara Liskov' HEAD >/dev/null 2>&1
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

    output=$(PAGER="cat" ANON_GIT_DRYRUN=1 ./${SCRIPT_NAME} HEAD 2>&1)
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

    output=$(HOME="$fake_home" PATH="/usr/bin:/bin" ./${SCRIPT_NAME} --install 2>&1)
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

    HOME="$fake_home" PATH="/usr/bin:/bin" ./${SCRIPT_NAME} --install >/dev/null 2>&1
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

    HOME="$fake_home" PATH="/usr/bin:/bin" ./${SCRIPT_NAME} --install >/dev/null 2>&1
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

    output=$(HOME="$fake_home" PATH="${fake_home}/.local/bin:/usr/bin:/bin" ./${SCRIPT_NAME} --install 2>&1)
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

    output=$(HOME="$fake_home" PATH="/usr/bin:/bin" ./${SCRIPT_NAME} --install 2>&1)
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

    HOME="$fake_home" PATH="/usr/bin:/bin" ./${SCRIPT_NAME} --install >/dev/null 2>&1
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
    # commit (HEAD); earlier history must be left untouched.
    local repo_dir prior_hash prior_commit new_commit errors=0

    repo_dir=$(new_hook_test_repo)
    prior_hash=$(cd "$repo_dir" && git rev-parse HEAD)
    prior_commit=$(cd "$repo_dir" && git show --pretty=fuller --no-patch --date=iso "$prior_hash")

    (cd "$repo_dir" && "./${SCRIPT_NAME}" --install-hook >/dev/null 2>&1)

    (
        cd "$repo_dir" || exit 1
        echo "This is file 2" >file_2.txt
        git add file_2.txt >/dev/null
        git commit -m "Add file_2.txt" >/dev/null 2>&1
    )

    new_commit=$(cd "$repo_dir" && git show --pretty=fuller --no-patch --date=iso HEAD)

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

    rm -rf "$repo_dir"

    record_result "$errors" 'flag --install-hook anonymizes only the just-made commit'
}

test_show_help() {
    local output exit_status errors=0

    output=$(./${SCRIPT_NAME} --help 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --help exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if ! grep -q 'Usage:' <<<"$output"; then
        printf 'Error: --help output missing usage text\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'show --help'
}

test_show_help_inside_dirty_repo() {
    # A bare invocation (no args) should show help unconditionally, before
    # any safety checks run — an unstaged change to a tracked file should
    # not turn it into a hard failure, since there's nothing here for the
    # script to do or lose. Modifies an existing tracked file (rather than
    # adding an untracked one) since the uncommitted-changes guard this is
    # meant to bypass only looks at diff-index/diff-files, not untracked
    # files.
    local tracked_file before after output exit_status errors=0

    tracked_file='file_1.txt'
    echo 'uncommitted change' >>"$tracked_file"

    before=$(git rev-parse HEAD)
    output=$(./${SCRIPT_NAME} 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: bare invocation in a dirty repo exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: bare invocation in a dirty repo modified HEAD\n'
        errors=$((errors + 1))
    fi
    if ! grep -q 'Usage:' <<<"$output"; then
        printf 'Error: bare invocation in a dirty repo did not show help\n'
        errors=$((errors + 1))
    fi

    git checkout -- "$tracked_file"

    record_result "$errors" 'show help inside dirty repo (no args)'
}

test_flag_keep_partial() {
    # @param $1  flag under test: --keep-year | --keep-month | --keep-day
    local flag="$1" random_index commit_hash old_year old_month old_day
    local new_commit_hash new_year new_month new_day exit_status errors=0

    random_index=$(($(od -An -N2 -tu2 </dev/urandom) % (COMMIT_COUNT - 1)))
    commit_hash=$(git rev-parse "HEAD~${random_index}")
    old_year=$(git show -s --date=format:'%Y' --format='%ad' "$commit_hash")
    old_month=$(git show -s --date=format:'%m' --format='%ad' "$commit_hash")
    old_day=$(git show -s --date=format:'%d' --format='%ad' "$commit_hash")

    ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch "$flag" "HEAD~${random_index}" >/dev/null 2>&1
    exit_status=$?

    new_commit_hash=$(git rev-parse "HEAD~${random_index}")
    new_year=$(git show -s --date=format:'%Y' --format='%ad' "$new_commit_hash")
    new_month=$(git show -s --date=format:'%m' --format='%ad' "$new_commit_hash")
    new_day=$(git show -s --date=format:'%d' --format='%ad' "$new_commit_hash")

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: %s exited with status %s\n' "$flag" "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$new_year" != "$old_year" ]]; then
        printf 'Error: %s did not preserve year\n' "$flag"
        errors=$((errors + 1))
    fi
    if [[ "$flag" == '--keep-month' || "$flag" == '--keep-day' ]]; then
        if [[ "$new_month" != "$old_month" ]]; then
            printf 'Error: %s did not preserve month\n' "$flag"
            errors=$((errors + 1))
        fi
    fi
    if [[ "$flag" == '--keep-day' ]]; then
        if [[ "$new_day" != "$old_day" ]]; then
            printf 'Error: %s did not preserve day\n' "$flag"
            errors=$((errors + 1))
        fi
    fi

    record_result "$errors" "flag $flag"
}

test_flag_missing_value() {
    # @param $1  flag under test: --date | --name | --email
    local flag="$1" before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(./${SCRIPT_NAME} --no-confirm --no-backup --current-branch "$flag" 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: %s with no value did not fail as expected\n' "$flag"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite %s missing its value\n' "$flag"
        errors=$((errors + 1))
    fi
    if ! grep -qi 'requires a value' <<<"$output"; then
        printf 'Error: expected "requires a value" message not found\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" "flag with missing value: $flag"
}

test_flag_new_branch() {
    # Exercises the default (no --current-branch) code path: a fresh
    # "<branch>_anonymized_<timestamp>" branch must be created and the
    # original branch/HEAD must be left untouched.
    local original_branch before_head exit_status new_branch_name errors=0

    original_branch=$(git branch --show-current)
    before_head=$(git rev-parse HEAD)

    ./${SCRIPT_NAME} --no-confirm --name 'John von Neumann' HEAD >/dev/null 2>&1
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: default run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi

    new_branch_name=$(git branch --format='%(refname:short)' | grep "^${original_branch}_anonymized_" | tail -1)
    if [[ -z "$new_branch_name" ]]; then
        printf 'Error: expected a new "%s_anonymized_*" branch to be created\n' "$original_branch"
        errors=$((errors + 1))
    fi

    git switch "$original_branch" >/dev/null 2>&1
    if [[ "$(git rev-parse HEAD)" != "$before_head" ]]; then
        printf 'Error: original branch was modified by the default (new-branch) run\n'
        errors=$((errors + 1))
    fi

    [[ -n "$new_branch_name" ]] && git branch -D "$new_branch_name" >/dev/null 2>&1

    record_result "$errors" 'it creates new branch by default'
}

test_flag_no_backup() {
    # Compare backup-branch counts before/after, rather than asserting zero,
    # since an earlier test (--current-branch without --no-backup) may have
    # already left a backup branch lying around in the shared test repo.
    local before_head after_head exit_status before_count after_count errors=0

    before_head=$(git rev-parse HEAD)
    before_count=$(git branch --format='%(refname:short)' | grep -c '_backup_')

    ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --name 'Rosalind Franklin' HEAD >/dev/null 2>&1
    exit_status=$?
    after_head=$(git rev-parse HEAD)
    after_count=$(git branch --format='%(refname:short)' | grep -c '_backup_')

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --no-backup run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$after_head" == "$before_head" ]]; then
        printf 'Error: current branch HEAD did not change\n'
        errors=$((errors + 1))
    fi
    if [[ "$after_count" -ne "$before_count" ]]; then
        printf 'Error: --no-backup created a new backup branch (before=%s, after=%s)\n' "$before_count" "$after_count"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --no-backup skips backup branch'
}

test_flag_no_confirm() {
    # Without --no-confirm the script must prompt for confirmation:
    # declining (n) must abort with no changes, accepting (y) must proceed.
    local before after exit_status errors=0

    before=$(git rev-parse HEAD)
    echo 'n' | ./${SCRIPT_NAME} --no-backup HEAD >/dev/null 2>&1
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: declining the confirmation prompt (n) did not abort\n'
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite declining the confirmation prompt\n'
        errors=$((errors + 1))
    fi

    before=$(git rev-parse HEAD)
    echo 'y' | ./${SCRIPT_NAME} --no-backup --current-branch --name 'Alonzo Church' HEAD >/dev/null 2>&1
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: accepting the confirmation prompt (y) did not succeed\n'
        errors=$((errors + 1))
    fi
    if [[ "$after" == "$before" ]]; then
        printf 'Error: accepting the confirmation prompt (y) did not rewrite HEAD\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --no-confirm skips confirmation prompt'
}

test_flag_unknown() {
    local before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(./${SCRIPT_NAME} --no-confirm --no-backup --bogus-flag HEAD 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: unknown flag did not cause failure\n'
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite unknown flag\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'unknown option' <<<"$output"; then
        printf 'Error: expected "Unknown option" message not found\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'unknown flag'
}

# ──────────────────────────────────────────────────────────────────────
# REGRESSION / MATCH TESTS (alphabetical order)
#
# Each test here pins down one specific behavior (usually security- or
# robustness-relevant) so a future change can't silently reintroduce it.

test_match_default_shows_help() {
    # Default behavior: without an explicit commit target or --entire-history,
    # the script shows help instead of silently defaulting to HEAD.
    local before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(./${SCRIPT_NAME} 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: bare invocation (no target) exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: bare invocation (no target) modified HEAD\n'
        errors=$((errors + 1))
    fi
    if ! grep -q 'Usage:' <<<"$output"; then
        printf 'Error: bare invocation (no target) did not show help\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'no commit target will show help by default'
}

test_match_detached_head_current_branch() {
    local original_branch before_head after_head output exit_status errors=0

    original_branch=$(git branch --show-current)
    before_head=$(git rev-parse HEAD)

    git checkout --detach HEAD >/dev/null 2>&1

    output=$(./${SCRIPT_NAME} --no-confirm --no-backup --current-branch HEAD 2>&1)
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

    record_result "$errors" 'running in detached HEAD with flag --current-branch is rejected'
}

test_match_dry_run_without_target_shows_help() {
    # --dry-run alone doesn't count as a target; without an explicit commit or
    # --entire-history it must still fall through to the help text, not
    # silently preview HEAD.
    local before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(PAGER="cat" ./${SCRIPT_NAME} --dry-run 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --dry-run without a target exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: --dry-run without a target modified HEAD\n'
        errors=$((errors + 1))
    fi
    if ! grep -q 'Usage:' <<<"$output"; then
        printf 'Error: --dry-run without a target did not show help\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --dry-run without a target still shows help'
}

test_match_malformed_date() {
    local before after output exit_status errors=0

    before=$(git rev-parse HEAD)
    output=$(./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --date 'not-a-real-date' HEAD 2>&1)
    exit_status=$?
    after=$(git rev-parse HEAD)

    if [[ "$exit_status" -eq 0 ]]; then
        printf 'Error: malformed --date value did not cause failure\n'
        errors=$((errors + 1))
    fi
    if [[ "$before" != "$after" ]]; then
        printf 'Error: repository was modified despite malformed --date value\n'
        errors=$((errors + 1))
    fi
    if ! grep -qi 'error' <<<"$output"; then
        printf 'Error: expected an error message for malformed --date\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'malformed --date value is rejected safely'
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

    ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --entire-history --name 'Merge Tester' >/dev/null 2>&1
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

    record_result "$errors" 'running outside a git repository fails cleanly'
}

test_match_rerun_cache() {
    # git-filter-repo caches metadata under .git/filter-repo/ after a run; a
    # second run against the same repo is a known trigger for an upstream
    # assertion bug unless that cache is cleared first (see anon-git.sh's
    # "CLEAN CACHE" section). Regression test for that workaround.
    local first_exit second_exit new_author errors=0

    ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --name 'First Run' HEAD >/dev/null 2>&1
    first_exit=$?
    ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --name 'Second Run' HEAD >/dev/null 2>&1
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

    record_result "$errors" 'consecutive runs do not hit the filter-repo cache bug'
}

test_match_shell_injection_email() {
    local marker payload commit_email exit_status errors=0

    marker="${TMP_DIR}/injection_marker_email"
    rm -f "$marker"
    payload="evil'\"; touch ${marker}; \`touch ${marker}\`; \$(touch ${marker}) #@example.com"

    ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --email "$payload" HEAD >/dev/null 2>&1
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

    record_result "$errors" 'shell metacharacters in --email are not executed'
}

test_match_shell_injection_name() {
    local marker payload commit_name exit_status errors=0

    marker="${TMP_DIR}/injection_marker_name"
    rm -f "$marker"
    payload="Evil'\"; touch ${marker}; \`touch ${marker}\`; \$(touch ${marker}) #"

    ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --name "$payload" HEAD >/dev/null 2>&1
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

    record_result "$errors" 'shell metacharacters in --name are not executed'
}

main() {
    init_repo
    test_python_callback_syntax
    test_script
    test_script --name 'Grace Hopper'
    test_script --name 'Alan Turing' --email 'alan.turing@example.com'
    test_script --name 'Ada Lovelace' --email 'ada.lovelace@example.com' --date '2020-01-01 00:03:03 +0000'
    test_script --name 'Katherine Johnson' --date '2020-01-01 00:04:04 +0000'
    test_script --email 'margaret.hamilton@example.com'
    test_script --email 'barbara.liskov@example.com' --date '2020-10-31 00:06:06 +0000'
    test_script --date '2020-01-01 00:07:07 +0000'
    test_script --keep-date
    test_script --keep-date --name 'Radia Perlman'
    test_script --keep-date --name 'Hedy Lamarr' --email 'hedy.lamarr@example.com'
    test_script --keep-user
    test_script --keep-user --date '2020-01-01 00:10:10 +0000'
    test_multiple_commits
    test_entire_history
    test_catch_incompatible_flags --date '2020-01-01 00:00:00 +0000' --keep-date
    test_catch_incompatible_flags --date '2020-01-01 00:00:00 +0000' --keep-year
    test_catch_incompatible_flags --keep-user --name 'Nobody'
    test_catch_incompatible_flags --keep-user --email 'nobody@example.com'
    test_catch_incompatible_flags --keep-year --keep-month
    test_catch_incompatible_flags --keep-year --keep-day
    test_catch_incompatible_flags --keep-month --keep-day
    test_catch_incompatible_flags --entire-history HEAD
    test_catch_invalid_commit
    test_catch_uncommitted_changes
    test_combo_dry_run_entire_history
    test_combo_env_var_flag_priority
    test_flag_current_branch_backup
    test_flag_dry_run
    test_flag_env_vars
    test_flag_env_var_entirehistory
    test_flag_env_var_currentbranch
    test_flag_env_var_dryrun
    test_flag_install_local_bin
    test_flag_install_bin_fallback
    test_flag_install_both_dirs
    test_flag_install_path_already_set
    test_flag_install_no_target_dir
    test_flag_install_idempotent
    test_flag_install_hook_creates_hook
    test_flag_install_hook_requires_git_repo
    test_flag_install_hook_preserves_foreign_hook
    test_flag_install_hook_idempotent
    test_flag_install_hook_anonymizes_next_commit
    test_show_help
    test_show_help_inside_dirty_repo
    test_flag_keep_partial --keep-year
    test_flag_keep_partial --keep-month
    test_flag_keep_partial --keep-day
    test_flag_missing_value --date
    test_flag_missing_value --name
    test_flag_missing_value --email
    test_flag_new_branch
    test_flag_no_backup
    test_flag_no_confirm
    test_flag_unknown
    test_match_default_shows_help
    test_match_detached_head_current_branch
    test_match_dry_run_without_target_shows_help
    test_match_malformed_date
    test_match_outside_git_repo
    test_match_rerun_cache
    test_match_shell_injection_email
    test_match_shell_injection_name
    test_match_merge_commit
    printf -- '----------------------------------------\n'
    printf 'Summary: %s/%s tests passed (%s errors)\n' "$TESTS_PASSED" "$((TESTS_PASSED + TESTS_FAILED))" "$TOTAL_ERRORS"
    if [[ "$TESTS_FAILED" -eq 0 ]]; then
        printf 'Result: PASS\n'
    else
        printf 'Result: FAIL (%s test(s) failed)\n' "$TESTS_FAILED"
    fi
}

main
[[ "$TESTS_FAILED" -eq 0 ]]
