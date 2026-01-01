"""--random-* end to end through git-filter-repo."""

import pytest
from helpers import (
    EPOCH_2019,
    EPOCH_2020,
    REWRITE,
    SECONDS_PER_DAY,
    commit,
    commit_date,
    git,
    new_repo,
    pick_random_index,
    run_cli,
)


@pytest.mark.parametrize(
    "flag, kept",
    [("--random-time", "%Y-%m-%d"), ("--random-day", "%Y-%m"), ("--random-month", "%Y")],
)
def test_random_flag_keeps_calendar_unit(repo, flag, kept):
    # Never asserts a change: randomness could reproduce the original.
    target = f"HEAD~{pick_random_index()}"
    old = commit_date(target, kept)
    result = run_cli(*REWRITE, flag, target)
    assert result.returncode == 0, result.stderr
    assert commit_date(target, kept) == old
    assert commit_date(target, "%z") == "+0000"


def test_random_day_multiple_targets_keep_month(repo):
    old = commit_date("HEAD~1", "%Y-%m"), commit_date("HEAD~3", "%Y-%m")
    result = run_cli(*REWRITE, "--random-day", "HEAD~1", "HEAD~3")
    assert result.returncode == 0, result.stderr
    assert (commit_date("HEAD~1", "%Y-%m"), commit_date("HEAD~3", "%Y-%m")) == old


def dated_repo(path, count, spacing, base, offset="+0000"):
    new_repo(path)
    for i in range(count):
        commit(f"commit {i}", date=f"{base + i * spacing} {offset}", cwd=path)


def assert_log_chronological():
    epochs = [int(e) for e in git("log", "--reverse", "--format=%at").splitlines()]
    assert epochs == sorted(epochs)


def test_random_day_keeps_log_ordered_vs_neighbors(tmp_path, monkeypatch):
    dated_repo(tmp_path / "r", 8, 3 * SECONDS_PER_DAY, EPOCH_2020)
    monkeypatch.chdir(tmp_path / "r")
    result = run_cli(*REWRITE, "--random-day", "HEAD~5", "HEAD~2")
    assert result.returncode == 0, result.stderr
    assert_log_chronological()


def test_random_month_entire_history_keeps_years_and_order(tmp_path, monkeypatch):
    dated_repo(tmp_path / "r", 20, 40 * SECONDS_PER_DAY, EPOCH_2019)
    monkeypatch.chdir(tmp_path / "r")
    years = git("log", "--reverse", "--date=format:%Y", "--format=%ad")
    result = run_cli(*REWRITE, "--random-month", "--entire-history")
    assert result.returncode == 0, result.stderr
    assert git("log", "--reverse", "--date=format:%Y", "--format=%ad") == years
    assert_log_chronological()


def test_random_month_keeps_local_year_across_utc_new_year(tmp_path, monkeypatch):
    new_repo(tmp_path / "r")
    monkeypatch.chdir(tmp_path / "r")
    commit("new year", date="2020-01-01 01:00:00 +0200")
    result = run_cli(*REWRITE, "--random-month", "HEAD")
    assert result.returncode == 0, result.stderr
    assert commit_date("HEAD", "%Y") == "2020"


def test_random_time_rewrites_committer_date_too(repo):
    result = run_cli(*REWRITE, "--random-time", "HEAD")
    assert result.returncode == 0, result.stderr
    assert git("show", "-s", "--format=%ad", "HEAD") == git("show", "-s", "--format=%cd", "HEAD")
