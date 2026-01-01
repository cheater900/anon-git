"""Anonymizes git commit metadata.

Python port of anon-git.sh: same flags, messages and exit codes. Module and
function names mirror the shell implementation's sections and functions so
the two can be audited side by side. The rewrite runs in-process through the
git_filter_repo library.
"""

from anon_git.cli import main

__all__ = ["main"]
