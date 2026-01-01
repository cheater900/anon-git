# ANON GIT

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
a git repository either directly `./anon-git.sh` or from your `$PATH`.

**For safety, the script creates a backup branch before rewriting history.**

Rewrite **one commit** (author, committer, dates).

```bash
./anon-git.sh [OPTIONS] [commits]
```

**Default behavior**: anonymizes `HEAD`

### Options

```
  -h, --help                      Show this help message and exit
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
```

**Priority order** (highest to lowest):

1. Command-line flags
2. Environment variables (`ANON_GIT_DATE`, `ANON_GIT_NAME`, `ANON_GIT_EMAIL`, `ANON_GIT_KEEPUSER`, `ANON_GIT_KEEPDATE`, `ANON_GIT_KEEPYEAR`, `ANON_GIT_KEEPMONTH`, `ANON_GIT_KEEPDAY`)
3. Hardcoded defaults

> [!WARNING]
> `--name`, `--email` and `--date` (and their `ANON_GIT_*` environment variable
> equivalents) are not meant to carry untrusted input — don't wire user-controlled
> values (e.g. from CI variables or another service) into them.

### Examples

```bash
# Anonymize current HEAD with defaults
./anon-git.sh

# Anonymize two commits ago
./anon-git.sh HEAD~2

# Explicit values + specific commit
./anon-git.sh --date "2024-01-01 00:00:00 +0000" \
                          --name "Jane Doe" \
                          --email "jane@anon.dev" \
                          8ddf55a

# Keep real name/email, only change date
./anon-git.sh --keep-user --date "2025-06-15T14:20:00Z"

# Preview what would change before actually rewriting anything
./anon-git.sh --dry-run HEAD~2

# Anonymize the whole repo before its first push to a remote
./anon-git.sh --entire-history --current-branch

# Keep the commit's day (and month/year) but scrub the time-of-day and timezone
./anon-git.sh --keep-day HEAD~2

# Use environment variables instead of flags (handy for hooks/CI)
ANON_GIT_NAME="Anon" ANON_GIT_EMAIL="anon@localhost" ./anon-git.sh --keep-date
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

### Using anonymize-git-commit as a post-commit hook

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
   "$SCRIPT" --no-confirm --current-branch HEAD

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

Spins up a disposable git repository in `/tmp`, runs the script against it through a range of flags and edge cases (defaults, `--keep-*`, `--dry-run`, `--entire-history`, `--current-branch`, invalid input, incompatible flags, the uncommitted-changes guard, ...), and prints a pass/fail summary. It cleans up the temp repo on exit.

`tests/test-manually.sh` instead just creates a disposable repo with sample commits and drops you into it, for manual/interactive poking at the script.
