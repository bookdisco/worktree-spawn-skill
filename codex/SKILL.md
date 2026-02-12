---
name: worktree-spawn
description: Spawn parallel git worktrees with session context for concurrent AI-assisted development. Use when the user asks to create, list, or finish parallel worktrees (`worktree-spawn`, `worktree-list`, `worktree-finish`) or wants to split work into branch-isolated agent sessions.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
metadata:
  short-description: Parallel git worktree orchestration for Codex
---

# Worktree Spawn (Codex)

Spawn parallel git worktrees with compact session context for concurrent AI-assisted development.

## Important for Codex

Codex skills do not run Claude-style hooks automatically.

Manual checkpoints (always run these):
1. Re-read `.worktree-snapshot.md` before major decisions in a spawned worktree.
2. Re-read `.worktrees.json` before any stateful operation (`worktree-spawn`, `worktree-list`, `worktree-finish`).
3. Update `.worktrees.json` immediately after operations that change state.
4. Before ending the task, verify registry updates and snapshot copy/cleanup steps are complete.

## Commands

| Command | Description |
|---------|-------------|
| `/worktree-spawn "<task>"` | Compact context, create worktree, output launch commands |
| `/worktree-list` | List all active parallel worktrees and their status |
| `/worktree-finish [slug]` | Show diff summary, confirm, merge, cleanup |

## How It Works

```text
Main worktree (you stay here)
  |
  |- /worktree-spawn "add auth middleware"
  |    -> creates ../project-wt-auth-middleware/
  |    -> launch codex:  cd ../project-wt-auth-middleware && codex ...
  |    -> launch claude: cd ../project-wt-auth-middleware && claude
  |
  |- /worktree-spawn "fix pagination bug"
  |    -> creates ../project-wt-fix-pagination/
  |
  \- You continue working in main worktree
```

---

## `/worktree-spawn` Flow

When the user invokes `/worktree-spawn "<task description>"`, follow these steps:

### Step 1: Compact Current Session Context

Generate a `.worktree-snapshot.md` file that captures:

1. Task description - what the spawned worktree should accomplish
2. Parent context - key decisions, constraints, and architectural context from the current session that the new workspace needs
3. Key files to read - specific file paths the new agent must read first (only directly relevant files)
4. TODOs - concrete, actionable items for the new workspace
5. Do NOT touch - files or areas the new workspace should avoid modifying

Use the template at `templates/snapshot.md` as the base. Fill it from:
- The user's task description
- Current conversation context

Ask the user if the snapshot looks good before proceeding.

Manual checkpoint:
- Re-read `.worktree-snapshot.md` before creating the branch/worktree.

### Step 2: Create the Git Worktree

Use inline shell logic or reuse `../claude-code/scripts/spawn.sh`.

Inline sequence:

```bash
# Derive slug from task description
SLUG="<kebab-case-slug>"  # e.g., "auth-middleware"
PROJECT=$(basename "$(git rev-parse --show-toplevel)")
BASE_BRANCH=$(git branch --show-current)

# Create branch and worktree
git branch "wt/${SLUG}" HEAD
git worktree add "../${PROJECT}-wt-${SLUG}" "wt/${SLUG}"
```

If the worktree already exists, inform the user and ask whether to reuse or recreate.

### Step 3: Copy Snapshot and Add Context Loader Files

```bash
WORKTREE="../${PROJECT}-wt-${SLUG}"

# Copy snapshot
cp .worktree-snapshot.md "${WORKTREE}/.worktree-snapshot.md"
```

Append this block to `AGENTS.md` in the new worktree (create if missing):

```markdown
## Worktree Context

This is a spawned worktree for parallel work. Before doing anything:
1. Read `.worktree-snapshot.md` to load task context and key files.
2. Follow the TODOs listed in the snapshot.
3. Do NOT modify files listed in "Do NOT Touch".
4. Re-read `.worktree-snapshot.md` before major decisions.
5. When done, commit your changes. The parent workspace will merge via `/worktree-finish`.
```

If `CLAUDE.md` exists in the new worktree, append the same block there for Claude sessions.

### Step 4: Update Worktree Registry

Update `.worktrees.json` in the main worktree root. Create it if it does not exist.

Schema (keep exactly this structure for cross-agent compatibility):

```json
{
  "worktrees": [
    {
      "slug": "auth-middleware",
      "branch": "wt/auth-middleware",
      "path": "../project-wt-auth-middleware",
      "abs_path": "/absolute/path/to/project-wt-auth-middleware",
      "task": "add auth middleware",
      "base_branch": "main",
      "created": "2026-02-11T10:30:00Z",
      "status": "active"
    }
  ]
}
```

Ensure `.worktrees.json` is in `.gitignore` or `.git/info/exclude`.

Manual checkpoint:
- Re-read `.worktrees.json` after write and confirm the new entry is present once.

### Step 5: Output Spawn Command

Tell the user:

```text
Worktree spawned successfully!

  Branch:    wt/auth-middleware
  Path:      ../project-wt-auth-middleware
  Snapshot:  .worktree-snapshot.md copied

To start a parallel Codex session:
  cd ../project-wt-auth-middleware && codex exec --skip-git-repo-check -m gpt-5.3-codex --sandbox workspace-write --full-auto "Read .worktree-snapshot.md first, then complete the TODOs listed in it." 2>/dev/null

To start a parallel Claude Code session:
  cd ../project-wt-auth-middleware && claude
```

Clean up the temporary `.worktree-snapshot.md` from the main worktree after copying.

Manual checkpoint:
- Confirm `.worktree-snapshot.md` was removed from the main worktree.

---

## `/worktree-list` Flow

1. Read `.worktrees.json` from the current project root.
2. Manual checkpoint: re-read `.worktrees.json` before reporting status.
3. For each entry with `status: "active"`, check if the worktree still exists (`test -d <path>`).
4. For existing worktrees, show:
   - Slug and task description
   - Branch name
   - Commit count ahead of base branch: `git log --oneline <base_branch>..<branch> | wc -l`
   - Modified file summary: `git diff --stat <base_branch>...<branch>`
5. Display as a formatted table.
6. If a worktree directory no longer exists, mark it as `"stale"` in the registry and write the file.

Manual checkpoint:
- If any status changed to `"stale"`, persist the update in `.worktrees.json` before finishing.

---

## `/worktree-finish` Flow

When the user invokes `/worktree-finish [slug]`:

### Step 1: Select Worktree

- If slug is provided, use it.
- If not, list active worktrees and ask the user to pick one.

Manual checkpoint:
- Re-read the selected entry in `.worktrees.json` before merge actions.

### Step 2: Show Diff Summary

```bash
BRANCH="wt/${SLUG}"
BASE_BRANCH="<from registry>"

# Show what will be merged
git log --oneline "${BASE_BRANCH}..${BRANCH}"
git diff --stat "${BASE_BRANCH}...${BRANCH}"
```

Present the summary to the user and ask for confirmation.

### Step 3: Merge

```bash
# Merge the worktree branch into the current branch
git merge --no-ff "wt/${SLUG}" -m "merge: worktree ${SLUG} - <task description>"
```

If conflicts appear, inform the user and help resolve interactively. Do not force-resolve.

Manual checkpoint:
- Re-read `.worktree-snapshot.md` from the worktree when conflict resolution needs original task intent.

### Step 4: Cleanup

After successful merge:

```bash
# Remove the worktree
git worktree remove "../${PROJECT}-wt-${SLUG}"

# Delete the branch
git branch -d "wt/${SLUG}"
```

### Step 5: Update Registry

Update the entry in `.worktrees.json`:
- Set `status` to `"merged"`
- Add `merged_at` timestamp

Manual checkpoint:
- Re-read `.worktrees.json` and verify only one matching entry was updated.

---

## Edge Cases

- Dirty working tree: before spawning, warn if there are uncommitted changes. Suggest commit/stash first.
- Branch already exists: if `wt/<slug>` exists, ask user whether to reuse or pick a different name.
- Worktree path conflict: if directory exists, check if valid worktree or stale, then offer cleanup.
- Merge conflicts: during `/worktree-finish`, show conflicting files and help resolve. Never auto-resolve.
- Missing git: if not in a git repository, explain that this skill requires git.

## Files

- `templates/snapshot.md` - Session snapshot template
- `../claude-code/scripts/spawn.sh` - Optional helper for worktree creation
- `../claude-code/scripts/list.sh` - Optional helper for listing active worktrees
- `../claude-code/scripts/finish.sh` - Optional helper for merge/cleanup
