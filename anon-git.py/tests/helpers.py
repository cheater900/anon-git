"""Shared test constants and helpers: git wrappers, repo builders, CLI runners."""

import os
import random
import subprocess
import sys
from importlib import resources
from pathlib import Path

from anon_git.constants import COMPLETION_FILES, DEFAULT_EMAIL, DEFAULT_NAME

COMMIT_COUNT = 20
TEST_USER_NAME = "Jordan Blake"
TEST_USER_EMAIL = "jordan.blake@example.com"
DEFAULT_AUTHOR = f"{DEFAULT_NAME} <{DEFAULT_EMAIL}>"
CLI = [sys.executable, "-m", "anon_git"]
SECONDS_PER_HOUR = 3600
SECONDS_PER_DAY = 86400
EPOCH_2019 = 1546300800
EPOCH_2020 = 1577836800
SHELL_SCRIPT = Path(__file__).resolve().parents[2] / "anon-git.sh" / "anon-git.sh"
# Rewrite the current branch in place: no prompt, no backup branch.
REWRITE = ("--no-confirm", "--no-backup", "--current-branch")


def git(*args, cwd=None, env=None):
    result = subprocess.run(
        ["git", *args], cwd=cwd, env=env, capture_output=True, text=True, check=True
    )
    return result.stdout.rstrip("\n")


def new_repo(path):
    git("init", "-q", str(path))
    git("-C", str(path), "config", "--local", "user.name", TEST_USER_NAME)
    git("-C", str(path), "config", "--local", "user.email", TEST_USER_EMAIL)
    return path


def commit(message, date=None, cwd=None):
    env = None
    if date is not None:
        env = {**os.environ, "GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date}
    git("commit", "-q", "--allow-empty", "-m", message, cwd=cwd, env=env)


def run_cli(*args, env=None, input=None, cwd=None):
    """Runs anon-git in a subprocess, like a user would."""
    full_env = {**os.environ, **(env or {})}
    return subprocess.run(
        [*CLI, *args],
        cwd=cwd,
        env=full_env,
        input=input,
        capture_output=True,
        text=True,
    )


def run_cli_without_tty(*args):
    """New session: no controlling terminal, so /dev/tty can't be opened."""
    return subprocess.run(
        [*CLI, *args],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        start_new_session=True,
    )


def preview_count(output):
    return sum(line.startswith("Commit:") for line in output.splitlines())


def commit_author(rev):
    return git("show", "-s", "--format=%an <%ae>", rev)


def commit_committer(rev):
    return git("show", "-s", "--format=%cn <%ce>", rev)


def commit_date(rev, fmt):
    return git("show", "-s", f"--date=format:{fmt}", "--format=%ad", rev)


def history_authors():
    return sorted(set(git("log", "--format=%an <%ae>").splitlines()))


def head():
    return git("rev-parse", "HEAD")


def branch_count():
    return len(git("branch", "--list").splitlines())


def pick_random_index():
    """Random HEAD~N target. Set TEST_RANDOM_INDEX to replay a failure."""
    index = int(os.environ.get("TEST_RANDOM_INDEX", random.randrange(COMMIT_COUNT - 1)))
    print(f"target HEAD~{index}, replay with TEST_RANDOM_INDEX={index}")
    return index


def completion_file(shell):
    return resources.files("anon_git") / "completions" / COMPLETION_FILES[shell]
