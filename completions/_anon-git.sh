#compdef anon-git.sh ./anon-git.sh
#
# Zsh completion for anon-git.sh
#
# Install (pick one):
#   source <(./anon-git.sh --print-completion zsh)                 # current shell only
#   fpath+=(/path/to/anon_git/completions) && autoload -U compinit && compinit
#   cp completions/_anon-git.sh ~/.zsh/completions/_anon-git.sh   # (must be in $fpath)
#
# Defines a normally-named function (_anon_git) and registers it via
# `compdef` at the end, rather than relying only on zsh's fpath/filename
# autoload convention (the `#compdef` line above) — that convention only
# kicks in once this file is on $fpath and `compinit` has processed it, so
# a plain `source <(...)` of the raw file would otherwise fail with
# "command not found: _arguments" (zsh's completion functions, like
# _arguments/_describe, aren't defined until compinit has run).
#
# Flag descriptions are hand-maintained here since zsh's _arguments format
# supports per-flag help text that --_list-flags (a plain flag list) can't
# express; run `./anon-git.sh --_list-flags` after changing flags to check
# nothing was missed.

(( $+functions[_arguments] )) || { autoload -Uz compinit; compinit }

_anon_git_commits() {
    local -a refs
    refs=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads refs/tags 2>/dev/null)"})
    _describe 'commit-ish' refs
}

_anon_git() {
    _arguments -s \
        '(-h --help)'{-h,--help}'[Show help message and exit]' \
        '(-v --version)'{-v,--version}'[Show version and exit]' \
        '--date=[ISO date to use]:date:' \
        '--name=[Full name to use for author & committer]:name:' \
        '--email=[Email address to use for author & committer]:email:' \
        '--keep-user[Do not change user name or author]' \
        '--keep-date[Do not change date]' \
        '--keep-year[Do not change commit year]' \
        '--keep-month[Do not change commit month (and year)]' \
        '--keep-day[Do not change commit day (and year and month)]' \
        '--strip-timezone[Force timezone offset to UTC+0000 without changing date/time digits]' \
        '--no-confirm[Do not prompt for confirmation]' \
        '--no-backup[Do not create backup branch]' \
        '--current-branch[Overwrite current branch instead of creating a copy]' \
        '--entire-history[Rewrite entire history and not a single commit]' \
        '--dry-run[Show history changes without rewriting it]' \
        '--quiet[Suppress informational output (errors still print)]' \
        '--verbose[Force informational output, overriding --quiet/ANON_GIT_QUIET/config]' \
        '--print-completion=[Print a shell completion script and exit]:shell:(bash zsh fish)' \
        '--install[Copy this script to ~/.local/bin and/or ~/.bin, whichever exist]' \
        '--install-system[Copy this script system-wide to /usr/bin via sudo]' \
        '--install-hook[Install a post-commit hook that anonymizes each new commit]' \
        '*:commit:_anon_git_commits'
}

compdef _anon_git anon-git.sh ./anon-git.sh
