# ANON GIT

AnonGit is a script to **anonymize** git commit authorship and timestamp.

It can useful to contributors of privacy, anti-surveillance, or
censorship-resistant open-source projects, by avoid **leaking information** from
commit **timestamps** and/or **email**. Specifically, anon-git can:

- Anonymize entire git history
- Anonymize single commit
- Anonymize multiple commits
- Anonymize commits filtered by author/commiter, date range, or commit message
- Anonymize metadata using arbitrary values for user name, user email and date
- Anonymize just the timestamps (keep authorship) or the username (keep timestamp)
- Anonymize the timestamps partially: preserve commit year or month or day while anonymizing other information (hour & timezone)

## Introduction

### Why anonymize meta-data of Git commits?

Even when using Tor and throwaway GitHub accounts, your **commit timestamps**
can still deanonymize you over time:

- timezone may be linked to location
- time of commit may be linked to work and routine schedules
- day of the week may be linked workdays and religious/cultural practices (rest days)
- day and month may be linked to holidays, festivals and cultural/religious events
- cadence between commits may leak information about commit frequency and coding pace, revealing personal development patterns (some developers commit frequently, while others code more before committing)

Such information could be used to target contributors of privacy-oriented projects:

- **Internet anonymity**: Tor Browser, I2P, FreeNet
- **Private finace**: Monero, Bisq, Samourai Wallet, CoinJoin tools
- **Mobile OS**: GrapheneOS, CalyxOS
- **Communication protocols**: Simplex, Matrix, Briar, XMPP
- **Social network**: Nostr, Mastodon, Scuttlebutt
- **Privacy guides**, KYC Not Me (kycnot.me), Digital Defense (digitaldefense.io)

The list above is not meant to be a compilation of privacy tools, but merely
examples of projects whose contributors may wish to stay anonymous.

### When to use it

- AnonGit **only removes metadata** — it does **not** hide IP addresses, contribution timing correlations, writing style, code patterns, etc.
- AnonGit is most useful to anonymize timestamp metadata along with anonymous email and name. If you leak personal data via public forges (GitHub, GitLab, Codeberg, SourceHut) the script becomes useless.
- AnonGit most useful on branches you have full control of the branch
- AnonGit most useful for commits that have not been published to remote branches and forges
- If the repository is public and has been cloned/forked, then the script may become useless since the old copies of the git history were not rewritten

## Usage

This section describe how to install and use anon-git, with detailed examples
and documented options.

### Installation

#### Pre-requisites

The script is based on `git filter-repo`, so you **must** have it installed.

#### Git clone

Clone the repository and install the script via `--install` or `--install-system`:

```
# clone repo
git clone https://github.com/radioactively/anon-git && cd anon-git

# local install to ~/.local/bin, falls back to ~/.bin
./anon-git.sh --install

# System-wide install to /usr/bin via sudo
./anon-git.sh --install-system
```

> [!NOTE]
> The `--install` only copies into `~/.local/bin` and/or `~/.bin` if they already exist.
> The `--install-system` requires `sudo`.
> The directory `~/.local/bin` or ``~/.bin` must be in your `$PATH`

#### Manual installation

Alternatively, just download or copy-paste the file and put it into your `$PATH`.


### Examples

```bash
# Anonymize current HEAD with defaults
./anon-git.sh HEAD

# Anonymize two commits ago
./anon-git.sh HEAD~2

# Explicit values + specific commit
./anon-git.sh --date "2024-01-01 00:00:00 +0000" \
                          --name "Jane Doe" \
                          --email "jane@anon.dev" \
                          8ddf55a

# Keep real name/email, only change date
./anon-git.sh --keep-user --date "2025-06-15T14:20:00Z" HEAD

# Preview what would change before actually rewriting anything
./anon-git.sh --dry-run HEAD~2

# Anonymize the whole repo before its first push to a remote
./anon-git.sh --entire-history --current-branch

# Keep the commit's day (and month/year) but scrub the time-of-day and timezone
./anon-git.sh --keep-day HEAD~2

# Silence informational output (only errors print)
./anon-git.sh --quiet HEAD

# Force informational output back on, overriding a quiet default
./anon-git.sh --verbose HEAD

# Use environment variables instead of flags (handy for hooks/CI)
ANON_GIT_NAME="Anon" ANON_GIT_EMAIL="anon@localhost" ./anon-git.sh --keep-date HEAD
```

More examples using built-in filters provided by `git` in order to pick a set of
commits matching the filter:

```bash
# Anonymize the last 10 commits using shell expansion (works in bash and zsh)
./anon-git.sh HEAD~{0..9}

# Anonymize commits within a specific date range
git log --format=%H --after='2023-01-01' --before='2024-01-01' | xargs ./anon-git.sh

# Anonymize commits where the commit author matches a pattern
git log --format=%H --author='Frederic' | xargs ./anon-git.sh

# Anonymize commits following the Conventional Commits "fix:" prefix
git log --format=%H --grep='^fix:' | xargs ./anon-git.sh
```

### Options

```
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
  --install                        Copy this script to ~/.local/bin and/or ~/.bin
                                   (whichever exist) and warn if neither is on $PATH
  --install-system                 Copy this script system-wide to /usr/bin (via sudo)
  --install-hook                   Install a post-commit hook in the current git repository
                                   that anonymizes each new commit (HEAD only) automatically
```

**Priority order** (highest to lowest):

1. Command-line flags
2. Environment variables (`ANON_GIT_DATE`, `ANON_GIT_NAME`, `ANON_GIT_EMAIL`, `ANON_GIT_KEEPUSER`, `ANON_GIT_KEEPDATE`, `ANON_GIT_KEEPYEAR`, `ANON_GIT_KEEPMONTH`, `ANON_GIT_KEEPDAY`, `ANON_GIT_ENTIREHISTORY`, `ANON_GIT_CURRENTBRANCH`, `ANON_GIT_DRYRUN`, `ANON_GIT_QUIET`)
3. Repo-local git config (`git config anon-git.name`, `anon-git.email`, `anon-git.date`, `anon-git.keepuser`, `anon-git.keepdate`, `anon-git.keepyear`, `anon-git.keepmonth`, `anon-git.keepday`, `anon-git.quiet` — see [Repo-local config](#repo-local-config) below; `--entire-history`/`--current-branch`/`--dry-run` have no config equivalent, flag/envvar only)
4. Hardcoded defaults

`--verbose` has no `ANON_GIT_VERBOSE` environment variable or config equivalent; it's a CLI-only override that forces informational output back on for one run, regardless of what set `ANON_GIT_QUIET` (flag, envvar, or repo-local config).

> [!WARNING]
> `--name`, `--email` and `--date` (and their `ANON_GIT_*` environment variable
> equivalents) are not meant to carry untrusted input — don't wire user-controlled
> values (e.g. from CI variables or another service) into them.

### Repo-local config

A repository can pin its own defaults instead of every invocation needing flags or exported envvars:

```bash
git config anon-git.name "Sherlock"
git config anon-git.email "sherlock@localhost"
git config anon-git.date "2026-01-01 12:00:00 +0000"
git config anon-git.keepuser true
git config anon-git.keepdate true
git config anon-git.keepyear true
git config anon-git.keepmonth true
git config anon-git.keepday true
git config anon-git.quiet true
```

Booleans accept anything `git config --bool` does (`true`/`false`, `yes`/`no`, `on`/`off`, `1`/`0`); anything else is a hard error rather than silently ignored, since a typo'd repo config shouldn't fail open. `git config` writes to `.git/config` (local to your clone) by default — use `git config --global` instead if you want the same defaults across every repo.

Deliberately scoped to `name`/`email`/`date`/`keep-*`/`quiet` -- the settings
that make sense to pin per-repo. `--entire-history`, `--current-branch` and
`--dry-run` stay flag/envvar-only: a silently-configured default for any of
those would be far more destructive than a wrong name or email (e.g. every
invocation silently rewriting the entire history instead of one commit).

Incompatible combinations (e.g. `anon-git.keepuser=true` with `anon-git.email` also set) are rejected the same way the equivalent flags/envvars are, regardless of where each side came from.

### Post-commit hook

To automatically anonymize every new commit in the *current* repository, install
a post-commit hook instead:

```bash
./anon-git.sh --install-hook
```

This writes `.git/hooks/post-commit`, which anonymizes only the commit you just
made (`HEAD`), using `--current-branch --no-backup --quiet` so it rewrites in
place rather than creating a new branch (or a backup branch) after every commit,
and doesn't print "Anonymizing commit(s): ..." / "Done." on top of git's own
commit summary — the hook fires on *every* commit, so a per-commit backup branch
(or message) would otherwise accumulate/spam forever; `git reflog`/`git reset`
still recover the pre-hook state if something goes wrong. Re-running
`--install-hook` safely refreshes a hook it created, but refuses to overwrite a
pre-existing hook it didn't write (remove or back that one up first).

### Shell completion

Tab-completion scripts for bash, zsh, and fish are hand-written and live in `completions/` (they don't need `git filter-repo`, only `anon-git.sh` itself and, for completing commit refs, `git`). The flag list they offer comes from the script's own `--_list-flags` (bash) or is kept in sync with it (zsh/fish; checked by the test suite), so there's one source of truth even though each shell's completion format is hand-maintained separately.

Print any of them with `--print-completion [bash|zsh|fish]` (the shell is inferred from `$SHELL` if omitted) instead of hunting for the file in `completions/`:

```bash
# Install for your current shell
./anon-git.sh --print-completion bash > ~/.local/share/bash-completion/completions/anon-git.sh
./anon-git.sh --print-completion zsh  > "${fpath[1]}/_anon-git.sh"   # must be a dir already in $fpath
./anon-git.sh --print-completion fish > ~/.config/fish/completions/anon-git.sh.fish

# Or just try it out in the current shell session (bash/zsh)
source <(./anon-git.sh --print-completion)
```

## Notes

- The script, by default, uses a new branch instead of rewriting the current. It
  can be changed via `--current-branch` flag.
- The script, by default, creates a backup branch when using `--current-branch`
  flag.
- You can recover with `git reflog` / `git reset` if something goes wrong even
  if you use `--current-branch` and `--no-backup`
- If you pushed before using the script, you'll need `git push
  --force-with-lease` afterward (dangerous on shared branches!)
- The flags `--keep-user` and `--keep-date` are useful for partial anonymization
- Timestamps must be in a format `git` understands (ISO 8601 with timezone
  recommended)
- The script runs `git filter-repo --force`, which skips filter-repo's own "is
  this repo safe to rewrite" check (normally it refuses to run outside of a
  fresh clone). This is safe here because the script always rewrites a
  new/backup branch first — but it does mean you're relying on that branch, not
  on filter-repo, to protect your other branches/history.
- Rewriting a commit invalidates any GPG signature on it (same as `git
  filter-branch`/`git rebase`); re-sign afterward if you sign your commits
- To temporarily disable the hook run `chmod -x .git/hooks/post-commit`
- Consider using environment variables (`export ANON_GIT_NAME="..."` etc.)
  instead of hard-coding flags in the hook
- Consider squashing commits or using merge requests from anonymous remotes
- The script's scratch files (the `--dry-run` preview, `git filter-repo`'s log)
  are cleaned up by an `EXIT` trap, so killing it mid-run (Ctrl-C, a CI timeout,
  ...) doesn't leave them behind in `/tmp` either

## License

[GPL-3.0](LICENSE).
