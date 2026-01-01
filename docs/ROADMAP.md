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
`src/anon_git/__init__.py`, `completions/`, pytest suite in `tests/` with
`conftest.py` fixtures (20-commit template repo, `run_cli`, `commit_author`,
`commit_date`, `history_authors`), `justfile` (lint, format, format-check,
test).

Code for every step below is in `anon-git.py/src/anon_git/__init__.py`;
remaining steps port the matching bats tests to pytest:

9. CI, docs: `python` job in `.github/workflows/ci.yml`
   (`working-directory: anon-git.py`, `astral-sh/setup-uv`), READMEs.
