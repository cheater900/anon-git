"""--install-hook / --uninstall-hook: marker guard, core.hooksPath, and the
generated hook anonymizing each new commit."""

import os
import sys

import pytest
from conftest import branch_count, commit_author, git, run_cli

import anon_git

DEFAULT_AUTHOR = f"{anon_git.DEFAULT_NAME} <{anon_git.DEFAULT_EMAIL}>"
HOOK_FILE = ".git/hooks/post-commit"
FOREIGN_SCRIPT = "#!/bin/sh\necho foreign\n"


def write_foreign_script(path):
    with open(path, "w") as fh:
        fh.write(FOREIGN_SCRIPT)
    os.chmod(path, 0o755)


def read(path):
    with open(path) as fh:
        return fh.read()


def install_hook():
    result = run_cli("--install-hook")
    assert result.returncode == 0, result.stderr
    return result


def test_install_hook_creates_post_commit_hook(repo):
    install_hook()
    assert os.access(HOOK_FILE, os.X_OK)
    hook = read(HOOK_FILE)
    assert anon_git.HOOK_MARKER in hook
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
    assert read(HOOK_FILE) == FOREIGN_SCRIPT
    assert "already exists" in result.stderr


def test_install_hook_uses_core_hooks_path(repo):
    git("config", "--local", "core.hooksPath", ".husky")
    install_hook()
    assert os.access(".husky/post-commit", os.X_OK)
    assert not os.path.exists(HOOK_FILE)


def test_hook_anonymizes_partial_commit_keeps_changes(repo):
    install_hook()
    for name in ("staged.txt", "committed.txt"):
        with open(name, "w") as fh:
            fh.write(f"{name}\n")
    git("add", "staged.txt", "committed.txt")
    with open("file_1.txt", "a") as fh:
        fh.write("unstaged\n")
    git("commit", "-q", "-m", "Partial commit", "committed.txt")
    assert commit_author("HEAD") == DEFAULT_AUTHOR
    assert git("diff", "--name-only") == "file_1.txt"
    assert git("diff", "--cached", "--name-only") == "staged.txt"


def test_hook_survives_interpreter_path_with_metacharacters(repo, tmp_path, monkeypatch):
    odd_dir = tmp_path / 'odd "$dir`'
    odd_dir.mkdir()
    wrapper = odd_dir / "python"
    wrapper.write_text(f'#!/bin/sh\nexec "{sys.executable}" "$@"\n')
    wrapper.chmod(0o755)
    monkeypatch.setattr(anon_git.sys, "executable", str(wrapper))
    with pytest.raises(SystemExit) as exc:
        anon_git.install_hook()
    assert exc.value.code == 0
    git("commit", "-q", "--allow-empty", "-m", "Hooked commit")
    assert git("show", "-s", "--format=%an", "HEAD") == anon_git.DEFAULT_NAME


def test_hook_skips_rebase(repo):
    install_hook()
    result = git("rebase", "-q", "--force-rebase", "HEAD~1")
    assert "Error" not in result
    assert git("show", "-s", "--format=%an", "HEAD") != anon_git.DEFAULT_NAME
    assert not os.path.exists(".git/rebase-merge")


def test_install_hook_idempotent_over_own_hook(repo):
    install_hook()
    install_hook()
    assert os.access(HOOK_FILE, os.X_OK)


def test_hook_anonymizes_only_new_commit(repo, head_before):
    prior = git("show", "-s", "--pretty=fuller", "--date=iso", "HEAD")
    install_hook()
    for i in (21, 22):
        with open(f"file_{i}.txt", "w") as fh:
            fh.write(f"This is file {i}\n")
        git("add", f"file_{i}.txt")
        git("commit", "-q", "-m", f"Add file_{i}.txt")
    assert commit_author("HEAD") == DEFAULT_AUTHOR
    assert git("show", "-s", "--format=%ai", "HEAD") == anon_git.DEFAULT_DATE
    assert git("show", "-s", "--pretty=fuller", "--date=iso", head_before) == prior
    assert branch_count() == 1


def test_uninstall_hook_removes_own_hook(repo):
    install_hook()
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
    assert read(HOOK_FILE) == FOREIGN_SCRIPT
    assert "not installed by anon-git" in result.stderr


def test_install_flag_as_name_value_not_run(repo):
    # `--name --install-hook` uses the flag as a name; no hook gets written.
    result = run_cli("--dry-run", "--name", "--install-hook", "HEAD", env={"PAGER": "cat"})
    assert result.returncode == 0, result.stderr
    assert not os.path.exists(HOOK_FILE)


@pytest.mark.parametrize("flag", ["--install-hook", "--uninstall-hook"])
def test_hook_flags_refuse_symlinked_hook(repo, tmp_path, flag):
    # The link target carries the marker (like a copy of anon-git.sh does);
    # it must still be left alone.
    target = tmp_path / "shared-hook"
    target.write_text(f"#!/bin/sh\n{anon_git.HOOK_MARKER}\n")
    os.symlink(target, HOOK_FILE)
    result = run_cli(flag)
    assert result.returncode == 1
    assert target.read_text() == f"#!/bin/sh\n{anon_git.HOOK_MARKER}\n"
    assert os.path.islink(HOOK_FILE)


def test_install_hook_refuses_dangling_symlink(repo, tmp_path):
    target = tmp_path / "missing"
    os.symlink(target, HOOK_FILE)
    result = run_cli("--install-hook")
    assert result.returncode == 1
    assert not target.exists()
