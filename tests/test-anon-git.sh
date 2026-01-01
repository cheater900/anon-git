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
  git config --local user.name "Test User"
  git config --local user.email "test@example.com"
  for i in $(seq 1 "$COMMIT_COUNT"); do
    filename="file_${i}.txt"
    echo "This is file $i" >"$filename"
    git add "$filename" >/dev/null
    git commit -m "Add file $filename" >/dev/null
  done
}

test_script() {
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
  commiter_matches=$(grep --count "^Commit:\s\+${expected_author}" <<<"$NEW_COMMIT")
  author_date_matches=$(grep --count "^AuthorDate:\s\+${expected_date}" <<<"$NEW_COMMIT")
  commiter_date_matches=$(grep --count "^CommitDate:\s\+${expected_date}" <<< "$NEW_COMMIT")

  # check for erros
  errors=0

  # exit status check
  if [[ "$script_exit" -ne 0 ]]; then
    printf 'Error: script exited with status %s\n' "$script_exit"
    errors=$(( errors + 1 ))
  fi

  # author & commiter check
  if [[ "$keep_user" != '1' && "$author_matches" -ne 1 ]]; then
    printf 'Error: author name & email not overwrriten\n'
    errors=$(( errors + 1 ))
  fi
  if [[ "$keep_user" != '1' && "$commiter_matches" -ne 1 ]]; then
    printf 'Error: commiter name & email not overwrriten\n'
    errors=$(( errors + 1 ))
  fi
  if [[ "$keep_user" == '1' && "$NEW_AUTHOR" != "$OLD_AUTHOR" ]]; then
    printf 'Error: flag --keep-user not respected\n'
    errors=$(( errors + 1 ))
  fi

  # date check
  if [[ "$keep_date" != '1' && "$author_date_matches" -ne 1 ]]; then
    printf 'Error: author date not overwrriten\n'
    errors=$(( errors + 1 ))
  fi
  if [[ "$keep_date" != '1' && "$commiter_date_matches" -ne 1 ]]; then
    printf 'Error: commiter date not overwrriten\n'
    errors=$(( errors + 1 ))
  fi
  if [[ "$keep_date" == '1' && "$NEW_DATE" != "$OLD_DATE" ]]; then
    printf 'Error: flag --keep-date not respected\n'
    errors=$(( errors + 1 ))
  fi

  # other commmits check
  if [[ "$OLD_COMMITS" != "$NEW_COMMITS" ]]; then
    printf 'Error: other commits were affected!'
    errors=$(( errors + 1))
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
  git switch "$original_branch"
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
# INTEGRATION TESTS

test_multiple_commits() {
  local h1 h2 exit_status a1 a2 errors=0

  h1=$(git rev-parse HEAD~1)
  h2=$(git rev-parse HEAD~3)

  ./${SCRIPT_NAME} --no-confirm --no-backup --current-branch --name 'Multi Test' --email 'multi@example.com' "$h1" "$h2" >/dev/null 2>&1
  exit_status=$?

  a1=$(git show -s --format='%an <%ae>' HEAD~1)
  a2=$(git show -s --format='%an <%ae>' HEAD~3)

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: multi-commit run exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$a1" == 'Multi Test <multi@example.com>' ]] || { printf 'Error: first target commit not anonymized\n'; errors=$(( errors + 1 )); }
  [[ "$a2" == 'Multi Test <multi@example.com>' ]] || { printf 'Error: second target commit not anonymized\n'; errors=$(( errors + 1 )); }

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
  local before after exit_status errors=0

  before=$(git rev-parse HEAD)
  ./${SCRIPT_NAME} --no-confirm --no-backup --date '2020-01-01 00:00:00 +0000' --keep-date >/dev/null 2>&1
  exit_status=$?
  after=$(git rev-parse HEAD)

  [[ "$exit_status" -ne 0 ]] || { printf 'Error: --date and --keep-date together did not fail\n'; errors=$(( errors + 1 )); }
  [[ "$before" == "$after" ]] || { printf 'Error: repository was modified despite incompatible flags\n'; errors=$(( errors + 1 )); }

  record_result "$errors" 'incompatible flags rejected'
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

test_flag_current_branch_backup() {
  local before_head after_head exit_status backup_branch errors=0

  before_head=$(git rev-parse HEAD)

  ./${SCRIPT_NAME} --no-confirm --current-branch --name 'Backup Test' HEAD >/dev/null 2>&1
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
  output=$(PAGER=cat ./${SCRIPT_NAME} --dry-run 2>&1)
  exit_status=$?
  after=$(git rev-parse HEAD)

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: --dry-run exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }
  [[ "$before" == "$after" ]] || { printf 'Error: --dry-run modified HEAD\n'; errors=$(( errors + 1 )); }
  grep -q 'AuthorDate:' <<<"$output" || { printf 'Error: --dry-run output missing expected preview content\n'; errors=$(( errors + 1 )); }

  record_result "$errors" 'dry-run'
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

test_flag_new_branch() {
  # Exercises the default (no --current-branch) code path: a fresh
  # "<branch>_anonymized_<timestamp>" branch must be created and the
  # original branch/HEAD must be left untouched.
  local original_branch before_head exit_status new_branch_name errors=0

  original_branch=$(git branch --show-current)
  before_head=$(git rev-parse HEAD)

  ./${SCRIPT_NAME} --no-confirm --name 'New Branch Test' HEAD >/dev/null 2>&1
  exit_status=$?

  [[ "$exit_status" -eq 0 ]] || { printf 'Error: default run exited with status %s\n' "$exit_status"; errors=$(( errors + 1 )); }

  new_branch_name=$(git branch --format='%(refname:short)' | grep "^${original_branch}_anonymized_" | tail -1)
  [[ -n "$new_branch_name" ]] || { printf 'Error: expected a new "%s_anonymized_*" branch to be created\n' "$original_branch"; errors=$(( errors + 1 )); }

  git switch "$original_branch" >/dev/null 2>&1
  [[ "$(git rev-parse HEAD)" == "$before_head" ]] || { printf 'Error: original branch was modified by the default (new-branch) run\n'; errors=$(( errors + 1 )); }

  [[ -n "$new_branch_name" ]] && git branch -D "$new_branch_name" >/dev/null 2>&1

  record_result "$errors" 'default run creates new branch'
}

cleanup() {
  cd - >/dev/null || exit 0
  rm -rf "$TMP_DIR"
}

main() {
  init_repo
  test_script
  test_script --name 'Test 1'
  test_script --name 'Test 2' --email 'test2@example.com'
  test_script --name 'Test 3' --email 'test3@example.com' --date '2020-01-01 00:03:03 +0000'
  test_script --name 'Test 4' --date '2020-01-01 00:04:04 +0000'
  test_script --email 'test5@example.com'
  test_script --email 'test6@example.com' --date '2020-10-31 00:06:06 +0000'
  test_script --date '2020-01-01 00:07:07 +0000'
  test_script --keep-date
  test_script --keep-date --name 'Test 8'
  test_script --keep-date --name 'Test 9' --email 'test9@example.com'
  test_script --keep-user
  test_script --keep-user --date '2020-01-01 00:10:10 +0000'
  test_multiple_commits
  test_entire_history
  test_catch_incompatible_flags
  test_catch_invalid_commit
  test_catch_uncommitted_changes
  test_flag_current_branch_backup
  test_flag_dry_run
  test_flag_help
  test_flag_keep_partial --keep-year
  test_flag_keep_partial --keep-month
  test_flag_keep_partial --keep-day
  test_flag_new_branch
  printf 'Summary:\n%s tests passed\n%s tests failed\n%s total errors\n' "$TESTS_PASSED" "$TESTS_FAILED" "$TOTAL_ERRORS"
  cleanup
}

main
