"""TAB really completes a flag and a ref in bash, zsh and fish (pexpect)."""

import os
import shutil
import sys

import pexpect
import pytest
from helpers import completion_file, git

PROMPT = "COMPLETION_TEST_PROMPT> "


REF_MARKER = "anon_git_completion_test_ref"


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
