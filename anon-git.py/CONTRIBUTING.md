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

| Path                        | Purpose                                                                                            |
| --------------------------- | -------------------------------------------------------------------------------------------------- |
| `src/anon_git/__init__.py`  | the whole tool, one file; function names mirror `anon-git.sh`                                      |
| `src/anon_git/__main__.py`  | `python -m anon_git`, used by the generated post-commit hook                                       |
| `src/anon_git/completions/` | bash/zsh/fish completion scripts served by `--print-completion`                                    |
| `tests/conftest.py`         | template repo (20 commits), per-test copy, `run_cli` and git helpers                               |
| `tests/test_*.py`           | tests by area: help, completion, options, validation, core, flags, random_dates, hooks, regression |

Keep behavior in step with `anon-git.sh`. `tests/test_regression.py` runs
both implementations on copies of one repo and compares `git log` and stdout;
it skips when `../anon-git.sh/anon-git.sh` is absent.

## Testing

```bash
uv run pytest tests/test_flags.py               # one file
uv run pytest -k keep_day                       # tests whose name matches
TEST_RANDOM_INDEX=3 uv run pytest tests/test_core.py   # replay a random HEAD~N target
```

Each test runs in its own copy of the template repo under pytest's
`tmp_path`, with `ANON_GIT_*`, `PAGER` and global/system git config cleared.

## Adding or changing a flag

1. `src/anon_git/__init__.py`: `FLAGS`, `FLAGS_BOOL`/`FLAGS_VALUE`, `HELP`,
   and wherever the value is consumed (`Options`, `BOOLS`/`CONFIG_BOOLS` if it
   has an envvar/config equivalent).
2. `src/anon_git/completions/_anon-git` and `anon-git.fish` (bash reads
   `--_list-flags` itself). `tests/test_completion.py` fails if they drift.
3. The same change in `anon-git.sh`, so the parity tests keep passing.
