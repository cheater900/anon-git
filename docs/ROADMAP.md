# Roadmap

## Both implementations

- Read `anon-git.*` config from repo-local scope only (`git config --local`).
  Help and README call it "repo-local git config", but `git config --get`
  also reads `~/.gitconfig` and system config, so a global
  `anon-git.keepuser` silently applies to every repo. Change in
  `read_git_config` of both `anon-git.sh/anon-git.sh` and
  `anon-git.py/src/anon_git/options.py`, with a test per implementation.

## anon-git.sh

- Handle out-of-range commit timezone offsets (e.g. `+9999` in old repos).
  `parse_git_date` in `python_commit_callback` builds a `datetime.timezone`,
  which rejects offsets of 24h or more, so `--dry-run`, `--keep-*` and
  `--strip-timezone --keep-date` crash in filter-repo. Port the Python
  implementation's fix (`anon_git/utils/dates.py`: wall clock as epoch plus
  offset seconds, ISO offset built by hand), with a test.
