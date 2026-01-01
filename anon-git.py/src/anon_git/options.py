"""Option sources (flags, git config, envvars) and their resolution into Options."""

import subprocess

from anon_git.constants import (
    BOOLS,
    CONFIG_BOOLS,
    DEFAULT_DATE,
    DEFAULT_EMAIL,
    DEFAULT_NAME,
    ERROR_NOT_A_COMMIT,
    FLAGS_BOOL,
    FLAGS_VALUE,
    GROUP_DATE,
    GROUP_IDENTITY,
    SOURCES,
    VALUE_OPTIONS,
)
from anon_git.models import Options
from anon_git.utils.errors import fail
from anon_git.utils.git import git_config_get


def config_key(opt):
    return f"anon-git.{opt.lower()}"


# Reads git config anon-git.<key> as "1"/"0", or "" if unset. Parsed by git
# itself (--type=bool), so "True", "YES" or a valueless key mean what git
# says. An unparseable value is a hard error: a typo must not fail open.
def read_git_config_bool(key):
    status, value = git_config_get(key, "--type=bool")
    if status == 1:
        return ""
    if status != 0:
        fail(
            f'Error: git config {key} has an invalid boolean value "{git_config_get(key)[1]}" '
            "(expected true/false)"
        )
    return "1" if value == "true" else "0"


def read_git_config():
    config = {}
    for opt in VALUE_OPTIONS:
        status, value = git_config_get(config_key(opt))
        config[opt] = value if status == 0 else ""
    for opt in CONFIG_BOOLS:
        config[opt] = read_git_config_bool(config_key(opt))
    return config


def read_env(environ):
    return {opt: environ.get(f"ANON_GIT_{opt}", "") for opt in (*VALUE_OPTIONS, *BOOLS)}


# --keep-user -> KEEPUSER.
def flag_option(flag):
    return flag.lstrip("-").replace("-", "").upper()


# Resolves revisions to commit hashes in one git process, so passing
# `$(git log --format=%H)` doesn't spawn one per commit. ^{commit} peels
# annotated tags, whose own hash never matches a commit.
def resolve_commits(revs):
    # A newline would split one revision into two batch lines.
    for rev in revs:
        if "\n" in rev:
            fail(ERROR_NOT_A_COMMIT.format(rev=rev))
    batch = subprocess.run(
        ["git", "cat-file", "--batch-check=%(objectname) %(objecttype)"],
        input="".join(f"{rev}^{{commit}}\n" for rev in revs),
        capture_output=True,
        text=True,
        check=True,
    )
    commits = []
    for rev, line in zip(revs, batch.stdout.splitlines(), strict=True):
        commit, kind = line.rsplit(" ", 1)
        if kind != "commit":
            fail(ERROR_NOT_A_COMMIT.format(rev=rev))
        commits.append(commit)
    return commits


# Parses argv into ({option: value} for given flags, [resolved commit hashes]).
def parse_args(argv):
    args = {}
    revs = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in FLAGS_VALUE:
            # Empty would silently fall back to the default identity/date.
            if i + 1 >= len(argv) or not argv[i + 1]:
                fail(f"Error: {arg} requires a value")
            args[flag_option(arg)] = argv[i + 1]
            i += 2
            continue
        if arg in FLAGS_BOOL:
            args[flag_option(arg)] = "1"
        elif arg.startswith("-"):
            fail(f"Unknown option: {arg}")
        else:
            revs.append(arg)
        i += 1
    return args, resolve_commits(revs) if revs else []


def is_on(value):
    return value not in ("", "0")


# The highest-priority source setting any member of a group owns the whole
# group: lower sources' members are cleared, so e.g. ANON_GIT_DATE doesn't
# conflict with --keep-date. Bool "0" doesn't count.
def drop_overridden_sources(sources):
    for group in (GROUP_IDENTITY, GROUP_DATE):
        owner = next(
            (s for s in SOURCES if any(is_on(sources[s].get(opt, "")) for opt in group)), None
        )
        if owner is None:
            continue
        for source in SOURCES:
            if source == owner:
                continue
            for opt in group:
                sources[source][opt] = ""
    return sources


def first_set(sources, opt):
    return next((sources[s][opt] for s in SOURCES if sources[s].get(opt)), "")


def bool_set(sources, opt):
    return (
        bool(sources["ARG"].get(opt))
        or sources["GITCONFIG"].get(opt) == "1"
        or sources["ANON_GIT"].get(opt) == "1"
    )


# Mutually-exclusive options, wherever each side came from. Returns error
# messages instead of exiting, so every conflict is reported at once.
def reject_incompatible_options(sources, commits):
    errors = []
    args = sources["ARG"]
    keepuser = bool_set(sources, "KEEPUSER")
    for flag in ("--name", "--email"):
        if keepuser and first_set(sources, flag_option(flag)):
            errors.append(f"Error: --keep-user and {flag} cannot be used together")
    # --date, --keep-* and --random-* each decide the whole date: one at most.
    date_flags = ["--date"] if first_set(sources, "DATE") else []
    date_flags += [
        flag
        for flag in FLAGS_BOOL
        if flag_option(flag) in GROUP_DATE and bool_set(sources, flag_option(flag))
    ]
    if len(date_flags) > 1:
        errors.append(f"Error: {' and '.join(date_flags)} cannot be used together")
    if commits and bool_set(sources, "ENTIREHISTORY"):
        errors.append("Error: commit(s) argument and --entire-history cannot be used together")
    # Only the two flags conflict: --verbose over ANON_GIT_QUIET=1 or
    # anon-git.quiet is the intended way to un-silence a quiet default.
    if args.get("QUIET") and args.get("VERBOSE"):
        errors.append("Error: --quiet and --verbose cannot be used together")
    return errors


# Flags > repo-local git config > ANON_GIT_* envvars > defaults.
def merge_args_with_defaults(sources):
    defaults = {"NAME": DEFAULT_NAME, "EMAIL": DEFAULT_EMAIL, "DATE": DEFAULT_DATE}
    defaults.update(dict.fromkeys(BOOLS, "0"))
    resolved = {opt: first_set(sources, opt) or default for opt, default in defaults.items()}
    # --verbose always wins over whatever set QUIET above.
    if sources["ARG"].get("VERBOSE") == "1":
        resolved["QUIET"] = "0"
    return resolved


# --strip-timezone alone implicitly behaves like --keep-user --keep-date
# (the callback still rewrites the offset). Any other identity/date CLI flag
# opts back into normal precedence; config/envvars don't count.
def apply_strip_timezone_alone(args, resolved):
    if args.get("STRIPTIMEZONE") != "1":
        return resolved
    if any(args.get(opt) for opt in GROUP_IDENTITY + GROUP_DATE):
        return resolved
    return {**resolved, "KEEPUSER": "1", "KEEPDATE": "1"}


# A stray envvar could produce a bogus value; check before anything acts on it.
def validate_final_options(resolved):
    for opt in BOOLS:
        if resolved[opt] not in ("0", "1"):
            fail(f'Error: ANON_GIT_{opt} must resolve to "0" or "1" (got "{resolved[opt]}")')


def build_options(argv, environ):
    args, commits = parse_args(argv)
    sources = drop_overridden_sources(
        {"ARG": dict(args), "GITCONFIG": read_git_config(), "ANON_GIT": read_env(environ)}
    )
    errors = reject_incompatible_options(sources, commits)
    if errors:
        fail("\n".join(errors))
    resolved = apply_strip_timezone_alone(args, merge_args_with_defaults(sources))
    validate_final_options(resolved)
    return Options(
        name=resolved["NAME"],
        email=resolved["EMAIL"],
        date=resolved["DATE"],
        commits=commits,
        noconfirm=args.get("NOCONFIRM") == "1",
        nobackup=args.get("NOBACKUP") == "1",
        cli_flags=args,
        **{opt.lower(): resolved[opt] == "1" for opt in BOOLS},
    )
