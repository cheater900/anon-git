#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # $lines/$output set by `run` in helpers, not lost

# RANDOM DATE TESTS: --random-time/--random-day/--random-month, the
# precomputed-random-timestamp mechanism (python_compute_random_dates) that
# backs them, and the flags/callback that consume it.

load test_helper

SECONDS_PER_HOUR=3600
SECONDS_PER_DAY=86400
EPOCH_2019_01_01=1546300800
EPOCH_2020_01_01=1577836800

# Runs python_compute_random_dates directly against synthetic
# "<hash> <epoch> <offset> [parents...]" stdin input (bypassing git/git-filter-repo),
# so its ordering guarantee can be checked against input a real repo test
# can't easily produce.
run_random_dates_script() {
    # $1: granularity envvar to set to '1'. $2: ANON_GIT_ENTIREHISTORY value.
    # $3: space-separated ANON_GIT_TARGET_COMMITS (ignored when $2 is '1').
    # stdin: "<hash> <epoch> <offset> [parents...]" lines, oldest to newest; parents
    # and children are what the script treats as "real neighbors". stdout:
    # "<hash> <epoch> <offset>", targets only.
    env ANON_GIT_RANDOMTIME=0 ANON_GIT_RANDOMDAY=0 ANON_GIT_RANDOMMONTH=0 "${1}=1" \
        ANON_GIT_ENTIREHISTORY="$2" ANON_GIT_TARGET_COMMITS="$3" \
        python3 -c "$(script_var python_compute_random_dates)"
}

# Builds $1 linear "<hash> <epoch> +0000 <parent>" lines, $2 seconds apart, from
# EPOCH_2020_01_01. Hashes named commit_0, commit_1, ...
build_synthetic_history() {
    local count=$1 spacing=$2 base=$EPOCH_2020_01_01 i
    printf 'commit_0 %s +0000\n' "$base"
    for ((i = 1; i < count; i++)); do
        printf 'commit_%s %s +0000 commit_%s\n' "$i" "$((base + i * spacing))" "$((i - 1))"
    done
}

# $1: hash to look up. stdin: run_random_dates_script's output.
random_dates_lookup() {
    awk -v h="$1" '$1 == h { print $2 }'
}

# Fails unless $@ are integers in strictly increasing order.
assert_increasing() {
    local prev=$1 cur
    shift
    for cur in "$@"; do
        assert [ "$prev" -lt "$cur" ]
        prev=$cur
    done
}

# $1: repo dir. Fails unless every commit's author time is >= its parent's,
# oldest first.
assert_log_chronological() {
    local prev=0 cur
    for cur in $(git -C "$1" log --reverse --format='%at'); do
        assert [ "$prev" -le "$cur" ]
        prev=$cur
    done
}

# Builds a repo in $1 of $2 commits, $3 seconds apart from epoch $4.
build_dated_repo() {
    local dir=$1 count=$2 spacing=$3 base=$4 i ts
    new_repo "$dir"
    for ((i = 0; i < count; i++)); do
        ts=$((base + i * spacing))
        echo "file $i" >"${dir}/file_${i}.txt"
        git -C "$dir" add "file_${i}.txt"
        GIT_AUTHOR_DATE="${ts} +0000" GIT_COMMITTER_DATE="${ts} +0000" \
            git -C "$dir" commit -q -m "commit $i"
    done
}

# UNIT TEST: a synthetic bucket of commits, all targets (--entire-history,
# no anchors), must come back in the same relative order as the original
# epochs -- the core guarantee --random-time/day/month depends on.
order_within_bucket() {
    # $1: granularity envvar
    local count=40 i got=()
    run run_random_dates_script "$1" 1 '' < <(build_synthetic_history "$count" "$SECONDS_PER_HOUR")
    assert_success
    assert_equal "${#lines[@]}" "$count"
    for ((i = 0; i < count; i++)); do
        got+=("$(random_dates_lookup "commit_${i}" <<<"$output")")
        assert [ -n "${got[i]}" ]
    done
    # Equal neighbors allowed: order must not reverse, ties are fine.
    for ((i = 1; i < count; i++)); do
        assert [ "${got[i - 1]}" -le "${got[i]}" ]
    done
}

@test "--random-time keeps chronological order in bucket" {
    order_within_bucket ANON_GIT_RANDOMTIME
}

@test "--random-day keeps chronological order in bucket" {
    order_within_bucket ANON_GIT_RANDOMDAY
}

@test "--random-month keeps chronological order in bucket" {
    order_within_bucket ANON_GIT_RANDOMMONTH
}

# UNIT TEST: two separate single-commit targets (commit_3, commit_6), each
# surrounded by real untouched neighbors. Each randomized date must land
# strictly between its own neighbors, not just anywhere in the shared
# bucket, and neighbor commits must never appear in the output.
@test "random dates: sparse targets bounded by real neighbors" {
    local history neighbor
    # 1 day apart, same month: --random-day's bucket is a full month, so
    # without neighbor-bounding a pick could land past a real neighbor.
    history=$(build_synthetic_history 10 "$SECONDS_PER_DAY")
    run run_random_dates_script ANON_GIT_RANDOMDAY 0 'commit_3 commit_6' <<<"$history"
    assert_success
    assert_equal "${#lines[@]}" 2
    for neighbor in commit_2 commit_4 commit_5 commit_7; do
        refute_line --regexp "^${neighbor} "
    done
    assert_increasing \
        "$(random_dates_lookup commit_2 <<<"$history")" \
        "$(random_dates_lookup commit_3 <<<"$output")" \
        "$(random_dates_lookup commit_4 <<<"$history")"
    assert_increasing \
        "$(random_dates_lookup commit_5 <<<"$history")" \
        "$(random_dates_lookup commit_6 <<<"$output")" \
        "$(random_dates_lookup commit_7 <<<"$history")"
}

# UNIT TEST: a contiguous target run (commit_3-5) between two real
# neighbors must land strictly inside (commit_2, commit_6), staying
# internally ordered.
@test "random dates: contiguous run bounded by real neighbors, stays ordered" {
    local history
    history=$(build_synthetic_history 10 "$SECONDS_PER_DAY")
    run run_random_dates_script ANON_GIT_RANDOMDAY 0 'commit_3 commit_4 commit_5' <<<"$history"
    assert_success
    assert_increasing \
        "$(random_dates_lookup commit_2 <<<"$history")" \
        "$(random_dates_lookup commit_3 <<<"$output")" \
        "$(random_dates_lookup commit_4 <<<"$output")" \
        "$(random_dates_lookup commit_5 <<<"$output")" \
        "$(random_dates_lookup commit_6 <<<"$history")"
}

# UNIT TEST: a run starting at the first commit has no "before" neighbor --
# the lower bound must fall back to the bucket's calendar start.
@test "random dates: run at first commit needs no lower neighbor" {
    local history
    history=$(build_synthetic_history 10 "$SECONDS_PER_DAY")
    run run_random_dates_script ANON_GIT_RANDOMDAY 0 'commit_0 commit_1' <<<"$history"
    assert_success
    assert_increasing \
        "$(random_dates_lookup commit_0 <<<"$output")" \
        "$(random_dates_lookup commit_1 <<<"$output")" \
        "$(random_dates_lookup commit_2 <<<"$history")"
}

# UNIT TEST: mirror of the above -- a run ending at the last commit has no
# "after" neighbor; the upper bound must fall back to the bucket's calendar end.
@test "random dates: run at last commit needs no upper neighbor" {
    local history
    history=$(build_synthetic_history 10 "$SECONDS_PER_DAY")
    run run_random_dates_script ANON_GIT_RANDOMDAY 0 'commit_8 commit_9' <<<"$history"
    assert_success
    assert_increasing \
        "$(random_dates_lookup commit_7 <<<"$history")" \
        "$(random_dates_lookup commit_8 <<<"$output")" \
        "$(random_dates_lookup commit_9 <<<"$output")"
}

@test "random dates bounded by parent and merge child" {
    # Side commit side_1 sits next to main_1 in log order but its real child
    # is the merge; main_1's skewed date must not stretch side_1's range past it.
    local history day=$SECONDS_PER_DAY base=$EPOCH_2020_01_01 merge_epoch i
    merge_epoch=$((base + 2 * day))
    history=$(printf '%s\n' \
        "root ${base} +0000" \
        "side_1 $((base + day)) +0000 root" \
        "main_1 $((base + 20 * day)) +0000 root" \
        "merge ${merge_epoch} +0000 main_1 side_1")
    for i in 1 2 3 4 5; do
        run run_random_dates_script ANON_GIT_RANDOMDAY 0 'side_1' <<<"$history"
        assert_success
        assert_increasing "$base" "$(random_dates_lookup side_1 <<<"$output")" "$merge_epoch"
    done
}

@test "random dates: same-second neighbors at bucket end stay in bucket" {
    # Parent, target and child all at 23:59:59: no room left, the target must
    # tie at the bucket's last second, not spill into the next day.
    local last=$((EPOCH_2020_01_01 + SECONDS_PER_DAY - 1))
    run run_random_dates_script ANON_GIT_RANDOMTIME 0 'target' < <(printf '%s\n' \
        "parent ${last} +0000" \
        "target ${last} +0000 parent" \
        "child ${last} +0000 target")
    assert_success
    assert_output "target ${last} +0000"
}

@test "random dates: bucket follows local calendar, not UTC" {
    # 2020-01-01 01:00 +0200 is 2019-12-31 23:00 UTC; the year shown must stay 2020.
    local epoch=$((EPOCH_2020_01_01 - SECONDS_PER_HOUR)) picked
    for _ in 1 2 3 4 5; do
        run run_random_dates_script ANON_GIT_RANDOMTIME 1 '' <<<"commit ${epoch} +0200"
        assert_success
        picked=$(random_dates_lookup commit <<<"$output")
        assert [ "$picked" -ge "$EPOCH_2020_01_01" ]
        assert [ "$picked" -lt $((EPOCH_2020_01_01 + SECONDS_PER_DAY)) ]
    done
}

@test "--random-month keeps local year across UTC new year" {
    local repo_dir=${BATS_TEST_TMPDIR}/random_local_year_repo
    new_repo "$repo_dir"
    cd "$repo_dir"
    GIT_AUTHOR_DATE='2020-01-01 01:00:00 +0200' GIT_COMMITTER_DATE='2020-01-01 01:00:00 +0200' \
        git commit -q --allow-empty -m 'new year'
    run ./anon-git.sh --no-confirm --no-backup --current-branch --random-month HEAD
    assert_success
    assert_equal "$(git log -1 --date=format:'%Y' --format='%ad')" 2020
}

# INTEGRATION TEST: same shape as keep_partial (flags.bats), for the
# random-* trio -- only kept calendar fields are asserted unchanged (never
# asserting a change happened, since randomness could reproduce the original).
random_partial() {
    # $1: --random-time | --random-day | --random-month
    local target old_year old_month
    pick_random_index
    target="HEAD~${PICKED_INDEX}"
    old_year=$(commit_date "$target" '%Y')
    old_month=$(commit_date "$target" '%m')
    run ./anon-git.sh --no-confirm --no-backup --current-branch "$1" "$target"
    assert_success
    assert_equal "$(commit_date "$target" '%Y')" "$old_year"
    if [[ "$1" != '--random-time' ]]; then
        return
    fi
    assert_equal "$(commit_date "$target" '%m')" "$old_month"
}

@test "--random-time keeps year, month" {
    random_partial --random-time
}

@test "--random-day keeps year" {
    random_partial --random-day
}

@test "--random-month keeps year" {
    random_partial --random-month
}

# INTEGRATION TEST: mirrors "multiple commits per run" (core.bats) -- only
# the targeted commits should change.
@test "--random-day with multiple targets keeps their year, month" {
    local old_month1 old_month2
    old_month1=$(commit_date HEAD~1 '%Y-%m')
    old_month2=$(commit_date HEAD~3 '%Y-%m')
    run ./anon-git.sh --no-confirm --no-backup --current-branch --random-day HEAD~1 HEAD~3
    assert_success
    assert_equal "$(commit_date HEAD~1 '%Y-%m')" "$old_month1"
    assert_equal "$(commit_date HEAD~3 '%Y-%m')" "$old_month2"
}

# INTEGRATION TEST: commits a few days apart within one month (--random-day's
# bucket), only two non-adjacent ones targeted. Asserts the *entire* log
# stays chronological afterward -- the neighbor-bounding guarantee, exercised
# end to end through git-filter-repo.
@test "--random-day keeps log ordered vs untouched neighbors" {
    local repo_dir=${BATS_TEST_TMPDIR}/random_day_neighbor_repo
    build_dated_repo "$repo_dir" 8 $((SECONDS_PER_DAY * 3)) "$EPOCH_2020_01_01"
    cd "$repo_dir"
    # HEAD~5 is commit 2, HEAD~2 commit 5, 0-indexed from the bottom.
    run ./anon-git.sh --no-confirm --no-backup --current-branch --random-day HEAD~5 HEAD~2
    assert_success
    assert_log_chronological "$repo_dir"
}

# INTEGRATION TEST: a dedicated repo (not the shared same-day fixture) with
# commits spread ~40 days apart across years, giving --random-month
# --entire-history more than one calendar-year bucket to keep ordered.
@test "--random-month --entire-history keeps year, order across years" {
    local repo_dir=${BATS_TEST_TMPDIR}/random_month_order_repo before_years
    build_dated_repo "$repo_dir" 20 $((SECONDS_PER_DAY * 40)) "$EPOCH_2019_01_01"
    cd "$repo_dir"
    before_years=$(git log --reverse --date=format:'%Y' --format='%ad')
    run ./anon-git.sh --no-confirm --no-backup --current-branch --random-month --entire-history
    assert_success
    assert_equal "$(git log --reverse --date=format:'%Y' --format='%ad')" "$before_years"
    assert_log_chronological "$repo_dir"
}
