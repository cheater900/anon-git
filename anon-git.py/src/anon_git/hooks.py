"""--install-hook / --uninstall-hook: the post-commit hook."""

import os
import shlex
import sys

from anon_git.constants import HOOK_MARKER
from anon_git.templates import HOOK_BODY
from anon_git.utils.errors import fail
from anon_git.utils.git import git, git_ok


# The post-commit hook path git actually runs. `--git-path hooks` honors
# core.hooksPath and resolves to the common dir in a linked worktree; a
# relative result is relative to the top-level dir.
def hook_file_path():
    top = git("rev-parse", "--show-toplevel")
    hooks_dir = git("-C", top, "rev-parse", "--git-path", "hooks")
    return os.path.join(top, hooks_dir, "post-commit")


# A symlink is never ours: writing through it would overwrite its target
# (e.g. a copy of anon-git.sh, which contains the marker text).
def hook_is_ours(hook_file):
    if os.path.islink(hook_file) or not os.path.isfile(hook_file):
        return False
    with open(hook_file, encoding="utf-8", errors="replace") as fh:
        return HOOK_MARKER in fh.read()


def require_work_tree_for(flag):
    if not git_ok("rev-parse", "--show-toplevel"):
        fail(f"Error: {flag} must be run inside a git repository.")


# --install-hook: re-anonymizes HEAD in place after every commit, with
# --no-backup (would accumulate one branch per commit) and --quiet. Calls
# this exact interpreter, never whatever `anon-git` is first on $PATH.
def install_hook():
    require_work_tree_for("--install-hook")
    hook_file = hook_file_path()
    if os.path.lexists(hook_file) and not hook_is_ours(hook_file):
        fail(
            f"Error: {hook_file} already exists and was not installed by anon-git.\n"
            "  Remove or back it up first, then re-run --install-hook."
        )
    os.makedirs(os.path.dirname(hook_file), exist_ok=True)
    with open(hook_file, "w", encoding="utf-8") as fh:
        fh.write(
            "#!/usr/bin/env bash\n"
            f"{HOOK_MARKER}\n"
            "#\n"
            "# Anonymizes the just-created commit (HEAD) after every `git commit`.\n"
            "# --no-backup avoids accumulating a branch per commit (use `git reflog`/\n"
            "# `git reset` to recover). --quiet drops the per-commit output; pass\n"
            "# --verbose to bring it back. Regenerate with: anon-git --install-hook\n"
            "\n"
            "set -e\n"
            f"anon_git=({shlex.quote(sys.executable)} -m anon_git)\n"
            f"{HOOK_BODY}"
        )
    os.chmod(hook_file, 0o755)
    print(f"Installed post-commit hook: {hook_file}")
    sys.exit(0)


# --uninstall-hook: guarded by the same HOOK_MARKER check install_hook uses,
# so a hook this tool didn't create is never touched.
def uninstall_hook():
    require_work_tree_for("--uninstall-hook")
    hook_file = hook_file_path()
    if not os.path.lexists(hook_file):
        print(f"No post-commit hook installed at {hook_file}")
        sys.exit(0)
    if not hook_is_ours(hook_file):
        fail(
            f"Error: {hook_file} was not installed by anon-git; refusing to remove it.\n"
            "  Remove it yourself if you are sure."
        )
    os.remove(hook_file)
    print(f"Removed post-commit hook: {hook_file}")
    sys.exit(0)
