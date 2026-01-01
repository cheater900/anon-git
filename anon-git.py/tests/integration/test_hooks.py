"""--install-hook / --uninstall-hook and the generated hook."""

import os
import subprocess
import sys
from pathlib import Path

import pytest
from helpers import (
    DEFAULT_AUTHOR,
    PAGER_CAT,
    append_line,
    branch_count,
    commit_author,
    git,
    new_repo,
    run_cli,
)

from anon_git.constants import DEFAULT_DATE, DEFAULT_NAME, HOOK_MARKER
from anon_git.hooks import install_hook

HOOK_FILE = ".git/hooks/post-commit"


FOREIGN_SCRIPT = "#!/bin/sh\necho foreign\n"


def write_foreign_script(path):
    with open(path, "w") as fh:
        fh.write(FOREIGN_SCRIPT)
    os.chmod(path, 0o755)


def run_install_hook():
    result = run_cli("--install-hook")
    assert result.returncode == 0, result.stderr
    return result


def test_install_hook_creates_post_commit_hook(repo):
    run_install_hook()
    assert os.access(HOOK_FILE, os.X_OK)
    hook = Path(HOOK_FILE).read_text()
    assert HOOK_MARKER in hook
    assert sys.executable in hook
    # Without --no-backup a backup branch would accumulate per commit.
    assert "--no-backup" in hook
    assert "--quiet" in hook


@pytest.mark.parametrize("flag", ["--install-hook", "--uninstall-hook"])
def test_hook_flags_require_git_repo(outside_repo, flag):
    result = run_cli(flag)
    assert result.returncode == 1
    assert "git repository" in result.stderr


def test_install_hook_keeps_foreign_hook(repo):
    write_foreign_script(HOOK_FILE)
    result = run_cli("--install-hook")
    assert result.returncode == 1
    assert Path(HOOK_FILE).read_text() == FOREIGN_SCRIPT
    assert "already exists" in result.stderr


def test_install_hook_uses_core_hooks_path(repo):
    git("config", "--local", "core.hooksPath", ".husky")
    run_install_hook()
    assert os.access(".husky/post-commit", os.X_OK)
    assert not os.path.exists(HOOK_FILE)


def test_install_hook_refuses_global_hooks_path(repo, tmp_path):
    shared = tmp_path / "shared-hooks"
    git("config", "--global", "core.hooksPath", str(shared))
    result = run_cli("--install-hook")
    assert result.returncode == 1
    assert "global config" in result.stderr
    assert not shared.exists()


def test_hook_anonymizes_partial_commit_keeps_changes(repo):
    run_install_hook()
    for name in ("staged.txt", "committed.txt"):
        with open(name, "w") as fh:
            fh.write(f"{name}\n")
    git("add", "staged.txt", "committed.txt")
    append_line("file_1.txt", "unstaged")
    git("commit", "-q", "-m", "Partial commit", "committed.txt")
    assert commit_author("HEAD") == DEFAULT_AUTHOR
    assert git("diff", "--name-only") == "file_1.txt"
    assert git("diff", "--cached", "--name-only") == "staged.txt"


def test_hook_keeps_unrelated_stash_when_push_saves_nothing(repo, tmp_path):
    sub = new_repo(tmp_path / "sub")
    git("-C", str(sub), "commit", "-q", "--allow-empty", "-m", "sub")
    git("-c", "protocol.file.allow=always", "submodule", "add", "-q", str(sub), "sub")
    git("commit", "-q", "-m", "Add submodule")
    append_line("file_1.txt", "stashed")
    git("stash", "push", "-q")
    run_install_hook()
    # Dirty submodule content: diff-files reports it, stash push saves nothing.
    (repo / "sub" / "new.txt").write_text("new\n")
    git("-C", "sub", "add", "new.txt")
    git("commit", "-q", "--allow-empty", "-m", "Commit with dirty submodule")
    assert git("stash", "list").count("\n") == 0
    assert git("stash", "list") != ""
    assert git("diff", "--name-only", "--", "file_1.txt") == ""


def test_hook_survives_interpreter_path_with_metacharacters(repo, tmp_path, monkeypatch):
    odd_dir = tmp_path / 'odd "$dir`'
    odd_dir.mkdir()
    wrapper = odd_dir / "python"
    wrapper.write_text(f'#!/bin/sh\nexec "{sys.executable}" "$@"\n')
    wrapper.chmod(0o755)
    monkeypatch.setattr(sys, "executable", str(wrapper))
    with pytest.raises(SystemExit) as exc:
        install_hook()
    assert exc.value.code == 0
    git("commit", "-q", "--allow-empty", "-m", "Hooked commit")
    assert git("show", "-s", "--format=%an", "HEAD") == DEFAULT_NAME


def test_hook_skips_rebase(repo):
    run_install_hook()
    result = git("rebase", "-q", "--force-rebase", "HEAD~1")
    assert "Error" not in result
    assert git("show", "-s", "--format=%an", "HEAD") != DEFAULT_NAME
    assert not os.path.exists(".git/rebase-merge")


def test_install_hook_idempotent_over_own_hook(repo):
    run_install_hook()
    run_install_hook()
    assert os.access(HOOK_FILE, os.X_OK)


def test_hook_anonymizes_only_new_commit(repo, head_before):
    prior = git("show", "-s", "--pretty=fuller", "--date=iso", "HEAD")
    run_install_hook()
    for i in (21, 22):
        with open(f"file_{i}.txt", "w") as fh:
            fh.write(f"This is file {i}\n")
        git("add", f"file_{i}.txt")
        git("commit", "-q", "-m", f"Add file_{i}.txt")
    assert commit_author("HEAD") == DEFAULT_AUTHOR
    assert git("show", "-s", "--format=%ai", "HEAD") == DEFAULT_DATE
    assert git("show", "-s", "--pretty=fuller", "--date=iso", head_before) == prior
    assert branch_count() == 1


def test_uninstall_hook_removes_own_hook(repo):
    run_install_hook()
    result = run_cli("--uninstall-hook")
    assert result.returncode == 0, result.stderr
    assert not os.path.exists(HOOK_FILE)
    assert "Removed post-commit hook" in result.stdout


def test_uninstall_hook_without_hook_succeeds(repo):
    result = run_cli("--uninstall-hook")
    assert result.returncode == 0, result.stderr
    assert "No post-commit hook installed" in result.stdout


def test_uninstall_hook_keeps_foreign_hook(repo):
    write_foreign_script(HOOK_FILE)
    result = run_cli("--uninstall-hook")
    assert result.returncode == 1
    assert Path(HOOK_FILE).read_text() == FOREIGN_SCRIPT
    assert "not installed by anon-git" in result.stderr


def test_install_flag_as_name_value_not_run(repo):
    # `--name --install-hook` uses the flag as a name; no hook gets written.
    result = run_cli("--dry-run", "--name", "--install-hook", "HEAD", env=PAGER_CAT)
    assert result.returncode == 0, result.stderr
    assert not os.path.exists(HOOK_FILE)


@pytest.mark.parametrize("flag", ["--install-hook", "--uninstall-hook"])
def test_hook_flags_refuse_symlinked_hook(repo, tmp_path, flag):
    # The link target carries the marker (like a copy of anon-git.sh does);
    # it must still be left alone.
    target = tmp_path / "shared-hook"
    target.write_text(f"#!/bin/sh\n{HOOK_MARKER}\n")
    os.symlink(target, HOOK_FILE)
    result = run_cli(flag)
    assert result.returncode == 1
    assert target.read_text() == f"#!/bin/sh\n{HOOK_MARKER}\n"
    assert os.path.islink(HOOK_FILE)


def test_install_hook_refuses_dangling_symlink(repo, tmp_path):
    target = tmp_path / "missing"
    os.symlink(target, HOOK_FILE)
    result = run_cli("--install-hook")
    assert result.returncode == 1
    assert not target.exists()


def test_hook_with_missing_install_explains_and_lets_commit_through(repo, monkeypatch):
    monkeypatch.setattr(sys, "executable", "/nonexistent/python")
    with pytest.raises(SystemExit):
        install_hook()
    result = subprocess.run(
        ["git", "commit", "-q", "--allow-empty", "-m", "after uninstall"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "/nonexistent/python missing, not anonymized" in result.stderr
    assert git("log", "-1", "--format=%s") == "after uninstall"
