"""--help, --version, --print-completion and the default-to-help paths."""

import re

import pytest
from helpers import PAGER_CAT, append_line, completion_file, head, run_cli

from anon_git.constants import DEFAULT_EMAIL, FLAGS_DROPPED

VERSION_RE = r"^anon-git [0-9]+\.[0-9]+\.[0-9]+\n$"


def test_help_shows_usage(repo):
    result = run_cli("--help")
    assert result.returncode == 0
    assert "Usage:" in result.stdout


def test_version_prints_version(repo):
    for flag in ("--version", "-v"):
        result = run_cli(flag)
        assert result.returncode == 0
        assert re.match(VERSION_RE, result.stdout)


def test_version_works_outside_repo(outside_repo):
    result = run_cli("--version")
    assert result.returncode == 0
    assert re.match(VERSION_RE, result.stdout)


def test_no_args_in_dirty_repo_shows_help(repo):
    # Help comes before safety checks; a tracked-file change must not block it.
    append_line("file_1.txt", "uncommitted change")
    before = head()
    result = run_cli()
    assert result.returncode == 0
    assert "Usage:" in result.stdout
    assert head() == before


def test_name_value_not_taken_as_help(repo):
    # `--name --help` sets the name; it must not short-circuit to help.
    result = run_cli("--dry-run", "--name", "--help", "HEAD", env=PAGER_CAT)
    assert "Usage:" not in result.stdout
    assert f"-> --help <{DEFAULT_EMAIL}>" in result.stdout


def test_dropped_install_flag_points_to_uv(outside_repo):
    for flag in FLAGS_DROPPED:
        result = run_cli(flag)
        assert result.returncode == 1
        assert "uv tool install" in result.stderr


def test_no_target_shows_help(repo):
    before = head()
    result = run_cli("--no-confirm")
    assert result.returncode == 0
    assert "Usage:" in result.stdout
    assert head() == before


def test_dry_run_without_target_shows_help(repo):
    before = head()
    result = run_cli("--dry-run", env=PAGER_CAT)
    assert result.returncode == 0
    assert "Usage:" in result.stdout
    assert head() == before


def test_print_completion_rejects_unknown_shell(outside_repo):
    result = run_cli("--print-completion", "tcsh")
    assert result.returncode == 1
    assert 'unsupported shell "tcsh"' in result.stderr


@pytest.mark.parametrize(
    "args, env, shell", [(["fish"], {}, "fish"), ([], {"SHELL": "/usr/bin/zsh"}, "zsh")]
)
def test_print_completion_prints_shell_script(outside_repo, args, env, shell):
    result = run_cli("--print-completion", *args, env=env)
    assert result.returncode == 0, result.stderr
    assert result.stdout == completion_file(shell).read_text()
