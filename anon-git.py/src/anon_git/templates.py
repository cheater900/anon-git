"""Long text blocks: --help output and the post-commit hook script."""

HOOK_BODY = """
# The install this hook calls is gone (e.g. `uv tool uninstall anon-git`):
# say so instead of failing every commit with a bare "No such file".
if [[ ! -x "${anon_git[0]}" ]]; then
    printf 'anon-git: %s missing, not anonymized; re-run --install-hook.\\n' "${anon_git[0]}" >&2
    exit 0
fi

# Rewriting HEAD mid-sequence would derail the rebase/cherry-pick/revert.
for state in rebase-merge rebase-apply sequencer CHERRY_PICK_HEAD REVERT_HEAD; do
    if [[ -e "$(git rev-parse --git-path "$state")" ]]; then
        printf 'anon-git: %s in progress, commit not anonymized.\\n' "$state" >&2
        exit 0
    fi
done

# A partial commit (git add -p, git commit <path>) leaves a dirty tree,
# which anon-git refuses; stash it around the run. Only pop what this push
# saved: it saves nothing for e.g. a dirty submodule, and popping would then
# apply an older, unrelated stash.
stashed=0
if ! git diff-index --quiet HEAD -- || ! git diff-files --quiet; then
    stash_before=$(git rev-parse --quiet --verify refs/stash || true)
    git stash push --quiet
    if [[ "$(git rev-parse --quiet --verify refs/stash || true)" != "$stash_before" ]]; then
        stashed=1
    fi
fi
status=0
"${anon_git[@]}" --no-confirm --no-backup --quiet --current-branch HEAD || status=$?
if [[ "$stashed" -eq 1 ]]; then
    git stash pop --quiet --index
fi
exit "$status"
"""


HELP = """Anonymizes git commit metadata.

Usage:
  anon-git [OPTIONS] [commits]

Options:
  -h, --help                      Show this help message and exit
  -v, --version                   Show version and exit
  --date        ISO Date          Date to use (example: "2025-03-10 13:37:00 +0000")
  --name        "Full name"       Name to use for author & committer
  --email       "Email address"   Email to use for author & committer
  --keep-user                     Do not change user name or author
  --keep-date                     Do not change date
  --keep-year                     Do not change commit year
  --keep-month                    Do not change commit month (and year)
  --keep-day                      Do not change commit day (and year and month)
  --random-time                   Keep commit date year, month and day; replace the time
                                   with a random one, ordered to match the original
                                   relative commit order (never touches the year)
  --random-day                    Keep commit date year and month; replace day and time
                                   with random values, ordered to match the original
                                   relative commit order (never touches the year)
  --random-month                  Keep commit date year; replace month, day and time
                                   with random values, ordered to match the original
                                   relative commit order (never touches the year)
  --strip-timezone                Force the timezone offset to UTC+0000 without changing
                                   the date/time digits. Used with no other option, also
                                   leaves author and date/time untouched (only the offset
                                   changes); combined with other options, those take their
                                   normal effect and the resulting offset is still forced
                                   to +0000
  --no-confirm                    Do not prompt for confirmation
  --no-backup                     Do not create backup branch
  --current-branch                Overwrite current branch instead of creating a copy of it
  --entire-history                Rewrite entire history and not a single commit
  --dry-run                       Show history changes without rewriting it
  --quiet                         Suppress informational output (errors/safety warnings still print)
  --verbose                       Force informational output, overriding --quiet,
                                   ANON_GIT_QUIET, or a repo-local quiet config
  --print-completion [SHELL]      Print a shell completion script (bash, zsh, or fish;
                                   defaults to $SHELL) and exit
  --install-hook                   Install a post-commit hook in the current git repository
                                   that anonymizes each new commit (HEAD only) automatically
  --uninstall-hook                 Remove the post-commit hook installed by --install-hook

Arguments:
  commit(s)               Commit(s) to anonymize (can be: hash, HEAD~3, branch, tag, ...)
                          Required, unless --entire-history is given.
                          If omitted (and --entire-history is not given), this help is shown.
                          If more than one, it should be a commit hash.

Priority (highest to lowest):
  1. Command-line flags (--date, --name, --email, --keep-user, --keep-date, ...)
  2. Repo-local git config (git config anon-git.name, anon-git.email, anon-git.date,
     anon-git.keepuser, anon-git.keepdate, anon-git.keepyear, anon-git.keepmonth,
     anon-git.keepday, anon-git.randomtime, anon-git.randomday, anon-git.randommonth,
     anon-git.striptimezone, anon-git.quiet;
     --entire-history/--current-branch/--dry-run have no config equivalent, flag/envvar only)
  3. Environment variables (ANON_GIT_DATE, ANON_GIT_NAME, ANON_GIT_EMAIL, ANON_GIT_KEEPUSER,
     ANON_GIT_KEEPDATE, ANON_GIT_KEEPYEAR, ANON_GIT_KEEPMONTH, ANON_GIT_KEEPDAY,
     ANON_GIT_RANDOMTIME, ANON_GIT_RANDOMDAY, ANON_GIT_RANDOMMONTH,
     ANON_GIT_STRIPTIMEZONE, ANON_GIT_ENTIREHISTORY, ANON_GIT_CURRENTBRANCH,
     ANON_GIT_DRYRUN, ANON_GIT_QUIET)
  4. Hardcoded defaults ({DEFAULT_NAME} <{DEFAULT_EMAIL}>)

Note: --verbose has no ANON_GIT_VERBOSE environment variable or config
      equivalent; it is a CLI-only override that forces informational
      output back on for one run.

Examples:
    # Anonymize current HEAD with defaults
    anon-git HEAD

    # Anonymize two commits ago
    anon-git HEAD~2

    # Explicit values at specific commit
    anon-git --date "2024-01-01 00:00:00 +0000"
             --name "Jane Doe"
             --email "jane@anon.dev"
             8ddf55a

    # Keep real name/email, only change date
    anon-git --keep-user --date "2025-06-15T14:20:00Z"

    # Keep the commit year, randomize month/day/time; commits keep their
    # relative order (a later commit never lands earlier than an earlier one)
    anon-git --random-month --entire-history

    # Used alone: keep author and date/time as-is, only force the timezone
    # offset to UTC+0000 (hides where the committer is, keeps everything else)
    anon-git --strip-timezone HEAD

    # Preview what would change before actually rewriting anything
    anon-git --dry-run HEAD~2

    # Silence informational output (only errors print)
    anon-git --quiet HEAD

    # Force informational output back on, overriding a quiet default
    anon-git --verbose HEAD

    # Pin this repo's own defaults instead of passing flags/envvars every time
    git config anon-git.name "Anon"
    git config anon-git.email "anon@localhost"
    git config anon-git.quiet true
    anon-git HEAD

    # Anonymize the last 10 commits using shell expansion (works in bash and zsh)
    anon-git HEAD~{{0..9}}

    # Anonymize commits within a specific date range
    anon-git $(git log --format=%H --after='2023-01-01' --before='2024-01-01')

    # Anonymize commits where the commit author matches a pattern
    anon-git $(git log --format=%H --author='Frederic')

    # Anonymize commits following the Conventional Commits "fix:" prefix
    anon-git $(git log --format=%H --grep='^fix:')

    # Install shell completion (shell inferred from $SHELL if omitted)
    anon-git --print-completion bash > ~/.local/share/bash-completion/completions/anon-git
    anon-git --print-completion zsh  > "${{fpath[1]}}/_anon-git"
    anon-git --print-completion fish > ~/.config/fish/completions/anon-git.fish

    # Install a post-commit hook so every new commit in this repo is
    # auto-anonymized (HEAD only, right after `git commit`)
    anon-git --install-hook

    # Remove the post-commit hook installed by --install-hook
    anon-git --uninstall-hook"""
