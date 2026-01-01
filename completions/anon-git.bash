# Bash completion for anon-git.sh
#
# Install (pick one):
#   source completions/anon-git.bash                                   # current shell only
#   cp completions/anon-git.bash /etc/bash_completion.d/anon-git       # system-wide
#   cp completions/anon-git.bash ~/.local/share/bash-completion/completions/anon-git.sh
#
# Flag names are read from the script itself (--_list-flags) so this file
# never needs to hardcode them.

_anon_git_completion() {
    local cur prev script flags refs
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    script="${COMP_WORDS[0]}"

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
        flags=$("$script" --_list-flags 2>/dev/null | sed 's/=$//')
        COMPREPLY=($(compgen -W "$flags" -- "$cur"))
    else
        refs=$(git for-each-ref --format='%(refname:short)' refs/heads refs/tags 2>/dev/null)
        COMPREPLY=($(compgen -W "$refs" -- "$cur"))
    fi
    return 0
}

complete -F _anon_git_completion anon-git.sh
complete -F _anon_git_completion ./anon-git.sh
complete -F _anon_git_completion anon-git
