SCRIPT := "anon-git.sh"
TEST_SCRIPT := "tests/test-anon-git.sh"
TEST_COMPLETION_SCRIPT := "tests/test-anon-git-completion.sh"

default:
    @just --list

all:
    just lint
    just format
    just test
    just test-completion

# Run the test suite
test:
    ./{{TEST_SCRIPT}}
    ./{{TEST_COMPLETION_SCRIPT}}

# Run only the shell-completion tests (bash/zsh/fish, via expect)
test-completion:
    ./{{TEST_COMPLETION_SCRIPT}}

# Check shell syntax and run shellcheck
lint:
    bash -n {{SCRIPT}} {{TEST_SCRIPT}} {{TEST_COMPLETION_SCRIPT}}
    shellcheck {{SCRIPT}} {{TEST_SCRIPT}} {{TEST_COMPLETION_SCRIPT}}

# Format the scripts in place with shfmt
format:
    shfmt -w -ln bash -i 4 {{SCRIPT}} {{TEST_SCRIPT}} {{TEST_COMPLETION_SCRIPT}}

# Check formatting without writing (used by CI; `just format` to fix)
format-check:
    shfmt -d -ln bash -i 4 {{SCRIPT}} {{TEST_SCRIPT}} {{TEST_COMPLETION_SCRIPT}}
