"""--help, --version, and the default-to-help paths."""

import re

from conftest import head, run_cli

import anon_git

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
    with open("file_1.txt", "a") as fh:
        fh.write("uncommitted change\n")
    before = head()
    result = run_cli()
    assert result.returncode == 0
    assert "Usage:" in result.stdout
    assert head() == before


def test_name_value_not_taken_as_help(repo):
    # `--name --help` sets the name; it must not short-circuit to help.
    result = run_cli("--name", "--help")
    assert "Usage:" not in result.stdout


def test_help_lists_every_flag():
    help_text = anon_git.HELP
    for flag in anon_git.FLAGS:
        assert flag.rstrip("=") in help_text


def test_help_omits_dropped_install_flags():
    options = anon_git.HELP.split("Options:")[1].split("Arguments:")[0]
    for flag in anon_git.FLAGS_DROPPED:
        assert not re.search(rf"^  {flag}\s", options, re.MULTILINE)


def test_dropped_install_flag_points_to_uv(outside_repo):
    for flag in anon_git.FLAGS_DROPPED:
        result = run_cli(flag)
        assert result.returncode == 1
        assert "uv tool install" in result.stderr
