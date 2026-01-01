# Roadmap

## Both implementations

- Read `anon-git.*` config from repo-local scope only (`git config --local`).
  Help and README call it "repo-local git config", but `git config --get`
  also reads `~/.gitconfig` and system config, so a global
  `anon-git.keepuser` silently applies to every repo. Change in
  `read_git_config` of both `anon-git.sh/anon-git.sh` and
  `anon-git.py/src/anon_git/options.py`, with a test per implementation.
