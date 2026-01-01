#!/usr/bin/env bash
#
# Sets up a disposable git repo with sample commits and drops you into an
# interactive shell inside it, for manual/interactive poking at anon-git.sh.
# The repo (and everything in it) is deleted once you exit that shell.

set -euo pipefail

SCRIPT_DIR=$(realpath "$(dirname "$0")/..")

# Creates a temp directory to work on
TMP_DIR=$(mktemp -d /tmp/anon_git_test.XXXXXX)

cleanup() {
  cd - >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cd "$TMP_DIR"

# copy scripts and make them executable
cp "$SCRIPT_DIR"/*.sh "$TMP_DIR"/
chmod +x "$TMP_DIR"/*.sh

# init git repo
git init >/dev/null
git config --local user.name "Test User"
git config --local user.email "test@example.com"

# Commits are spread ~31 days apart (using raw "<epoch> <tz>" author/committer
# dates, so this works the same on GNU and BSD without shelling out to `date`)
# so --keep-year/--keep-month/--keep-day have distinct years/months/days to
# preserve and compare against.
COMMIT_COUNT=20
BASE_EPOCH=1420070400 # 2015-01-01T00:00:00Z
for i in $(seq 1 "$COMMIT_COUNT"); do
  filename="file_${i}.txt"
  echo "This is file $i" >"$filename"
  git add "$filename" >/dev/null
  commit_date="$(( BASE_EPOCH + i * 2700000 + i * 61 )) +0000"
  GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" \
    git commit -m "Add file $filename" >/dev/null
done

# A couple of commits from different authors, so --keep-user (and filtering
# commits by author) has something to show.
echo 'feature work' >feature_file.txt
git add feature_file.txt >/dev/null
GIT_AUTHOR_NAME='Feature Dev' GIT_AUTHOR_EMAIL='feature.dev@example.com' \
  GIT_COMMITTER_NAME='Feature Dev' GIT_COMMITTER_EMAIL='feature.dev@example.com' \
  git commit -m 'Add feature file' >/dev/null

echo 'hotfix' >hotfix_file.txt
git add hotfix_file.txt >/dev/null
GIT_AUTHOR_NAME='Hotfix Hank' GIT_AUTHOR_EMAIL='hotfix.hank@example.com' \
  GIT_COMMITTER_NAME='Hotfix Hank' GIT_COMMITTER_EMAIL='hotfix.hank@example.com' \
  git commit -m 'Add hotfix file' >/dev/null

cat <<EOF
Disposable repo ready at: ${TMP_DIR}
  - ${COMMIT_COUNT} commits by "Test User", spread ~31 days apart from 2015 onward
    (good for --keep-year / --keep-month / --keep-day)
  - 1 commit by "Feature Dev" (good for --keep-user)
  - 1 commit (HEAD) by "Hotfix Hank" (good for author-filtered runs, e.g.
    git log --format=%H --author='Hank' | xargs ./anon-git.sh)

Try things like:
  ./anon-git.sh --dry-run
  ./anon-git.sh --dry-run --entire-history
  ./anon-git.sh --keep-day HEAD~3
  git log --format='%h %ad %an <%ae>' --date=iso

Dropping you into an interactive shell here.
Exit the shell (or Ctrl-D) to clean up the temp directory.
EOF

"${SHELL:-bash}" -i
