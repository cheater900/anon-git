# anon-git (Python)

Python implementation of anon-git. It takes the same options as
`anon-git.sh`; see the [top-level README](../README.md) for every option,
examples and notes.

## Install

Needs `git` and Python >= 3.10. [`uv`](https://docs.astral.sh/uv/) pulls in
`git-filter-repo` itself.

Install from a checkout, run from the repo root:

```sh
uv tool install ./anon-git.py
```

Install from git:

```sh
uv tool install 'git+https://github.com/radioactively/anon-git#subdirectory=anon-git.py'
```

Uninstall:

```sh
uv tool uninstall anon-git
```

## Usage

Run `anon-git` with the same options and arguments as `anon-git.sh`:

```sh
anon-git --dry-run HEAD~2
```

- The executable is `anon-git`, the same name `anon-git.sh --install` uses.
  Whichever comes first on `$PATH` wins; `anon-git --version` does not tell
  them apart.
- `--install`, `--install-system` and `--uninstall` don't exist here: use
  `uv tool install`/`uv tool uninstall`. Passing one exits 1 with that hint.
- The post-commit hook from `--install-hook` calls this exact install
  (`<python> -m anon_git`), not whatever `anon-git` is on `$PATH`.
- `--dry-run` pipes the preview to `$PAGER` on stdin and writes no preview
  file to disk. Control characters in commit metadata show as `\xNN`.

## Shell completion

Install bash completion:

```sh
anon-git --print-completion bash > ~/.local/share/bash-completion/completions/anon-git
```

Install zsh completion, into a directory already in `$fpath`:

```sh
anon-git --print-completion zsh > "${fpath[1]}/_anon-git"
```

Install fish completion:

```sh
anon-git --print-completion fish > ~/.config/fish/completions/anon-git.fish
```
