# Changelog

Condensed from git history, newest first, grouped by month.

## 2026-11

### Added

- `anon-git.py`: Python port. Same flags, messages and exit codes; runs
  `git_filter_repo` in-process. Install with `uv tool install`, so shell-only
  `--install`, `--install-system` and `--uninstall` are dropped. Parity tests
  compare its output with `anon-git.sh`.
- Docs: Python `DEVELOPMENT`, `NOTES`, `KNOWN_ISSUES`; top-level `IDEA`.

### Changed

- Shell implementation moved into `anon-git.sh/`.
- Random dates come from OS entropy, not Mersenne Twister.
- Scratch files created owner-only.
- CI runs Python lint, format and tests; `GITHUB_TOKEN` limited to read
  contents.

### Fixed

- `--random-*` dates stay in commit's local calendar unit; same-second
  commits keep order.
- zsh completion inserted `--date=`, `--name=`, `--email=`, which both parsers
  reject. Now completes value as next word.
- Post-commit hook refuses symlinked hook file and `core.hooksPath` shared via
  global or system config. Pops only stash it pushed. Explains missing
  install instead of failing every commit.
- `--dry-run` preview escapes terminal control chars in commit metadata.
- Detached HEAD with `--current-branch` reported before confirmation prompt.
- Python only: out-of-range timezone offsets (`+9999`) no longer crash. Ctrl-C
  and filter-repo failures reported without traceback. Many target commits
  resolved in one git call.

### Tests

- Python: unit, property (hypothesis), integration, and pexpect completion
  tests.
- Shell: isolated from user's git config, `ANON_GIT_*` and `PAGER`. Embedded
  Python compiled as bash expands it. Stricter checks on kept date fields,
  random-date units and rejection messages.

## 2026-10

### Fixed

- Input validated before confirmation and branch creation: date, identity
  chars, commits not reachable from HEAD, `ANON_GIT_ENTIREHISTORY=1` with a
  commit argument, repo without commits.
- `--dry-run` forwarded to filter-repo: preview never rewrites history, signed
  commits keep hash.
- Post-commit hook skips rebase, cherry-pick and revert; survives partial
  commits; honors `core.hooksPath`; shell-quotes script path.
- Higher-priority source owns whole identity or date option group instead of
  conflicting with lower one.
- Random dates bounded by real parent and child commits, not log-order
  neighbors.
- Annotated tags peeled to their commit.
- Confirmation read from terminal, not stdin.
- `--name --install` uses `--install` as name instead of installing.
- `--uninstall` refuses files that are not anon-git.
- `PAGER` runs through `sh`, so it may carry arguments.
- Completions installed alongside script.
- Safety errors and no-backup warning go to stderr.
- Smaller: non-UTF-8 metadata in dry-run, empty array under bash 3.2 `set -u`,
  filter-repo cache found from subdir, scratch files named before creation so
  kill trap removes them.

### Changed

- Test suite migrated to bats. Each test copies pristine template repo;
  random target replayable via `TEST_RANDOM_INDEX`.
- Bool options table-driven; date conflicts checked as one at-most-one rule.

## 2026-09

- `test_manually.sh` generates realistic-looking history.

## 2026-08

- Added `--random-time`, `--random-day`, `--random-month`: randomize finer date
  fields, keep relative commit order.

## 2008-10

Initial development.

### Added

- `anon-git.sh`: rewrites author and committer name, email and date of chosen
  commits or entire history via git-filter-repo. Merged from separate history
  and commit scripts.
- Flags: `--name`, `--email`, `--date`, `--keep-user`, `--keep-date`,
  `--keep-year`, `--keep-month`, `--keep-day`, `--strip-timezone`,
  `--no-confirm`, `--no-backup`, `--current-branch`, `--entire-history`,
  `--dry-run`, `--quiet`, `--verbose`.
- Rewrite goes to new branch by default. No arguments shows help (breaking
  change).
- Option sources: `ANON_GIT_*` envvars, repo `git config anon-git.*`
  (outranks envvars).
- bash, zsh and fish completion; `--install`, `--install-system`,
  `--uninstall`; `--install-hook`, `--uninstall-hook`.
- GPL-3.0 license, CONTRIBUTING, CI on Linux and macOS, `just` recipes.

### Fixed

- Timezone respected when keeping year, month or day.
- Stale filter-repo cache cleared before each run.
- Refuses dirty working tree; help still works there.
- Non-hash refs resolved; incompatible envvar combinations caught.
- Scratch files removed on any exit via EXIT trap.
