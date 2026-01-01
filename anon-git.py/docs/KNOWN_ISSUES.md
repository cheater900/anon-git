# Known issues

- Missing `git` binary shows a raw `FileNotFoundError` traceback. Message
  already names `git`; anon-git is useless without it anyway.
- `$PAGER` not found: `sh` prints its own error and `--dry-run` exits 0.
  Pager exit codes are not checked, since a pager quit early (`q` in `less`,
  `| head`) is normal.
- A commit timestamp beyond year 9999 raises in date parsing. `git fsck`
  rejects such commits (`badDate`), so real repos don't carry them.
- An unreadable or unwritable post-commit hook file raises a raw `OSError`.
- `clean_cache` raises if `.git/filter-repo` is a symlink (`shutil.rmtree`
  refuses symlinks, so nothing outside `.git` is deleted). Planting it needs
  write access to `.git`, which already allows running code via hooks.
- `--install-hook` checks the hook file, then writes it; a symlink swapped in
  between is followed. Same precondition: write access to `.git`.
- Identity trailers in commit messages (`Signed-off-by:`, `Co-authored-by:`)
  are not rewritten; only author/committer headers are.
