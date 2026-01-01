SCRIPT := "anon-git.sh"
TEST_SCRIPT := "tests/test_anon_git.sh"
TEST_LIB_FILES := "tests/lib/common.sh tests/cases/core.sh tests/cases/validation.sh tests/cases/config_priority.sh tests/cases/install.sh tests/cases/flags.sh tests/cases/help.sh tests/cases/regression.sh tests/cases/random_dates.sh"
TEST_COMPLETION_SCRIPT := "tests/test_anon_git_completion.sh"
README := "README.md"

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
    bash -n {{SCRIPT}} {{TEST_SCRIPT}} {{TEST_LIB_FILES}} {{TEST_COMPLETION_SCRIPT}}
    shellcheck -x {{SCRIPT}} {{TEST_SCRIPT}} {{TEST_LIB_FILES}} {{TEST_COMPLETION_SCRIPT}}

# Format the scripts in place with shfmt
format:
    shfmt -w -ln bash -i 4 {{SCRIPT}} {{TEST_SCRIPT}} {{TEST_LIB_FILES}} {{TEST_COMPLETION_SCRIPT}}

# Check formatting without writing (used by CI; `just format` to fix)
format-check:
    shfmt -d -ln bash -i 4 {{SCRIPT}} {{TEST_SCRIPT}} {{TEST_LIB_FILES}} {{TEST_COMPLETION_SCRIPT}}

# Run the CI workflow locally via `act` (https://github.com/nektos/act); only ubuntu-latest, act can't run the macos-latest job
ci-local:
    act push --job test --matrix os:ubuntu-latest

# Regenerate README's ### Options code block from `anon-git.sh --help`'s own Options section, so the two can't silently drift apart
sync-docs:
    #!/usr/bin/env bash
    set -euo pipefail
    options=$(./{{SCRIPT}} --help | sed -n '/^Options:$/,/^$/p' | sed '1d;$d')
    awk -v options="$options" '
        /^### Options$/ {
            print
            getline; print   # blank line between the heading and the fence
            getline; print   # opening ``` fence
            print options
            while ((getline line) > 0) {
                if (line == "```") { print line; break }
            }
            next
        }
        { print }
    ' {{README}} >{{README}}.tmp
    mv {{README}}.tmp {{README}}
