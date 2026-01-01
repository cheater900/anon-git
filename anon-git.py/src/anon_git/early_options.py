"""Options handled before any repo check: help, version, completion, hooks."""

import os
import sys
from importlib import resources

from anon_git.constants import (
    COMPLETION_FILES,
    DEFAULT_EMAIL,
    DEFAULT_NAME,
    FLAGS,
    FLAGS_DROPPED,
    FLAGS_VALUE,
    VERSION,
)
from anon_git.hooks import install_hook, uninstall_hook
from anon_git.templates import HELP
from anon_git.utils.errors import fail


def show_help():
    print(HELP.format(DEFAULT_NAME=DEFAULT_NAME, DEFAULT_EMAIL=DEFAULT_EMAIL))
    sys.exit(0)


def show_version():
    print(f"anon-git {VERSION}")
    sys.exit(0)


def list_flags():
    print("\n".join(FLAGS))
    sys.exit(0)


def print_completion(shell):
    shell = shell or os.path.basename(os.environ.get("SHELL", ""))
    if shell not in COMPLETION_FILES:
        fail(f'Error: unsupported shell "{shell}" (expected bash, zsh, or fish)')
    completion = resources.files("anon_git") / "completions" / COMPLETION_FILES[shell]
    sys.stdout.write(completion.read_text())
    sys.exit(0)


def dropped_install_flag(flag):
    fail(
        f"Error: {flag} is not supported by the Python implementation.\n"
        "  Install: uv tool install ./anon-git.py\n"
        "  Remove:  uv tool uninstall anon-git"
    )


# Handled before any git-repo/safety checks, so these work even outside a
# git repository or with a dirty working tree.
def handle_early_options(argv):
    if not argv:
        show_help()
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in FLAGS_VALUE:
            # Skip the value, so `--name --help` uses "--help" as the name.
            i += 1
        elif arg in ("-h", "--help"):
            show_help()
        elif arg in ("-v", "--version"):
            show_version()
        elif arg == "--_list-flags":
            list_flags()
        elif arg == "--print-completion":
            print_completion(argv[i + 1] if i + 1 < len(argv) else "")
        elif arg == "--install-hook":
            install_hook()
        elif arg == "--uninstall-hook":
            uninstall_hook()
        elif arg in FLAGS_DROPPED:
            dropped_install_flag(arg)
        i += 1
