# Ideas

Not planned; may never be added. Move an idea to `ROADMAP.md` once planned.

## anon-git.sh

- Line coverage for `anon-git.sh` via [kcov](https://github.com/SimonKagstrom/kcov),
  like `pytest-cov` gives the Python version. Add a `just coverage` recipe
  running `kcov --include-path=anon-git.sh coverage/ bats tests/`, HTML report
  in `coverage/index.html`. It would show functions, branches and error paths
  the bats suite never reaches. Limits: the embedded Python
  (`python_commit_callback`, `python_compute_random_dates`) runs in `python3`,
  so kcov sees each string as one line. Heredocs, `case` arms and multi-line
  commands are sometimes marked missed. The suite runs several times slower.
  Not installed by default (AUR `kcov`, `apt install kcov`).
