# Roadmap

## Python implementation (`anon-git.py/`)

Port `anon-git.sh` to Python with the same options and behavior. Call the
`git_filter_repo` library directly (`FilteringOptions.parse_args`,
`RepoFilter(args, commit_callback=...).run()`) instead of spawning
`git filter-repo`. Other git calls go through `subprocess.run([...])` with
list args, never a shell.

Decisions:

- Executable `anon-git`, same as the shell version; first on `$PATH` wins.
- Install from local path or git URL only: `uv tool install ./anon-git.py`
  or `git+…#subdirectory=anon-git.py`. No PyPI.
- `--install`, `--install-system`, `--uninstall` dropped: exit 1 pointing to
  `uv tool install`/`uv tool uninstall`. `--install-hook`/`--uninstall-hook`
  stay.

Layout: `pyproject.toml` (hatchling, dep `git-filter-repo`, script
`anon-git = "anon_git:main"`, dev group pytest/hypothesis/ruff), single module
`src/anon_git.py`, `completions/`, pytest suite in `tests/` with
`conftest.py` fixtures (20-commit template repo, `run_cli`, `commit_author`,
`commit_date`, `history_authors`), `justfile` (lint, format, format-check,
test).

Steps, each porting matching bats tests to pytest:

1. Skeleton, early options: `--help`, `--version`, `--_list-flags`,
   `--print-completion`, help on no target. Port `help.bats`, `completion.bats`.
2. Options resolution: flags > `git config anon-git.*` > `ANON_GIT_*` >
   defaults, group ownership, incompatibility checks, `--strip-timezone`
   alone, `--verbose` over quiet, bool validation. Pure functions. Port
   `config_priority.bats`, flag parts of `validation.bats`; parametrize every
   incompatible pair.
3. Safety, target validation: work tree, HEAD, clean tree, filter-repo
   importable, `^{commit}` resolution, reachability, date parsing (ISO,
   `T…Z`, not pre-1970), identity (`<`, `>`, newline). Port rest of
   `validation.bats`; hypothesis round-trip for `parse_target_date`.
4. Rewrite core: confirm via `/dev/tty`, new/backup branch, cache clean,
   commit callback as real function. `--keep-*`, `--strip-timezone`,
   `--entire-history`. Port `core.bats`, `flags.bats`.
5. Dry run: 0600 temp preview file, `$PAGER`, `--dry-run` to filter-repo.
   Assert refs untouched.
6. Randomized timestamps: `compute_random_dates(history, targets,
   granularity, entire, rng)`, same semantics (local-calendar buckets,
   topo tie-break, clamped fallback, `SystemRandom`), injectable `rng`. Port
   `random_dates.bats`; hypothesis properties over random histories (mixed
   offsets, ties, merges, bucket edges): pick stays in local calendar unit,
   and between parent/child anchors absent timezone conflict.
7. Hooks: `--install-hook`/`--uninstall-hook`, marker, `core.hooksPath`;
   dropped install flags. Port hook parts of `install.bats`.
8. Regression parity: port `regression.bats`; parity test running both
   implementations on same repo, comparing `git log` metadata.
9. CI, docs: `python` job in `.github/workflows/ci.yml`
   (`working-directory: anon-git.py`, `astral-sh/setup-uv`), READMEs.
