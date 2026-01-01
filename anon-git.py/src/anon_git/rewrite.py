"""The filter-repo commit callback and the in-process rewrite."""

import os
import shutil
import sys
import tempfile

import git_filter_repo as fr

from anon_git.preview import preview_entry
from anon_git.utils.dates import as_utc_epoch, parse_git_date, parse_target_date, utc_git_date
from anon_git.utils.git import git


# git-filter-repo caches metadata in .git/filter-repo/; reusing it after
# certain repo state changes hits a known assertion bug in the tool.
def clean_cache():
    cache = os.path.join(git("rev-parse", "--git-dir"), "filter-repo")
    if os.path.isdir(cache):
        shutil.rmtree(cache)


def target_date_bytes(opts, commit, random_dates):
    if random_dates is not None:
        epoch = random_dates.get(commit.original_id.decode())
        if epoch is None:
            raise SystemExit(
                f"anon-git: no precomputed random date for commit {commit.original_id.decode()}"
            )
        return utc_git_date(epoch)
    if opts.keepyear or opts.keepmonth or opts.keepday:
        # Keep the calendar date as seen, re-anchored to midnight UTC, so
        # only time/tz leak.
        dt = parse_git_date(commit.author_date).replace(hour=0, minute=0, second=0, microsecond=0)
        if opts.keepyear or opts.keepmonth:
            dt = dt.replace(day=1)
        if opts.keepyear:
            dt = dt.replace(month=1)
        return utc_git_date(as_utc_epoch(dt))
    dt = parse_target_date(opts.date)
    if opts.striptimezone:
        return utc_git_date(as_utc_epoch(dt))
    offset_seconds = int(dt.utcoffset().total_seconds())
    sign = "+" if offset_seconds >= 0 else "-"
    hours, minutes = divmod(abs(offset_seconds) // 60, 60)
    return b"%d %s%02d%02d" % (int(dt.timestamp()), sign.encode(), hours, minutes)


# Returns the filter-repo commit callback. Under --dry-run it appends a
# preview entry to `preview` instead of changing the commit.
def make_commit_callback(opts, random_dates, preview):
    targets = {commit.encode() for commit in opts.commits}

    def callback(commit, _metadata):
        if not opts.entirehistory and commit.original_id not in targets:
            return
        new = {
            "author_name": commit.author_name,
            "author_email": commit.author_email,
            "author_date": commit.author_date,
            "committer_name": commit.committer_name,
            "committer_email": commit.committer_email,
            "committer_date": commit.committer_date,
        }
        if not opts.keepuser:
            for field in ("author_name", "committer_name"):
                new[field] = opts.name.encode()
            for field in ("author_email", "committer_email"):
                new[field] = opts.email.encode()
        if not opts.keepdate:
            new["author_date"] = new["committer_date"] = target_date_bytes(
                opts, commit, random_dates
            )
        elif opts.striptimezone:
            # Digits untouched, each offset relabeled to +0000 independently
            # (author and committer can differ, e.g. after a rebase).
            for field in ("author_date", "committer_date"):
                new[field] = utc_git_date(as_utc_epoch(parse_git_date(getattr(commit, field))))
        if opts.dryrun:
            preview.append(preview_entry(commit, new))
            return
        for field, value in new.items():
            setattr(commit, field, value)

    return callback


# Runs filter-repo in-process. Its output, and that of the fast-export/
# fast-import children it spawns, goes to an unnamed temp file (fds 1/2
# redirected), shown only on failure. --dry-run is forwarded: without it
# filter-repo still rewrites history even when the callback changes nothing
# (e.g. signed commits lose their signature).
def run_filter_repo(opts, callback):
    filter_args = fr.FilteringOptions.parse_args(
        ["--force", "--refs", "HEAD", *(["--dry-run"] if opts.dryrun else [])]
    )
    with tempfile.TemporaryFile() as log:
        sys.stdout.flush()
        sys.stderr.flush()
        saved = os.dup(1), os.dup(2)
        os.dup2(log.fileno(), 1)
        os.dup2(log.fileno(), 2)
        error = None
        try:
            fr.RepoFilter(filter_args, commit_callback=callback).run()
        except SystemExit as exc:
            error = exc
        finally:
            sys.stdout.flush()
            sys.stderr.flush()
            os.dup2(saved[0], 1)
            os.dup2(saved[1], 2)
            os.close(saved[0])
            os.close(saved[1])
        if error is None or error.code in (None, 0):
            return
        log.seek(0)
        print("Error: git filter-repo failed:", file=sys.stderr)
        sys.stderr.write(log.read().decode(errors="replace"))
        # filter-repo exits with either a message or a bare status code.
        if isinstance(error.code, str):
            print(error.code, file=sys.stderr)
        sys.exit(1)
