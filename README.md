# ANON GIT

AnonGit is a script that anonymizes git commit authorship and timestamps.

It's meant for contributors to privacy, anti-surveillance, or
censorship-resistant open-source projects who don't want their commit
timestamps or email leaking information about them. Specifically, anon-git can:

- Anonymize entire git history
- Anonymize a single commit
- Anonymize multiple commits
- Anonymize commits filtered by author/committer, date range, or commit message
- Anonymize metadata using arbitrary values for user name, user email and date
- Anonymize just the timestamps (keep authorship) or the username (keep timestamp)
- Anonymize timestamps partially: preserve the commit year, month, or day while anonymizing the rest (hour & timezone)
- Anonymize timestamps by *randomizing* month, day, or time instead of zeroing them (never the year), while keeping commits in their original relative order

## Introduction

### Why anonymize meta-data of Git commits?

Even when using Tor and a throwaway GitHub account, your commit timestamps
can still deanonymize you over time:

- timezone may be linked to location
- time of commit may be linked to work and routine schedules
- day of the week may be linked to workdays and religious/cultural practices (rest days)
- day and month may be linked to holidays, festivals and cultural/religious events
- cadence between commits may leak information about commit frequency and coding pace, revealing personal development patterns (some developers commit frequently, while others code more before committing)

That kind of information could be used to target contributors to
privacy-oriented projects:

- Internet anonymity: Tor Browser, I2P, FreeNet
- Private finance: Monero, Bisq, Samourai Wallet, CoinJoin tools
- Mobile OS: GrapheneOS, CalyxOS
- Communication protocols: Simplex, Matrix, Briar, XMPP
- Social networks: Nostr, Mastodon, Scuttlebutt
- Privacy guides: KYC Not Me (kycnot.me), Digital Defense (digitaldefense.io)

This isn't meant to be a full list of privacy tools, just examples of the
kind of project whose contributors might want to stay anonymous.

### When to use it

- AnonGit only removes metadata. It does not hide IP addresses, timing correlations between your contributions, writing style, code patterns, etc.
- AnonGit works best when you anonymize timestamps along with an anonymous name and email. Leaking your identity elsewhere on the forge (GitHub, GitLab, Codeberg, SourceHut) defeats the purpose.
- AnonGit is most useful on branches you fully control, for commits that haven't been pushed to a remote or forge yet.
- If the repo is public and already cloned or forked, rewriting history won't help much. The old copies are still out there.

## Usage

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

# Remove it again, from wherever --install/--install-system put it
./anon-git.sh --uninstall
```

> [!NOTE]
> The `--install` only copies into `~/.local/bin` and/or `~/.bin` if they already exist.
> The `--install-system` requires `sudo`.
> The directory `~/.local/bin` or `~/.bin` must be in your `$PATH`.
> `--uninstall` removes the script from all three locations at once, skipping whichever don't have a copy.

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

# Used alone: keep author and date/time as-is, only force the timezone
# offset to UTC+0000 (hides where the committer is, keeps everything else)
./anon-git.sh --strip-timezone HEAD

# Preview what would change before actually rewriting anything
./anon-git.sh --dry-run HEAD~2

# Anonymize the whole repo before its first push to a remote
./anon-git.sh --entire-history --current-branch

# Keep the commit's day (and month/year) but scrub the time-of-day and timezone
./anon-git.sh --keep-day HEAD~2

# Keep the commit year, randomize month/day/time; commits being rewritten in
# this run keep their original relative order (an earlier commit's random
# date never lands after a later commit's, and vice versa)
./anon-git.sh --random-month --entire-history

# Silence informational output (only errors print)
./anon-git.sh --quiet HEAD

# Force informational output back on, overriding a quiet default
./anon-git.sh --verbose HEAD

# Use environment variables instead of flags (handy for hooks/CI)
ANON_GIT_NAME="Anon" ANON_GIT_EMAIL="anon@localhost" ./anon-git.sh --keep-date HEAD
```

More examples, using `git`'s own filters to pick a set of matching commits:

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
  --install                        Copy this script to ~/.local/bin and/or ~/.bin
                                   (whichever exist) and warn if neither is on $PATH
  --install-system                 Copy this script system-wide to /usr/bin (via sudo)
  --install-hook                   Install a post-commit hook in the current git repository
                                   that anonymizes each new commit (HEAD only) automatically
  --uninstall                      Remove this script from ~/.local/bin, ~/.bin, and
                                   /usr/bin (wherever --install/--install-system put it)
  --uninstall-hook                 Remove the post-commit hook installed by --install-hook
```

**Priority order** (highest to lowest):

1. Command-line flags
2. Repo-local git config (`git config anon-git.name`, `anon-git.email`, `anon-git.date`, `anon-git.keepuser`, `anon-git.keepdate`, `anon-git.keepyear`, `anon-git.keepmonth`, `anon-git.keepday`, `anon-git.randomtime`, `anon-git.randomday`, `anon-git.randommonth`, `anon-git.striptimezone`, `anon-git.quiet`, see [Repo-local config](#repo-local-config) below; `--entire-history`/`--current-branch`/`--dry-run` have no config equivalent, flag/envvar only)
3. Environment variables (`ANON_GIT_DATE`, `ANON_GIT_NAME`, `ANON_GIT_EMAIL`, `ANON_GIT_KEEPUSER`, `ANON_GIT_KEEPDATE`, `ANON_GIT_KEEPYEAR`, `ANON_GIT_KEEPMONTH`, `ANON_GIT_KEEPDAY`, `ANON_GIT_RANDOMTIME`, `ANON_GIT_RANDOMDAY`, `ANON_GIT_RANDOMMONTH`, `ANON_GIT_STRIPTIMEZONE`, `ANON_GIT_ENTIREHISTORY`, `ANON_GIT_CURRENTBRANCH`, `ANON_GIT_DRYRUN`, `ANON_GIT_QUIET`)
4. Hardcoded defaults

`--verbose` has no `ANON_GIT_VERBOSE` environment variable or config equivalent; it's a CLI-only override that forces informational output back on for one run, regardless of what set `ANON_GIT_QUIET` (flag, repo-local config, envvar, or default).

> [!WARNING]
> `--name`, `--email` and `--date` (and their `ANON_GIT_*` environment variable
> equivalents) are not meant to carry untrusted input. Don't wire user-controlled
> values (e.g. from CI variables or another service) into them.

### Exit codes

The script only ever exits `0` (success) or `1` (any failure: bad flags,
failed preconditions, a declined confirmation prompt, or `git`/`git
filter-repo` erroring out). There's no finer-grained code to script against.

### Repo-local config

A repository can pin its own defaults so you don't have to pass flags or export envvars every time. Repo config outranks `ANON_GIT_*` envvars (it wins over an inherited/exported envvar you didn't set for this specific invocation), but a CLI flag still overrides it:

```bash
git config anon-git.name "Sherlock"
git config anon-git.email "sherlock@localhost"
git config anon-git.date "2026-01-01 12:00:00 +0000"
git config anon-git.keepuser true
git config anon-git.keepdate true
git config anon-git.keepyear true
git config anon-git.keepmonth true
git config anon-git.keepday true
git config anon-git.randomtime true
git config anon-git.randomday true
git config anon-git.randommonth true
git config anon-git.striptimezone true
git config anon-git.quiet true
```

Booleans accept anything `git config --bool` does (`true`/`false`, `yes`/`no`, `on`/`off`, `1`/`0`); anything else is a hard error rather than silently ignored, since a typo'd repo config shouldn't fail open. `git config` writes to `.git/config` (local to your clone) by default; use `git config --global` instead if you want the same defaults across every repo.

This is deliberately scoped to `name`/`email`/`date`/`keep-*`/`random-*`/`striptimezone`/`quiet`,
the settings that make sense to pin per-repo. `--entire-history`, `--current-branch` and
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

This writes a `post-commit` hook, which anonymizes only the commit you just
made (`HEAD`), using `--current-branch --no-backup --quiet` so it rewrites in
place rather than creating a new branch (or a backup branch) after every commit,
and doesn't print "Anonymizing commit(s): ..." / "Done." on top of git's own
commit summary. The hook fires on *every* commit, so a per-commit backup branch
(or message) would otherwise pile up forever; `git reflog`/`git reset` still
recover the pre-hook state if something goes wrong. Re-running `--install-hook`
safely refreshes a hook it created, but refuses to overwrite a pre-existing
hook it didn't write (remove or back that one up first).

The hook goes wherever git runs hooks from: `core.hooksPath` if set (common
with husky/pre-commit/lefthook), and the shared hooks dir from a linked worktree.

During a rebase, cherry-pick or revert the hook skips the rewrite, since
rewriting `HEAD` mid-sequence would derail it; anonymize those commits
afterwards. A partial commit (`git add -p`, `git commit <path>`) leaves a dirty
tree, so the hook stashes leftover changes around the rewrite and restores them.

Remove it again with `--uninstall-hook`, which refuses to touch a `post-commit`
hook it didn't write (same safety check as above, just in reverse):

```bash
./anon-git.sh --uninstall-hook
```

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
- `--random-time`/`--random-day`/`--random-month` keep every rewritten
  commit in its original relative order, including relative to real,
  untouched neighboring commits when only a single/multiple explicit commit
  target is given (not `--entire-history`): the one real commit immediately
  before and after each target is used to bound that target's randomized
  date, without itself being touched or appearing anywhere in the rewrite
- Timestamps must be in a format `git` understands (ISO 8601 with timezone
  recommended)
- The script runs `git filter-repo --force`, which skips filter-repo's own "is
  this repo safe to rewrite" check (normally it refuses to run outside of a
  fresh clone). This is safe here because the script always rewrites a
  new/backup branch first, but it does mean you're relying on that branch, not
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
