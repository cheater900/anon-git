"""--dry-run preview: one entry per commit, shown through $PAGER."""

import os
import subprocess
import sys

from anon_git.constants import CONTROL_ESCAPES, PREVIEW_SEPARATOR
from anon_git.utils.dates import git_date_iso


# Commit metadata is raw bytes with no guaranteed encoding.
def decode_metadata(raw):
    return raw.decode(errors="replace").translate(CONTROL_ESCAPES)


def ident(name, email):
    return f"{decode_metadata(name)} <{decode_metadata(email)}>"


def preview_entry(commit, new):
    author = ident(commit.author_name, commit.author_email)
    new_author = ident(new["author_name"], new["author_email"])
    committer = ident(commit.committer_name, commit.committer_email)
    new_committer = ident(new["committer_name"], new["committer_email"])
    return (
        f"Commit:{commit.original_id.decode()}\n"
        f"Author:\t\t{author} -> {new_author} \n"
        f"Committer:\t{committer} -> {new_committer} \n"
        f"AuthorDate:\t{git_date_iso(commit.author_date)} -> {git_date_iso(new['author_date'])}\n"
        f"CommitterDate:\t{git_date_iso(commit.committer_date)} -> "
        f"{git_date_iso(new['committer_date'])}\n"
        "\n"
        f"{decode_metadata(commit.message)}"
        f"\n{PREVIEW_SEPARATOR}\n"
    )


def print_result(opts, preview):
    if not opts.dryrun:
        if not opts.quiet:
            print("Done. History has been rewritten.")
        return
    # Through sh, like git, so PAGER may carry arguments ("less -R").
    sys.stdout.flush()
    subprocess.run(
        ["sh", "-c", os.environ.get("PAGER") or "cat"], input="".join(preview), text=True
    )
