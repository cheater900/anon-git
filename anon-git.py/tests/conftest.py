"""Shared fixtures. Each test runs in `repo`, a fresh copy of a 20-commit
template repo, so one test's leftovers can't cascade into the next."""

import os
import shutil

import pytest
from helpers import COMMIT_COUNT, git, head, new_repo


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
def head_before(repo):
    return head()


@pytest.fixture
def outside_repo(tmp_path, monkeypatch):
    path = tmp_path / "norepo"
    path.mkdir()
    monkeypatch.chdir(path)
    return path
