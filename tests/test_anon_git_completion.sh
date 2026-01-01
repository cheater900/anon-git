#!/usr/bin/env bash

# Shell-completion tests for anon-git.sh (bash/zsh/fish), split out from
# test_anon_git.sh since they drive real interactive shells via `expect`
# instead of exercising anon-git.sh itself, and depend on tooling
# (expect, and optionally bash/zsh/fish) that not every environment has.

# Assume anon-git.sh is in the parent directory
SCRIPT_DIR=$(realpath "$(dirname "$0")/..")
SCRIPT_NAME=anon-git.sh
SCRIPT=${SCRIPT_DIR}/${SCRIPT_NAME}

# Create temp dir to work on
TMP_DIR=$(mktemp -d /tmp/anon_git_test_completion.XXXXXX)
cd "$TMP_DIR" || exit 1
cp "$SCRIPT" .
chmod +x "./${SCRIPT_NAME}"

cleanup() {
    cd - >/dev/null 2>&1 || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Global variables shared among functions

CURRENT_TEST_INDEX=0
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_ERRORS=0

# ──────────────────────────────────────────────────────────────────────

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

test_completion_flags() {
    # Zsh and fish completions hand-maintain flag names (so they can attach
    # per-flag descriptions); regression test that every flag from
    # --_list-flags (the script's own source of truth) is still mentioned in
    # both, so a flag added to anon-git.sh can't silently go unmentioned.
    # Flags are compared by bare name (dashes/= stripped) since fish's
    # `complete -l <name>` convention omits the leading "--".
    # The bash completion is dynamic (calls --_list-flags itself at
    # completion time), so it's only checked for still being wired up.
    local bash_completion zsh_completion fish_completion
    local flags flag errors=0

    bash_completion="${SCRIPT_DIR}/completions/anon-git.bash"
    zsh_completion="${SCRIPT_DIR}/completions/_anon-git.sh"
    fish_completion="${SCRIPT_DIR}/completions/anon-git.sh.fish"

    if ! grep -qF -- '--_list-flags' "$bash_completion" 2>/dev/null; then
        printf 'Error: bash completion no longer calls --_list-flags\n'
        errors=$((errors + 1))
    fi

    flags=$(./${SCRIPT_NAME} --_list-flags | sed 's/=$//; s/^-*//')

    while IFS= read -r flag; do
        [[ "${#flag}" -gt 1 ]] || continue
        if ! grep -qF -- "$flag" "$zsh_completion" 2>/dev/null; then
            printf 'Error: "%s" missing from zsh completion (%s)\n' "$flag" "$zsh_completion"
            errors=$((errors + 1))
        fi
        if ! grep -qF -- "$flag" "$fish_completion" 2>/dev/null; then
            printf 'Error: "%s" missing from fish completion (%s)\n' "$flag" "$fish_completion"
            errors=$((errors + 1))
        fi
    done <<<"$flags"

    record_result "$errors" 'zsh/fish completions list every flag'
}

# Drives a real interactive shell (bash/zsh/fish) via `expect` and checks
# that TAB actually completes a flag and a ref through the shipped
# completion scripts, rather than just checking the scripts mention the
# right strings (that's test_completion_flags above). expect matches
# "keep-user" / the ref name rather than the flag/ref plus trailing space,
# since zsh wraps the freshly-inserted text in bold escape codes that split
# up a literal trailing-space match. Uses a dedicated git tag as the
# ref-completion target since a real branch name is otherwise the only ref
# in this repo and there's nothing to make the prefix ambiguous either way,
# but a tag keeps this independent of how init_repo sets up the repo.
_completion_expect() {
    # @param $1  spawn command (e.g. "bash --norc --noprofile")
    # @param $2  command that sets the prompt to $prompt (shell-specific:
    #            bash/zsh use PS1=..., fish needs a fish_prompt function)
    # @param $3  newline-separated setup lines to send once the prompt is set
    # @param $4  ref marker to complete against
    local spawn_cmd="$1" prompt_cmd="$2" setup="$3" ref_marker="$4"
    local prompt='COMPLETION_TEST_PROMPT> '
    local send_setup line

    send_setup=""
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        send_setup+="send \"${line}\\r\"
expect \"${prompt}\"
"
    done <<<"$setup"

    expect >/dev/null 2>&1 <<EOF
set timeout 10
log_user 0
spawn ${spawn_cmd}
send "${prompt_cmd}\r"
expect "${prompt}"
${send_setup}
send "./${SCRIPT_NAME} --keep-u\t"
expect {
  "keep-user" {}
  timeout {exit 1}
}
send "\003"
expect "${prompt}"
send "./${SCRIPT_NAME} ${ref_marker}\t"
expect {
  "${ref_marker}" {}
  timeout {exit 1}
}
EOF
}

test_completion() {
    local errors=0 ref_marker='anon_git_completion_test_ref'

    if ! command -v expect >/dev/null 2>&1; then
        printf 'SKIP shell completion: expect not installed\n'
        return
    fi

    git tag "$ref_marker" >/dev/null 2>&1

    if command -v bash >/dev/null 2>&1; then
        if ! _completion_expect 'bash --norc --noprofile' \
            "PS1='COMPLETION_TEST_PROMPT> '" \
            "source ${SCRIPT_DIR}/completions/anon-git.bash" "$ref_marker"; then
            printf 'Error: bash completion did not complete flag or ref\n'
            errors=$((errors + 1))
        fi
    else
        printf 'SKIP bash completion: bash not installed\n'
    fi

    if command -v zsh >/dev/null 2>&1; then
        if ! _completion_expect 'zsh -f' \
            "PS1='COMPLETION_TEST_PROMPT> '" \
            "autoload -Uz compinit && compinit -u
source ${SCRIPT_DIR}/completions/_anon-git.sh" "$ref_marker"; then
            printf 'Error: zsh completion did not complete flag or ref\n'
            errors=$((errors + 1))
        fi
    else
        printf 'SKIP zsh completion: zsh not installed\n'
    fi

    if command -v fish >/dev/null 2>&1; then
        if ! _completion_expect 'env TERM=dumb fish -N -P' \
            "function fish_prompt; echo -n 'COMPLETION_TEST_PROMPT> '; end" \
            "source ${SCRIPT_DIR}/completions/anon-git.sh.fish" "$ref_marker"; then
            printf 'Error: fish completion did not complete flag or ref\n'
            errors=$((errors + 1))
        fi
    else
        printf 'SKIP fish completion: fish not installed\n'
    fi

    git tag -d "$ref_marker" >/dev/null 2>&1

    record_result "$errors" 'shell completion (bash/zsh/fish)'
}

main() {
    # Ref completion needs a real commit to tag against; the anonymization
    # logic itself isn't under test here, so an empty commit is enough.
    git init >/dev/null
    git config --local user.name "Jordan Blake"
    git config --local user.email "jordan.blake@example.com"
    git commit --allow-empty -m 'Initial commit' >/dev/null

    test_completion_flags
    test_completion
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
