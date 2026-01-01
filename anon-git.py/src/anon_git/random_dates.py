"""--random-time/--random-day/--random-month: randomized, order-keeping dates."""

import random
from collections import defaultdict
from datetime import datetime, timedelta, timezone

from anon_git.constants import KEPT_DAY, KEPT_MONTH, KEPT_YEAR
from anon_git.models import BucketMember, HistoryCommit
from anon_git.utils.dates import local_datetime
from anon_git.utils.git import git


# dt: UTC-labeled date. Returns (bucket key, start epoch, end epoch) of the
# calendar unit kept.
def bucket_bounds(dt, kept_unit):
    if kept_unit == KEPT_YEAR:
        start = datetime(dt.year, 1, 1, tzinfo=timezone.utc)
        end = datetime(dt.year, 12, 31, 23, 59, 59, tzinfo=timezone.utc)
        return (dt.year,), int(start.timestamp()), int(end.timestamp())
    if kept_unit == KEPT_MONTH:
        start = datetime(dt.year, dt.month, 1, tzinfo=timezone.utc)
        if dt.month == 12:
            next_month_start = datetime(dt.year + 1, 1, 1, tzinfo=timezone.utc)
        else:
            next_month_start = datetime(dt.year, dt.month + 1, 1, tzinfo=timezone.utc)
        end = next_month_start - timedelta(seconds=1)
        return (dt.year, dt.month), int(start.timestamp()), int(end.timestamp())
    start = datetime(dt.year, dt.month, dt.day, tzinfo=timezone.utc)
    end = start + timedelta(days=1, seconds=-1)
    return (dt.year, dt.month, dt.day), int(start.timestamp()), int(end.timestamp())


# Real neighbors are parents and children: across a merge, the commit next
# in log order can sit on another branch.
def find_anchors(history, targets):
    anchors = set()
    for commit in history:
        if commit.hash in targets:
            anchors.update(commit.parents)
        elif any(parent in targets for parent in commit.parents):
            anchors.add(commit.hash)
    return anchors


# Groups targets and anchors by the calendar unit each must stay in: the
# commit's local unit (what `git log` shows, as --keep-* uses); an anchor
# also bounds targets whose bucket holds its real instant. Returns
# [(sorted members, (start epoch, end epoch))].
def bucket_members(history, targets, kept_unit, entire):
    anchors = find_anchors(history, targets)
    buckets = defaultdict(list)
    bounds = {}
    for index, commit in enumerate(history):
        is_target = entire or commit.hash in targets
        if not is_target and commit.hash not in anchors:
            continue
        keys = {bucket_bounds(local_datetime(commit.epoch, commit.offset), kept_unit)}
        if not is_target:
            real_instant = datetime.fromtimestamp(commit.epoch, tz=timezone.utc)
            keys.add(bucket_bounds(real_instant, kept_unit))
        for key, start, end in keys:
            buckets[key].append(BucketMember(commit.epoch, index, commit.hash, is_target))
            bounds[key] = (start, end)
    return [(sorted(members), bounds[key]) for key, members in buckets.items()]


# count sorted random epochs in [lower, upper], kept within the bucket.
def pick_epochs(lower, upper, bucket, count, rng):
    bucket_start, bucket_end = bucket
    if upper < lower:
        # No room between anchors, or an anchor outside the bucket. Share the
        # nearest in-bucket timestamp: git allows identical dates, the
        # calendar unit must not change.
        return [min(max(lower - 1, bucket_start), bucket_end)] * count
    if count <= upper - lower + 1:
        return sorted(rng.sample(range(lower, upper + 1), count))
    return sorted(rng.randint(lower, upper) for _ in range(count))


# One random epoch per target, {hash: epoch}. history: [HistoryCommit],
# oldest first, parents before children; the history index breaks epoch
# ties so a parent sorts before its same-second child. Each run of targets
# between two anchors gets sorted epochs strictly between them.
def compute_random_dates(history, targets, kept_unit, entire, rng=None):
    rng = rng or random.SystemRandom()
    picked = {}
    for members, bucket in bucket_members(history, targets, kept_unit, entire):
        bucket_start, bucket_end = bucket
        i = 0
        lower = bucket_start
        while i < len(members):
            if not members[i].is_target:
                lower = max(members[i].epoch + 1, bucket_start)
                i += 1
                continue
            run_start = i
            while i < len(members) and members[i].is_target:
                i += 1
            run = members[run_start:i]
            upper = min(members[i].epoch - 1, bucket_end) if i < len(members) else bucket_end
            epochs = pick_epochs(lower, upper, bucket, len(run), rng)
            for member, epoch in zip(run, epochs, strict=True):
                picked[member.hash] = epoch
    return picked


def read_history():
    log = git(
        "log", "--reverse", "--topo-order", "--date=format:%z", "--format=%H %at %ad %P", "HEAD"
    )
    history = []
    for line in log.splitlines():
        commit_hash, epoch, offset, *parents = line.split()
        history.append(HistoryCommit(commit_hash, int(epoch), offset, parents))
    return history


def kept_calendar_unit(opts):
    if opts.randommonth:
        return KEPT_YEAR
    if opts.randomday:
        return KEPT_MONTH
    if opts.randomtime:
        return KEPT_DAY
    return None


# {hash: epoch} for --random-*, or None when dates aren't randomized.
def random_dates_for(opts):
    kept_unit = None if opts.keepdate else kept_calendar_unit(opts)
    if kept_unit is None:
        return None
    return compute_random_dates(read_history(), set(opts.commits), kept_unit, opts.entirehistory)
