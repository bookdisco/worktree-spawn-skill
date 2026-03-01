#!/usr/bin/env bash
set -euo pipefail

# finish.sh — Merge a worktree branch and clean up
# Usage: finish.sh <slug> [base_branch]
#
# Steps:
#   1. Show diff summary
#   2. Merge wt/<slug> into current branch
#   3. Remove worktree
#   4. Delete branch

SLUG="${1:?Usage: finish.sh <slug> [base_branch]}"

GIT_ROOT=$(git rev-parse --show-toplevel) || { echo "ERROR: not a git repository"; exit 1; }
PROJECT=$(basename "$GIT_ROOT")

BRANCH="wt/${SLUG}"
WORKTREE_DIR="${GIT_ROOT}/../${PROJECT}-wt-${SLUG}"

# Verify branch exists
if ! git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  echo "ERROR: branch '${BRANCH}' does not exist"
  exit 1
fi

# Show diff summary
echo "=== Commits to merge ==="
git log --oneline "HEAD..${BRANCH}" 2>/dev/null || echo "(no commits ahead)"

echo ""
echo "=== Files changed ==="
git diff --stat "HEAD...${BRANCH}" 2>/dev/null || echo "(no file changes)"

echo ""
echo "=== Diff preview ==="
git diff --shortstat "HEAD...${BRANCH}" 2>/dev/null || true

echo ""
echo "CONFIRM: Review the above and confirm merge."
echo "To proceed, run: git merge --no-ff '${BRANCH}' -m 'merge: worktree ${SLUG}'"
echo "Then clean up:   git branch -d '${BRANCH}'"
echo "When ready:      git worktree remove '${WORKTREE_DIR}'"
