"""Date parsing and git date-string conversion."""

import re
from datetime import datetime, timezone


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


# Returns (epoch, offset sign, hours, minutes, seconds). The offset is not
# range-checked: old repos carry bogus ones like +9999 that datetime's
# timezone rejects.
def split_git_date(date_bytes):
    unix_ts, offset = date_bytes.decode().split()
    sign = 1 if offset.startswith("+") else -1
    offset = offset.lstrip("+-")
    if len(offset) not in (4, 6):
        raise ValueError("unsupported timezone format")
    return int(unix_ts), sign, int(offset[:2]), int(offset[2:4]), int(offset[4:] or 0)


# Wall-clock date/time in the date's own offset, labeled UTC.
def parse_git_date(date_bytes):
    epoch, sign, hours, minutes, seconds = split_git_date(date_bytes)
    return datetime.fromtimestamp(
        epoch + sign * (hours * 3600 + minutes * 60 + seconds), tz=timezone.utc
    )


# Same digits, relabeled (not converted) as UTC.
def as_utc_epoch(dt):
    return int(dt.replace(tzinfo=timezone.utc).timestamp())


# Bucket bounds must be these digits read as UTC: the output is +0000.
def local_datetime(epoch, offset):
    return parse_git_date(f"{epoch} {offset}".encode())


def utc_git_date(epoch):
    return b"%d +0000" % epoch


# ISO 8601 with the original offset, built by hand so a bogus offset shows
# as-is instead of raising.
def git_date_iso(git_date):
    _, sign, hours, minutes, seconds = split_git_date(git_date)
    negative = sign < 0 and (hours or minutes or seconds)
    offset = f"{'-' if negative else '+'}{hours:02d}:{minutes:02d}"
    if seconds:
        offset += f":{seconds:02d}"
    return f"{parse_git_date(git_date).replace(tzinfo=None).isoformat()}{offset}"
