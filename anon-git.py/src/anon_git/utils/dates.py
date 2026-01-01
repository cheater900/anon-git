"""Date parsing and git date-string conversion."""

import re
from datetime import datetime, timedelta, timezone


def parse_target_date(date_str):
    # Also accepts ISO 8601 compact form (e.g. '2025-06-15T14:20:00Z'),
    # normalized to the space-separated, 4-digit-offset form '%z' expects.
    normalized = date_str.strip()
    if "T" in normalized:
        normalized = normalized.replace("T", " ", 1)
        if normalized.endswith("Z"):
            normalized = normalized[:-1] + "+0000"
        match = re.match(r"^(.*\d{2}:\d{2}:\d{2})([+-]\d{2}:?\d{2})$", normalized)
        if match:
            normalized = f"{match.group(1)} {match.group(2).replace(':', '')}"
    return datetime.strptime(normalized, "%Y-%m-%d %H:%M:%S %z")


def parse_git_date(date_bytes):
    unix_ts, offset = date_bytes.decode().split()
    sign = 1 if offset.startswith("+") else -1
    offset = offset.lstrip("+-")
    if len(offset) not in (4, 6):
        raise ValueError("unsupported timezone format")
    tz_offset = timedelta(
        hours=int(offset[:2]), minutes=int(offset[2:4]), seconds=int(offset[4:] or 0)
    )
    return datetime.fromtimestamp(float(unix_ts), tz=timezone(sign * tz_offset))


# Same digits, relabeled (not converted) as UTC.
def as_utc_epoch(dt):
    return int(dt.replace(tzinfo=timezone.utc).timestamp())


# Wall-clock date/time in the commit's own offset, labeled UTC: the output is
# +0000, so bucket bounds must be these digits read as UTC.
def local_datetime(epoch, offset):
    return parse_git_date(f"{epoch} {offset}".encode()).replace(tzinfo=timezone.utc)


def utc_git_date(epoch):
    return b"%d +0000" % epoch


def git_date_iso(git_date):
    return parse_git_date(git_date).isoformat()
