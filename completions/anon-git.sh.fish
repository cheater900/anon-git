# Fish completion for anon-git.sh
#
# Install:
#   cp completions/anon-git.sh.fish ~/.config/fish/completions/
#
# Flag descriptions are hand-maintained here since fish's `complete` format
# supports per-flag help text that --_list-flags (a plain flag list) can't
# express; run `./anon-git.sh --_list-flags` after changing flags to check
# nothing was missed.

function __anon_git_commits
    git for-each-ref --format='%(refname:short)' refs/heads refs/tags 2>/dev/null
end

complete -c anon-git.sh -f
complete -c anon-git.sh -s h -l help -d 'Show help message and exit'
complete -c anon-git.sh -l date -x -d 'ISO date to use'
complete -c anon-git.sh -l name -x -d 'Full name to use for author & committer'
complete -c anon-git.sh -l email -x -d 'Email address to use for author & committer'
complete -c anon-git.sh -l keep-user -d 'Do not change user name or author'
complete -c anon-git.sh -l keep-date -d 'Do not change date'
complete -c anon-git.sh -l keep-year -d 'Do not change commit year'
complete -c anon-git.sh -l keep-month -d 'Do not change commit month (and year)'
complete -c anon-git.sh -l keep-day -d 'Do not change commit day (and year and month)'
complete -c anon-git.sh -l no-confirm -d 'Do not prompt for confirmation'
complete -c anon-git.sh -l no-backup -d 'Do not create backup branch'
complete -c anon-git.sh -l current-branch -d 'Overwrite current branch instead of creating a copy'
complete -c anon-git.sh -l entire-history -d 'Rewrite entire history and not a single commit'
complete -c anon-git.sh -l dry-run -d 'Show history changes without rewriting it'
complete -c anon-git.sh -l print-completion -x -a 'bash zsh fish' -d 'Print a shell completion script and exit'
complete -c anon-git.sh -a '(__anon_git_commits)' -d 'commit'
