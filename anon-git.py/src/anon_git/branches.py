"""New or backup branch made before a rewrite, so old history stays reachable."""

import os
import random
import subprocess
import sys
import time

from anon_git.constants import BRANCH_RANDOM_RANGE, BRANCH_SUFFIX_ANONYMIZED, BRANCH_SUFFIX_BACKUP
from anon_git.utils.errors import fail
from anon_git.utils.git import git


# Creates a new branch (default) or a backup branch (--current-branch, unless
# --no-backup) so pre-rewrite history stays reachable. No-op under --dry-run.
def backup_branch(opts):
    if opts.dryrun:
        return
    current_branch = git("branch", "--show-current")
    branch_label = current_branch or f"detached-{git('rev-parse', '--short', 'HEAD')}"
    # Colon-free (git ref names disallow ":"); PID + random suffix for
    # uniqueness within the same second.
    timestamp = (
        f"{time.strftime('%Y%m%d_%H%M%S')}_{os.getpid()}_{random.randrange(BRANCH_RANDOM_RANGE)}"
    )
    if not opts.currentbranch:
        new_branch = f"{branch_label}{BRANCH_SUFFIX_ANONYMIZED}{timestamp}"
        # --quiet also silences git's own "Switched to a new branch" line.
        stderr = subprocess.DEVNULL if opts.quiet else None
        if subprocess.run(["git", "switch", "--create", new_branch], stderr=stderr).returncode:
            fail(f"Error: failed to create branch {new_branch}")
        if not opts.quiet:
            print(f"Created new branch {new_branch} from {branch_label}")
            print(f"Using branch {new_branch} to rewrite commits.")
        return
    if opts.nobackup:
        # Not gated by --quiet: a data-loss warning, not routine output.
        print(
            f"WARNING! Overwriting existing branch {branch_label} without backup!", file=sys.stderr
        )
        return
    backup_branch_name = f"{branch_label}{BRANCH_SUFFIX_BACKUP}{timestamp}"
    if subprocess.run(["git", "branch", backup_branch_name]).returncode:
        fail(f"Error: failed to create backup branch {backup_branch_name}")
    if not opts.quiet:
        print(f"Created backup branch {backup_branch_name} from {branch_label}")
        print(f"Using branch {branch_label} to rewrite commits")
