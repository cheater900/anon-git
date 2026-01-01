"""compute_random_dates on synthetic histories: examples and properties."""

import random

import pytest
from helpers import EPOCH_2019, EPOCH_2020, SECONDS_PER_DAY, SECONDS_PER_HOUR
from hypothesis import given, settings
from hypothesis import strategies as st

from anon_git.constants import KEPT_DAY, KEPT_MONTH, KEPT_YEAR
from anon_git.models import HistoryCommit
from anon_git.random_dates import bucket_bounds, compute_random_dates, pick_epochs
from anon_git.utils.dates import local_datetime

Commit = HistoryCommit


KEPT_UNITS = [KEPT_DAY, KEPT_MONTH, KEPT_YEAR]


def linear_history(count, spacing, base=EPOCH_2020, offset="+0000"):
    """count commits commit_0..commit_{count-1}, spacing seconds apart."""
    return [
        Commit(f"commit_{i}", base + i * spacing, offset, [f"commit_{i - 1}"] if i else [])
        for i in range(count)
    ]


def epoch_of(history, commit_hash):
    return next(epoch for h, epoch, _offset, _parents in history if h == commit_hash)


def local_unit(epoch, offset, kept_unit):
    return bucket_bounds(local_datetime(epoch, offset), kept_unit)[0]


@pytest.mark.parametrize("kept_unit", KEPT_UNITS)
def test_order_kept_within_bucket(kept_unit):
    history = linear_history(40, SECONDS_PER_HOUR)
    picked = compute_random_dates(history, set(), kept_unit, entire=True)
    assert len(picked) == 40
    epochs = [picked[f"commit_{i}"] for i in range(40)]
    assert epochs == sorted(epochs)


def test_sparse_targets_bounded_by_real_neighbors():
    # --random-day's bucket is a full month: without neighbor bounds a pick
    # could land past a real neighbor.
    history = linear_history(10, SECONDS_PER_DAY)
    picked = compute_random_dates(history, {"commit_3", "commit_6"}, KEPT_MONTH, False)
    assert set(picked) == {"commit_3", "commit_6"}
    assert epoch_of(history, "commit_2") < picked["commit_3"] < epoch_of(history, "commit_4")
    assert epoch_of(history, "commit_5") < picked["commit_6"] < epoch_of(history, "commit_7")


def test_contiguous_run_bounded_and_ordered():
    history = linear_history(10, SECONDS_PER_DAY)
    targets = {"commit_3", "commit_4", "commit_5"}
    picked = compute_random_dates(history, targets, KEPT_MONTH, False)
    chain = [
        epoch_of(history, "commit_2"),
        picked["commit_3"],
        picked["commit_4"],
        picked["commit_5"],
        epoch_of(history, "commit_6"),
    ]
    assert chain == sorted(set(chain))


def test_run_at_first_commit_needs_no_lower_neighbor():
    history = linear_history(10, SECONDS_PER_DAY)
    picked = compute_random_dates(history, {"commit_0", "commit_1"}, KEPT_MONTH, False)
    assert EPOCH_2020 <= picked["commit_0"] < picked["commit_1"] < epoch_of(history, "commit_2")


def test_run_at_last_commit_needs_no_upper_neighbor():
    history = linear_history(10, SECONDS_PER_DAY)
    picked = compute_random_dates(history, {"commit_8", "commit_9"}, KEPT_MONTH, False)
    assert epoch_of(history, "commit_7") < picked["commit_8"] < picked["commit_9"]


def test_bounded_by_parent_and_merge_child():
    # side_1 sits next to main_1 in log order but its real child is the
    # merge; main_1's skewed date must not stretch side_1's range past it.
    merge_epoch = EPOCH_2020 + 2 * SECONDS_PER_DAY
    history = [
        Commit("root", EPOCH_2020, "+0000", []),
        Commit("side_1", EPOCH_2020 + SECONDS_PER_DAY, "+0000", ["root"]),
        Commit("main_1", EPOCH_2020 + 20 * SECONDS_PER_DAY, "+0000", ["root"]),
        Commit("merge", merge_epoch, "+0000", ["main_1", "side_1"]),
    ]
    for _ in range(20):
        picked = compute_random_dates(history, {"side_1"}, KEPT_MONTH, False)
        assert EPOCH_2020 < picked["side_1"] < merge_epoch


def test_same_second_neighbors_at_bucket_end_stay_in_bucket():
    last = EPOCH_2020 + SECONDS_PER_DAY - 1
    history = [
        Commit("parent", last, "+0000", []),
        Commit("target", last, "+0000", ["parent"]),
        Commit("child", last, "+0000", ["target"]),
    ]
    assert compute_random_dates(history, {"target"}, KEPT_DAY, False) == {"target": last}


def test_bucket_follows_local_calendar_not_utc():
    # 2020-01-01 01:00 +0200 is 2019-12-31 23:00 UTC; the day shown stays Jan 1.
    history = [Commit("commit", EPOCH_2020 - SECONDS_PER_HOUR, "+0200", [])]
    for _ in range(20):
        picked = compute_random_dates(history, set(), KEPT_DAY, True)
        assert EPOCH_2020 <= picked["commit"] < EPOCH_2020 + SECONDS_PER_DAY


def test_seeded_rng_reproducible():
    history = linear_history(10, SECONDS_PER_HOUR)
    first = compute_random_dates(history, set(), KEPT_YEAR, True, random.Random(7))
    second = compute_random_dates(history, set(), KEPT_YEAR, True, random.Random(7))
    assert first == second


OFFSETS = st.sampled_from(["+0000", "+0200", "-0500", "+0530", "+1400", "-1200"])


@st.composite
def histories(draw, utc_only):
    """Random DAG, oldest first: each commit's parents are earlier commits,
    epochs non-decreasing along history (ties allowed, bucket edges likely)."""
    count = draw(st.integers(min_value=1, max_value=25))
    epoch = draw(st.integers(min_value=EPOCH_2019, max_value=EPOCH_2020 + 365 * SECONDS_PER_DAY))
    history = []
    for i in range(count):
        epoch += draw(
            st.sampled_from(
                [
                    0,
                    1,
                    59,
                    SECONDS_PER_HOUR,
                    SECONDS_PER_DAY - 1,
                    SECONDS_PER_DAY,
                    31 * SECONDS_PER_DAY,
                ]
            )
        )
        parents = []
        if i:
            parents.append(f"c{draw(st.integers(min_value=max(0, i - 3), max_value=i - 1))}")
            if i > 1 and draw(st.booleans()):
                parents.append(f"c{draw(st.integers(min_value=0, max_value=i - 1))}")
        history.append(
            Commit(f"c{i}", epoch, "+0000" if utc_only else draw(OFFSETS), sorted(set(parents)))
        )
    targets = {h for h, *_ in history if draw(st.booleans())}
    entire = draw(st.booleans())
    kept_unit = draw(st.sampled_from(KEPT_UNITS))
    return history, targets, entire, kept_unit


@settings(max_examples=300, deadline=None)
@given(histories(utc_only=False))
def test_property_pick_stays_in_local_calendar_unit(case):
    history, targets, entire, kept_unit = case
    picked = compute_random_dates(history, targets, kept_unit, entire)
    expected = {h for h, *_ in history} if entire else targets
    assert set(picked) == expected
    for commit_hash, epoch, offset, _parents in history:
        if commit_hash not in picked:
            continue
        # Output is +0000, so its calendar unit is read in UTC.
        assert local_unit(picked[commit_hash], "+0000", kept_unit) == local_unit(
            epoch, offset, kept_unit
        )


@settings(max_examples=300, deadline=None)
@given(histories(utc_only=True))
def test_property_pick_between_parent_and_child(case):
    # Output is +0000; with +0000 input no timezone conflicts with the kept
    # calendar unit, so parent <= child must hold.
    history, targets, entire, kept_unit = case
    picked = compute_random_dates(history, targets, kept_unit, entire)
    new_epoch = {h: picked.get(h, epoch) for h, epoch, _offset, _parents in history}
    for commit_hash, _epoch, _offset, parents in history:
        for parent in parents:
            assert new_epoch[parent] <= new_epoch[commit_hash]


@pytest.mark.parametrize(
    "lower, upper, expected",
    [
        (11, 10, [10, 10]),  # no room between anchors 10 and 11: tie with lower anchor
        (0, -1, [0, 0]),  # next anchor at bucket start: tie at bucket start
        (101, 100, [100, 100]),  # previous anchor at bucket end: tie at bucket end
        (150, 140, [100, 100]),  # anchor past bucket end: clamp to bucket end
    ],
)
def test_pick_epochs_without_room_stays_in_bucket(lower, upper, expected):
    assert pick_epochs(lower, upper, (0, 100), 2, random.Random(0)) == expected


def test_pick_epochs_more_targets_than_seconds_allows_ties():
    epochs = pick_epochs(5, 6, (0, 100), 5, random.Random(0))
    assert epochs == sorted(epochs)
    assert set(epochs) <= {5, 6}
