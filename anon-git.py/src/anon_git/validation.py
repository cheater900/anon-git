"""Checks that run before anything is touched."""

from anon_git.constants import IDENT_FORBIDDEN_CHARS
from anon_git.early_options import show_help
from anon_git.utils.dates import parse_target_date
from anon_git.utils.errors import fail
from anon_git.utils.git import git, git_ok


# Dies unless inside a git repo with a clean working tree. Everything after
# this can assume a usable repo.
def safety_checks():
    if not git_ok("rev-parse", "--git-dir"):
        fail("AnonGit must be run inside a git repository.")
    # Bare repo or inside .git: the dirty-tree check below would misreport.
    if git("rev-parse", "--is-inside-work-tree") != "true":
        fail(
            "Error: AnonGit must be run inside a work tree "
            "(not a bare repository or .git directory)."
        )
    if not git_ok("rev-parse", "--quiet", "--verify", "HEAD"):
        fail("Error: repository has no commits yet; nothing to anonymize.")
    if not git_ok("diff-index", "--quiet", "HEAD", "--") or not git_ok("diff-files", "--quiet"):
        fail(
            "Repository has uncommitted changes. "
            "Commit or stash first to prevent losing the changes."
        )


# Without a commit target or --entire-history, show help instead of silently
# defaulting to HEAD.
def require_target(opts):
    if not opts.commits and not opts.entirehistory:
        show_help()


# Pre-1970 is rejected: git writes the negative timestamp, but fsck (and so
# most hosts on push) rejects the commit as badDate.
def validate_date(opts):
    try:
        valid = parse_target_date(opts.date).timestamp() >= 0
    except ValueError:
        valid = False
    if not valid:
        fail(
            f'Error: invalid date "{opts.date}" '
            '(expected e.g. "2025-03-10 13:37:00 +0000", not before 1970)'
        )


# fast-import aborts mid-rewrite on an ident with <, > or a newline, after
# the new/backup branch already exists; reject it before anything runs.
def validate_identity(opts):
    if opts.keepuser:
        return
    for field, value in (("name", opts.name), ("email", opts.email)):
        if any(char in value for char in IDENT_FORBIDDEN_CHARS):
            fail(f'Error: {field} must not contain "<", ">" or a newline (got "{value}")')


# --current-branch rewrites the checked-out branch, so there must be one.
def require_branch_to_overwrite(opts):
    if opts.currentbranch and not git("branch", "--show-current"):
        fail(
            "Error: HEAD is detached, so there is no current branch to overwrite. "
            "Drop --current-branch or check out a branch first."
        )


# Only HEAD's history is rewritten (--refs HEAD), so any other target would
# silently stay untouched.
def require_reachable(opts):
    if not opts.commits:
        return
    reachable = set(git("rev-list", "HEAD").splitlines())
    for commit in opts.commits:
        if commit not in reachable:
            fail(
                f"Error: commit {git('rev-parse', '--short', commit)} is not reachable "
                "from HEAD; check out a branch containing it first."
            )
