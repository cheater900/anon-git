"""Flags governing how a run behaves: branching, backups, quiet/verbose,
partial dates, timezone stripping, confirmation."""

import os
import pty
import subprocess

import pytest
from conftest import (
    CLI,
    DEFAULT_AUTHOR,
    REWRITE,
    branch_count,
    commit,
    commit_author,
    commit_date,
    git,
    head,
    pick_random_index,
    run_cli,
    run_cli_without_tty,
)

import anon_git


def branches(pattern):
    return [b for b in git("branch", "--format=%(refname:short)").splitlines() if pattern in b]


def run_with_tty(keys, *args):
    """confirm() reads /dev/tty, not stdin, so a pipe can't answer it; a pty can."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(CLI[0], [*CLI, *args])
    os.write(fd, keys.encode())
    while True:
        try:
            if not os.read(fd, 1024):
                break
        except OSError:
            break
    return os.waitstatus_to_exitcode(os.waitpid(pid, 0)[1])


def test_current_branch_creates_backup(repo, head_before):
    result = run_cli("--no-confirm", "--current-branch", "--name", "Edsger Dijkstra", "HEAD")
    assert result.returncode == 0, result.stderr
    assert head() != head_before
    backups = branches("_backup_")
    assert len(backups) == 1
    assert git("rev-parse", backups[0]) == head_before


@pytest.mark.parametrize(
    "flag, kept", [("--keep-year", "%Y"), ("--keep-month", "%Y-%m"), ("--keep-day", "%Y-%m-%d")]
)
def test_keep_partial_keeps_fields(repo, flag, kept):
    target = f"HEAD~{pick_random_index()}"
    old = commit_date(target, kept)
    result = run_cli(*REWRITE, flag, target)
    assert result.returncode == 0, result.stderr
    assert commit_date(target, kept) == old
    # Everything finer than the kept unit is zeroed, at +0000.
    zeroed = {"%Y": "-01-01 00:00:00 +0000", "%Y-%m": "-01 00:00:00 +0000"}.get(
        kept, " 00:00:00 +0000"
    )
    assert git("show", "-s", "--date=iso", "--format=%ad", target) == old + zeroed
    assert git("show", "-s", "--date=iso", "--format=%cd", target) == old + zeroed


def test_keep_day_uses_local_calendar_date(repo):
    # 01:00 +0200 is the previous day in UTC; the kept day is the local one.
    commit("late night", date="2020-03-01 01:00:00 +0200")
    result = run_cli(*REWRITE, "--keep-day", "HEAD")
    assert result.returncode == 0, result.stderr
    assert git("show", "-s", "--date=iso", "--format=%ad", "HEAD") == "2020-03-01 00:00:00 +0000"


def test_creates_new_branch_by_default(repo, head_before):
    original_branch = git("branch", "--show-current")
    result = run_cli("--no-confirm", "--name", "John von Neumann", "HEAD")
    assert result.returncode == 0, result.stderr
    new_branch = git("branch", "--show-current")
    assert new_branch.startswith(f"{original_branch}_anonymized_")
    assert git("show", "-s", "--format=%an", new_branch) == "John von Neumann"
    git("switch", "-q", original_branch)
    assert head() == head_before


def test_no_backup_skips_backup_branch(repo, head_before):
    result = run_cli(*REWRITE, "--name", "Rosalind Franklin", "HEAD")
    assert result.returncode == 0, result.stderr
    assert head() != head_before
    assert branch_count() == 1
    assert "without backup" in result.stderr


def test_quiet_silences_informational_output(repo):
    result = run_cli("--no-confirm", "--quiet", "--name", "Ken Thompson", "HEAD")
    assert result.returncode == 0, result.stderr
    assert result.stdout == ""
    assert result.stderr == ""
    new_branch = branches("_anonymized_")[0]
    assert git("show", "-s", "--format=%an", new_branch) == "Ken Thompson"


def test_strip_timezone_alone_keeps_author_and_digits(repo):
    commit("Strip timezone alone test", date="1600000000 +0530")
    old_author = commit_author("HEAD")
    old_digits = commit_date("HEAD", "%Y-%m-%d %H:%M:%S")
    result = run_cli(*REWRITE, "--strip-timezone", "HEAD")
    assert result.returncode == 0, result.stderr
    assert commit_author("HEAD") == old_author
    assert commit_date("HEAD", "%Y-%m-%d %H:%M:%S") == old_digits
    assert commit_date("HEAD", "%z") == "+0000"


def test_strip_timezone_keep_date_relabels_each_offset(repo):
    env = {
        **os.environ,
        "GIT_AUTHOR_DATE": "1650000000 -0700",
        "GIT_COMMITTER_DATE": "1650000000 +0900",
    }
    subprocess.run(["git", "commit", "-q", "--allow-empty", "-m", "tz"], env=env, check=True)
    author_digits = commit_date("HEAD", "%Y-%m-%d %H:%M:%S")
    committer_digits = git("show", "-s", "--date=format:%Y-%m-%d %H:%M:%S", "--format=%cd")
    result = run_cli(*REWRITE, "--strip-timezone", "--keep-date", "HEAD")
    assert result.returncode == 0, result.stderr
    assert commit_author("HEAD") == DEFAULT_AUTHOR
    assert git("show", "-s", "--date=iso", "--format=%ad") == f"{author_digits} +0000"
    assert git("show", "-s", "--date=iso", "--format=%cd") == f"{committer_digits} +0000"


def test_strip_timezone_date_keeps_digits_forces_utc(repo):
    result = run_cli(*REWRITE, "--strip-timezone", "--date", "2025-06-15 14:20:00 +0300", "HEAD")
    assert result.returncode == 0, result.stderr
    assert git("show", "-s", "--date=iso", "--format=%ad", "HEAD") == "2025-06-15 14:20:00 +0000"


def test_strip_timezone_with_other_flag_resets_date(repo):
    result = run_cli(*REWRITE, "--strip-timezone", "--name", "Strip TZ Not Alone", "HEAD")
    assert result.returncode == 0, result.stderr
    assert commit_author("HEAD") == f"Strip TZ Not Alone <{anon_git.DEFAULT_EMAIL}>"
    assert git("show", "-s", "--date=iso", "--format=%ad", "HEAD") == anon_git.DEFAULT_DATE


def test_confirmation_n_aborts_y_proceeds(repo, head_before):
    assert run_with_tty("n", "--no-backup", "HEAD") == 1
    assert head() == head_before
    status = run_with_tty("y", "--no-backup", "--current-branch", "--name", "Alonzo Church", "HEAD")
    assert status == 0
    assert head() != head_before


def test_declined_confirmation_creates_no_branch(repo):
    branch = git("branch", "--show-current")
    run_with_tty("n", "HEAD")
    assert git("branch", "--show-current") == branch
    assert branch_count() == 1


def test_confirmation_without_terminal_hints_no_confirm(repo, head_before):
    result = run_cli_without_tty("--no-backup", "--current-branch", "HEAD")
    assert result.returncode == 1
    assert "--no-confirm" in result.stderr
    assert head() == head_before


def test_keep_flags_print_not_overwriting(repo):
    result = run_cli(*REWRITE, "--keep-user", "--keep-date", "HEAD")
    assert result.returncode == 0, result.stderr
    assert "Not overwriting user/email." in result.stdout
    assert "Not overwriting date." in result.stdout
    assert "Using identity:" not in result.stdout
