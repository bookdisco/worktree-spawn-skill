---
name: worktree-spawn
version: "1.0.0"
description: Spawn parallel git worktrees with session context. Use when the user says "spawn worktree", "parallel workspace", "worktree spawn", "worktree list", "worktree finish", or wants to work on multiple tasks in parallel using git worktrees.
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Task
---

# Worktree Spawn Skill

Spawn parallel git worktrees with compact session context for concurrent AI-assisted development.

## Commands

| Command | Description |
|---------|-------------|
| `/worktree-spawn "<task>"` | Compact context, create worktree, output spawn command |
| `/worktree-list` | List all active parallel worktrees and their status |
| `/worktree-finish [slug]` | Show diff summary, confirm, merge, cleanup |

## How It Works

```
Main worktree (you stay here)
  │
  ├─ /worktree-spawn "add auth middleware"
  │    → creates ../project-wt-auth-middleware/
  │    → outputs: cd ../project-wt-auth-middleware && claude
  │
  ├─ /worktree-spawn "fix pagination bug"
  │    → creates ../project-wt-fix-pagination/
  │    → outputs: cd ../project-wt-fix-pagination && claude
  │
  └─ You continue working in main worktree
```

---

## `/worktree-spawn` Flow

When the user invokes `/worktree-spawn "<task description>"`, follow these steps:

### Step 1: Compact Current Session Context

Generate a `.worktree-snapshot.md` file that captures:

1. **Task description** — what the spawned worktree should accomplish
2. **Parent context** — key decisions, constraints, and architectural context from the current session that the new workspace needs to know
3. **Key files to read** — specific file paths the new agent must read first to be on the same page (not the whole codebase — only files directly relevant to the task)
4. **TODOs** — concrete, actionable items for the new workspace
5. **Do NOT touch** — files or areas the new workspace should avoid modifying (to prevent merge conflicts with ongoing work in other worktrees)

Use the template at `templates/snapshot.md` as the base. Fill it in based on:
- The user's task description
- The current conversation context (what you know about the project, decisions made, etc.)
- Ask the user if the snapshot looks good before proceeding

### Step 2: Create the Git Worktree

```bash
# Derive slug from task description
SLUG="<kebab-case-slug>"  # e.g., "auth-middleware" from "add auth middleware"
PROJECT=$(basename "$(git rev-parse --show-toplevel)")
BASE_BRANCH=$(git branch --show-current)

# Create branch and worktree
git branch "wt/${SLUG}" HEAD
git worktree add "../${PROJECT}-wt-${SLUG}" "wt/${SLUG}"
```

If the worktree already exists, inform the user and ask whether to reuse or recreate.

### Step 3: Copy Snapshot and Hook CLAUDE.md

```bash
WORKTREE="../${PROJECT}-wt-${SLUG}"

# Copy snapshot
cp .worktree-snapshot.md "${WORKTREE}/.worktree-snapshot.md"

# Append context-loading instruction to CLAUDE.md in the new worktree
# If CLAUDE.md exists, append. If not, create.
```

Add this block to the new worktree's `CLAUDE.md`:

```markdown
## Worktree Context

This is a spawned worktree for parallel work. Before doing anything:
1. Read `.worktree-snapshot.md` to load the task context and key files.
2. Follow the TODOs listed in the snapshot.
3. Do NOT modify files listed in the "Do NOT Touch" section.
4. When done, commit your changes. The parent workspace will merge via `/worktree-finish`.
```

### Step 4: Update Worktree Registry

Update `.worktrees.json` in the **main worktree** root. Create if it doesn't exist.

**Schema:**
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

Ensure `.worktrees.json` is in `.gitignore` (or `.git/info/exclude`).

### Step 5: Output Spawn Command

Tell the user:

```
Worktree spawned successfully!

  Branch:    wt/auth-middleware
  Path:      ../project-wt-auth-middleware
  Snapshot:  .worktree-snapshot.md copied

To start a parallel Claude Code session:
  cd ../project-wt-auth-middleware && claude

To start a parallel Codex session:
  cd ../project-wt-auth-middleware && codex exec --skip-git-repo-check -m gpt-5.3-codex --sandbox workspace-write --full-auto "Read .worktree-snapshot.md first, then complete the TODOs listed in it." 2>/dev/null
```

Clean up the temporary `.worktree-snapshot.md` from the main worktree after copying.

---

## `/worktree-list` Flow

1. Read `.worktrees.json` from the current project root.
2. For each entry with `status: "active"`, check if the worktree still exists (`test -d <path>`).
3. For existing worktrees, show:
   - Slug and task description
   - Branch name
   - Commit count ahead of base branch: `git log --oneline <base_branch>..<branch> | wc -l`
   - Modified file count: `git diff --stat <base_branch>...<branch>`
4. Display as a formatted table.
5. If a worktree directory no longer exists, mark it as `"stale"` in the registry.

---

## `/worktree-finish` Flow

When the user invokes `/worktree-finish [slug]`:

### Step 1: Select Worktree

- If slug is provided, use it.
- If not, list active worktrees and ask the user to pick one.

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

If there are conflicts, inform the user and help resolve them interactively. Do NOT force-resolve.

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

---

## Edge Cases

- **Dirty working tree**: Before spawning, warn the user if there are uncommitted changes. Suggest committing or stashing first so the worktree starts from a clean state.
- **Branch already exists**: If `wt/<slug>` already exists, ask user whether to reuse or pick a different name.
- **Worktree path conflict**: If the directory already exists, check if it's a valid worktree or stale. Offer to clean up stale ones.
- **Merge conflicts**: During `/worktree-finish`, if merge conflicts arise, show the conflicting files and help the user resolve them. Never auto-resolve.
- **Missing git**: If not in a git repository, inform the user that this skill requires git.

## Files

- `templates/snapshot.md` — Session snapshot template
- `scripts/spawn.sh` — Worktree creation helper
- `scripts/finish.sh` — Merge and cleanup helper
- `scripts/list.sh` — List active worktrees
