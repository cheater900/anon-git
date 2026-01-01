#!/usr/bin/env bash

# Runs the anon-git.sh test suite: lib/common.sh (shared setup/helpers) and
# cases/*.sh (test_* functions by category), sourced here so every test
# function shares $TMP_DIR, $SCRIPT, and lib/common.sh's pass/fail counters.

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)

# shellcheck source=tests/lib/common.sh
source "${TESTS_DIR}/lib/common.sh"
# shellcheck source=tests/cases/core.sh
source "${TESTS_DIR}/cases/core.sh"
# shellcheck source=tests/cases/validation.sh
source "${TESTS_DIR}/cases/validation.sh"
# shellcheck source=tests/cases/config_priority.sh
source "${TESTS_DIR}/cases/config_priority.sh"
# shellcheck source=tests/cases/install.sh
source "${TESTS_DIR}/cases/install.sh"
# shellcheck source=tests/cases/flags.sh
source "${TESTS_DIR}/cases/flags.sh"
# shellcheck source=tests/cases/help.sh
source "${TESTS_DIR}/cases/help.sh"
# shellcheck source=tests/cases/regression.sh
source "${TESTS_DIR}/cases/regression.sh"
# shellcheck source=tests/cases/random_dates.sh
source "${TESTS_DIR}/cases/random_dates.sh"

main() {
    init_repo
    test_python_callback_syntax
    test_python_random_dates_syntax
    test_random_dates_order_within_bucket --random-time ANON_GIT_RANDOMTIME
    test_random_dates_order_within_bucket --random-day ANON_GIT_RANDOMDAY
    test_random_dates_order_within_bucket --random-month ANON_GIT_RANDOMMONTH
    test_random_dates_neighbor_bounds_sparse_targets
    test_random_dates_neighbor_bounds_contiguous_run
    test_random_dates_no_lower_neighbor_at_history_start
    test_random_dates_no_upper_neighbor_at_history_end
    test_random_dates_merge_neighbors
    test_script
    test_script --name 'Grace Hopper'
    test_script --name 'Alan Turing' --email 'alan.turing@example.com'
    test_script --name 'Ada Lovelace' --email 'ada.lovelace@example.com' --date '2020-01-01 00:03:03 +0000'
    test_script --name 'Katherine Johnson' --date '2020-01-01 00:04:04 +0000'
    test_script --email 'margaret.hamilton@example.com'
    test_script --email 'barbara.liskov@example.com' --date '2020-10-31 00:06:06 +0000'
    test_script --date '2020-01-01 00:07:07 +0000'
    test_script --keep-date
    test_script --keep-date --name 'Radia Perlman'
    test_script --keep-date --name 'Hedy Lamarr' --email 'hedy.lamarr@example.com'
    test_script --keep-user
    test_script --keep-user --date '2020-01-01 00:10:10 +0000'
    test_multiple_commits
    test_entire_history
    test_catch_incompatible --date '2020-01-01 00:00:00 +0000' --keep-date
    test_catch_incompatible --date '2020-01-01 00:00:00 +0000' --keep-year
    test_catch_incompatible --keep-user --name 'Nobody'
    test_catch_incompatible --keep-user --email 'nobody@example.com'
    test_catch_incompatible --keep-year --keep-month
    test_catch_incompatible --keep-year --keep-day
    test_catch_incompatible --keep-month --keep-day
    test_catch_incompatible --entire-history HEAD
    # random-time/day/month: only one at a time, none with --keep-*
    # (both families dictate a fill strategy), none with an explicit --date.
    test_catch_incompatible --random-day --keep-day
    test_catch_incompatible --random-time --keep-year
    test_catch_incompatible --random-month --keep-month
    test_catch_incompatible --keep-date --random-time
    test_catch_incompatible --random-time --random-day
    test_catch_incompatible --random-day --random-month
    test_catch_incompatible --random-time --random-month
    test_catch_incompatible --date '2020-01-01 00:00:00 +0000' --random-month
    # Same combinations via their ANON_GIT_* envvar equivalents (--entire-history
    # has none: no ANON_GIT_COMMIT envvar exists, so it's flag-only).
    test_catch_incompatible 'ANON_GIT_DATE=2020-01-01 00:00:00 +0000' ANON_GIT_KEEPDATE=1
    test_catch_incompatible 'ANON_GIT_DATE=2020-01-01 00:00:00 +0000' ANON_GIT_KEEPYEAR=1
    test_catch_incompatible ANON_GIT_KEEPUSER=1 ANON_GIT_NAME=Nobody
    test_catch_incompatible ANON_GIT_KEEPUSER=1 ANON_GIT_EMAIL=nobody@example.com
    test_catch_incompatible ANON_GIT_KEEPYEAR=1 ANON_GIT_KEEPMONTH=1
    test_catch_incompatible ANON_GIT_KEEPYEAR=1 ANON_GIT_KEEPDAY=1
    test_catch_incompatible ANON_GIT_KEEPMONTH=1 ANON_GIT_KEEPDAY=1
    test_catch_incompatible ANON_GIT_RANDOMDAY=1 ANON_GIT_KEEPDAY=1
    test_catch_incompatible ANON_GIT_RANDOMTIME=1 ANON_GIT_RANDOMMONTH=1
    # Mixed: one side via flag, the other via envvar.
    test_catch_incompatible --keep-user ANON_GIT_NAME=Nobody
    test_catch_incompatible ANON_GIT_KEEPUSER=1 --name 'Nobody'
    test_catch_invalid_commit
    test_catch_uncommitted_changes
    test_combo_dry_run_entire_history
    test_combo_env_var_dry_run_entire_history
    test_combo_env_var_flag_priority
    test_flag_current_branch_backup
    test_flag_dry_run cat
    test_flag_dry_run "cat -u"
    test_flag_env_vars
    test_gitconfig_defaults
    test_gitconfig_beats_envvar
    test_gitconfig_flag_priority
    test_gitconfig_keepuser_bool
    test_gitconfig_invalid_bool
    test_gitconfig_catch_incompatible
    test_gitconfig_quiet
    test_flag_env_var_entirehistory
    test_catch_env_var_entirehistory_with_commit
    test_flag_env_var_currentbranch
    test_flag_env_var_dryrun
    test_flag_install_local_bin
    test_flag_install_print_completion
    test_flag_install_as_flag_value
    test_flag_install_bin_fallback
    test_flag_install_both_dirs
    test_flag_install_path_already_set
    test_flag_install_no_target_dir
    test_flag_install_idempotent
    test_flag_uninstall_removes_both_dirs
    test_flag_uninstall_skips_missing_dir
    test_flag_uninstall_nothing_installed
    test_flag_install_hook_creates_hook
    test_flag_install_hook_requires_git_repo
    test_flag_install_hook_preserves_foreign_hook
    test_flag_install_hook_honors_hookspath
    test_flag_install_hook_partial_commit
    test_flag_install_hook_skips_rebase
    test_flag_install_hook_idempotent
    test_flag_install_hook_anonymizes_next_commit
    test_show_help
    test_show_version
    test_show_help_inside_dirty_repo
    test_flag_keep_partial --keep-year
    test_flag_keep_partial --keep-month
    test_flag_keep_partial --keep-day
    test_flag_random_partial --random-time
    test_flag_random_partial --random-day
    test_flag_random_partial --random-month
    test_random_day_multiple_commits
    test_random_day_preserves_neighbor_order_real_repo
    test_random_month_preserves_order_and_year
    test_flag_missing_value --date
    test_flag_missing_value --name
    test_flag_missing_value --email
    test_flag_new_branch
    test_flag_no_backup
    test_flag_quiet
    test_flag_strip_timezone_alone
    test_flag_strip_timezone_with_keep_date
    test_flag_strip_timezone_with_date_arg
    test_flag_strip_timezone_not_alone_resets_date
    test_flag_verbose_overrides_env_quiet
    test_catch_incompatible_quiet_verbose
    test_flag_install_hook_quiet
    test_flag_uninstall_hook_removes_hook
    test_flag_uninstall_hook_requires_git_repo
    test_flag_uninstall_hook_nothing_installed
    test_flag_uninstall_hook_preserves_foreign_hook
    test_flag_no_confirm
    test_noconfirm_executes_first
    test_confirm_without_tty
    test_flag_keep_user_keep_date_verbose_message
    test_flag_unknown
    test_match_default_shows_help
    test_match_detached_head_current_branch
    test_match_dry_run_without_target_shows_help
    test_match_malformed_date
    test_match_malformed_date_no_branch
    test_match_unreachable_commit
    test_match_outside_git_repo
    test_match_annotated_tag
    test_match_dry_run_keeps_signed_commit
    test_match_dry_run_non_utf8
    test_match_rerun_cache
    test_match_clean_cache_from_subdir
    test_match_trap_cleanup_on_kill
    test_match_shell_injection_email
    test_match_shell_injection_name
    test_match_merge_commit
    test_match_merge_commit_single_target
    test_match_merge_commit_ancestor_only
    printf -- '----------------------------------------\n'
    printf 'Summary: %s/%s tests passed (%s errors)\n' "$TESTS_PASSED" "$((TESTS_PASSED + TESTS_FAILED))" "$TOTAL_ERRORS"
    if [[ "$TESTS_FAILED" -eq 0 ]]; then
        printf 'Result: PASS\n'
    else
        printf 'Result: FAIL (%s test(s) failed)\n' "$TESTS_FAILED"
    fi
}

main
[[ "$TESTS_FAILED" -eq 0 ]]
