"""Date parsing and offset helpers."""

from datetime import datetime, timedelta, timezone

from helpers import EPOCH_2020
from hypothesis import given
from hypothesis import strategies as st

from anon_git.utils.dates import local_datetime, parse_target_date


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
