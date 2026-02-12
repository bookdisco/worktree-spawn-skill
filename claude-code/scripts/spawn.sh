#!/usr/bin/env bash
set -euo pipefail

# spawn.sh — Create a git worktree for parallel work
# Usage: spawn.sh <slug> [base_branch]
#
# Creates:
#   - Branch: wt/<slug>
#   - Worktree: ../<project>-wt-<slug>/
#
# Outputs JSON with worktree metadata on success.

SLUG="${1:?Usage: spawn.sh <slug> [base_branch]}"
BASE_BRANCH="${2:-$(git branch --show-current)}"

# Validate git repo
GIT_ROOT=$(git rev-parse --show-toplevel) || { echo "ERROR: not a git repository"; exit 1; }
PROJECT=$(basename "$GIT_ROOT")

BRANCH="wt/${SLUG}"
WORKTREE_DIR="${GIT_ROOT}/../${PROJECT}-wt-${SLUG}"
ABS_WORKTREE=$(cd "$GIT_ROOT/.." && pwd)/"${PROJECT}-wt-${SLUG}"

# Check if branch already exists
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  echo "WARN: branch '${BRANCH}' already exists"
  echo "ACTION_NEEDED: ask user whether to reuse or pick a different name"
  exit 2
fi

# Check if worktree directory already exists
if [ -d "$WORKTREE_DIR" ]; then
  echo "WARN: directory '${WORKTREE_DIR}' already exists"
  echo "ACTION_NEEDED: ask user whether to clean up or pick a different slug"
  exit 2
fi

# Check for dirty working tree
if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet HEAD 2>/dev/null; then
  echo "WARN: uncommitted changes detected in working tree"
  echo "ACTION_NEEDED: suggest user commit or stash before spawning"
fi

# Create branch from current HEAD
git branch "${BRANCH}" HEAD

# Create worktree
git worktree add "${WORKTREE_DIR}" "${BRANCH}"

# Ensure .worktrees.json is gitignored
grep -qxF '.worktrees.json' "${GIT_ROOT}/.git/info/exclude" 2>/dev/null || \
  echo '.worktrees.json' >> "${GIT_ROOT}/.git/info/exclude"

# Output metadata as JSON
CREATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat <<EOF
{
  "slug": "${SLUG}",
  "branch": "${BRANCH}",
  "path": "../${PROJECT}-wt-${SLUG}",
  "abs_path": "${ABS_WORKTREE}",
  "task": "",
  "base_branch": "${BASE_BRANCH}",
  "created": "${CREATED}",
  "status": "active"
}
EOF
