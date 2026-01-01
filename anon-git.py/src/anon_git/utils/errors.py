"""Error reporting for a CLI: message to stderr, exit 1."""

import sys


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)
