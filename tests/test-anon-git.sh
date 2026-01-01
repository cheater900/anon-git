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
  local expected_name expected_email expected_date keep_user keep_date args
  local expected_author random_index commit_hash commit_format original_branch cmd
  local script_exit new_commit_hash OLD_AUTHOR OLD_DATE OLD_COMMITS
  local NEW_AUTHOR NEW_DATE NEW_COMMITS NEW_COMMIT
  local author_matches committer_matches author_date_matches committer_date_matches errors

  CURRENT_TEST_INDEX=$(( CURRENT_TEST_INDEX + 1 ))

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
  random_index=$(( $(od -An -N2 -tu2 </dev/urandom) % (COMMIT_COUNT - 1) ))

  # store old logs (except commit to be modified)
  commit_hash=$(git rev-parse "HEAD~${random_index}")
  commit_format='%H %an <%aE> (%ai) %cn <%cE> (%ci)'
  OLD_AUTHOR=$(git show --format='%an <%ae> %cn <%ce>' "$commit_hash")
  OLD_DATE=$(git show --format='%ai %ci' "$commit_hash")
  OLD_COMMITS=$(git log --format="$commit_format" | grep --invert-match "$commit_hash" | sed 's/^[0-9a-f]\+//')

  # Store current branch because the script by default will create a new one
  original_branch=$(git branch --show-current)

  # Run script
  cmd="./${SCRIPT_NAME} ${args[*]} HEAD~${random_index}"
  printf 'Running %s\n' "$cmd"
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
  committer_date_matches=$(grep --count "^CommitDate:\s\+${expected_date}" <<< "$NEW_COMMIT")

  # check for errors
  errors=0

  # exit status check
  if [[ "$script_exit" -ne 0 ]]; then
    printf 'Error: script exited with status %s\n' "$script_exit"
    errors=$(( errors + 1 ))
  fi

  # author & committer check
  if [[ "$keep_user" != '1' && "$author_matches" -ne 1 ]]; then
    printf 'Error: author name & email not overwritten\n'
    errors=$(( errors + 1 ))
  fi
  if [[ "$keep_user" != '1' && "$committer_matches" -ne 1 ]]; then
    printf 'Error: committer name & email not overwritten\n'
    errors=$(( errors + 1 ))
  fi
  if [[ "$keep_user" == '1' && "$NEW_AUTHOR" != "$OLD_AUTHOR" ]]; then
    printf 'Error: flag --keep-user not respected\n'
    errors=$(( errors + 1 ))
  fi

  # date check
  if [[ "$keep_date" != '1' && "$author_date_matches" -ne 1 ]]; then
    printf 'Error: author date not overwritten\n'
    errors=$(( errors + 1 ))
  fi
  if [[ "$keep_date" != '1' && "$committer_date_matches" -ne 1 ]]; then
    printf 'Error: committer date not overwritten\n'
    errors=$(( errors + 1 ))
  fi
  if [[ "$keep_date" == '1' && "$NEW_DATE" != "$OLD_DATE" ]]; then
    printf 'Error: flag --keep-date not respected\n'
    errors=$(( errors + 1 ))
  fi

  # other commits check
  if [[ "$OLD_COMMITS" != "$NEW_COMMITS" ]]; then
    printf 'Error: other commits were affected!\n'
    errors=$(( errors + 1 ))
  fi

  # feedback
  if [[ "$errors" -eq 0 ]]; then
    TESTS_PASSED=$(( TESTS_PASSED + 1 ))
    printf 'Test %s passed.\n\n' "$CURRENT_TEST_INDEX"
  else
    TESTS_FAILED=$(( TESTS_FAILED + 1 ))
    printf 'Test %s failed with %s errors.\n\n' "$CURRENT_TEST_INDEX" "$errors"
  fi
  TOTAL_ERRORS=$(( TOTAL_ERRORS + errors ))

  # switch to original branch
  git switch "$original_branch" >/dev/null 2>&1
}

record_result() {
  # @param $1  number of errors found by the caller
  # @param $2  short label describing the test, for the summary line
  local errors="$1" label="$2"
  CURRENT_TEST_INDEX=$(( CURRENT_TEST_INDEX + 1 ))
  if [[ "$errors" -eq 0 ]]; then
    TESTS_PASSED=$(( TESTS_PASSED + 1 ))
    printf 'Test %s (%s) passed.\n\n' "$CURRENT_TEST_INDEX" "$label"
  else
    TESTS_FAILED=$(( TESTS_FAILED + 1 ))
    printf 'Test %s (%s) failed with %s errors.\n\n' "$CURRENT_TEST_INDEX" "$label" "$errors"
  fi
  TOTAL_ERRORS=$(( TOTAL_ERRORS + errors ))
}

# ──────────────────────────────────────────────────────────────────────
# LINT / STATIC CHECKS
#
# Run first, before init_repo, since they don't need a repo at all — just
# the script file already copied into $TMP_DIR at the top of this file.

test_lint_syntax() {
  local output exit_status errors=0

  output=$(bash -n "./${SCRIPT_NAME}" 2>&1)
  exit_status=$?

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: bash -n reported syntax errors:\n%s\n' "$output"; errors=$(( errors + 1 )); }

  record_result "$errors" 'bash -n syntax check'
}

test_lint_shellcheck() {
  local output exit_status errors=0

  if ! command -v shellcheck >/dev/null 2>&1; then
    printf 'shellcheck not installed, skipping lint test.\n\n'
    return
  fi

  output=$(shellcheck "./${SCRIPT_NAME}" 2>&1)
  exit_status=$?

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: shellcheck reported issues:\n%s\n' "$output"; errors=$(( errors + 1 )); }

  record_result "$errors" 'shellcheck'
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

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: multi-commit run exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$a1" == 'Donald Knuth <donald.knuth@example.com>' ]] || { printf 'Error: first target commit not anonymized\n'; errors=$(( errors + 1 )); }
  [[ "$a2" == 'Donald Knuth <donald.knuth@example.com>' ]] || { printf 'Error: second target commit not anonymized\n'; errors=$(( errors + 1 )); }

  record_result "$errors" 'multiple commits in one run'
}

test_entire_history() {
  local exit_status mismatches errors=0

  ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --entire-history >/dev/null 2>&1
  exit_status=$?

  mismatches=$(git log --format='%an <%ae>' | grep --invert-match --count "^${DEFAULT_NAME} <${DEFAULT_EMAIL}>\$")

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: --entire-history exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$mismatches" -eq 0 ]] || { printf 'Error: --entire-history left %s commit(s) with a non-default author\n' "$mismatches"; errors=$(( errors + 1 )); }

  record_result "$errors" '--entire-history'
}

# ──────────────────────────────────────────────────────────────────────
# UNIT TESTS (alphabetical order)

test_catch_incompatible_flags() {
  # @param $@  the incompatible combination of flags/args to reject
  local before after exit_status errors=0

  before=$(git rev-parse HEAD)
  ./${SCRIPT_NAME} --no-confirm --no-backup "$@" >/dev/null 2>&1
  exit_status=$?
  after=$(git rev-parse HEAD)

  [[ "$exit_status" -ne 0 ]] || { printf 'Error: flags "%s" did not fail as expected\n' "$*"; errors=$(( errors + 1 )); }
  [[ "$before" == "$after" ]] || { printf 'Error: repository was modified despite incompatible flags "%s"\n' "$*"; errors=$(( errors + 1 )); }

  record_result "$errors" "incompatible: $*"
}

test_catch_invalid_commit() {
  local before after output exit_status errors=0

  before=$(git rev-parse HEAD)
  output=$(./${SCRIPT_NAME} --no-confirm --no-backup deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 2>&1)
  exit_status=$?
  after=$(git rev-parse HEAD)

  [[ "$exit_status" -ne 0 ]] || { printf 'Error: invalid commit ref did not cause failure\n'; errors=$(( errors + 1 )); }
  [[ "$before" == "$after" ]] || { printf 'Error: repository was modified despite invalid commit ref\n'; errors=$(( errors + 1 )); }
  grep -qi 'does not exist' <<<"$output" || { printf 'Error: expected "does not exist" message not found\n'; errors=$(( errors + 1 )); }

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

  [[ "$exit_status" -ne 0 ]] || { printf 'Error: script proceeded despite uncommitted changes\n'; errors=$(( errors + 1 )); }
  [[ "$before" == "$after" ]] || { printf 'Error: HEAD changed despite uncommitted-changes guard\n'; errors=$(( errors + 1 )); }

  record_result "$errors" 'uncommitted changes guard'
}

# ──────────────────────────────────────────────────────────────────────
# COMBINATION TESTS (alphabetical order)

test_combo_dry_run_entire_history() {
  local before after output exit_status preview_count errors=0

  before=$(git rev-parse HEAD)
  output=$(PAGER=cat ./${SCRIPT_NAME} --dry-run --entire-history 2>&1)
  exit_status=$?
  after=$(git rev-parse HEAD)
  preview_count=$(grep -c '^Commit:' <<<"$output")

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: --dry-run --entire-history exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$before" == "$after" ]] || { printf 'Error: --dry-run --entire-history modified HEAD\n'; errors=$(( errors + 1 )); }
  [[ "$preview_count" -eq "$COMMIT_COUNT" ]] || { printf 'Error: expected %s commits previewed, got %s\n' "$COMMIT_COUNT" "$preview_count"; errors=$(( errors + 1 )); }

  record_result "$errors" '--dry-run + --entire-history'
}

test_combo_dry_run_keep_user() {
  local before after output exit_status errors=0

  before=$(git rev-parse HEAD)
  output=$(PAGER=cat ./${SCRIPT_NAME} --dry-run --keep-user HEAD 2>&1)
  exit_status=$?
  after=$(git rev-parse HEAD)

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: --dry-run --keep-user exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$before" == "$after" ]] || { printf 'Error: --dry-run --keep-user modified HEAD\n'; errors=$(( errors + 1 )); }
  grep -q 'AuthorDate:' <<<"$output" || { printf 'Error: --dry-run --keep-user output missing expected preview content\n'; errors=$(( errors + 1 )); }

  record_result "$errors" '--dry-run + --keep-user'
}

test_combo_entire_history_keep_date() {
  local sample_hash before_date new_hash after_date exit_status mismatches errors=0

  sample_hash=$(git rev-parse HEAD~5)
  before_date=$(git show -s --format='%ad' --date=iso "$sample_hash")

  ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --entire-history --keep-date --name 'Alonzo Church' >/dev/null 2>&1
  exit_status=$?

  new_hash=$(git rev-parse HEAD~5)
  after_date=$(git show -s --format='%ad' --date=iso "$new_hash")
  mismatches=$(git log --format='%an' | grep --invert-match --count '^Alonzo Church$')

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: --entire-history --keep-date --name exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$before_date" == "$after_date" ]] || { printf 'Error: --keep-date not respected during --entire-history\n'; errors=$(( errors + 1 )); }
  [[ "$mismatches" -eq 0 ]] || { printf 'Error: --entire-history left %s commit(s) with the wrong author despite --name\n' "$mismatches"; errors=$(( errors + 1 )); }

  record_result "$errors" '--entire-history + --keep-date + --name'
}

test_combo_env_var_flag_priority() {
  # Command-line flags must win over ANON_GIT_* environment variables
  # (documented priority: flags > env vars > hardcoded defaults).
  local exit_status commit_info errors=0
  local env_name='Ignored Env Name' flag_name='Flag Wins'

  ANON_GIT_NAME="$env_name" ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --name "$flag_name" HEAD >/dev/null 2>&1
  exit_status=$?

  commit_info=$(git show --pretty=fuller --no-patch HEAD)

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: --name + ANON_GIT_NAME run exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  grep -q "^Author:\s\+${flag_name} <" <<<"$commit_info" || { printf 'Error: --name flag did not take priority over ANON_GIT_NAME\n'; errors=$(( errors + 1 )); }
  grep -qF "$env_name" <<<"$commit_info" && { printf 'Error: ANON_GIT_NAME leaked through despite --name flag\n'; errors=$(( errors + 1 )); }

  record_result "$errors" '--name flag overrides ANON_GIT_NAME'
}

test_combo_keep_year_keep_user() {
  local random_index commit_hash old_year old_author
  local new_commit_hash new_year new_author exit_status errors=0

  random_index=$(( $(od -An -N2 -tu2 </dev/urandom) % (COMMIT_COUNT - 1) ))
  commit_hash=$(git rev-parse "HEAD~${random_index}")
  old_year=$(git show -s --date=format:'%Y' --format='%ad' "$commit_hash")
  old_author=$(git show -s --format='%an <%ae>' "$commit_hash")

  ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --keep-year --keep-user "HEAD~${random_index}" >/dev/null 2>&1
  exit_status=$?

  new_commit_hash=$(git rev-parse "HEAD~${random_index}")
  new_year=$(git show -s --date=format:'%Y' --format='%ad' "$new_commit_hash")
  new_author=$(git show -s --format='%an <%ae>' "$new_commit_hash")

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: --keep-year --keep-user exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$new_year" == "$old_year" ]] || { printf 'Error: --keep-year not respected\n'; errors=$(( errors + 1 )); }
  [[ "$new_author" == "$old_author" ]] || { printf 'Error: --keep-user not respected\n'; errors=$(( errors + 1 )); }

  record_result "$errors" '--keep-year + --keep-user'
}

test_combo_multiple_commits_keep_date() {
  local h1 h2 d1_before d2_before exit_status a1 a2 d1_after d2_after errors=0

  h1=$(git rev-parse HEAD~1)
  h2=$(git rev-parse HEAD~4)
  d1_before=$(git show -s --format='%ad' --date=iso "$h1")
  d2_before=$(git show -s --format='%ad' --date=iso "$h2")

  ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --keep-date --name 'Simone de Beauvoir' "$h1" "$h2" >/dev/null 2>&1
  exit_status=$?

  a1=$(git show -s --format='%an' HEAD~1)
  a2=$(git show -s --format='%an' HEAD~4)
  d1_after=$(git show -s --format='%ad' --date=iso HEAD~1)
  d2_after=$(git show -s --format='%ad' --date=iso HEAD~4)

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: multi-commit --keep-date run exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$a1" == 'Simone de Beauvoir' ]] || { printf 'Error: first target commit not renamed\n'; errors=$(( errors + 1 )); }
  [[ "$a2" == 'Simone de Beauvoir' ]] || { printf 'Error: second target commit not renamed\n'; errors=$(( errors + 1 )); }
  [[ "$d1_after" == "$d1_before" ]] || { printf 'Error: --keep-date not respected for first target commit\n'; errors=$(( errors + 1 )); }
  [[ "$d2_after" == "$d2_before" ]] || { printf 'Error: --keep-date not respected for second target commit\n'; errors=$(( errors + 1 )); }

  record_result "$errors" 'multiple commits + --keep-date + --name'
}

test_flag_current_branch_backup() {
  local before_head after_head exit_status backup_branch errors=0

  before_head=$(git rev-parse HEAD)

  ./${SCRIPT_NAME} --no-confirm --current-branch --name 'Edsger Dijkstra' HEAD >/dev/null 2>&1
  exit_status=$?
  after_head=$(git rev-parse HEAD)

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: --current-branch run exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$after_head" != "$before_head" ]] || { printf 'Error: current branch HEAD did not change\n'; errors=$(( errors + 1 )); }

  backup_branch=$(git branch --format='%(refname:short)' | grep '_backup_' | tail -1)
  if [[ -z "$backup_branch" ]]; then
    printf 'Error: no backup branch was created\n'
    errors=$(( errors + 1 ))
  elif [[ "$(git rev-parse "$backup_branch")" != "$before_head" ]]; then
    printf 'Error: backup branch does not point at pre-rewrite HEAD\n'
    errors=$(( errors + 1 ))
  fi

  record_result "$errors" '--current-branch creates backup'
}

test_flag_dry_run() {
  local before after output exit_status errors=0

  before=$(git rev-parse HEAD)
  output=$(PAGER=cat ./${SCRIPT_NAME} --dry-run HEAD 2>&1)
  exit_status=$?
  after=$(git rev-parse HEAD)

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: --dry-run exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$before" == "$after" ]] || { printf 'Error: --dry-run modified HEAD\n'; errors=$(( errors + 1 )); }
  grep -q 'AuthorDate:' <<<"$output" || { printf 'Error: --dry-run output missing expected preview content\n'; errors=$(( errors + 1 )); }

  record_result "$errors" 'dry-run'
}

test_flag_env_vars() {
  # ANON_GIT_NAME/EMAIL/DATE must work as priority-2 config (README:
  # "Environment variables"), same as their --name/--email/--date flags.
  local random_index commit_hash new_commit_hash exit_status commit_info errors=0
  local env_name='Grace Murray' env_email='grace.murray@example.com' env_date='2019-05-05 00:00:00 +0000'

  random_index=$(( $(od -An -N2 -tu2 </dev/urandom) % (COMMIT_COUNT - 1) ))
  commit_hash=$(git rev-parse "HEAD~${random_index}")

  ANON_GIT_NAME="$env_name" ANON_GIT_EMAIL="$env_email" ANON_GIT_DATE="$env_date" \
    ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch "HEAD~${random_index}" >/dev/null 2>&1
  exit_status=$?

  new_commit_hash=$(git rev-parse "HEAD~${random_index}")
  commit_info=$(git show --pretty=fuller --no-patch --date=iso "$new_commit_hash")

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: ANON_GIT_* env-var run exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  grep -q "^Author:\s\+${env_name} <${env_email}>" <<<"$commit_info" || { printf 'Error: ANON_GIT_NAME/ANON_GIT_EMAIL not respected\n'; errors=$(( errors + 1 )); }
  grep -q "^AuthorDate:\s\+${env_date}" <<<"$commit_info" || { printf 'Error: ANON_GIT_DATE not respected\n'; errors=$(( errors + 1 )); }

  record_result "$errors" 'ANON_GIT_* environment variables'
}

test_flag_help() {
  local output exit_status errors=0

  output=$(./${SCRIPT_NAME} --help 2>&1)
  exit_status=$?

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: --help exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  grep -q 'Usage:' <<<"$output" || { printf 'Error: --help output missing usage text\n'; errors=$(( errors + 1 )); }

  record_result "$errors" '--help'
}

test_flag_keep_partial() {
  # @param $1  flag under test: --keep-year | --keep-month | --keep-day
  local flag="$1" random_index commit_hash old_year old_month old_day
  local new_commit_hash new_year new_month new_day exit_status errors=0

  random_index=$(( $(od -An -N2 -tu2 </dev/urandom) % (COMMIT_COUNT - 1) ))
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

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: %s exited with status %s\n' "$flag" "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$new_year" == "$old_year" ]] || { printf 'Error: %s did not preserve year\n' "$flag"; errors=$(( errors + 1 )); }
  if [[ "$flag" == '--keep-month' || "$flag" == '--keep-day' ]]; then
    [[ "$new_month" == "$old_month" ]] || { printf 'Error: %s did not preserve month\n' "$flag"; errors=$(( errors + 1 )); }
  fi
  if [[ "$flag" == '--keep-day' ]]; then
    [[ "$new_day" == "$old_day" ]] || { printf 'Error: %s did not preserve day\n' "$flag"; errors=$(( errors + 1 )); }
  fi

  record_result "$errors" "$flag"
}

test_flag_missing_value() {
  # @param $1  flag under test: --date | --name | --email
  local flag="$1" before after output exit_status errors=0

  before=$(git rev-parse HEAD)
  output=$(./${SCRIPT_NAME} --no-confirm --no-backup --current-branch "$flag" 2>&1)
  exit_status=$?
  after=$(git rev-parse HEAD)

  [[ "$exit_status" -ne 0 ]] || { printf 'Error: %s with no value did not fail as expected\n' "$flag"; errors=$(( errors + 1 )); }
  [[ "$before" == "$after" ]] || { printf 'Error: repository was modified despite %s missing its value\n' "$flag"; errors=$(( errors + 1 )); }
  grep -qi 'requires a value' <<<"$output" || { printf 'Error: expected "requires a value" message not found\n'; errors=$(( errors + 1 )); }

  record_result "$errors" "missing value: $flag"
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

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: default run exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }

  new_branch_name=$(git branch --format='%(refname:short)' | grep "^${original_branch}_anonymized_" | tail -1)
  [[ -n "$new_branch_name" ]] || { printf 'Error: expected a new "%s_anonymized_*" branch to be created\n' "$original_branch"; errors=$(( errors + 1 )); }

  git switch "$original_branch" >/dev/null 2>&1
  [[ "$(git rev-parse HEAD)" == "$before_head" ]] || { printf 'Error: original branch was modified by the default (new-branch) run\n'; errors=$(( errors + 1 )); }

  [[ -n "$new_branch_name" ]] && git branch -D "$new_branch_name" >/dev/null 2>&1

  record_result "$errors" 'default run creates new branch'
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

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: --no-backup run exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$after_head" != "$before_head" ]] || { printf 'Error: current branch HEAD did not change\n'; errors=$(( errors + 1 )); }
  [[ "$after_count" -eq "$before_count" ]] || { printf 'Error: --no-backup created a new backup branch (before=%s, after=%s)\n' "$before_count" "$after_count"; errors=$(( errors + 1 )); }

  record_result "$errors" '--no-backup skips backup branch'
}

test_flag_no_confirm() {
  # Without --no-confirm the script must prompt for confirmation:
  # declining (n) must abort with no changes, accepting (y) must proceed.
  local before after exit_status errors=0

  before=$(git rev-parse HEAD)
  echo 'n' | ./${SCRIPT_NAME} --no-backup HEAD >/dev/null 2>&1
  exit_status=$?
  after=$(git rev-parse HEAD)

  [[ "$exit_status" -ne 0 ]] || { printf 'Error: declining the confirmation prompt (n) did not abort\n'; errors=$(( errors + 1 )); }
  [[ "$before" == "$after" ]] || { printf 'Error: repository was modified despite declining the confirmation prompt\n'; errors=$(( errors + 1 )); }

  before=$(git rev-parse HEAD)
  echo 'y' | ./${SCRIPT_NAME} --no-backup --current-branch --name 'Alonzo Church' HEAD >/dev/null 2>&1
  exit_status=$?
  after=$(git rev-parse HEAD)

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: accepting the confirmation prompt (y) did not succeed\n'; errors=$(( errors + 1 )); }
  [[ "$after" != "$before" ]] || { printf 'Error: accepting the confirmation prompt (y) did not rewrite HEAD\n'; errors=$(( errors + 1 )); }

  record_result "$errors" 'confirmation prompt (no --no-confirm)'
}

test_flag_unknown() {
  local before after output exit_status errors=0

  before=$(git rev-parse HEAD)
  output=$(./${SCRIPT_NAME} --no-confirm --no-backup --bogus-flag HEAD 2>&1)
  exit_status=$?
  after=$(git rev-parse HEAD)

  [[ "$exit_status" -ne 0 ]] || { printf 'Error: unknown flag did not cause failure\n'; errors=$(( errors + 1 )); }
  [[ "$before" == "$after" ]] || { printf 'Error: repository was modified despite unknown flag\n'; errors=$(( errors + 1 )); }
  grep -qi 'unknown option' <<<"$output" || { printf 'Error: expected "Unknown option" message not found\n'; errors=$(( errors + 1 )); }

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

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: bare invocation (no target) exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$before" == "$after" ]] || { printf 'Error: bare invocation (no target) modified HEAD\n'; errors=$(( errors + 1 )); }
  grep -q 'Usage:' <<<"$output" || { printf 'Error: bare invocation (no target) did not show help\n'; errors=$(( errors + 1 )); }

  record_result "$errors" 'no target shows help by default'
}

test_match_detached_head_current_branch() {
  local original_branch before_head after_head output exit_status errors=0

  original_branch=$(git branch --show-current)
  before_head=$(git rev-parse HEAD)

  git checkout --detach HEAD >/dev/null 2>&1

  output=$(./${SCRIPT_NAME} --no-confirm --no-backup --current-branch HEAD 2>&1)
  exit_status=$?
  after_head=$(git rev-parse HEAD)

  [[ "$exit_status" -ne 0 ]] || { printf 'Error: --current-branch on a detached HEAD did not fail\n'; errors=$(( errors + 1 )); }
  [[ "$before_head" == "$after_head" ]] || { printf 'Error: HEAD changed despite detached-HEAD guard\n'; errors=$(( errors + 1 )); }
  grep -qi 'detached' <<<"$output" || { printf 'Error: expected "detached" message not found\n'; errors=$(( errors + 1 )); }

  git checkout "$original_branch" >/dev/null 2>&1

  record_result "$errors" 'detached HEAD + --current-branch is rejected'
}

test_match_dry_run_without_target_shows_help() {
  # --dry-run alone doesn't count as a target; without an explicit commit or
  # --entire-history it must still fall through to the help text, not
  # silently preview HEAD.
  local before after output exit_status errors=0

  before=$(git rev-parse HEAD)
  output=$(PAGER=cat ./${SCRIPT_NAME} --dry-run 2>&1)
  exit_status=$?
  after=$(git rev-parse HEAD)

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: --dry-run without a target exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$before" == "$after" ]] || { printf 'Error: --dry-run without a target modified HEAD\n'; errors=$(( errors + 1 )); }
  grep -q 'Usage:' <<<"$output" || { printf 'Error: --dry-run without a target did not show help\n'; errors=$(( errors + 1 )); }

  record_result "$errors" '--dry-run without a target still shows help'
}

test_match_malformed_date() {
  local before after output exit_status errors=0

  before=$(git rev-parse HEAD)
  output=$(./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --date 'not-a-real-date' HEAD 2>&1)
  exit_status=$?
  after=$(git rev-parse HEAD)

  [[ "$exit_status" -ne 0 ]] || { printf 'Error: malformed --date value did not cause failure\n'; errors=$(( errors + 1 )); }
  [[ "$before" == "$after" ]] || { printf 'Error: repository was modified despite malformed --date value\n'; errors=$(( errors + 1 )); }
  grep -qi 'error' <<<"$output" || { printf 'Error: expected an error message for malformed --date\n'; errors=$(( errors + 1 )); }

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

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: --entire-history on history with a merge commit exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$mismatches" -eq 0 ]] || { printf 'Error: --entire-history left %s commit(s) unrewritten around the merge commit\n' "$mismatches"; errors=$(( errors + 1 )); }

  git branch -D "$feature_branch" >/dev/null 2>&1

  record_result "$errors" '--entire-history handles merge commits'
}

test_match_outside_git_repo() {
  local no_repo_dir output exit_status errors=0

  no_repo_dir=$(mktemp -d /tmp/anon_git_test_norepo.XXXXXX)
  cp "$SCRIPT" "$no_repo_dir/"
  chmod +x "${no_repo_dir}/${SCRIPT_NAME}"

  output=$(cd "$no_repo_dir" && "./${SCRIPT_NAME}" --no-confirm 2>&1)
  exit_status=$?

  [[ "$exit_status" -ne 0 ]] || { printf 'Error: running outside a git repository did not fail\n'; errors=$(( errors + 1 )); }
  grep -qi 'git repository' <<<"$output" || { printf 'Error: expected "git repository" message not found\n'; errors=$(( errors + 1 )); }

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

  [[ "$first_exit" -eq 0 ]] || { printf 'Error: first run exited with status %s\n' "$first_exit"; errors=$(( errors + 1 )); }
  [[ "$second_exit" -eq 0 ]] || { printf 'Error: second (back-to-back) run exited with status %s\n' "$second_exit"; errors=$(( errors + 1 )); }
  [[ "$new_author" == 'Second Run' ]] || { printf 'Error: second run did not take effect (got author "%s")\n' "$new_author"; errors=$(( errors + 1 )); }

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

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: run with shell-metacharacter --email exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$commit_email" == "$payload" ]] || { printf 'Error: email was not stored literally (got "%s")\n' "$commit_email"; errors=$(( errors + 1 )); }
  [[ ! -e "$marker" ]] || { printf 'Error: shell metacharacters in --email were executed (marker file created)\n'; errors=$(( errors + 1 )); }

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

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: run with shell-metacharacter --name exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$commit_name" == "$payload" ]] || { printf 'Error: author name was not stored literally (got "%s")\n' "$commit_name"; errors=$(( errors + 1 )); }
  [[ ! -e "$marker" ]] || { printf 'Error: shell metacharacters in --name were executed (marker file created)\n'; errors=$(( errors + 1 )); }

  record_result "$errors" 'shell metacharacters in --name are not executed'
}

main() {
  test_lint_syntax
  test_lint_shellcheck
  init_repo
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
  test_combo_dry_run_keep_user
  test_combo_entire_history_keep_date
  test_combo_env_var_flag_priority
  test_combo_keep_year_keep_user
  test_combo_multiple_commits_keep_date
  test_flag_current_branch_backup
  test_flag_dry_run
  test_flag_env_vars
  test_flag_help
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
  printf 'Summary:\n%s tests passed\n%s tests failed\n%s total errors\n' "$TESTS_PASSED" "$TESTS_FAILED" "$TOTAL_ERRORS"
}

main
[[ "$TESTS_FAILED" -eq 0 ]]
