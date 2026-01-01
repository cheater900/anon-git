"""Same results as anon-git.sh on copies of one repo."""

import os
import shutil
import subprocess

import pytest
from helpers import PAGER_CAT, REWRITE, SHELL_SCRIPT, commit, git, new_repo, run_cli

from anon_git.constants import FLAGS, FLAGS_DROPPED

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
    python = run_cli(*args, env=PAGER_CAT, cwd=mixed_tz_repo)
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
    assert shell_flags - set(FLAGS_DROPPED) == set(FLAGS)
    assert "Usage:" in shell
