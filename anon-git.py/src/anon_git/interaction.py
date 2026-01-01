"""Informational output and the confirmation prompt."""

import termios
import tty

from anon_git.constants import VERBOSE_FLAG_MESSAGES
from anon_git.utils.errors import fail
from anon_git.utils.git import git


# One rev-parse for the repo's abbrev length, not one per commit.
def short_hashes(commits):
    length = len(git("rev-parse", "--short", commits[0]))
    return [commit[:length] for commit in commits]


# Gated on flags explicitly passed on the CLI (not the resolved value), so
# e.g. ANON_GIT_KEEPUSER in a shell profile doesn't spam this on every run.
def verbose_info(opts):
    if opts.quiet:
        return
    if opts.entirehistory:
        print("Anonymizing entire history!")
    else:
        print(f"Anonymizing commit(s): {' '.join(short_hashes(opts.commits))} ")
    for opt, message in VERBOSE_FLAG_MESSAGES.items():
        if opts.cli_flags.get(opt):
            print(message)
    print()


# Reads one key from the terminal, not stdin: under xargs stdin is /dev/null.
# Skipped for --no-confirm or --dry-run (nothing is touched either way).
def confirm(opts):
    if opts.noconfirm or opts.dryrun:
        return
    try:
        terminal = open("/dev/tty", "r+b", buffering=0)  # noqa: SIM115 -- closed by `with` below
    except OSError:
        fail("Error: no terminal to ask for confirmation; pass --no-confirm.")
    with terminal:
        terminal.write(b"Continue? (y/N) ")
        saved = termios.tcgetattr(terminal)
        single_key = list(saved)
        single_key[tty.LFLAG] &= ~termios.ICANON
        termios.tcsetattr(terminal, termios.TCSANOW, single_key)
        try:
            reply = terminal.read(1)
        finally:
            termios.tcsetattr(terminal, termios.TCSANOW, saved)
    print()
    if reply not in (b"y", b"Y"):
        fail("Aborted.")
