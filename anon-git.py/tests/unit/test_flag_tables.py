"""Flag tables stay in sync with --help and the completion scripts."""

import re

from helpers import completion_file

from anon_git.constants import COMPLETION_FILES, FLAGS, FLAGS_DROPPED
from anon_git.templates import HELP


def test_help_lists_every_flag():
    help_text = HELP
    for flag in FLAGS:
        assert flag.rstrip("=") in help_text


def test_help_omits_dropped_install_flags():
    options = HELP.split("Options:")[1].split("Arguments:")[0]
    for flag in FLAGS_DROPPED:
        assert not re.search(rf"^  {flag}\s", options, re.MULTILINE)


def test_zsh_fish_completions_list_all_flags():
    # Matched whole, so "date" can't hit "keep-date". Never '--flag=[: zsh
    # would insert "--flag=", which parse_args rejects as an unknown option.
    zsh = completion_file("zsh").read_text()
    fish = completion_file("fish").read_text()
    assert "_list-flags" in completion_file("bash").read_text()
    for flag in FLAGS:
        name = flag.rstrip("=").lstrip("-")
        if len(name) <= 1:
            continue
        assert re.search(rf"^ *'--{name}\[|[{{,]--{name}[,}}]", zsh, re.MULTILINE), name
        assert re.search(rf"-l {name}( |$)", fish, re.MULTILINE), name


def test_completions_omit_dropped_flags():
    for shell in COMPLETION_FILES:
        text = completion_file(shell).read_text()
        for flag in FLAGS_DROPPED:
            name = flag.lstrip("-")
            assert not re.search(rf"'--{name}\[|-l {name} ", text), (shell, flag)
