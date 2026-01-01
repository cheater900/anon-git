"""Shared data types: commit history records and resolved options."""

from dataclasses import dataclass
from typing import NamedTuple


class HistoryCommit(NamedTuple):
    hash: str
    epoch: int
    offset: str
    parents: list


# One commit placed in a calendar-unit bucket; sorts by (epoch, index).
class BucketMember(NamedTuple):
    epoch: int
    index: int
    hash: str
    is_target: bool


@dataclass(frozen=True)
class Options:
    name: str
    email: str
    date: str
    commits: list
    keepuser: bool
    keepdate: bool
    keepyear: bool
    keepmonth: bool
    keepday: bool
    randomtime: bool
    randomday: bool
    randommonth: bool
    striptimezone: bool
    entirehistory: bool
    currentbranch: bool
    dryrun: bool
    quiet: bool
    # CLI-only, never read from config/envvars.
    noconfirm: bool
    nobackup: bool
    # Flags given on the CLI, for messages gated on explicit flags.
    cli_flags: dict
