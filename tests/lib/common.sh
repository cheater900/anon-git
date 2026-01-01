#!/usr/bin/env bash

# Sourced by test_anon_git.sh — not meant to be run directly.
# Shared setup, globals, and helper functions used across cases/.

SCRIPT_DIR=$(realpath "$(dirname "$0")/..")
SCRIPT_NAME=anon-git.sh
SCRIPT=${SCRIPT_DIR}/${SCRIPT_NAME}

TMP_DIR=$(mktemp -d /tmp/anon_git_test.XXXXXX)
cd "$TMP_DIR" || exit 1
cp "$SCRIPT" .
chmod +x "./${SCRIPT_NAME}"

cleanup() {
    cd - >/dev/null 2>&1 || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

COMMIT_COUNT=20
CURRENT_TEST_INDEX=0
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_ERRORS=0

DEFAULT_DATE=$(grep '^DEFAULT_DATE=' "$SCRIPT" | sed -e "s/DEFAULT_DATE='//" -e "s/'\$//")
DEFAULT_NAME=$(grep '^DEFAULT_NAME=' "$SCRIPT" | sed -e "s/DEFAULT_NAME='//" -e "s/'\$//")
DEFAULT_EMAIL=$(grep '^DEFAULT_EMAIL=' "$SCRIPT" | sed -e "s/DEFAULT_EMAIL='//" -e "s/'\$//")
DEFAULT_KEEPUSER=$(sed -n "s/^ *DEFAULT_KEEPUSER='\(.*\)'$/\1/p" "$SCRIPT")
DEFAULT_KEEPDATE=$(sed -n "s/^ *DEFAULT_KEEPDATE='\(.*\)'$/\1/p" "$SCRIPT")

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
    # $@: flags to pass through (--name, --email, --date, --keep-user, --keep-date)
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

    random_index=$(($(od -An -N2 -tu2 </dev/urandom) % (COMMIT_COUNT - 1)))

    # Logs of every other commit, to verify only the target one changes.
    commit_hash=$(git rev-parse "HEAD~${random_index}")
    commit_format='%H %an <%aE> (%ai) %cn <%cE> (%ci)'
    OLD_AUTHOR=$(git show --format='%an <%ae> %cn <%ce>' "$commit_hash")
    OLD_DATE=$(git show --format='%ai %ci' "$commit_hash")
    OLD_COMMITS=$(git log --format="$commit_format" | grep --invert-match "$commit_hash" | sed 's/^[0-9a-f]\+//')

    # Saved because the script defaults to creating a new branch.
    original_branch=$(git branch --show-current)

    ./"${SCRIPT_NAME}" "${args[@]}" "HEAD~${random_index}" >/dev/null 2>&1
    script_exit=$?

    new_commit_hash=$(git rev-parse "HEAD~${random_index}")

    NEW_AUTHOR=$(git show --format='%an <%ae> %cn <%ce>' "$new_commit_hash")
    NEW_DATE=$(git show --format='%ai %ci' "$new_commit_hash")
    NEW_COMMITS=$(git log --format="$commit_format" | grep --invert-match "$new_commit_hash" | sed 's/^[0-9a-f]\+//')
    NEW_COMMIT=$(git show --pretty=fuller --no-patch --date=iso "$new_commit_hash")

    # Compare against expected values.
    author_matches=$(grep --count "^Author:\s\+${expected_author}" <<<"$NEW_COMMIT")
    committer_matches=$(grep --count "^Commit:\s\+${expected_author}" <<<"$NEW_COMMIT")
    author_date_matches=$(grep --count "^AuthorDate:\s\+${expected_date}" <<<"$NEW_COMMIT")
    committer_date_matches=$(grep --count "^CommitDate:\s\+${expected_date}" <<<"$NEW_COMMIT")

    errors=0

    if [[ "$script_exit" -ne 0 ]]; then
        printf 'Error: script exited with status %s\n' "$script_exit"
        errors=$((errors + 1))
    fi

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

    if [[ "$OLD_COMMITS" != "$NEW_COMMITS" ]]; then
        printf 'Error: other commits were affected!\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" "$label"

    git switch "$original_branch" >/dev/null 2>&1
}

record_result() {
    # $1: error count, $2: label for the summary line
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

run_with_tty() {
    # $1: keystrokes typed into the terminal, rest: command. confirm() reads
    # /dev/tty, not stdin, so a pipe can't answer it; a pty can.
    python3 -c '
import os, pty, sys
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[2], sys.argv[2:])
os.write(fd, sys.argv[1].encode())
while True:
    try:
        if not os.read(fd, 1024):
            break
    except OSError:
        break
sys.exit(os.waitstatus_to_exitcode(os.waitpid(pid, 0)[1]))
' "$@"
}

run_without_tty() {
    # New session: no controlling terminal, so /dev/tty can't be opened.
    python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@"
}
