# Notes

## Layout decisions

- Split by concern, unlike `anon-git.sh`. The single-file rule applies only to
  the shell implementation. Module names follow the shell script's sections
  and functions, so the two can be compared side by side. See
  [`CONTRIBUTING.md`](../CONTRIBUTING.md#code-layout) for the module table.
- Data types live in `models.py`, not `types.py`, to avoid confusion with the
  stdlib `types` module.
- `__init__.py` only re-exports `main`. The console script points at
  `anon_git.cli:main`; `python -m anon_git` (used by the generated
  post-commit hook) goes through `__main__.py`.

## Tests

- `tests/helpers.py` holds shared constants and helpers; `tests/conftest.py`
  holds fixtures only.
- `tests/unit/` runs without git repos, `tests/integration/` runs `anon-git`
  against real repos (including parity with `anon-git.sh`), `tests/e2e/`
  drives real bash/zsh/fish sessions.
- pytest runs with `--import-mode=importlib` and `pythonpath = ["tests"]`, so
  test files in different folders may share a basename (e.g. both
  `unit/test_random_dates.py` and `integration/test_random_dates.py`).

## Configurable values

- No new settings were added. Default name, email and date are already
  configurable by flag, `git config anon-git.*` or `ANON_GIT_*` envvar; the
  pager by `$PAGER`.
- Branch suffixes (`_anonymized_`, `_backup_`) and the random suffix range
  stay fixed so branch names match what `anon-git.sh` creates.

## Open question

- `--dry-run` prints commit names, emails and messages verbatim, so a cloned
  repo can embed terminal escape sequences in them (`git log` behaves the
  same). Stripping control characters would make the preview differ from
  `anon-git.sh` output and break the preview parity test. Undecided.
