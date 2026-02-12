#!/usr/bin/env bash
set -euo pipefail

# list.sh — List active worktrees from .worktrees.json
# Usage: list.sh
#
# Reads .worktrees.json and shows status of each active worktree.

GIT_ROOT=$(git rev-parse --show-toplevel) || { echo "ERROR: not a git repository"; exit 1; }
REGISTRY="${GIT_ROOT}/.worktrees.json"

if [ ! -f "$REGISTRY" ]; then
  echo "No worktrees registered. Use /worktree-spawn to create one."
  exit 0
fi

# Check jq availability
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed"
  exit 1
fi

COUNT=$(jq '.worktrees | length' "$REGISTRY")
if [ "$COUNT" -eq 0 ]; then
  echo "No worktrees registered."
  exit 0
fi

echo "Active Worktrees:"
echo "================="
echo ""

jq -r '.worktrees[] | select(.status == "active") | [.slug, .branch, .task, .path, .base_branch, .created] | @tsv' "$REGISTRY" | \
while IFS=$'\t' read -r slug branch task path base_branch created; do
  abs_path="${GIT_ROOT}/${path}"

  echo "  Slug:     ${slug}"
  echo "  Branch:   ${branch}"
  echo "  Task:     ${task}"
  echo "  Path:     ${path}"
  echo "  Created:  ${created}"

  # Check if worktree still exists
  if [ -d "$abs_path" ] || [ -d "${GIT_ROOT}/../$(basename "$path")" ]; then
    # Count commits ahead
    ahead=$(git log --oneline "${base_branch}..${branch}" 2>/dev/null | wc -l | tr -d ' ')
    files=$(git diff --stat "${base_branch}...${branch}" 2>/dev/null | tail -1 || echo "unknown")
    echo "  Commits:  ${ahead} ahead of ${base_branch}"
    echo "  Changes:  ${files}"
  else
    echo "  Status:   STALE (directory missing)"
  fi
  echo ""
done

# Show merged worktrees count
merged=$(jq '[.worktrees[] | select(.status == "merged")] | length' "$REGISTRY")
if [ "$merged" -gt 0 ]; then
  echo "(${merged} previously merged worktree(s))"
fi
