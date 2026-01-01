"""Date parsing and offset helpers."""

from datetime import datetime, timedelta, timezone

from helpers import EPOCH_2020
from hypothesis import given
from hypothesis import strategies as st

from anon_git.utils.dates import git_date_iso, local_datetime, parse_git_date, parse_target_date


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
    assert parse_target_date(text) == aware


def test_local_datetime_applies_offset():
    dt = local_datetime(EPOCH_2020, "-0530")
    assert dt == datetime(2020, 1, 1, tzinfo=timezone.utc) - timedelta(hours=5, minutes=30)


def test_git_date_iso_matches_python_isoformat():
    for offset in ("+0000", "-0000", "+0530", "-0800"):
        expected = datetime.fromtimestamp(EPOCH_2020, tz=timezone.utc).astimezone(
            datetime.strptime(offset, "%z").tzinfo
        )
        assert git_date_iso(f"{EPOCH_2020} {offset}".encode()) == expected.isoformat()


def test_bogus_offset_parses_like_git():
    # Git shows 1700000000 +9999 as 2023-11-19 02:52:20 (+99h99m wall clock).
    date = b"1700000000 +9999"
    assert parse_git_date(date) == datetime(2023, 11, 19, 2, 52, 20, tzinfo=timezone.utc)
    assert git_date_iso(date) == "2023-11-19T02:52:20+99:99"
