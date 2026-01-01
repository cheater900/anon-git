"""Bad input rejected before anything is touched."""

import subprocess

import pytest
from helpers import append_line, branch_count, git, head, run_cli

from anon_git.options import parse_args

DATE = "2020-01-01 00:00:00 +0000"


INCOMPATIBLE = [
    (["--date", DATE, "--keep-date"], {}),
    (["--date", DATE, "--keep-year"], {}),
    (["--keep-user", "--name", "Nobody"], {}),
    (["--keep-user", "--email", "nobody@example.com"], {}),
    (["--keep-year", "--keep-month"], {}),
    (["--keep-year", "--keep-day"], {}),
    (["--keep-month", "--keep-day"], {}),
    (["--entire-history", "HEAD"], {}),
    (["--random-day", "--keep-day"], {}),
    (["--random-time", "--keep-year"], {}),
    (["--random-month", "--keep-month"], {}),
    (["--keep-date", "--random-time"], {}),
    (["--random-time", "--random-day"], {}),
    (["--random-day", "--random-month"], {}),
    (["--random-time", "--random-month"], {}),
    (["--date", DATE, "--random-month"], {}),
    ([], {"ANON_GIT_DATE": DATE, "ANON_GIT_KEEPDATE": "1"}),
    ([], {"ANON_GIT_DATE": DATE, "ANON_GIT_KEEPYEAR": "1"}),
    ([], {"ANON_GIT_KEEPUSER": "1", "ANON_GIT_NAME": "Nobody"}),
    ([], {"ANON_GIT_KEEPUSER": "1", "ANON_GIT_EMAIL": "nobody@example.com"}),
    ([], {"ANON_GIT_KEEPYEAR": "1", "ANON_GIT_KEEPMONTH": "1"}),
    ([], {"ANON_GIT_KEEPYEAR": "1", "ANON_GIT_KEEPDAY": "1"}),
    ([], {"ANON_GIT_KEEPMONTH": "1", "ANON_GIT_KEEPDAY": "1"}),
    ([], {"ANON_GIT_RANDOMDAY": "1", "ANON_GIT_KEEPDAY": "1"}),
    ([], {"ANON_GIT_RANDOMTIME": "1", "ANON_GIT_RANDOMMONTH": "1"}),
]


@pytest.mark.parametrize("args, env", INCOMPATIBLE)
def test_rejects_incompatible(repo, head_before, args, env):
    result = run_cli("--no-confirm", "--no-backup", *args, env=env)
    assert result.returncode == 1
    assert "cannot be used together" in result.stderr
    assert head() == head_before


def test_rejects_quiet_with_verbose(repo, head_before):
    result = run_cli("--no-confirm", "--no-backup", "--quiet", "--verbose", "HEAD")
    assert result.returncode == 1
    assert head() == head_before


def test_rejects_invalid_commit_ref(repo, head_before):
    result = run_cli("--no-confirm", "--no-backup", "deadbeef" * 5)
    assert result.returncode == 1
    assert "does not exist" in result.stderr
    assert head() == head_before


def test_rejects_uncommitted_changes(repo, head_before):
    append_line("file_1.txt", "dirty")
    result = run_cli("--no-confirm", "--no-backup")
    assert result.returncode == 1
    assert "uncommitted changes" in result.stderr
    assert head() == head_before


@pytest.mark.parametrize(
    "args", [["--date"], ["--name"], ["--email"], ["--name", ""], ["--date", ""]]
)
def test_rejects_missing_value(repo, head_before, args):
    result = run_cli("--no-confirm", "--no-backup", "--current-branch", *args)
    assert result.returncode == 1
    assert "requires a value" in result.stderr
    assert head() == head_before


def test_rejects_unknown_flag(repo, head_before):
    result = run_cli("--no-confirm", "--no-backup", "--bogus-flag", "HEAD")
    assert result.returncode == 1
    assert "Unknown option" in result.stderr
    assert head() == head_before


@pytest.mark.parametrize(
    "date", ["not-a-real-date", "2025-13-45 99:00:00 +0000", "1960-01-01 00:00:00 +0000"]
)
def test_rejects_bad_date_before_branch_creation(repo, head_before, date):
    result = run_cli("--no-confirm", "--date", date, "HEAD")
    assert result.returncode == 1
    assert "invalid date" in result.stderr
    assert branch_count() == 1
    assert head() == head_before


@pytest.mark.parametrize(
    "flag, value", [("--name", "Ev<il>"), ("--email", "a>b@example.com"), ("--name", "Line\nBreak")]
)
def test_rejects_bad_identity_before_branch_creation(repo, head_before, flag, value):
    result = run_cli("--no-confirm", flag, value, "HEAD")
    assert result.returncode == 1
    assert "must not contain" in result.stderr
    assert branch_count() == 1
    assert head() == head_before


def test_rejects_commit_not_reachable_from_head(repo, head_before):
    branch = git("branch", "--show-current")
    git("switch", "-q", "--create", "side")
    git("commit", "-q", "--allow-empty", "-m", "Side commit")
    side = head()
    git("switch", "-q", branch)
    result = run_cli("--no-confirm", "--no-backup", "--current-branch", side)
    assert result.returncode == 1
    assert "not reachable from HEAD" in result.stderr
    assert head() == head_before


def test_many_targets_resolve_in_one_git_call(repo, monkeypatch):
    revs = [f"HEAD~{i}" for i in range(19)]
    expected = [git("rev-parse", rev) for rev in revs]
    calls = []
    real_run = subprocess.run

    def counting_run(cmd, *args, **kwargs):
        calls.append(cmd)
        return real_run(cmd, *args, **kwargs)

    monkeypatch.setattr(subprocess, "run", counting_run)
    _args, commits = parse_args(revs)
    assert commits == expected
    assert len(calls) == 1


def test_invalid_rev_among_many_named_in_error(repo, head_before):
    result = run_cli("--no-confirm", "HEAD", "HEAD~1", "no-such-ref", "HEAD~2")
    assert result.returncode == 1
    assert 'Commit "no-such-ref" does not exist' in result.stderr
    assert head() == head_before


@pytest.mark.parametrize("rev", ["HEAD^{tree}", "HEAD:file_1.txt", "bad\nrev"])
def test_rejects_non_commit_objects(repo, head_before, rev):
    result = run_cli("--no-confirm", rev)
    assert result.returncode == 1
    assert "is not a commit object" in result.stderr
    assert head() == head_before
