"""Identity validation over generated input."""

import pytest
from hypothesis import given
from hypothesis import strategies as st

from anon_git.constants import BOOLS, DEFAULT_DATE
from anon_git.models import Options
from anon_git.validation import validate_identity


@given(st.text(min_size=1))
def test_validate_identity_rejects_exactly_bad_chars(name):
    opts = Options(
        name=name,
        email="a@b",
        date=DEFAULT_DATE,
        commits=[],
        **{opt.lower(): False for opt in BOOLS},
        noconfirm=True,
        nobackup=True,
        cli_flags={},
    )
    bad = any(char in name for char in "<>\n")
    if bad:
        with pytest.raises(SystemExit):
            validate_identity(opts)
        return
    validate_identity(opts)
