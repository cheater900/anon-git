#!/usr/bin/env bash
#
# Sets up a disposable git repo with sample commits and drops you into an
# interactive shell inside it, for manual/interactive poking at anon-git.sh.
# The repo (and everything in it) is deleted once you exit that shell.

set -euo pipefail

SCRIPT_DIR=$(realpath "$(dirname "$0")/..")

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}"/anon_git_test.XXXXXX)

cleanup() {
  cd - >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cd "$TMP_DIR"

cp "$SCRIPT_DIR"/*.sh "$TMP_DIR"/
chmod +x "$TMP_DIR"/*.sh

git init >/dev/null
git config --local user.name "Test User"
git config --local user.email "test@example.com"

# Real-world-looking authors, each with their own committer identity.
AUTHOR_NAMES=(
  "Alice Nguyen"
  "Marcus Webb"
  "Priya Sharma"
  "Diego Fernandez"
)
AUTHOR_EMAILS=(
  "alice.nguyen@protonmail.com"
  "marcus.webb@webbdev.io"
  "priya.sharma@sharma-labs.dev"
  "diego.fernandez@fernandez.codes"
)

# Conventional-commit-style messages; text doesn't need to match the
# (trivial) file diff.
SUBJECTS=(
  "chore: deduplicate log entries"
  "chore: extract shared logic into util"
  "chore: format files"
  "chore: prune unused dependencies"
  "chore: rename internal helper for clarity"
  "chore: simplify config parsing"
  "chore: update dependency versions"
  "chore: update lockfile"
  "ci: add integration test for auth flow"
  "ci: add integration tests"
  "ci: add unit tests"
  "ci: bump runner to node 20"
  "ci: fix flaky test in suite"
  "ci: speed up matrix build"
  "docs: add changelog entry"
  "docs: clarify install steps in README"
  "docs: update badges in README"
  "docs: update changelog"
  "docs: update README"
  "feat: add caching layer for lookups"
  "feat: add feature flag for new UI"
  "feat: add metrics for request latency"
  "feat: add pagination to results view"
  "feat: add retry with backoff to client"
  "feat: add support for custom headers"
  "feat: support dark mode toggle"
  "fix: add missing null check"
  "fix: correct off-by-one in retry loop"
  "fix: fix memory leak in worker pool"
  "fix: fix race condition in queue consumer"
  "fix: fix typo in error string"
  "fix: guard against nil pointer on shutdown"
  "fix: handle empty input on startup"
  "fix: improve error message on failed upload"
  "fix: lint complaints"
  "fix: tighten timeout on health check"
  "fix: validate config schema on load"
  "perf: cache db search results"
  "perf: cache network requests"
  "perf: lazy-load images"
  "refact: extract duplicate code to utils"
  "refact: remove unused variables"
  "refact: rename variables"
  "refact: sort imports"
)

# BASE_EPOCH..BASE_EPOCH+SPAN_SECONDS covers a bit over 3 years
# (2015-01-01 .. 2018-04-ish), commits scattered pseudo-randomly across it so
# some land in the same day/month and others are far apart.
BASE_EPOCH=1420070400 # 2015-01-01T00:00:00Z
SPAN_SECONDS=100000000 # ~3.17 years

COMMIT_COUNT=80
for i in $(seq 1 "$COMMIT_COUNT"); do
  filename="file${i}.txt"
  : >"$filename"
  git add "$filename" >/dev/null

  R=$RANDOM
  author_idx=$(( R % ${#AUTHOR_NAMES[@]} ))
  subject_idx=$(( R % ${#SUBJECTS[@]} ))
  # Deterministic pseudo-random spread (not just i*step) so commits cluster
  # unevenly: some same-day, some same-month, some years apart.
  offset=$(( (i * 2654435761) % SPAN_SECONDS ))
  commit_date="$(( BASE_EPOCH + offset )) +0000"

  GIT_AUTHOR_NAME="${AUTHOR_NAMES[$author_idx]}" \
    GIT_AUTHOR_EMAIL="${AUTHOR_EMAILS[$author_idx]}" \
    GIT_COMMITTER_NAME="${AUTHOR_NAMES[$author_idx]}" \
    GIT_COMMITTER_EMAIL="${AUTHOR_EMAILS[$author_idx]}" \
    GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" \
    git commit -m "${SUBJECTS[$subject_idx]}" >/dev/null
done

cat <<EOF
Disposable repo ready at: ${TMP_DIR}
  - ${COMMIT_COUNT} commits across ${#AUTHOR_NAMES[@]} authors:
$(for n in "${AUTHOR_NAMES[@]}"; do echo "      ${n}"; done)
  - dates spread pseudo-randomly over ~3.2 years (2015-01 .. ~2018-04),
    some commits land on the same day/month, others are years apart
  - conventional-commit-style messages (fix:, ci:, feat:, chore:, docs:)

Try things like:
  ./anon-git.sh --dry-run
  ./anon-git.sh --dry-run --entire-history
  ./anon-git.sh --keep-day HEAD~3
  ./anon-git.sh --keep-user HEAD~10
  git log --format='%h %ad %an <%ae> %s' --date=iso

Dropping you into an interactive shell here.
Exit the shell (or Ctrl-D) to clean up the temp directory.
EOF

"${SHELL:-bash}" -i
