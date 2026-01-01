"""Informational output and the confirmation prompt."""

import termios
import tty

from anon_git.utils.errors import fail
from anon_git.utils.git import git


# Gated on flags explicitly passed on the CLI (not the resolved value), so
# e.g. ANON_GIT_KEEPUSER in a shell profile doesn't spam this on every run.
def verbose_info(opts):
    if opts.quiet:
        return
    if opts.entirehistory:
        print("Anonymizing entire history!")
    else:
        # One rev-parse for the repo's abbrev length, not one per commit.
        length = len(git("rev-parse", "--short", opts.commits[0]))
        shorts = [commit[:length] for commit in opts.commits]
        print(f"Anonymizing commit(s): {' '.join(shorts)} ")
    messages = {
        "KEEPUSER": "Not overwriting user/email.",
        "KEEPDATE": "Not overwriting date.",
        "KEEPYEAR": "Using commit date year (anonymizing only month, day, time and tz).",
        "KEEPMONTH": "Using commit date year and month (anonymizing only day, time and tz).",
        "KEEPDAY": "Using commit date year, month and day (anonymizing only time and tz).",
        "RANDOMTIME": "Randomizing time only (keeping commit date year, month and day), "
        "preserving relative commit order.",
        "RANDOMDAY": "Randomizing day and time (keeping commit date year and month), "
        "preserving relative commit order.",
        "RANDOMMONTH": "Randomizing month, day and time (keeping commit date year), "
        "preserving relative commit order.",
        "STRIPTIMEZONE": "Forcing timezone offset to UTC+0000 (date/time digits unchanged).",
    }
    for opt, message in messages.items():
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
