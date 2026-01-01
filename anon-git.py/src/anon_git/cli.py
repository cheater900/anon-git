"""Entry point: runs every step in order."""

import os
import shlex
import subprocess
import sys

from anon_git.branches import backup_branch
from anon_git.early_options import handle_early_options
from anon_git.interaction import confirm, verbose_info
from anon_git.options import build_options
from anon_git.preview import print_result
from anon_git.random_dates import random_dates_for
from anon_git.rewrite import clean_cache, make_commit_callback, run_filter_repo
from anon_git.utils.errors import fail
from anon_git.validation import (
    require_branch_to_overwrite,
    require_reachable,
    require_target,
    safety_checks,
    validate_date,
    validate_identity,
)


def run(argv):
    handle_early_options(argv)
    safety_checks()
    opts = build_options(argv, os.environ)
    require_target(opts)
    validate_date(opts)
    validate_identity(opts)
    require_reachable(opts)
    require_branch_to_overwrite(opts)
    verbose_info(opts)
    confirm(opts)
    backup_branch(opts)
    clean_cache()
    preview = []
    run_filter_repo(opts, make_commit_callback(opts, random_dates_for(opts), preview))
    print_result(opts, preview)


def main(argv=None):
    # Keeps stdout and stderr lines in order when both go to one pipe.
    sys.stdout.reconfigure(line_buffering=True)
    try:
        run(sys.argv[1:] if argv is None else argv)
    except subprocess.CalledProcessError as exc:
        fail(f"Error: {shlex.join(exc.cmd)} failed: {(exc.stderr or '').strip()}")
    except KeyboardInterrupt:
        # Ctrl-C mid-run: a backup/new branch may already exist; say so
        # instead of dumping a traceback.
        fail("\nInterrupted. Check `git branch` and `git reflog` before re-running.")
