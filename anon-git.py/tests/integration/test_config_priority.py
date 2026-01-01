"""End-to-end priority among flags, git config anon-git.* and ANON_GIT_* envvars."""

import pytest
from helpers import (
    COMMIT_COUNT,
    DEFAULT_AUTHOR,
    PAGER_CAT,
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


def test_invalid_bool_envvar_fails(repo, head_before):
    result = run_cli(*REWRITE, "HEAD", env={"ANON_GIT_KEEPUSER": "yes"})
    assert result.returncode == 1
    assert 'must resolve to "0" or "1"' in result.stderr
    assert head() == head_before


def test_dry_run_entire_history_previews_all(repo, head_before):
    result = run_cli("--dry-run", "--entire-history", env=PAGER_CAT)
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
