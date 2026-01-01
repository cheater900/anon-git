#!/usr/bin/env bash

# Shell-completion tests for anon-git.sh (bash/zsh/fish), split out from
# test_anon_git.sh since they drive real interactive shells via `expect`
# and depend on tooling (expect, bash/zsh/fish) not every environment has.

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)

# shellcheck source=tests/lib/common.sh
source "${TESTS_DIR}/lib/common.sh"

test_completion_flags() {
    # Zsh and fish hand-maintain flag names (for per-flag descriptions); this
    # regression-tests that every flag from --_list-flags (the source of
    # truth) is still declared in both: as `'--flag[`, `'--flag=[` or
    # `{-f,--flag}` in zsh and `-l flag` in fish, matched whole so "date"
    # can't hit "keep-date". Bash
    # completion is dynamic (calls --_list-flags itself), so it's only
    # checked for still being wired up.
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
        if ! grep -qE -- "^ *'--${flag}=?\[|[{,]--${flag}[,}]" "$zsh_completion" 2>/dev/null; then
            printf 'Error: "%s" missing from zsh completion (%s)\n' "$flag" "$zsh_completion"
            errors=$((errors + 1))
        fi
        if ! grep -qE -- "-l ${flag}( |$)" "$fish_completion" 2>/dev/null; then
            printf 'Error: "%s" missing from fish completion (%s)\n' "$flag" "$fish_completion"
            errors=$((errors + 1))
        fi
    done <<<"$flags"

    record_result "$errors" 'zsh/fish completions list all flags'
}

# Drives a real interactive shell via `expect` and checks TAB actually
# completes a flag and a ref through the shipped scripts (unlike
# test_completion_flags above, which only checks the scripts mention the
# right strings). Types only a prefix, so the echoed input alone can't match.
# Clears the line with Ctrl-U, not Ctrl-C: fish can drop a SIGINT that lands
# mid-completion, while Ctrl-U is read in order with the following keys. Matches "keep-user"/the ref name without a trailing space,
# since zsh wraps freshly-inserted text in bold escape codes that split up a
# literal trailing-space match. Uses a dedicated git tag as the ref target so
# this stays independent of how init_repo sets up the repo.
_completion_expect() {
    # $1: spawn command. $2: command that sets the prompt to $prompt
    # (shell-specific: bash/zsh use PS1=..., fish needs a fish_prompt
    # function). $3: newline-separated setup lines sent once the prompt is
    # set. $4: ref marker to complete against.
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
send "\025"
send "./${SCRIPT_NAME} ${ref_marker:0:20}\t"
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
    init_repo
    test_completion_flags
    test_completion
    print_summary
}

main
[[ "$TESTS_FAILED" -eq 0 ]]
