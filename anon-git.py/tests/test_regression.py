"""Pinned-down edge cases (merges, detached HEAD, odd repos, injection,
filter-repo cache) and parity with the shell implementation."""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from conftest import commit, commit_author, git, head, new_repo, run_cli

import anon_git

REWRITE = ("--no-confirm", "--no-backup", "--current-branch")
SHELL_SCRIPT = Path(__file__).resolve().parents[2] / "anon-git.sh" / "anon-git.sh"


def merge_side_branch(before_merge=None):
    original_branch = git("branch", "--show-current")
    git("switch", "-q", "--create", "feature")
    Path("feature_file.txt").write_text("feature work\n")
    git("add", "feature_file.txt")
    git("commit", "-q", "-m", "Add feature file")
    git("switch", "-q", original_branch)
    if before_merge:
        before_merge()
    git("merge", "-q", "--no-ff", "-m", "Merge feature branch", "feature")


def add_main_ancestor():
    Path("main_ancestor_file.txt").write_text("main ancestor work\n")
    git("add", "main_ancestor_file.txt")
    git("commit", "-q", "-m", "Add main ancestor file")


def test_rejects_detached_head_with_current_branch(repo, head_before):
    git("checkout", "-q", "--detach", "HEAD")
    result = run_cli(*REWRITE, "HEAD")
    assert result.returncode == 1
    assert "detached" in result.stderr
    assert head() == head_before


def test_detached_head_new_branch_named_after_commit(repo):
    git("checkout", "-q", "--detach", "HEAD")
    short = git("rev-parse", "--short", "HEAD")
    result = run_cli("--no-confirm", "HEAD")
    assert result.returncode == 0, result.stderr
    assert git("branch", "--show-current").startswith(f"detached-{short}_anonymized_")


def test_entire_history_handles_merge_commits(repo):
    merge_side_branch()
    result = run_cli(*REWRITE, "--entire-history", "--name", "Merge Tester")
    assert result.returncode == 0, result.stderr
    assert set(git("log", "--format=%an").splitlines()) == {"Merge Tester"}


def test_merge_commit_by_hash_keeps_topology(repo):
    merge_side_branch()
    parents = git("show", "-s", "--format=%P", "HEAD")
    parent_author = commit_author("HEAD^1")
    tree = git("show", "-s", "--format=%T", "HEAD")
    result = run_cli(*REWRITE, "--name", "Merge Single", "--email", "m@example.com", "HEAD")
    assert result.returncode == 0, result.stderr
    assert commit_author("HEAD") == "Merge Single <m@example.com>"
    assert git("show", "-s", "--format=%P", "HEAD") == parents
    assert git("show", "-s", "--format=%T", "HEAD") == tree
    assert commit_author("HEAD^1") == parent_author
    git("fsck", "--full")


def test_merge_ancestor_rewrite_cascades_parent_pointer(repo):
    merge_side_branch(add_main_ancestor)
    other_parent = git("rev-parse", "HEAD^2")
    tree = git("show", "-s", "--format=%T", "HEAD")
    result = run_cli(*REWRITE, "--name", "Ancestor Tester", "--email", "a@example.com", "HEAD^1")
    assert result.returncode == 0, result.stderr
    assert commit_author("HEAD^1") == "Ancestor Tester <a@example.com>"
    assert len(git("show", "-s", "--format=%P", "HEAD").split()) == 2
    assert git("rev-parse", "HEAD^2") == other_parent
    assert git("show", "-s", "--format=%T", "HEAD") == tree
    git("fsck", "--full")


def test_outside_git_repo_fails_cleanly(outside_repo):
    result = run_cli("--no-confirm")
    assert result.returncode == 1
    assert "git repository" in result.stderr


def test_bare_repo_fails_with_work_tree_message(repo, tmp_path):
    bare = tmp_path / "bare"
    git("clone", "-q", "--bare", str(repo), str(bare))
    result = run_cli("--no-confirm", "HEAD", cwd=bare)
    assert result.returncode == 1
    assert "not a bare repository" in result.stderr


def test_unset_home_keeps_startup_working(outside_repo):
    env = {k: v for k, v in os.environ.items() if k != "HOME"}
    result = subprocess.run(
        [sys.executable, "-m", "anon_git", "--version"], env=env, capture_output=True
    )
    assert result.returncode == 0


def test_unborn_head_fails_with_clear_message(tmp_path, monkeypatch):
    new_repo(tmp_path / "unborn")
    monkeypatch.chdir(tmp_path / "unborn")
    result = run_cli("--no-confirm", "HEAD")
    assert result.returncode == 1
    assert "no commits yet" in result.stderr


def test_linked_worktree_run_and_hook_install(repo, tmp_path):
    worktree = tmp_path / "wt"
    git("worktree", "add", "-q", "-b", "wt_branch", str(worktree))
    result = run_cli(*REWRITE, "--name", "Worktree Run", "HEAD", cwd=worktree)
    assert result.returncode == 0, result.stderr
    assert git("-C", str(worktree), "show", "-s", "--format=%an", "HEAD") == "Worktree Run"
    assert run_cli("--install-hook", cwd=worktree).returncode == 0
    assert os.access(repo / ".git/hooks/post-commit", os.X_OK)


def test_filter_repo_cache_cleared_from_subdir(repo):
    marker = Path(git("rev-parse", "--absolute-git-dir")) / "filter-repo" / "stale_marker"
    marker.parent.mkdir(parents=True)
    marker.touch()
    (repo / "subdir").mkdir()
    result = run_cli("--dry-run", "HEAD", env={"PAGER": "cat"}, cwd=repo / "subdir")
    assert result.returncode == 0, result.stderr
    assert not marker.exists()


def test_annotated_tag_target_rewritten(repo):
    git("tag", "-a", "-m", "Annotated tag", "annotated", "HEAD")
    result = run_cli(*REWRITE, "--name", "Tag Target", "annotated")
    assert result.returncode == 0, result.stderr
    assert git("show", "-s", "--format=%an", "HEAD") == "Tag Target"


@pytest.mark.skipif(shutil.which("ssh-keygen") is None, reason="ssh-keygen not installed")
def test_dry_run_keeps_signed_commit_hash(tmp_path, monkeypatch):
    path = new_repo(tmp_path / "signed")
    monkeypatch.chdir(path)
    subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", "signing_key"], check=True)
    git("config", "--local", "gpg.format", "ssh")
    git("config", "--local", "user.signingkey", str(path / "signing_key"))
    with open(".git/info/exclude", "a") as fh:
        fh.write("signing_key*\n")
    git("commit", "-q", "-S", "--allow-empty", "-m", "Signed commit")
    before = head()
    result = run_cli("--no-confirm", "--dry-run", "HEAD", env={"PAGER": "cat"})
    assert result.returncode == 0, result.stderr
    assert head() == before


def test_dry_run_handles_non_utf8_metadata(tmp_path, monkeypatch):
    path = new_repo(tmp_path / "non_utf8")
    monkeypatch.chdir(path)
    raw = (
        b"tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\n"
        b"author Bad \xff Name <bad@example.com> 1700000000 +0000\n"
        b"committer Bad \xff Name <bad@example.com> 1700000000 +0000\n\nMessage \xfe\n"
    )
    sha = (
        subprocess.run(
            ["git", "hash-object", "-t", "commit", "-w", "--stdin"],
            input=raw,
            capture_output=True,
            check=True,
        )
        .stdout.decode()
        .strip()
    )
    git("reset", "-q", "--hard", sha)
    result = run_cli("--dry-run", "HEAD", env={"PAGER": "cat"})
    assert result.returncode == 0, result.stderr
    assert "AuthorDate:" in result.stdout


def test_consecutive_runs_avoid_filter_repo_cache_bug(repo):
    assert run_cli(*REWRITE, "--name", "First Run", "HEAD").returncode == 0
    result = run_cli(*REWRITE, "--name", "Second Run", "HEAD")
    assert result.returncode == 0, result.stderr
    assert git("show", "-s", "--format=%an", "HEAD") == "Second Run"


@pytest.mark.parametrize(
    "flag, fmt, prefix, suffix",
    [
        ("--email", "%ae", "evil", "@example.com"),
        ("--name", "%an", "Evil", ""),
    ],
)
def test_shell_metacharacters_not_executed(repo, tmp_path, flag, fmt, prefix, suffix):
    marker = tmp_path / "injection_marker"
    payload = f"{prefix}'\"; touch {marker}; `touch {marker}`; $(touch {marker}) #{suffix}"
    result = run_cli(*REWRITE, flag, payload, "HEAD")
    assert result.returncode == 0, result.stderr
    assert git("show", "-s", f"--format={fmt}", "HEAD") == payload
    assert not marker.exists()


def test_filter_repo_failure_reports_log(repo, head_before, monkeypatch, capfd):
    # A commit missing from the random-date table aborts the rewrite with a
    # clear message, not a traceback.
    monkeypatch.setattr(anon_git, "compute_random_dates", lambda *args, **kwargs: {})
    with pytest.raises(SystemExit) as exc:
        anon_git.run([*REWRITE, "--random-day", "HEAD"])
    assert exc.value.code == 1
    stderr = capfd.readouterr().err
    assert "Error: git filter-repo failed:" in stderr
    assert "no precomputed random date" in stderr
    assert head() == head_before


def test_no_scratch_files_left_behind(repo, tmp_path):
    scratch = tmp_path / "scratch"
    scratch.mkdir()
    result = run_cli(
        "--dry-run",
        "--random-day",
        "--entire-history",
        env={"PAGER": "cat", "TMPDIR": str(scratch)},
    )
    assert result.returncode == 0, result.stderr
    assert list(scratch.iterdir()) == []


# ── parity with anon-git.sh ──────────────────────────────────────────────

PARITY_LOG = "--format=%an%x00%ae%x00%ad%x00%cn%x00%ce%x00%cd%x00%s"
PARITY_CASES = [
    ["HEAD"],
    ["--name", "Ada", "--email", "ada@example.com", "HEAD~2", "HEAD~5"],
    ["--date", "2020-02-03 04:05:06 -0300", "HEAD~1"],
    ["--date", "2025-06-15T14:20:00Z", "--keep-user", "HEAD"],
    ["--keep-date", "--entire-history"],
    ["--keep-year", "HEAD~3"],
    ["--keep-month", "--entire-history"],
    ["--keep-day", "HEAD", "HEAD~4"],
    ["--strip-timezone", "HEAD~1"],
    ["--strip-timezone", "--keep-date", "--entire-history"],
    ["--strip-timezone", "--date", "2025-06-15 14:20:00 +0300", "HEAD"],
]


@pytest.fixture
def mixed_tz_repo(tmp_path):
    path = new_repo(tmp_path / "mixed")
    offsets = ["+0000", "+0530", "-0700", "+0200", "-0330", "+1400"]
    for i in range(8):
        commit(
            f"commit {i}", date=f"{1600000000 + i * 40000} {offsets[i % len(offsets)]}", cwd=path
        )
    return path


@pytest.mark.skipif(not SHELL_SCRIPT.exists(), reason="anon-git.sh not checked out")
@pytest.mark.parametrize("args", PARITY_CASES)
def test_parity_with_shell_implementation(mixed_tz_repo, tmp_path, args):
    shell_repo = tmp_path / "shell"
    python_repo = tmp_path / "python"
    shutil.copytree(mixed_tz_repo, shell_repo)
    shutil.copytree(mixed_tz_repo, python_repo)
    shell = subprocess.run(
        [str(SHELL_SCRIPT), *REWRITE, *args], cwd=shell_repo, capture_output=True, text=True
    )
    python = run_cli(*REWRITE, *args, cwd=python_repo)
    assert shell.returncode == 0, shell.stderr
    assert python.returncode == 0, python.stderr
    assert python.stdout == shell.stdout
    assert git("-C", str(python_repo), "log", PARITY_LOG) == git(
        "-C", str(shell_repo), "log", PARITY_LOG
    )


@pytest.mark.skipif(not SHELL_SCRIPT.exists(), reason="anon-git.sh not checked out")
@pytest.mark.parametrize("args", [["--dry-run", "--entire-history"], ["--dry-run", "HEAD~2"]])
def test_dry_run_preview_parity_with_shell(mixed_tz_repo, args):
    env = {**os.environ, "PAGER": "cat"}
    shell = subprocess.run(
        [str(SHELL_SCRIPT), *args], cwd=mixed_tz_repo, env=env, capture_output=True, text=True
    )
    python = run_cli(*args, env={"PAGER": "cat"}, cwd=mixed_tz_repo)
    assert shell.returncode == 0, shell.stderr
    assert python.stdout == shell.stdout


@pytest.mark.skipif(not SHELL_SCRIPT.exists(), reason="anon-git.sh not checked out")
def test_help_matches_shell_minus_install_flags():
    shell = subprocess.run([str(SHELL_SCRIPT), "--help"], capture_output=True, text=True).stdout
    shell_flags = set(
        subprocess.run(
            [str(SHELL_SCRIPT), "--_list-flags"], capture_output=True, text=True
        ).stdout.split()
    )
    assert shell_flags - set(anon_git.FLAGS_DROPPED) == set(anon_git.FLAGS)
    assert "Usage:" in shell


def test_filter_repo_bare_exit_code_not_printed(repo, monkeypatch, capfd):
    def exit_with_code(*_args, **_kwargs):
        raise SystemExit(3)

    monkeypatch.setattr(anon_git.fr.RepoFilter, "run", exit_with_code)
    with pytest.raises(SystemExit) as exc:
        anon_git.run([*REWRITE, "HEAD"])
    assert exc.value.code == 1
    stderr = capfd.readouterr().err
    assert stderr.rstrip().endswith("Error: git filter-repo failed:")


def test_ctrl_c_reports_interrupt_not_traceback(repo, monkeypatch, capsys):
    def interrupt(_opts):
        raise KeyboardInterrupt

    monkeypatch.setattr(anon_git, "confirm", interrupt)
    with pytest.raises(SystemExit) as exc:
        anon_git.main(["HEAD"])
    assert exc.value.code == 1
    assert "Interrupted" in capsys.readouterr().err
