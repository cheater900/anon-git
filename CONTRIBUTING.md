# Contributing

## Prerequisites

- `bash` (the script and test suite are bash, not POSIX `sh`)
- [`git-filter-repo`](README.md#pre-requisites) — required to actually run `anon-git.sh`, and by the test suite
- `python3` — one test compiles the embedded commit-callback to check it's valid Python
- [`just`](https://github.com/casey/just) — runs the recipes below
- [`shellcheck`](https://www.shellcheck.net/) — used by `just lint`
- [`shfmt`](https://github.com/mvdan/sh) — used by `just format`
- `expect` — only needed for `just test-completion` (drives real bash/zsh/fish shells to check tab-completion)

## Workflow

```bash
just lint             # bash -n + shellcheck
just format           # shfmt -w, 4-space indent
just test             # tests/test-anon-git.sh + tests/test-anon-git-completion.sh
just test-completion  # just the completion tests
just all              # lint, format, test, test-completion, in order
```

Run `just lint`, `just format`, and `just test` before every commit — `.github/workflows/ci.yml` runs `just lint`, `just format-check` (fails if you forgot `just format`), and `just test` on every push/PR, so catching drift locally first saves a round-trip.

`tests/test-manually.sh` drops you into a disposable git repo with sample commits for interactive poking — useful when a failing test isn't enough context to see what's going on.

## Code style

- Match the existing style: 4-space indent (`shfmt -i 4`), `snake_case` function names, `local` for anything not meant to leak out of a function.
- `anon-git.sh` is organized as small, single-purpose functions (`parse_args`, `merge_args_with_defaults`, `reject_incompatible_options`, `backup_branch`, ...) called in sequence from `main()` at the bottom. Keep new logic in a similarly-scoped function rather than adding to `main()` directly or to an existing function's unrelated concern.
- One exception: the `python_commit_callback` string assignment must stay an unindented, top-level `python_commit_callback="..."` (opening) / `"` (closing) pair — `tests/test-anon-git.sh` locates it with a `sed` line-anchor regex to check it's valid Python. Don't nest it inside a function.
- Comments explain *why*, not *what* — see the existing header comments on each function for the expected tone.

## Adding or changing a flag

A new flag touches several places; grep for an existing similar flag (e.g. `--dry-run`) to find them all, but roughly:

1. `anon-git.sh`: `show_help()` (usage text), `list_flags()` (the `--_list-flags` source of truth), the `case` in `parse_args()`, and wherever the resulting value is consumed.
2. `completions/_anon-git.sh` (zsh) and `completions/anon-git.sh.fish` — hand-maintained, since they carry per-flag descriptions that `--_list-flags` can't express. `completions/anon-git.bash` needs no change; it calls `--_list-flags` dynamically.
3. `tests/test-anon-git-completion.sh`'s `test_completion_flags` will fail if zsh/fish drift from `--_list-flags` — that's the tripwire for step 2.
4. `README.md`: the `### Options` block, and an example if the flag isn't obvious from its description.
5. `tests/test-anon-git.sh`: at least one test exercising the new flag, plus incompatibility tests if it conflicts with existing flags (see `test_catch_incompatible` and its call sites in `main()`).
6. If the flag has an `ANON_GIT_*` environment variable equivalent, it needs a spot in `merge_args_with_defaults()`'s three-tier `${FLAG_ARG:-${ANON_GIT_X:-${DEFAULT_X}}}` fallback, a mention in the "Priority" list in both `show_help()` and `README.md`, and — if it can conflict with another option — a `*_set` computation in `reject_incompatible_options()` (see the comment at the top of that function for why it must run *before* `merge_args_with_defaults`, not after).

## Commit messages

This repo loosely follows Conventional Commits: `type: short imperative description`, lowercase, no trailing period. Types used so far: `feat`, `fix`, `docs`, `chore`, `refact`, `ci`, `break` (breaking change). Keep the subject line short; put any "why" in a body if it's not obvious from the diff.
