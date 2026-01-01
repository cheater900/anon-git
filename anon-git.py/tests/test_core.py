"""Rewrites: single target with each identity/date flag mix, multiple
commits, entire history, dry run."""

import pytest
from conftest import (
    COMMIT_COUNT,
    DEFAULT_AUTHOR,
    branch_count,
    commit_author,
    commit_committer,
    git,
    head,
    history_authors,
    pick_random_index,
    preview_count,
    run_cli,
)

import anon_git

LOG_FORMAT = "--format=%an <%aE> (%ai) %cn <%cE> (%ci)"


def commits_except(index):
    lines = git("log", LOG_FORMAT).splitlines()
    return lines[:index] + lines[index + 1 :]


def option(args, flag, default):
    return args[args.index(flag) + 1] if flag in args else default


REWRITES = [
    [],
    ["--name", "Grace Hopper"],
    ["--name", "Alan Turing", "--email", "alan.turing@example.com"],
    ["--name", "Ada Lovelace", "--email", "ada@example.com", "--date", "2020-01-01 00:03:03 +0000"],
    ["--name", "Katherine Johnson", "--date", "2020-01-01 00:04:04 +0000"],
    ["--email", "margaret.hamilton@example.com"],
    ["--email", "barbara.liskov@example.com", "--date", "2020-10-31 00:06:06 +0000"],
    ["--date", "2020-01-01 00:07:07 +0000"],
    ["--date", "2020-01-01 03:07:07 -0230"],
    ["--date", "2025-06-15T14:20:00Z"],
    ["--keep-date"],
    ["--keep-date", "--name", "Radia Perlman"],
    ["--keep-date", "--name", "Hedy Lamarr", "--email", "hedy.lamarr@example.com"],
    ["--keep-user"],
    ["--keep-user", "--date", "2020-01-01 00:10:10 +0000"],
]


@pytest.mark.parametrize("args", REWRITES)
def test_rewrite_changes_only_target(repo, args):
    index = pick_random_index()
    target = f"HEAD~{index}"
    old_user = commit_author(target), commit_committer(target)
    old_date = git("show", "-s", "--format=%ai %ci", target)
    untouched = commits_except(index)
    result = run_cli("--no-confirm", "--no-backup", *args, target)
    assert result.returncode == 0, result.stderr
    if "--keep-user" in args:
        assert (commit_author(target), commit_committer(target)) == old_user
    else:
        expected = (
            f"{option(args, '--name', anon_git.DEFAULT_NAME)} "
            f"<{option(args, '--email', anon_git.DEFAULT_EMAIL)}>"
        )
        assert commit_author(target) == expected
        assert commit_committer(target) == expected
    if "--keep-date" in args:
        assert git("show", "-s", "--format=%ai %ci", target) == old_date
    else:
        date = anon_git.parse_target_date(option(args, "--date", anon_git.DEFAULT_DATE))
        expected_date = date.strftime("%Y-%m-%d %H:%M:%S %z")
        assert git("show", "-s", "--format=%ai", target) == expected_date
        assert git("show", "-s", "--format=%ci", target) == expected_date
    assert commits_except(index) == untouched


def test_multiple_commits_per_run(repo):
    author = "Donald Knuth <donald.knuth@example.com>"
    result = run_cli(
        "--no-confirm",
        "--no-backup",
        "--current-branch",
        "--name",
        "Donald Knuth",
        "--email",
        "donald.knuth@example.com",
        "HEAD~1",
        "HEAD~3",
    )
    assert result.returncode == 0, result.stderr
    assert commit_author("HEAD~1") == author
    assert commit_author("HEAD~3") == author
    assert commit_author("HEAD~2") != author


def test_entire_history_rewrites_all(repo):
    result = run_cli("--no-confirm", "--no-backup", "--current-branch", "--entire-history")
    assert result.returncode == 0, result.stderr
    assert history_authors() == [DEFAULT_AUTHOR]


def test_duplicate_targets_rewrite_once(repo):
    result = run_cli("--no-confirm", "--no-backup", "--current-branch", "HEAD", "HEAD")
    assert result.returncode == 0, result.stderr
    assert commit_author("HEAD") == DEFAULT_AUTHOR


@pytest.mark.parametrize("pager", ["cat", "cat -u"])
def test_dry_run_previews_without_rewrite(repo, head_before, pager):
    refs_before = git("for-each-ref")
    result = run_cli("--dry-run", "HEAD", env={"PAGER": pager})
    assert result.returncode == 0, result.stderr
    assert head() == head_before
    assert git("for-each-ref") == refs_before
    assert branch_count() == 1
    assert "AuthorDate:" in result.stdout
    assert f"-> {DEFAULT_AUTHOR}" in result.stdout
    assert "Add file file_20.txt" in result.stdout


def test_dry_run_without_pager_prints_preview(repo):
    result = run_cli("--dry-run", "--entire-history")
    assert result.returncode == 0, result.stderr
    assert preview_count(result.stdout) == COMMIT_COUNT
