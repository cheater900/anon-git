#!/usr/bin/env bats

# Shell-completion tests for anon-git.sh (bash/zsh/fish). The TAB tests
# drive real interactive shells via `expect` and skip when expect or the
# shell is missing.

load test_helper

@test "zsh/fish completions list all flags" {
    # Zsh and fish hand-maintain flag names (for per-flag descriptions); this
    # regression-tests that every flag from --_list-flags (the source of
    # truth) is still declared in both: as `'--flag[` or `{-f,--flag}` in
    # zsh and `-l flag` in fish, matched whole so "date" can't hit
    # "keep-date". Never `'--flag=[`: zsh would insert `--flag=`, which
    # parse_args rejects as an unknown option. Bash completion is dynamic (calls --_list-flags
    # itself), so it's only checked for still being wired up.
    local zsh_completion=${SCRIPT_DIR}/completions/_anon-git.sh
    local fish_completion=${SCRIPT_DIR}/completions/anon-git.sh.fish flag
    assert_file_contains "${SCRIPT_DIR}/completions/anon-git.bash" '_list-flags'
    for flag in $(./anon-git.sh --_list-flags | sed 's/=$//; s/^-*//'); do
        if [[ "${#flag}" -le 1 ]]; then
            continue
        fi
        assert grep -qE -- "^ *'--${flag}\[|[{,]--${flag}[,}]" "$zsh_completion"
        assert grep -qE -- "-l ${flag}( |$)" "$fish_completion"
    done
}

# Drives a real interactive shell via `expect` and checks TAB actually
# completes a flag and a ref through the shipped scripts (unlike the test
# above, which only checks the scripts mention the right strings). Types
# only a prefix, so the echoed input alone can't match. Clears the line with
# Ctrl-U, not Ctrl-C: fish can drop a SIGINT that lands mid-completion, while
# Ctrl-U is read in order with the following keys. Matches "keep-user"/the
# ref name without a trailing space, since zsh wraps freshly-inserted text
# in bold escape codes that split up a literal trailing-space match. Uses a
# dedicated git tag as the ref target so this stays independent of how the
# template repo is set up.
completion_expect() {
    # $1: shell binary, skipped when missing. $2: spawn command. $3: command
    # that sets the prompt to $prompt (shell-specific: bash/zsh use PS1=...,
    # fish needs a fish_prompt function). $4: newline-separated setup lines
    # sent once the prompt is set.
    local spawn_cmd=$2 prompt_cmd=$3 setup=$4
    local prompt='COMPLETION_TEST_PROMPT> ' ref_marker='anon_git_completion_test_ref'
    local send_setup='' line
    if ! command -v expect >/dev/null; then
        skip 'expect not installed'
    fi
    if ! command -v "$1" >/dev/null; then
        skip "$1 not installed"
    fi
    git tag "$ref_marker"
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi
        send_setup+="send \"${line}\\r\"
expect \"${prompt}\"
"
    done <<<"$setup"
    run expect <<EOF
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
    assert_success
}

@test "bash completion completes flag and ref" {
    completion_expect bash 'bash --norc --noprofile' \
        "PS1='COMPLETION_TEST_PROMPT> '" \
        "source ${SCRIPT_DIR}/completions/anon-git.bash"
}

@test "zsh completion completes flag and ref" {
    completion_expect zsh 'zsh -f' \
        "PS1='COMPLETION_TEST_PROMPT> '" \
        "autoload -Uz compinit && compinit -u
source ${SCRIPT_DIR}/completions/_anon-git.sh"
}

@test "fish completion completes flag and ref" {
    completion_expect fish 'env TERM=dumb fish -N -P' \
        "function fish_prompt; echo -n 'COMPLETION_TEST_PROMPT> '; end" \
        "source ${SCRIPT_DIR}/completions/anon-git.sh.fish"
}
