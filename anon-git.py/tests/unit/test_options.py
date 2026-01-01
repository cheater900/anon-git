"""Option resolution as pure functions: priority, group ownership, conflicts."""

import itertools

import pytest

from anon_git.constants import DEFAULT_DATE, GROUP_DATE, GROUP_IDENTITY, SOURCES
from anon_git.options import (
    apply_strip_timezone_alone,
    drop_overridden_sources,
    merge_args_with_defaults,
    reject_incompatible_options,
)

# Every option that decides the date; any two together conflict.
DATE_OPTIONS = GROUP_DATE


def sources(arg=None, config=None, env=None):
    return {"ARG": dict(arg or {}), "GITCONFIG": dict(config or {}), "ANON_GIT": dict(env or {})}


def value_for(opt):
    return "2020-01-01 00:00:00 +0000" if opt == "DATE" else "1"


@pytest.mark.parametrize("first, second", list(itertools.combinations(DATE_OPTIONS, 2)))
@pytest.mark.parametrize("source", SOURCES)
def test_two_date_options_same_source_conflict(first, second, source):
    src = sources()
    src[source] = {first: value_for(first), second: value_for(second)}
    errors = reject_incompatible_options(drop_overridden_sources(src), [])
    assert len(errors) == 1
    assert "cannot be used together" in errors[0]


@pytest.mark.parametrize("identity", ["NAME", "EMAIL"])
@pytest.mark.parametrize("source", SOURCES)
def test_keepuser_with_identity_same_source_conflicts(identity, source):
    src = sources()
    src[source] = {"KEEPUSER": "1", identity: "x"}
    errors = reject_incompatible_options(drop_overridden_sources(src), [])
    assert errors == [f"Error: --keep-user and --{identity.lower()} cannot be used together"]


@pytest.mark.parametrize("high, low", list(itertools.combinations(SOURCES, 2)))
def test_higher_source_owns_date_group(high, low):
    src = sources()
    src[high] = {"KEEPDATE": "1"}
    src[low] = {"DATE": "2020-01-01 00:00:00 +0000"}
    src = drop_overridden_sources(src)
    assert reject_incompatible_options(src, []) == []
    assert merge_args_with_defaults(src)["DATE"] == DEFAULT_DATE


def test_bool_zero_does_not_own_group():
    src = drop_overridden_sources(sources(config={"KEEPUSER": "0"}, env={"NAME": "Env"}))
    assert merge_args_with_defaults(src)["NAME"] == "Env"


def test_quiet_verbose_flags_conflict():
    errors = reject_incompatible_options(sources(arg={"QUIET": "1", "VERBOSE": "1"}), [])
    assert errors == ["Error: --quiet and --verbose cannot be used together"]


def test_verbose_beats_quiet_config_and_env():
    src = sources(arg={"VERBOSE": "1"}, config={"QUIET": "1"}, env={"QUIET": "1"})
    assert reject_incompatible_options(src, []) == []
    assert merge_args_with_defaults(src)["QUIET"] == "0"


def test_entire_history_env_with_commit_conflicts():
    errors = reject_incompatible_options(sources(env={"ENTIREHISTORY": "1"}), ["abc"])
    assert errors == ["Error: commit(s) argument and --entire-history cannot be used together"]


def test_merge_priority_flag_config_env_default():
    src = sources(
        arg={"NAME": "Flag"}, config={"NAME": "Config", "EMAIL": "c@x"}, env={"DATE": "d"}
    )
    resolved = merge_args_with_defaults(src)
    assert (resolved["NAME"], resolved["EMAIL"], resolved["DATE"]) == ("Flag", "c@x", "d")
    assert resolved["KEEPUSER"] == "0"


def test_strip_timezone_alone_keeps_user_and_date():
    resolved = merge_args_with_defaults(sources())
    out = apply_strip_timezone_alone({"STRIPTIMEZONE": "1", "NOCONFIRM": "1"}, resolved)
    assert (out["KEEPUSER"], out["KEEPDATE"]) == ("1", "1")


@pytest.mark.parametrize("opt", GROUP_IDENTITY + GROUP_DATE)
def test_strip_timezone_with_other_flag_keeps_precedence(opt):
    resolved = merge_args_with_defaults(sources())
    out = apply_strip_timezone_alone({"STRIPTIMEZONE": "1", opt: "x"}, resolved)
    assert out == resolved
