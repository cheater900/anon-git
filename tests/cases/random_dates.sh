#!/usr/bin/env bash

# Sourced by test_anon_git.sh — not meant to be run directly.
# RANDOM DATE TESTS: --random-time/--random-day/--random-month, the
# precomputed-random-timestamp mechanism (python_compute_random_dates) that
# backs them, and the flags/callback that consume it.

# Internal: extracts python_compute_random_dates's Python source from the
# script, the same way test_python_callback_syntax (validation.sh) extracts
# python_commit_callback -- by its exact, unindented
# `python_compute_random_dates="` ... `"` line anchors.
extract_random_dates_script() {
    local raw_block
    raw_block=$(sed -n '/^python_compute_random_dates="$/,/^"$/p' "$SCRIPT")
    sed -e '1d' -e '$d' <<<"$raw_block"
}

# Internal: runs python_compute_random_dates directly (bypassing git and
# git-filter-repo entirely) against synthetic "<hash> <epoch>" stdin input,
# so its ordering guarantee (including neighbor-bounding) can be checked
# against denser/wider-spanning/sparser input than a real git repo test
# would want to create commits for.
run_random_dates_script() {
    # @param $1        which granularity envvar to set to '1' (ANON_GIT_RANDOMTIME | ANON_GIT_RANDOMDAY | ANON_GIT_RANDOMMONTH)
    # @param $2        ANON_GIT_ENTIREHISTORY value to set ('0' or '1')
    # @param $3        space-separated ANON_GIT_TARGET_COMMITS value (ignored when $2 is '1')
    # @param stdin     "<hash> <epoch>" lines, oldest to newest -- adjacency in
    #                  this stream is what the script treats as "real neighbors"
    # @returns stdout  "<hash> <epoch> <offset>" lines, targets only
    local granularity_var="$1" entirehistory="$2" target_commits="$3" python_code
    python_code=$(extract_random_dates_script)
    env ANON_GIT_RANDOMTIME=0 ANON_GIT_RANDOMDAY=0 ANON_GIT_RANDOMMONTH=0 "${granularity_var}=1" \
        ANON_GIT_ENTIREHISTORY="$entirehistory" ANON_GIT_TARGET_COMMITS="$target_commits" \
        python3 -c "$python_code"
}

# Internal: builds $1 synthetic "<hash> <epoch>" lines, $2 seconds apart,
# starting at a fixed 2020-01-01 UTC epoch -- one per line, oldest to
# newest, hashes named commit_0, commit_1, ...
build_synthetic_history() {
    # @param $1  number of commits
    # @param $2  seconds between each commit
    local count="$1" spacing="$2" base=1577836800 i
    for ((i = 0; i < count; i++)); do
        printf 'commit_%s %s\n' "$i" "$((base + i * spacing))"
    done
}

# Internal: extracts the randomized epoch for one hash from
# run_random_dates_script's output, or prints nothing if that hash isn't in it.
random_dates_lookup() {
    # @param $1     hash to look up
    # @param stdin  run_random_dates_script's output
    awk -v h="$1" '$1 == h { print $2 }'
}

test_python_random_dates_syntax() {
    local python_code check_file output exit_status errors=0

    python_code=$(extract_random_dates_script)

    if [[ -z "$python_code" ]]; then
        printf 'Error: could not extract python_compute_random_dates contents from %s\n' "$SCRIPT_NAME"
        errors=$((errors + 1))
    fi

    check_file="${TMP_DIR}/python_compute_random_dates_check.py"
    printf '%s\n' "$python_code" >"$check_file"

    output=$(python3 -m py_compile "$check_file" 2>&1)
    exit_status=$?

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: python_compute_random_dates has a syntax error:\n%s\n' "$output"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'python compute-random-dates script syntax'
}

# UNIT TEST: feeds python_compute_random_dates a synthetic set of
# "<hash> <epoch>" commits (all landing in the same bucket for the given
# granularity, all targets under --entire-history so there are no anchors
# to bound them) and checks the timestamps it writes back come back in the
# same relative order as the original epochs -- the guarantee the whole
# --random-time/day/month feature depends on.
test_random_dates_order_within_bucket() {
    # @param $1  flag name, for the result label: --random-time | --random-day | --random-month
    # @param $2  matching envvar: ANON_GIT_RANDOMTIME | ANON_GIT_RANDOMDAY | ANON_GIT_RANDOMMONTH
    local flag="$1" granularity_var="$2" errors=0
    local i count=40 history output line_count cur prev=-1

    history=$(build_synthetic_history "$count" 3600)

    output=$(printf '%s\n' "$history" | run_random_dates_script "$granularity_var" 1 '')

    line_count=$(printf '%s\n' "$output" | grep -c .)
    if [[ "$line_count" -ne "$count" ]]; then
        printf 'Error: %s produced %s output lines, expected %s\n' "$flag" "$line_count" "$count"
        errors=$((errors + 1))
    fi

    for ((i = 0; i < count; i++)); do
        cur=$(random_dates_lookup "commit_${i}" <<<"$output")
        if [[ -z "$cur" ]]; then
            printf 'Error: %s: no randomized date found for commit_%s\n' "$flag" "$i"
            errors=$((errors + 1))
            continue
        fi
        if [[ "$cur" -lt "$prev" ]]; then
            printf 'Error: %s: commit_%s (%s) sorts earlier than the previous original commit (%s) -- order not preserved\n' \
                "$flag" "$i" "$cur" "$prev"
            errors=$((errors + 1))
        fi
        prev="$cur"
    done

    record_result "$errors" "temp file for $flag keeps commits in original chronological order"
}

# UNIT TEST: two separate single-commit target runs (commit_3 and commit_6),
# surrounded on all sides by real, untouched commits -- the exact "cover
# neighbor before and after" scenario. Each target's randomized date must
# land strictly between its own real neighbors, not just somewhere in the
# shared calendar bucket, and neither neighbor commit may itself appear in
# the output (they were never targets, so they're never rewritten).
test_random_dates_neighbor_bounds_sparse_targets() {
    local errors=0 history output lo3 hi3 lo6 hi6 got3 got6 line_count

    # 10 commits, 1 day apart, all in the same month -- --random-day's
    # bucket is a full month, so without neighbor-bounding a target's random
    # pick could legally land anywhere in that month, past a real neighbor.
    history=$(build_synthetic_history 10 86400)

    output=$(printf '%s\n' "$history" | run_random_dates_script ANON_GIT_RANDOMDAY 0 'commit_3 commit_6')

    line_count=$(printf '%s\n' "$output" | grep -c .)
    if [[ "$line_count" -ne 2 ]]; then
        printf 'Error: expected exactly 2 output lines (the 2 targets), got %s\n' "$line_count"
        errors=$((errors + 1))
    fi

    for neighbor in commit_2 commit_4 commit_5 commit_7; do
        if [[ -n "$(random_dates_lookup "$neighbor" <<<"$output")" ]]; then
            printf 'Error: untouched neighbor %s appeared in the output (must never be rewritten)\n' "$neighbor"
            errors=$((errors + 1))
        fi
    done

    lo3=$(random_dates_lookup commit_2 <<<"$history")
    hi3=$(random_dates_lookup commit_4 <<<"$history")
    lo6=$(random_dates_lookup commit_5 <<<"$history")
    hi6=$(random_dates_lookup commit_7 <<<"$history")
    got3=$(random_dates_lookup commit_3 <<<"$output")
    got6=$(random_dates_lookup commit_6 <<<"$output")

    if [[ -z "$got3" || "$got3" -le "$lo3" || "$got3" -ge "$hi3" ]]; then
        printf 'Error: commit_3 (%s) is not strictly between its real neighbors commit_2 (%s) and commit_4 (%s)\n' \
            "$got3" "$lo3" "$hi3"
        errors=$((errors + 1))
    fi
    if [[ -z "$got6" || "$got6" -le "$lo6" || "$got6" -ge "$hi6" ]]; then
        printf 'Error: commit_6 (%s) is not strictly between its real neighbors commit_5 (%s) and commit_7 (%s)\n' \
            "$got6" "$lo6" "$hi6"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'random dates: sparse target runs are bounded by their real neighbors'
}

# UNIT TEST: a contiguous run of target commits (commit_3, commit_4,
# commit_5) sandwiched between two real, untouched neighbors. The whole run
# must land strictly inside (commit_2, commit_6) and stay internally
# ordered among itself.
test_random_dates_neighbor_bounds_contiguous_run() {
    local errors=0 history output lo hi got3 got4 got5

    history=$(build_synthetic_history 10 86400)

    output=$(printf '%s\n' "$history" | run_random_dates_script ANON_GIT_RANDOMDAY 0 'commit_3 commit_4 commit_5')

    lo=$(random_dates_lookup commit_2 <<<"$history")
    hi=$(random_dates_lookup commit_6 <<<"$history")
    got3=$(random_dates_lookup commit_3 <<<"$output")
    got4=$(random_dates_lookup commit_4 <<<"$output")
    got5=$(random_dates_lookup commit_5 <<<"$output")

    if [[ -z "$got3" || -z "$got4" || -z "$got5" ]]; then
        printf 'Error: not all 3 commits in the contiguous run were assigned a date\n'
        errors=$((errors + 1))
    elif [[ ! ("$lo" -lt "$got3" && "$got3" -lt "$got4" && "$got4" -lt "$got5" && "$got5" -lt "$hi") ]]; then
        printf 'Error: contiguous run not strictly ordered within its real bounds (%s < %s < %s < %s < %s expected)\n' \
            "$lo" "$got3" "$got4" "$got5" "$hi"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'random dates: a contiguous target run is bounded by its real neighbors and stays internally ordered'
}

# UNIT TEST: the target run starts at the very first commit in history
# (commit_0), so there is no "before" neighbor to bound it with -- the
# lower bound must fall back to the bucket's own calendar start rather than
# the script inventing or crashing on a nonexistent neighbor.
test_random_dates_no_lower_neighbor_at_history_start() {
    local errors=0 history output hi got0 got1

    history=$(build_synthetic_history 10 86400)

    output=$(printf '%s\n' "$history" | run_random_dates_script ANON_GIT_RANDOMDAY 0 'commit_0 commit_1')

    hi=$(random_dates_lookup commit_2 <<<"$history")
    got0=$(random_dates_lookup commit_0 <<<"$output")
    got1=$(random_dates_lookup commit_1 <<<"$output")

    if [[ -z "$got0" || -z "$got1" ]]; then
        printf 'Error: commit_0/commit_1 missing from output\n'
        errors=$((errors + 1))
    elif [[ ! ("$got0" -lt "$got1" && "$got1" -lt "$hi") ]]; then
        printf 'Error: run starting at history'\''s first commit not correctly ordered/bounded (got0=%s got1=%s hi=%s)\n' \
            "$got0" "$got1" "$hi"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'random dates: a run starting at the very first commit needs no fabricated lower neighbor'
}

# UNIT TEST: mirror of the above at the other end -- the target run ends at
# the very last commit in history (commit_9), so there is no "after"
# neighbor; the upper bound must fall back to the bucket's calendar end.
test_random_dates_no_upper_neighbor_at_history_end() {
    local errors=0 history output lo got8 got9

    history=$(build_synthetic_history 10 86400)

    output=$(printf '%s\n' "$history" | run_random_dates_script ANON_GIT_RANDOMDAY 0 'commit_8 commit_9')

    lo=$(random_dates_lookup commit_7 <<<"$history")
    got8=$(random_dates_lookup commit_8 <<<"$output")
    got9=$(random_dates_lookup commit_9 <<<"$output")

    if [[ -z "$got8" || -z "$got9" ]]; then
        printf 'Error: commit_8/commit_9 missing from output\n'
        errors=$((errors + 1))
    elif [[ ! ("$lo" -lt "$got8" && "$got8" -lt "$got9") ]]; then
        printf 'Error: run ending at history'\''s last commit not correctly ordered/bounded (lo=%s got8=%s got9=%s)\n' \
            "$lo" "$got8" "$got9"
        errors=$((errors + 1))
    fi

    record_result "$errors" 'random dates: a run ending at the very last commit needs no fabricated upper neighbor'
}

# INTEGRATION TEST: same shape as test_flag_keep_partial (flags.sh), but for
# the random-* trio -- only the calendar fields the flag keeps are asserted
# unchanged (never asserting a change happened, since randomness could
# legitimately reproduce the original value).
test_flag_random_partial() {
    # @param $1  flag under test: --random-time | --random-day | --random-month
    local flag="$1" random_index commit_hash old_year old_month
    local new_commit_hash new_year new_month exit_status errors=0

    random_index=$(($(od -An -N2 -tu2 </dev/urandom) % (COMMIT_COUNT - 1)))
    commit_hash=$(git rev-parse "HEAD~${random_index}")
    old_year=$(git show -s --date=format:'%Y' --format='%ad' "$commit_hash")
    old_month=$(git show -s --date=format:'%m' --format='%ad' "$commit_hash")

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch "$flag" "HEAD~${random_index}" >/dev/null 2>&1
    exit_status=$?

    new_commit_hash=$(git rev-parse "HEAD~${random_index}")
    new_year=$(git show -s --date=format:'%Y' --format='%ad' "$new_commit_hash")
    new_month=$(git show -s --date=format:'%m' --format='%ad' "$new_commit_hash")

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: %s exited with status %s\n' "$flag" "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$new_year" != "$old_year" ]]; then
        printf 'Error: %s did not preserve year\n' "$flag"
        errors=$((errors + 1))
    fi
    if [[ "$flag" == '--random-time' && "$new_month" != "$old_month" ]]; then
        printf 'Error: %s changed month, expected it kept\n' "$flag"
        errors=$((errors + 1))
    fi

    record_result "$errors" "flag $flag"
}

# INTEGRATION TEST: mirrors test_multiple_commits (core.sh) -- only the
# explicitly targeted commits should change; everything else in the shared
# fixture repo must be left alone.
test_random_day_multiple_commits() {
    local h1 h2 exit_status old_month1 old_month2 new_month1 new_month2 errors=0

    h1=$(git rev-parse HEAD~1)
    h2=$(git rev-parse HEAD~3)

    old_month1=$(git show -s --date=format:'%Y-%m' --format='%ad' "$h1")
    old_month2=$(git show -s --date=format:'%Y-%m' --format='%ad' "$h2")

    ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --random-day "$h1" "$h2" >/dev/null 2>&1
    exit_status=$?

    new_month1=$(git show -s --date=format:'%Y-%m' --format='%ad' HEAD~1)
    new_month2=$(git show -s --date=format:'%Y-%m' --format='%ad' HEAD~3)

    if [[ "$exit_status" -ne 0 ]]; then
        printf 'Error: --random-day multi-commit run exited with status %s\n' "$exit_status"
        errors=$((errors + 1))
    fi
    if [[ "$new_month1" != "$old_month1" ]]; then
        printf 'Error: --random-day changed year/month of first target commit\n'
        errors=$((errors + 1))
    fi
    if [[ "$new_month2" != "$old_month2" ]]; then
        printf 'Error: --random-day changed year/month of second target commit\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --random-day with multiple explicit target commits'
}

# INTEGRATION TEST: a dedicated repo with commits pinned a few days apart
# within a single month, so --random-day's bucket (a whole month) is wider
# than the gaps between commits. Only two non-adjacent commits are
# targeted; the rest are real, untouched neighbors. Asserts the *entire*
# log stays in chronological order afterward, not just that the targets'
# own year/month didn't change -- the neighbor-bounding guarantee, exercised
# end to end through git-filter-repo rather than the script directly.
test_random_day_preserves_neighbor_order_real_repo() {
    local repo_dir errors=0 i ts h2 h5 order_ok=1 prev_ts cur_ts

    repo_dir="${TMP_DIR}/random_day_neighbor_repo"
    mkdir -p "$repo_dir"
    (
        cd "$repo_dir" || exit 1
        git init -q
        git config --local user.name "Jordan Blake"
        git config --local user.email "jordan.blake@example.com"
        cp "${SCRIPT_DIR}/${SCRIPT_NAME}" .
        chmod +x "./${SCRIPT_NAME}"
        for i in $(seq 0 7); do
            ts=$((1577836800 + i * 86400 * 3))
            echo "file $i" >"file_${i}.txt"
            git add "file_${i}.txt" >/dev/null
            GIT_AUTHOR_DATE="${ts} +0000" GIT_COMMITTER_DATE="${ts} +0000" \
                git commit -q -m "commit $i"
        done
    )

    h2=$(git -C "$repo_dir" rev-parse HEAD~5) # commit 2, 0-indexed from the bottom
    h5=$(git -C "$repo_dir" rev-parse HEAD~2) # commit 5

    (
        cd "$repo_dir" || exit 1
        ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --random-day "$h2" "$h5" >/dev/null 2>&1
    )

    prev_ts=0
    while read -r cur_ts; do
        if [[ "$cur_ts" -lt "$prev_ts" ]]; then
            order_ok=0
        fi
        prev_ts="$cur_ts"
    done < <(git -C "$repo_dir" log --reverse --format='%at')

    if [[ "$order_ok" -ne 1 ]]; then
        printf 'Error: --random-day with sparse targets produced a log out of chronological order relative to untouched neighbors\n'
        errors=$((errors + 1))
        git -C "$repo_dir" log --reverse --format='%ad' --date=iso-strict >&2
    fi

    record_result "$errors" 'flag --random-day keeps the whole log ordered relative to untouched neighboring commits'
}

# INTEGRATION TEST: a dedicated repo (not the shared COMMIT_COUNT fixture,
# whose commits are all made "now" within the same real day) with commits
# spread ~40 days apart across several years, so --random-month --entire-
# history has more than one calendar-year bucket to keep in relative order.
test_random_month_preserves_order_and_year() {
    local repo_dir errors=0 i ts before_years after_years order_ok=1
    local prev_ts cur_ts

    repo_dir="${TMP_DIR}/random_month_order_repo"
    mkdir -p "$repo_dir"
    (
        cd "$repo_dir" || exit 1
        git init -q
        git config --local user.name "Jordan Blake"
        git config --local user.email "jordan.blake@example.com"
        cp "${SCRIPT_DIR}/${SCRIPT_NAME}" .
        chmod +x "./${SCRIPT_NAME}"
        for i in $(seq 0 19); do
            ts=$((1546300800 + i * 86400 * 40))
            echo "file $i" >"file_${i}.txt"
            git add "file_${i}.txt" >/dev/null
            GIT_AUTHOR_DATE="${ts} +0000" GIT_COMMITTER_DATE="${ts} +0000" \
                git commit -q -m "commit $i"
        done
    )

    before_years=$(git -C "$repo_dir" log --reverse --date=format:'%Y' --format='%ad')

    (
        cd "$repo_dir" || exit 1
        ./"${SCRIPT_NAME}" --no-confirm --no-backup --current-branch --random-month --entire-history >/dev/null 2>&1
    )

    after_years=$(git -C "$repo_dir" log --reverse --date=format:'%Y' --format='%ad')

    if [[ "$before_years" != "$after_years" ]]; then
        printf 'Error: --random-month changed at least one commit year\n'
        errors=$((errors + 1))
    fi

    prev_ts=0
    while read -r cur_ts; do
        if [[ "$cur_ts" -lt "$prev_ts" ]]; then
            order_ok=0
        fi
        prev_ts="$cur_ts"
    done < <(git -C "$repo_dir" log --reverse --format='%at')

    if [[ "$order_ok" -ne 1 ]]; then
        printf 'Error: --random-month --entire-history produced out-of-order commit timestamps\n'
        errors=$((errors + 1))
    fi

    record_result "$errors" 'flag --random-month --entire-history preserves year and relative commit order across years'
}
