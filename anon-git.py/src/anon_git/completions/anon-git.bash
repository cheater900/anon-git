# Bash completion for anon-git (Python implementation)
#
# Install (pick one):
#   source <(anon-git --print-completion bash)                         # current shell only
#   anon-git --print-completion bash > ~/.local/share/bash-completion/completions/anon-git
#
# Flag names are read from anon-git itself (--_list-flags) so this file
# never needs to hardcode them.

_anon_git_completion() {
    local cur prev flags refs
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "$prev" in
        --date|--name|--email)
            # Free-form value; nothing sensible to complete.
            return 0
            ;;
        --print-completion)
            COMPREPLY=($(compgen -W "bash zsh fish" -- "$cur"))
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        flags=$("${COMP_WORDS[0]}" --_list-flags 2>/dev/null | sed 's/=$//')
        COMPREPLY=($(compgen -W "$flags" -- "$cur"))
    else
        refs=$(git for-each-ref --format='%(refname:short)' refs/heads refs/tags 2>/dev/null)
        COMPREPLY=($(compgen -W "$refs" -- "$cur"))
    fi
    return 0
}

complete -F _anon_git_completion anon-git
