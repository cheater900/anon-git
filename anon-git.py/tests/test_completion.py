"""Shell completion: zsh/fish files list every flag, and TAB really
completes a flag and a ref in bash, zsh and fish (driven via pexpect)."""

import os
import re
import shutil
import sys
from importlib import resources

import pexpect
import pytest
from conftest import git, run_cli

import anon_git

PROMPT = "COMPLETION_TEST_PROMPT> "
REF_MARKER = "anon_git_completion_test_ref"


def completion_file(shell):
    return resources.files("anon_git") / "completions" / anon_git.COMPLETION_FILES[shell]


def test_zsh_fish_completions_list_all_flags():
    # Matched whole, so "date" can't hit "keep-date".
    zsh = completion_file("zsh").read_text()
    fish = completion_file("fish").read_text()
    assert "_list-flags" in completion_file("bash").read_text()
    for flag in anon_git.FLAGS:
        name = flag.rstrip("=").lstrip("-")
        if len(name) <= 1:
            continue
        assert re.search(rf"^ *'--{name}=?\[|[{{,]--{name}[,}}]", zsh, re.MULTILINE), name
        assert re.search(rf"-l {name}( |$)", fish, re.MULTILINE), name


def test_completions_omit_dropped_flags():
    for shell in anon_git.COMPLETION_FILES:
        text = completion_file(shell).read_text()
        for flag in anon_git.FLAGS_DROPPED:
            name = flag.lstrip("-")
            assert not re.search(rf"'--{name}\[|-l {name} ", text), (shell, flag)


def test_print_completion_rejects_unknown_shell(outside_repo):
    result = run_cli("--print-completion", "tcsh")
    assert result.returncode == 1
    assert 'unsupported shell "tcsh"' in result.stderr


@pytest.fixture
def anon_git_on_path(tmp_path, monkeypatch):
    # Completion scripts call `anon-git --_list-flags`; point it at this checkout.
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    wrapper = bin_dir / "anon-git"
    wrapper.write_text(f'#!/bin/sh\nexec "{sys.executable}" -m anon_git "$@"\n')
    wrapper.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")


def expect_completion(spawn, prompt_cmd, setup):
    # Ctrl-U clears the line: fish can drop a SIGINT mid-completion.
    shell = pexpect.spawn(spawn, encoding="utf-8", timeout=10)
    shell.sendline(prompt_cmd)
    shell.expect_exact(PROMPT)
    for line in setup:
        shell.sendline(line)
        shell.expect_exact(PROMPT)
    shell.send("anon-git --keep-u\t")
    shell.expect_exact("keep-user")
    shell.send("\x15")
    shell.send(f"anon-git {REF_MARKER[:20]}\t")
    shell.expect_exact(REF_MARKER)
    shell.terminate(force=True)


SHELLS = {
    "bash": ("bash --norc --noprofile", f"PS1='{PROMPT}'", []),
    "zsh": ("zsh -f", f"PS1='{PROMPT}'", ["autoload -Uz compinit && compinit -u"]),
    "fish": (
        "env TERM=dumb fish -N -P",
        f"function fish_prompt; echo -n '{PROMPT}'; end",
        [],
    ),
}


@pytest.mark.parametrize("shell", SHELLS)
def test_tab_completes_flag_and_ref(shell, repo, anon_git_on_path):
    if shutil.which(shell) is None:
        pytest.skip(f"{shell} not installed")
    git("tag", REF_MARKER)
    spawn, prompt_cmd, setup = SHELLS[shell]
    expect_completion(spawn, prompt_cmd, [*setup, f"source {completion_file(shell)}"])
