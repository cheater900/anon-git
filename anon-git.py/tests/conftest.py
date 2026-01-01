"""Shared fixtures. Each test runs in `repo`, a fresh copy of a 20-commit
template repo, so one test's leftovers can't cascade into the next."""

import os
import random
import shutil
import subprocess
import sys

import pytest

COMMIT_COUNT = 20
TEST_USER_NAME = "Jordan Blake"
TEST_USER_EMAIL = "jordan.blake@example.com"


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
        [sys.executable, "-m", "anon_git", *args],
        cwd=cwd,
        env=full_env,
        input=input,
        capture_output=True,
        text=True,
    )


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


@pytest.fixture(autouse=True)
def isolated_env(monkeypatch, tmp_path_factory):
    # The user's own ANON_GIT_*, pager or global git config must not leak in.
    for key in list(os.environ):
        if key.startswith("ANON_GIT_"):
            monkeypatch.delenv(key)
    monkeypatch.delenv("PAGER", raising=False)
    gitconfig = tmp_path_factory.mktemp("home") / ".gitconfig"
    gitconfig.write_text("")
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", str(gitconfig))
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")


@pytest.fixture(scope="session")
def template_repo(tmp_path_factory):
    path = new_repo(tmp_path_factory.mktemp("template") / "repo")
    env = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}
    for i in range(1, COMMIT_COUNT + 1):
        (path / f"file_{i}.txt").write_text(f"This is file {i}\n")
        git("add", f"file_{i}.txt", cwd=path, env=env)
        git("commit", "-q", "-m", f"Add file file_{i}.txt", cwd=path, env=env)
    return path


@pytest.fixture
def repo(template_repo, tmp_path, monkeypatch):
    path = tmp_path / "repo"
    shutil.copytree(template_repo, path, symlinks=True)
    monkeypatch.chdir(path)
    # The copy's stat info differs from the index; refresh so the tree is clean.
    git("update-index", "-q", "--refresh")
    return path


@pytest.fixture
def outside_repo(tmp_path, monkeypatch):
    path = tmp_path / "norepo"
    path.mkdir()
    monkeypatch.chdir(path)
    return path
