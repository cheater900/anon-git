# anon-git (Python)

Python implementation of anon-git: same options, messages and exit codes as
[`anon-git.sh`](../anon-git.sh/README.md). Rewrites run in-process through the
`git_filter_repo` library instead of spawning `git filter-repo`.

See [`anon-git.sh/README.md`](../anon-git.sh/README.md) for why and when to
anonymize, every option, and examples. This file only covers what differs.

## Install

Needs `git` and Python ≥ 3.10. [`uv`](https://docs.astral.sh/uv/) pulls in
`git-filter-repo` itself.

```bash
uv tool install ./anon-git.py                                                        # from a checkout
uv tool install 'git+<repo-url>#subdirectory=anon-git.py'                           # from git
```

Remove:

```bash
uv tool uninstall anon-git
```

## Differences from anon-git.sh

- Executable is `anon-git`, same name `anon-git.sh --install` uses. Whichever
  comes first on `$PATH` wins; `anon-git --version` does not tell them apart.
- `--install`, `--install-system` and `--uninstall` are gone: `uv tool
install`/`uv tool uninstall` replace them. Passing one exits 1 with that hint.
- The post-commit hook from `--install-hook` calls this exact install
  (`<python> -m anon_git`), not whatever `anon-git` is on `$PATH`.
- `--dry-run` pipes the preview to `$PAGER` on stdin; no preview file is
  written to disk.

## Shell completion

```bash
anon-git --print-completion bash > ~/.local/share/bash-completion/completions/anon-git
anon-git --print-completion zsh  > "${fpath[1]}/_anon-git"
anon-git --print-completion fish > ~/.config/fish/completions/anon-git.fish
```

## Development

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Design notes and open questions:
[`docs/NOTES.md`](docs/NOTES.md).

## License

[GPL-3.0](../LICENSE).
