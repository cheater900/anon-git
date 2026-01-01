# ANON GIT

[![CI](https://github.com/radioactively/anon-git/actions/workflows/ci.yml/badge.svg)](https://github.com/radioactively/anon-git/actions/workflows/ci.yml)

AnonGit is a script to **anonymize** git commit authorship and timestamp.

Useful when you want to contribute to privacy-sensitive, anti-surveillance, or censorship-resistant open-source projects **without leaking information** from your commit **timestamps** and **email**.

The script can:

- Anonymize entire git history
- Anonymize single commit
- Anonymize multiple commits
- Anonymize commits filtered by author/commiter, date range, or commit message
- Anonymize metadata using arbitrary values for user name, user email and date
- Anonymize just the timestamps (keep authorship) or the username (keep timestamp)
- Anonymize the timestamps partially: preserve commit year or month or day while anonymizing other information (hour & timezone)

## Why anonymize Git commits?

Even when using Tor and throwaway GitHub accounts, your **commit timestamps** can still deanonymize you over time:

- timezone may be linked to location
- time of commit may be linked to work and routine schedules
- day of the week may be linked workdays and religious/cultural practices (rest days)
- day and month may be linked to holidays, festivals and cultural/religious events
- cadence between commits may leak information about commit frequency and coding pace, revealing personal development patterns (some developers commit frequently, while others code more before committing)

Many privacy & freedom-oriented projects would prefer contributors to avoid leaking personal information:

- **Internet anonymity**
  - Tor Browser
  - I2P
  - FreeNet
- **Private finace**
  - Monero
  - Bisq
  - Samourai Wallet
  - CoinJoin tools
- **Mobile OS**
  - GrapheneOS
  - CalyxOS
- **Communication protocols**
  - Simplex
  - Matrix
  - Briar
  - XMPP
- **Social network**
  - Nostr
  - Mastodon
  - Scuttlebutt
- **Privacy guides**
  - KYC Not Me (kycnot.me)
  - Digital Defense (digitaldefense.io)

(The list above is not meant to be a compilation of privacy tools, but merely examples of projects whose contributors may wish to stay anonymous).

## Use cases

- AnonGit **only removes metadata** — it does **not** hide IP addresses, contribution timing correlations, writing style, code patterns, etc.
- AnonGit is most useful to anonymize timestamp metadata along with anonymous email and name. If you leak personal data via public forges (GitHub, GitLab, Codeberg, SourceHut) the script becomes useless.
- AnonGit most useful on branches you have full control of the branch
- AnonGit most useful for commits that have not been published to remote branches and forges
- If the repository is public and has been cloned/forked, then the script may become useless since the old copies of the git history were not rewritten

## Pre-requisites

The script is based on `git filter-repo` (much faster & safer than `filter-branch`).

**You must have `git-filter-repo` installed:**

```bash
# Debian/Ubuntu
sudo apt install git-filter-repo

# Fedora
sudo dnf install git-filter-repo

# macOS (Homebrew)
brew install git-filter-repo

# or via pip (any platform)
pip install git-filter-repo
```

## Usage

This repository contains a script called `anon-git.sh`, which relies upon `git
filter-repo`. Download it or copy-paste into a file. Execute it from inside
a git repository either directly `./anon-git.sh` or from your `$PATH` (see
[Installing anon-git.sh](#installing-anon-gitsh) to put it on your `$PATH`).

**For safety, the script creates a backup branch before rewriting history.**

Rewrite **one commit** (author, committer, dates).

```bash
./anon-git.sh [OPTIONS] [commits]
```

**Default behavior**: shows the help message. A commit target (or `--entire-history`) is
required — pass `HEAD` explicitly to anonymize the last commit.

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
  --entire-history                Rewrite entire history and not a single commit
  --current-branch                Overwrite current branch and not a copy of it
  --dry-run                       Show history changes without rewriting them
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
3. Hardcoded defaults

`--verbose` has no `ANON_GIT_VERBOSE` environment variable equivalent; it's a CLI-only override that forces informational output back on for one run, regardless of what set `ANON_GIT_QUIET` (flag, envvar, or a repo-local quiet config).

> [!WARNING]
> `--name`, `--email` and `--date` (and their `ANON_GIT_*` environment variable
> equivalents) are not meant to carry untrusted input — don't wire user-controlled
> values (e.g. from CI variables or another service) into them.

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

### Installing anon-git.sh

Instead of running `./anon-git.sh` from a local checkout, you can copy it onto your `$PATH`:

```bash
# Copy to ~/.local/bin and/or ~/.bin, whichever of the two already exist
# (neither is created for you). Warns if the directory it copied to isn't
# on $PATH.
./anon-git.sh --install

# System-wide install to /usr/bin, via sudo
./anon-git.sh --install-system
```

> [!NOTE]
> `--install` only copies into `~/.local/bin` and/or `~/.bin` if they already
> exist; if neither does, create one first (e.g. `mkdir -p ~/.local/bin`) and
> re-run it. `--install-system` requires `sudo` and is not covered by the test
> suite (it isn't run as root, and isn't mocked either), so verify it manually.

To automatically anonymize every new commit in the *current* repository, install a post-commit hook instead:

```bash
./anon-git.sh --install-hook
```

This writes `.git/hooks/post-commit`, which anonymizes only the commit you just made (`HEAD`), using `--current-branch --no-backup --quiet` so it rewrites in place rather than creating a new branch (or a backup branch) after every commit, and doesn't print "Anonymizing commit(s): ..." / "Done." on top of git's own commit summary — the hook fires on *every* commit, so a per-commit backup branch (or message) would otherwise accumulate/spam forever; `git reflog`/`git reset` still recover the pre-hook state if something goes wrong. Re-running `--install-hook` safely refreshes a hook it created, but refuses to overwrite a pre-existing hook it didn't write (remove or back that one up first). See [Using anon-git as a post-commit hook](#using-anon-git-as-a-post-commit-hook) below to customize the flags it runs with instead.

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

### Using anon-git as a post-commit hook

`./anon-git.sh --install-hook` (see above) covers this in one step. The manual setup below is only needed if you want to customize the flags/environment variables the hook runs with, or understand what `--install-hook` generates.

You can automatically anonymize **every new commit right after** you run `git commit` by installing the script as a **post-commit** hook. This rewrites only the just-created commit (HEAD) without affecting earlier history.

1. Go to your repository:
   ```bash
   cd your-repo
   ```

2. Create or edit the post-commit hook:
   ```bash
   mkdir -p .git/hooks
   nano .git/hooks/post-commit
   ```

3. Paste the following content (adjust paths/flags as needed):
   ```bash
   #!/usr/bin/env bash
   #
   # .git/hooks/post-commit - Automatically anonymize the just-made commit
   #

   # Exit on any error
   set -e

   # Path to your anonymize script (adjust if needed)
   SCRIPT="$PWD/anon-git.sh"

   if [ ! -x "$SCRIPT" ]; then
       echo "Error: anon-git.sh not found or not executable" >&2
       exit 1
   fi

   # Optional: skip anonymization for merge commits, fixup commits, etc.
   # (uncomment and adjust if desired)
   # if git log -1 --pretty=%s | grep -iqE '^(Merge|fixup|squash)'; then
   #     echo "Skipping anonymization for merge/fixup commit"
   #     exit 0
   # fi

   # Run anonymization on HEAD (the commit we just created)
   #
   # IMPORTANT: Customize flags/environment variables here before running it!
   # --no-backup: this hook runs on every commit, so a per-commit backup
   # branch would accumulate forever; drop it if you'd rather have one.
   # --quiet: silences the per-commit "Anonymizing commit(s): ..." / "Done."
   # output; drop it (or pass --verbose) if you want that back.
   "$SCRIPT" --no-confirm --no-backup --quiet --current-branch HEAD

   # Optional: show what changed
   echo "Last commit anonymized:"
   git --no-pager log -1 --pretty=fuller

   exit 0
   ```

4. Make it executable:
   ```bash
   chmod +x .git/hooks/post-commit
   ```

Now every `git commit` automatically triggers anonymization of that commit's author name, email, and dates (using your script's defaults, environment variables, or flags you hard-code in the hook).

## Important notes

- The script, by default, uses a new branch instead of rewriting the current. It can be changed via `--current-branch` flag.
- The script, by default, creates a backup branch when using `--current-branch` flag.
- You can recover with `git reflog` / `git reset` if something goes wrong even if you use `--current-branch` and `--no-backup`
- If you pushed before using the script, you'll need `git push --force-with-lease` afterward (dangerous on shared branches!)
- The flags `--keep-user` and `--keep-date` are useful for partial anonymization
- Timestamps must be in a format `git` understands (ISO 8601 with timezone recommended)
- The script runs `git filter-repo --force`, which skips filter-repo's own "is this repo safe to rewrite" check (normally it refuses to run outside of a fresh clone). This is safe here because the script always rewrites a new/backup branch first — but it does mean you're relying on that branch, not on filter-repo, to protect your other branches/history.
- Rewriting a commit invalidates any GPG signature on it (same as `git filter-branch`/`git rebase`); re-sign afterward if you sign your commits
- To temporarily disable the hook run `chmod -x .git/hooks/post-commit`
- Consider using environment variables (`export ANON_GIT_NAME="..."` etc.) instead of hard-coding flags in the hook
- Consider squashing commits or using merge requests from anonymous remotes

## Testing

```bash
./tests/test-anon-git.sh
```

Spins up a disposable git repository in `/tmp`, runs the script against it through a range of flags and edge cases (defaults, `--keep-*`, `--dry-run`, `--entire-history`, `--current-branch`, invalid input, incompatible combinations — flags, `ANON_GIT_*` envvars, and mixes of both — the uncommitted-changes guard, ...), and prints a pass/fail summary. It cleans up the temp repo on exit.

`tests/test-manually.sh` instead just creates a disposable repo with sample commits and drops you into it, for manual/interactive poking at the script.

`--install` and `--install-hook` are covered (`--install` with `$HOME` pointed at a disposable directory, so it never touches your real `~/.local/bin` or `~/.bin`; `--install-hook` against disposable repos separate from the suite's own, so an installed hook can't fire during later tests). `--install-system` is not: it needs `sudo` and a real `/usr/bin`, and the suite intentionally doesn't run as root or mock it — verify it manually.

A [`justfile`](justfile) wraps the day-to-day commands (`just test`, `just lint`, `just format`, `just test-completion`, `just all`); see [CONTRIBUTING.md](CONTRIBUTING.md) for the full development workflow.

## License

[GPL-3.0](LICENSE).
