# Contributing

## Prerequisites

- `bash` (the script and test suite are bash, not POSIX `sh`)
- [`git-filter-repo`](README.md#pre-requisites) — required to actually run `anon-git.sh`, and by the test suite
- `python3` — one test compiles the embedded commit-callback to check it's valid Python
- [`bats-core`](https://github.com/bats-core/bats-core) ≥ 1.5 with [`bats-support`](https://github.com/bats-core/bats-support), [`bats-assert`](https://github.com/bats-core/bats-assert), [`bats-file`](https://github.com/bats-core/bats-file) — runs the test suite; libs are found via `BATS_LIB_PATH` (default `/usr/lib/bats`, e.g. Arch `pacman -S bats bats-support bats-assert bats-file`)
- [`just`](https://github.com/casey/just) — runs the recipes below
- [`shellcheck`](https://www.shellcheck.net/) — used by `just lint`
- [`shfmt`](https://github.com/mvdan/sh) — used by `just format`
- `expect` — only needed for the completion tests in `just test`/`just test-completion` (drives real bash/zsh/fish shells to check tab-completion)

## Workflow

```bash
just lint             # bash -n + shellcheck
just format           # shfmt -w, 4-space indent
just test             # bats tests/
just test-completion  # bats tests/completion.bats
just all              # lint, format, test, in order
just sync-docs        # regenerate README's ### Options block from `anon-git.sh --help`
```

Run `just lint`, `just format`, and `just test` before every commit — `.github/workflows/ci.yml` runs `just lint`, `just format-check` (fails if you forgot `just format`), and `just test` on every push/PR, so catching drift locally first saves a round-trip.

If you change `show_help()`'s `Options:` section (new/renamed/reworded flag), run `just sync-docs` too — it regenerates README's `### Options` code block from `anon-git.sh --help` so the two can't silently drift apart, and stages the result like any other edit.

`tests/test_manually.sh` drops you into a disposable git repo with sample commits for interactive poking — useful when a failing test isn't enough context to see what's going on.

## Code style

- Match the existing style: 4-space indent (`shfmt -i 4`), `snake_case` function names, `local` for anything not meant to leak out of a function.
- `anon-git.sh` is organized as small, single-purpose functions (`parse_args`, `merge_args_with_defaults`, `reject_incompatible_options`, `backup_branch`, ...) called in sequence from `main()` at the bottom. Keep new logic in a similarly-scoped function rather than adding to `main()` directly or to an existing function's unrelated concern.
- One exception: the `python_commit_callback` string assignment must stay an unindented, top-level `python_commit_callback="..."` (opening) / `"` (closing) pair — `tests/test_helper.bash`'s `extract_script_block` locates it with a `sed` line-anchor regex to check it's valid Python. Don't nest it inside a function.
- Comments explain *why*, not *what* — see the existing header comments on each function for the expected tone.

## Adding or changing a flag

A new flag touches several places; grep for an existing similar flag (e.g. `--dry-run`) to find them all, but roughly:

1. `anon-git.sh`: `show_help()` (usage text), `list_flags()` (the
   `--_list-flags` source of truth), the `case` in `parse_args()`, and wherever
   the resulting value is consumed.
2. `completions/_anon-git.sh` (zsh) and `completions/anon-git.sh.fish` —
   hand-maintained, since they carry per-flag descriptions that `--_list-flags`
   can't express. `completions/anon-git.bash` needs no change; it calls
   `--_list-flags` dynamically.
3. `tests/completion.bats`'s "zsh/fish completions list all flags" will fail if
   zsh/fish drift from `--_list-flags` — that's the tripwire for step 2.
4. `README.md`: the `### Options` block, and an example if the flag isn't
   obvious from its description.
5. `tests/*.bats`: at least one `@test` exercising the new flag, plus
   incompatibility tests if it conflicts with existing flags (see
   `assert_incompatible` and its call sites in `tests/validation.bats`).
6. If the flag has an `ANON_GIT_*` environment variable equivalent, it needs a
   spot in `merge_args_with_defaults()`'s three-tier
   `${FLAG_ARG:-${ANON_GIT_X:-${DEFAULT_X}}}` fallback (four-tier —
   `${FLAG_ARG:-${GITCONFIG_X:-${ANON_GIT_X:-${DEFAULT_X}}}}` — if it also has
   a repo-local `git config anon-git.*` equivalent; config outranks the
   envvar, see `read_git_config()`), a mention in the "Priority" list in both
   `show_help()` and `README.md`, and — if it can conflict with another
   option — a `*_set` computation in `reject_incompatible_options()` (see the
   comment at the top of that function for why it must run *before*
   `merge_args_with_defaults`, not after).

## Testing

```bash
bats tests/                                   # whole suite (= just test)
bats tests/flags.bats                         # one file
bats -f 'keep-date' tests/                    # tests whose name matches
TEST_RANDOM_INDEX=3 bats tests/core.bats      # replay a random HEAD~N target
```

| Path                     | Purpose                                                                                                          |
|--------------------------|------------------------------------------------------------------------------------------------------------------|
| `tests/setup_suite.bash` | once per run: builds the template repo (20 commits), reads the script's `DEFAULT_*` values                       |
| `tests/test_helper.bash` | loaded by every file: per-test fresh repo copy in `setup()`, shared assert helpers                               |
| `tests/*.bats`           | tests by category: core, validation, config_priority, flags, help, install, random_dates, regression, completion |

Every test runs in its own copy of the template repo under `$BATS_TEST_TMPDIR`,
so no test sees another's leftovers; bats deletes it afterwards. Bats prints a
test's output only when it fails, including the `target HEAD~N` line from tests
that pick a random commit.

The test `tests/test_manually.sh` creates a disposable repo with sample commits
and drops you into it, for manual/interactive poking at the script.

## Commit messages

This repo loosely follows Conventional Commits: `type: short imperative
description`, lowercase, no trailing period. Types used so far: `feat`, `fix`,
`docs`, `chore`, `refact`, `ci`, `break` (breaking change). Keep the subject
line short; put any "why" in a body if it's not obvious from the diff.
