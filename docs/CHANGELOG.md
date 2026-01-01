# Changelog

Derived from git history, newest first.

## 2026-11-04

- test(sh): compile embedded Python as bash expands it, not raw script text
- fix(sh): escape control chars in --dry-run preview
- fix(sh): refuse --install-hook into shared core.hooksPath
- fix(sh): refuse symlinked post-commit hook instead of writing through it
- fix(sh): make post-commit hook explain a moved script instead of failing
- fix(sh): hook pops only stash it pushed
- fix(sh): check detached HEAD before prompting
- test(py): drop conflict and dry-run cases duplicated elsewhere
- test(py): cover --print-completion output, quiet no-backup warning, git failure report
- fix: complete zsh value flags as separate word, not --flag=
- test(sh): isolate tests from user's git config, ANON_GIT_*, PAGER

## 2026-11-02

- docs(py): move CONTRIBUTING to docs/DEVELOPMENT, add KNOWN_ISSUES
- test(py): share append_line, checkout_raw_commit, PAGER_CAT, EMPTY_TREE helpers
- refactor(py): move verbose flag messages to constants, name short-hash helper
- refactor(py): move hook script header into templates, name hook file mode
- refactor(py): move raw git date formatting into utils/dates, name time units
- fix(py): hook pops only stash it pushed
- fix(py): handle out-of-range commit timezone offsets
- fix(py): escape control chars in --dry-run preview
- fix(py): refuse --install-hook into shared core.hooksPath
- docs(py): add NOTES with layout decisions and open dry-run question
- docs(py): document module and test layout
- refactor(py): split anon_git into modules by concern, tests into unit/integration/e2e
- docs(py): describe derived flag list in CONTRIBUTING
- test(py): share DEFAULT_AUTHOR, REWRITE, CLI and no-tty runner via conftest
- refactor(py): check detached HEAD before prompting, name preview and tty helpers
- refactor(py): split random-date bucketing into named steps, gather date helpers
- refactor(py): group constants and types at top, derive flag list, share git config helper
- fix(py): report Ctrl-C and bare filter-repo exit codes without traceback or stray number
- fix(py): make post-commit hook explain a removed install instead of failing
- fix(py): resolve and check many target commits in one git call each
- fix(py): refuse symlinked post-commit hook instead of writing through it
- ci: run anon-git.py lint, format, tests; document Python implementation
- test: add anon-git.py regression tests, parity tests against anon-git.sh
- test: cover anon-git.py post-commit hook install, run, uninstall
- test: cover anon-git.py random dates with unit, property, end-to-end tests
- feat: port anon-git rewrite to Python, calling git_filter_repo in-process
- feat: add anon-git.py skeleton with early options, completions
- refactor: move shell implementation into anon-git.sh/
- fix: keep --random-* dates inside commit's local calendar unit and same-second order
- fix: draw random commit dates from OS entropy, not Mersenne Twister
- fix: create scratch files owner-only, not world-readable
- ci: restrict GITHUB_TOKEN to contents read

## 2026-10-29

- docs: describe test_helper contents in CONTRIBUTING
- refactor: move single-file test helpers next to their tests
- refactor: add commit_author, history_authors, DEFAULT_AUTHOR test helpers
- refactor: share hook path, foreign-script fixture in install tests
- refactor: name epoch, time-unit constants in random_dates tests
- refactor: share test constants, new_repo, cd_outside_repo via test_helper
- test: migrate suite to bats

## 2026-10-27

- fix: validate input before rewrite, harden startup checks

## 2026-10-15

- build: stop just all from running completion tests twice
- test: read DEFAULT_* by sourcing script instead of grep/sed
- test: lint/format test_manually.sh, draw author and subject independently
- test: source lib/common.sh in completion test, share print_summary
- test: cover run and hook install in linked worktree
- test: create temp dirs under $TMPDIR instead of hardcoded /tmp
- fix: name scratch files before creating them; make kill-trap test deterministic
- test: report random target index on failure, allow replay via TEST_RANDOM_INDEX
- test: restore pristine repo after each test to stop cascading failures
- test: require conflict message in test_catch_incompatible
- test: match completion flags whole instead of by substring
- test: type ref prefix in completion test, clear line with Ctrl-U
- refactor: localize ref, compare dryrun as string, write preview with context manager
- docs: clarify quiet/verbose conflict comment
- refactor: replace pairwise date conflict checks with single at-most-one check
- refactor: table-drive bool options via BOOLS/CONFIG_BOOLS and indirect expansion
- fix: report repository without commits instead of raw git error
- fix: print safety errors and no-backup warning to stderr
- fix: shell-quote script path embedded in post-commit hook
- fix: let higher-priority source own identity/date option group instead of conflicting
- fix: refuse to uninstall files that are not anon-git
- fix: append to COMMITS_ARG with += to avoid empty-array expansion under bash 3.2 set -u
- fix: skip flag values when scanning for early options
- fix: bound random dates by parent/child commits, not log-order neighbors
- docs: list identity leaks outside author/committer metadata
- fix: decode dry-run metadata with errors=replace to survive non-UTF-8 bytes
- fix: declare RANDOM_DATES global so dates file loads once per run
- fix: reject target commits not reachable from HEAD
- fix: resolve filter-repo cache via git rev-parse --git-dir
- fix: install completions alongside script, bind them to installed anon-git name
- fix: run PAGER through sh so it may carry arguments
- fix: validate date before confirmation and branch creation
- fix: read confirmation from terminal, replace xargs examples with single invocation
- fix: make post-commit hook skip sequences, survive partial commits, honor core.hooksPath
- fix: forward --dry-run to filter-repo so preview never rewrites history
- fix: reject ANON_GIT_ENTIREHISTORY=1 combined with commit argument
- fix: peel annotated tag targets to their commit
- test: shorten test labels

## 2026-09-03

- test: make test_manually.sh generate realistic-looking history

## 2026-08-31

- docs: trim comments in anon-git.sh and tests/

## 2026-08-30

- feat: add --random-time/--random-day/--random-month flags

## 2008-10-31

- fix: correct --keep-user/--keep-date verbose output
- docs: cleanup readme
- test: rename test scripts to snake_case
- docs: document script exit codes (0/1)
- feat: add --uninstall and --uninstall-hook flags
- test: split test-anon-git.sh into shared lib + per-category case files
- feat: add --strip-timezone flag
- test: cover merge-commit handling in single-commit mode
- fix: warn on --install-hook when core.hooksPath is set
- fix: repo-local config now outranks ANON_GIT_* envvars
- docs: clean up README
- feat: support repo-local config via git config anon-git.*
- chore: add just sync-docs recipe to derive README options from --help
- fix: clean up scratch files on any exit path via an EXIT trap
- chore: add just recipe to run CI locally via act
- ci: add macos-latest to the CI matrix
- feat: add --quiet/--verbose flags to silence routine output
- chore: fix outdated comment references
- ci: add github workflow
- chore: add contributing with dev instructions
- chore: add license
- refact: group related code into own procedure calls
- fix: catch incompatible combination of some envvars
- ci: add test coverage for env vars
- docs: document missing ANON_GIT_* vars
- feat: add option to install a post-commit hook
- feat: add option to local install and system-wide install
- fix: show help not working inside dirty repo
- feat: add shell completion
- ci: add test for python commit callback syntax
- ci: pretty-print test outputs
- break: new default behavior is to show help
- ci: enhance script for manual testing
- ci: improve test coverage
- chore: improve test coverage
- docs: improve README
- chore: add more tests
- chore: improve input validation and security checks
- feat: split preview of author and date in dryrun
- fix: do not run script if there is uncommitted changes
- chore: update script helper flag
- docs: update readme
- feat: show commit message in dry-run
- feat: upon --dry-run, dismiss backup branch and confirmation prompt
- feat: add dryrun flag
- docs: improve readme
- docs: update readme
- feat: create new branch by default instead of using current one
- docs: update readme
- docs: update readme
- feat: validate a chunk of arbitrary commits
- fiz: force UTC timezone when running git filter-repo
- fix: git filter-repo not working sometimes due to cached metadata
- fix: not taking tz into account when keeping year, month or day
- feat: unify anonymization scripts into a single one
- feat: add flags to keep year, month, or day + refactor code
- refact: commit anonymization script
- chore: validate incompatible flags
- feat: add `--no-backup` flag to stop creating backup branch
- ci: update tests
- fix: not using rev-parse for non-hash refs in commit anonymization script
- ci: add manual test
- chore: change default user email to a non-valid domain to avoid clashes
- docs: add roadmap
- docs: add README
- refact: unit tests
- ci: improve unit tests summary
- ci: add test cases for commit anonymization script
- feat: add flags to keep date, keep user, and skip prompt to commit anonymization script
- refact: commit anonymization script
- ci: add more test cases for history anonymization script
- feat: add flag to skip confirmation prompt and refactor history anonymization script
- feat: validate args in history anonymization script
- ci: validate other commits not affected in commit anonymization script
- fix: wrong logic in commit anonymization script
- fix: wrong logic in unit test for commit anonymization
- ci: test arguments in history anonymization script
- fix: wrong logic in commit anonymization script
- ci: add test for commit anonymization script
- ci: verify fields individually (date, name, email) in unit tests for anonymization script
- fix: wrong script path in unit tests for history anonymization
- refact: commit anonymization script
- refact: history anonymization script and tests
- fix: bug in git history anonymization script
- ci: add test for git history anonymization script
- feat: add flags to override env vars
- feat: add flag to show help
- feat: add script to anonymize specific commit
- feat: add script to anonymize git history
