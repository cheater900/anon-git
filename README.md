# ANON GIT

AnonGit anonymizes git commit authorship and timestamps.

It's meant for contributors to privacy, anti-surveillance, or
censorship-resistant open-source projects who don't want their commit
timestamps or email leaking information about them. Specifically, anon-git can:

- Anonymize entire git history
- Anonymize a single commit
- Anonymize multiple commits
- Anonymize commits filtered by author/committer, date range, or commit message
- Anonymize metadata using arbitrary values for user name, user email and date
- Anonymize just the timestamps (keep authorship) or the username (keep timestamp)
- Anonymize timestamps partially: preserve the commit year, month, or day while anonymizing the rest (hour & timezone)
- Anonymize timestamps by _randomizing_ month, day, or time instead of zeroing them (never the year), while keeping commits in their original relative order

## Implementations

| Path                           | Purpose                                                                               |
| ------------------------------ | ------------------------------------------------------------------------------------- |
| [`anon-git.sh/`](anon-git.sh/) | Bash implementation: one standalone script, easy to audit, copy and run. **Default.** |
| [`anon-git.py/`](anon-git.py/) | Python implementation: same options and behavior, installs via `uv tool install`.     |

Use `anon-git.sh` unless you need the Python version. See
[`anon-git.sh/README.md`](anon-git.sh/README.md) for usage, options and
install steps, and [`anon-git.py/README.md`](anon-git.py/README.md) for what
the Python version does differently.

## Docs

- [`docs/ROADMAP.md`](docs/ROADMAP.md): planned work
- [`docs/IDEA.md`](docs/IDEA.md): unplanned ideas
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md): change history

## License

[GPL-3.0](LICENSE).
