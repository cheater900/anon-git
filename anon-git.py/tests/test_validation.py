"""Rejecting bad input before anything is touched: conflicting flags, bad
refs, dirty tree, missing values, malformed dates and identities."""

from datetime import datetime, timedelta, timezone

import pytest
from conftest import branch_count, git, head, run_cli
from hypothesis import given
from hypothesis import strategies as st

import anon_git

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
    with open("file_1.txt", "a") as fh:
        fh.write("dirty\n")
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


@given(
    st.datetimes(
        min_value=datetime(1970, 1, 2), max_value=datetime(9998, 12, 31), timezones=st.just(None)
    ),
    st.integers(min_value=-14 * 60, max_value=14 * 60),
    st.sampled_from(["space", "iso", "isoz"]),
)
def test_parse_target_date_round_trips(dt, offset_minutes, form):
    dt = dt.replace(microsecond=0)
    tz = timezone(timedelta(minutes=offset_minutes))
    if form == "isoz":
        tz = timezone.utc
    aware = dt.replace(tzinfo=tz)
    text = {
        "space": aware.strftime("%Y-%m-%d %H:%M:%S %z"),
        "iso": aware.isoformat(),
        "isoz": dt.strftime("%Y-%m-%dT%H:%M:%SZ"),
    }[form]
    assert anon_git.parse_target_date(text) == aware


@given(st.text(min_size=1))
def test_validate_identity_rejects_exactly_bad_chars(name):
    opts = anon_git.Options(
        name=name,
        email="a@b",
        date=anon_git.DEFAULT_DATE,
        commits=[],
        **{opt.lower(): False for opt in anon_git.BOOLS},
        noconfirm=True,
        nobackup=True,
        args={},
    )
    bad = any(char in name for char in "<>\n")
    if bad:
        with pytest.raises(SystemExit):
            anon_git.validate_identity(opts)
        return
    anon_git.validate_identity(opts)
