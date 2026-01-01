# Contributing

## Prerequisites

- [`uv`](https://docs.astral.sh/uv/): installs Python deps (`git-filter-repo`, pytest, hypothesis, pexpect, ruff)
- [`just`](https://github.com/casey/just): runs the recipes below
- `git`
- Optional: `bash`, `zsh`, `fish` for completion tests (skipped when missing); `ssh-keygen` for the signed-commit test

## Workflow

```bash
uv sync               # create .venv with dev deps
just lint             # ruff check
just format           # ruff format
just format-check     # ruff format --check (CI)
just test             # pytest
```

`.github/workflows/ci.yml` runs `just lint`, `just format-check` and
`just test` on Linux and macOS for every push and PR.

## Code layout

Unlike `anon-git.sh`, this implementation is split by concern. Module names
follow the shell script's sections and functions, so the two can be compared.

| Path                            | Purpose                                                              |
| ------------------------------- | -------------------------------------------------------------------- |
| `src/anon_git/cli.py`           | entry point: `main()`, `run()` calls every step in order             |
| `src/anon_git/constants.py`     | defaults, option/flag tables, names, error messages                  |
| `src/anon_git/templates.py`     | long text: `--help` output, post-commit hook script                  |
| `src/anon_git/models.py`        | data types: `Options`, `HistoryCommit`, `BucketMember`               |
| `src/anon_git/early_options.py` | options handled before repo checks: help, version, completion, hooks |
| `src/anon_git/hooks.py`         | `--install-hook` / `--uninstall-hook`                                |
| `src/anon_git/options.py`       | flags, git config, envvars resolved into `Options`                   |
| `src/anon_git/validation.py`    | checks run before anything is touched                                |
| `src/anon_git/interaction.py`   | informational output, confirmation prompt                            |
| `src/anon_git/branches.py`      | new/backup branch made before a rewrite                              |
| `src/anon_git/random_dates.py`  | `--random-*` order-keeping random dates                              |
| `src/anon_git/rewrite.py`       | filter-repo commit callback and in-process rewrite                   |
| `src/anon_git/preview.py`       | `--dry-run` preview and pager                                        |
| `src/anon_git/utils/`           | generic helpers: `git.py`, `dates.py`, `errors.py`                   |
| `src/anon_git/__main__.py`      | `python -m anon_git`, used by the generated post-commit hook         |
| `src/anon_git/completions/`     | bash/zsh/fish completion scripts served by `--print-completion`      |
| `tests/helpers.py`              | shared test constants, git wrappers, repo builders, CLI runners      |
| `tests/conftest.py`             | fixtures: template repo (20 commits), per-test copy, clean env       |
| `tests/unit/`                   | pure functions: option resolution, dates, random dates, flag tables  |
| `tests/integration/`            | `anon-git` run against real repos, plus parity with `anon-git.sh`    |
| `tests/e2e/`                    | real bash/zsh/fish sessions completing flags and refs via pexpect    |

Keep behavior in step with `anon-git.sh`. `tests/integration/test_parity.py`
runs both implementations on copies of one repo and compares `git log` and
stdout; it skips when `../anon-git.sh/anon-git.sh` is absent.

## Testing

```bash
uv run pytest tests/unit                                    # fast, no git repos
uv run pytest tests/integration/test_flags.py               # one file
uv run pytest -k keep_day                                   # tests whose name matches
TEST_RANDOM_INDEX=3 uv run pytest tests/integration/test_core.py   # replay a random HEAD~N target
```

Each test runs in its own copy of the template repo under pytest's
`tmp_path`, with `ANON_GIT_*`, `PAGER` and global/system git config cleared.

## Adding or changing a flag

1. `constants.py`: `FLAGS_BOOL` or `FLAGS_VALUE` (`FLAGS`, the
   `--_list-flags` list, derives from them), and `BOOLS`/`CONFIG_BOOLS`/
   `VALUE_OPTIONS` if it has an envvar or config equivalent. Then `HELP` in
   `templates.py`, `Options` in `models.py`, and the module that acts on it.
2. `src/anon_git/completions/_anon-git` and `anon-git.fish` (bash reads
   `--_list-flags` itself). `tests/unit/test_flag_tables.py` fails if they drift.
3. The same change in `anon-git.sh`, so the parity tests keep passing.
