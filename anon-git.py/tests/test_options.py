"""Option resolution: flags > git config anon-git.* > ANON_GIT_* envvars >
defaults, group ownership and conflicts. Unit tests on the pure functions,
then end-to-end runs ported from config_priority.bats."""

import itertools

import pytest
from conftest import (
    COMMIT_COUNT,
    DEFAULT_AUTHOR,
    REWRITE,
    branch_count,
    commit_author,
    git,
    head,
    history_authors,
    pick_random_index,
    preview_count,
    run_cli,
)

import anon_git

# Every option that decides the date; any two together conflict.
DATE_OPTIONS = anon_git.GROUP_DATE


def sources(arg=None, config=None, env=None):
    return {"ARG": dict(arg or {}), "GITCONFIG": dict(config or {}), "ANON_GIT": dict(env or {})}


def value_for(opt):
    return "2020-01-01 00:00:00 +0000" if opt == "DATE" else "1"


# ── unit: drop_overridden_sources / reject_incompatible_options ──────────


@pytest.mark.parametrize("first, second", list(itertools.combinations(DATE_OPTIONS, 2)))
@pytest.mark.parametrize("source", anon_git.SOURCES)
def test_two_date_options_same_source_conflict(first, second, source):
    src = sources()
    src[source] = {first: value_for(first), second: value_for(second)}
    errors = anon_git.reject_incompatible_options(anon_git.drop_overridden_sources(src), [])
    assert len(errors) == 1
    assert "cannot be used together" in errors[0]


@pytest.mark.parametrize("identity", ["NAME", "EMAIL"])
@pytest.mark.parametrize("source", anon_git.SOURCES)
def test_keepuser_with_identity_same_source_conflicts(identity, source):
    src = sources()
    src[source] = {"KEEPUSER": "1", identity: "x"}
    errors = anon_git.reject_incompatible_options(anon_git.drop_overridden_sources(src), [])
    assert errors == [f"Error: --keep-user and --{identity.lower()} cannot be used together"]


@pytest.mark.parametrize("high, low", list(itertools.combinations(anon_git.SOURCES, 2)))
def test_higher_source_owns_date_group(high, low):
    src = sources()
    src[high] = {"KEEPDATE": "1"}
    src[low] = {"DATE": "2020-01-01 00:00:00 +0000"}
    src = anon_git.drop_overridden_sources(src)
    assert anon_git.reject_incompatible_options(src, []) == []
    assert anon_git.merge_args_with_defaults(src)["DATE"] == anon_git.DEFAULT_DATE


def test_bool_zero_does_not_own_group():
    src = anon_git.drop_overridden_sources(sources(config={"KEEPUSER": "0"}, env={"NAME": "Env"}))
    assert anon_git.merge_args_with_defaults(src)["NAME"] == "Env"


def test_quiet_verbose_flags_conflict():
    errors = anon_git.reject_incompatible_options(sources(arg={"QUIET": "1", "VERBOSE": "1"}), [])
    assert errors == ["Error: --quiet and --verbose cannot be used together"]


def test_verbose_beats_quiet_config_and_env():
    src = sources(arg={"VERBOSE": "1"}, config={"QUIET": "1"}, env={"QUIET": "1"})
    assert anon_git.reject_incompatible_options(src, []) == []
    assert anon_git.merge_args_with_defaults(src)["QUIET"] == "0"


def test_entire_history_env_with_commit_conflicts():
    errors = anon_git.reject_incompatible_options(sources(env={"ENTIREHISTORY": "1"}), ["abc"])
    assert errors == ["Error: commit(s) argument and --entire-history cannot be used together"]


def test_merge_priority_flag_config_env_default():
    src = sources(
        arg={"NAME": "Flag"}, config={"NAME": "Config", "EMAIL": "c@x"}, env={"DATE": "d"}
    )
    resolved = anon_git.merge_args_with_defaults(src)
    assert (resolved["NAME"], resolved["EMAIL"], resolved["DATE"]) == ("Flag", "c@x", "d")
    assert resolved["KEEPUSER"] == "0"


def test_strip_timezone_alone_keeps_user_and_date():
    resolved = anon_git.merge_args_with_defaults(sources())
    out = anon_git.apply_strip_timezone_alone({"STRIPTIMEZONE": "1", "NOCONFIRM": "1"}, resolved)
    assert (out["KEEPUSER"], out["KEEPDATE"]) == ("1", "1")


@pytest.mark.parametrize("opt", anon_git.GROUP_IDENTITY + anon_git.GROUP_DATE)
def test_strip_timezone_with_other_flag_keeps_precedence(opt):
    resolved = anon_git.merge_args_with_defaults(sources())
    out = anon_git.apply_strip_timezone_alone({"STRIPTIMEZONE": "1", opt: "x"}, resolved)
    assert out == resolved


def test_invalid_bool_envvar_fails(repo, head_before):
    result = run_cli(*REWRITE, "HEAD", env={"ANON_GIT_KEEPUSER": "yes"})
    assert result.returncode == 1
    assert 'must resolve to "0" or "1"' in result.stderr
    assert head() == head_before


# ── end to end ───────────────────────────────────────────────────────────


def test_dry_run_entire_history_previews_all(repo, head_before):
    result = run_cli("--dry-run", "--entire-history", env={"PAGER": "cat"})
    assert result.returncode == 0, result.stderr
    assert head() == head_before
    assert preview_count(result.stdout) == COMMIT_COUNT


def test_dryrun_entirehistory_envvars_preview_all(repo, head_before):
    env = {"PAGER": "cat", "ANON_GIT_DRYRUN": "1", "ANON_GIT_ENTIREHISTORY": "1"}
    result = run_cli("--no-confirm", env=env)
    assert result.returncode == 0, result.stderr
    assert head() == head_before
    assert preview_count(result.stdout) == COMMIT_COUNT


def test_name_flag_overrides_envvar(repo):
    result = run_cli(*REWRITE, "--name", "Flag Wins", "HEAD", env={"ANON_GIT_NAME": "Ignored"})
    assert result.returncode == 0, result.stderr
    assert git("show", "-s", "--format=%an", "HEAD") == "Flag Wins"
    assert "Ignored" not in git("show", "-s", "--pretty=fuller", "HEAD")


def test_flag_overrides_envvar_of_same_group(repo):
    author = git("show", "-s", "--format=%an", "HEAD")
    result = run_cli(*REWRITE, "--keep-user", "HEAD", env={"ANON_GIT_NAME": "Env Name"})
    assert result.returncode == 0, result.stderr
    assert git("show", "-s", "--format=%an", "HEAD") == author
    date = "2021-02-03 04:05:06 +0000"
    result = run_cli(*REWRITE, "--date", date, "HEAD", env={"ANON_GIT_KEEPDATE": "1"})
    assert result.returncode == 0, result.stderr
    assert git("show", "-s", "--format=%ai", "HEAD") == date


def test_envvars_overwrite_defaults(repo):
    target = f"HEAD~{pick_random_index()}"
    env = {
        "ANON_GIT_NAME": "Grace Murray",
        "ANON_GIT_EMAIL": "grace.murray@example.com",
        "ANON_GIT_DATE": "2019-05-05 00:00:00 +0000",
    }
    result = run_cli(*REWRITE, target, env=env)
    assert result.returncode == 0, result.stderr
    assert commit_author(target) == "Grace Murray <grace.murray@example.com>"
    assert git("show", "-s", "--format=%ai", target) == "2019-05-05 00:00:00 +0000"


def test_git_config_sets_repo_defaults(repo):
    git("config", "--local", "anon-git.name", "Barbara McClintock")
    git("config", "--local", "anon-git.email", "barbara.mcclintock@example.com")
    git("config", "--local", "anon-git.date", "2018-08-08 00:00:00 +0000")
    result = run_cli(*REWRITE, "HEAD")
    assert result.returncode == 0, result.stderr
    assert commit_author("HEAD") == "Barbara McClintock <barbara.mcclintock@example.com>"
    assert git("show", "-s", "--format=%ai", "HEAD") == "2018-08-08 00:00:00 +0000"


def test_config_name_overrides_envvar(repo):
    git("config", "--local", "anon-git.name", "Config Wins")
    result = run_cli(*REWRITE, "HEAD", env={"ANON_GIT_NAME": "Envvar Loses"})
    assert result.returncode == 0, result.stderr
    assert git("show", "-s", "--format=%an", "HEAD") == "Config Wins"
    assert "Envvar Loses" not in git("show", "-s", "--pretty=fuller", "HEAD")


def test_name_flag_overrides_config(repo):
    git("config", "--local", "anon-git.name", "Config Loses")
    result = run_cli(*REWRITE, "--name", "Flag Wins", "HEAD")
    assert result.returncode == 0, result.stderr
    assert git("show", "-s", "--format=%an", "HEAD") == "Flag Wins"


@pytest.mark.parametrize("spelling", ["yes", "YES", "True", "on", "1"])
def test_keepuser_config_bool_spellings_act_as_flag(repo, spelling):
    author = commit_author("HEAD")
    git("config", "--local", "anon-git.keepuser", spelling)
    result = run_cli(*REWRITE, "HEAD")
    assert result.returncode == 0, result.stderr
    assert commit_author("HEAD") == author


def test_non_boolean_keepuser_config_fails(repo, head_before):
    git("config", "--local", "anon-git.keepuser", "bogus")
    result = run_cli("--no-confirm", "--no-backup", "HEAD")
    assert result.returncode == 1
    assert "invalid boolean value" in result.stderr
    assert head() == head_before


def test_keepuser_config_with_email_config_rejected(repo, head_before):
    git("config", "--local", "anon-git.keepuser", "true")
    git("config", "--local", "anon-git.email", "nobody@example.com")
    result = run_cli("--no-confirm", "--no-backup", "HEAD")
    assert result.returncode == 1
    assert head() == head_before


def test_quiet_config_silences_verbose_overrides(repo):
    original_branch = git("branch", "--show-current")
    git("config", "--local", "anon-git.quiet", "true")
    result = run_cli("--no-confirm", "--name", "Grace Hopper Quiet", "HEAD")
    assert result.returncode == 0, result.stderr
    assert result.stdout == ""
    git("switch", "-q", original_branch)
    result = run_cli("--no-confirm", "--verbose", "--name", "Grace Hopper Verbose", "HEAD")
    assert "Anonymizing commit" in result.stdout


def test_entirehistory_envvar_rewrites_all(repo):
    result = run_cli(*REWRITE, env={"ANON_GIT_ENTIREHISTORY": "1"})
    assert result.returncode == 0, result.stderr
    assert history_authors() == [DEFAULT_AUTHOR]


def test_entirehistory_envvar_with_commit_rejected(repo, head_before):
    result = run_cli(*REWRITE, "HEAD", env={"ANON_GIT_ENTIREHISTORY": "1"})
    assert result.returncode == 1
    assert "cannot be used together" in result.stderr
    assert head() == head_before


def test_currentbranch_envvar_rewrites_in_place(repo, head_before):
    branch = git("branch", "--show-current")
    result = run_cli(
        "--no-confirm",
        "--no-backup",
        "--name",
        "Barbara Liskov",
        "HEAD",
        env={"ANON_GIT_CURRENTBRANCH": "1"},
    )
    assert result.returncode == 0, result.stderr
    assert head() != head_before
    assert git("branch", "--show-current") == branch


def test_dryrun_envvar_previews_no_rewrite(repo, head_before):
    result = run_cli("HEAD", env={"PAGER": "cat", "ANON_GIT_DRYRUN": "1"})
    assert result.returncode == 0, result.stderr
    assert head() == head_before
    assert branch_count() == 1
    assert "AuthorDate:" in result.stdout


def test_verbose_overrides_quiet_envvar(repo):
    result = run_cli(
        *REWRITE, "--verbose", "--name", "Dennis Ritchie", "HEAD", env={"ANON_GIT_QUIET": "1"}
    )
    assert result.returncode == 0, result.stderr
    assert "Anonymizing commit" in result.stdout
