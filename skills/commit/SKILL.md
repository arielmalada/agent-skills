---
name: commit
description: This skill should be used when the user asks to "commit", "commit changes", "create a commit", "commit my work", "commit this", "stage and commit", "git commit", "make a commit", or "/commit". Creates git commits following conventional commit conventions. When a plan-mode task list exists, creates one commit per completed task.
---

# Git Commit

Create well-formatted git commits following conventional commit conventions.

## Workflow

### Step 0: Check for Plan Mode Task List

If the harness exposes a plan-mode task list (Claude Code: the `TaskList` tool), check whether there are completed tasks.

- **If completed tasks exist**: Follow the **Multi-Commit Workflow** (one commit per completed task)
- **If no tasks exist, or the harness has no task-list mechanism**: Follow the **Single Commit Workflow** (standard behavior)

---

## Multi-Commit Workflow (Plan Mode)

When completed tasks are found from a plan, create a separate commit for each task:

### Step M1: Gather Context

Run in parallel:

```bash
git branch --show-current
git status
git diff
git log --oneline -5
```

### Step M2: Map Files to Tasks

For each completed task:
1. Read the task description (Claude Code: `TaskGet`)
2. Identify which changed files belong to that task based on the work described
3. Group files by task

### Step M3: Create Commits Sequentially

For each task (in task ID order):
1. Stage only the files belonging to that task (`git add <specific files>`)
2. Create a commit message that describes what that task accomplished
3. Commit using the HEREDOC format:
   ```bash
   git commit -m "$(cat <<'EOF'
   feat: description here

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```
4. Verify with `git status`

If some changed files don't belong to any task, create a final catch-all commit for them.

### Step M4: Final Verification

```bash
git status
git log --oneline -<number of commits created>
```

---

## Single Commit Workflow (Standard)

### Step 1: Gather Context

Run in parallel:

```bash
git branch --show-current
git status
git diff --staged
git diff
git log --oneline -5
```

### Step 2: Stage Changes

- If changes are already staged, proceed to step 3
- **If a conductor skill invoked this one with an explicit file list** (`implement-feature` commits one pre-sliced unit at a time, and the slice names its files): stage exactly those files and proceed — do not ask. Asking here stalls the pipeline on every unit, and the slice already encodes the answer.
- Otherwise, if nothing is staged, ask the user what to stage
- If the user says "all" or "everything", stage specific changed files by name (avoid `git add -A` or `git add .`)
- Never stage files that likely contain secrets (`.env`, `credentials.json`, etc.)

### Step 3: Create Commit Message

Follow conventional commits format:

```
feat: description of changes
fix: description of changes
chore: description of changes
```

**Prefix rules:**
- `feat:` — new features or functionality
- `fix:` — bug fixes
- `chore:` — non-functional changes (translations, config, docs, refactoring, cleanup)

**Message guidelines:**
- Keep concise (1-2 sentences)
- Focus on the "why" rather than the "what"
- Summarize the nature of changes accurately ("add" for new, "update" for enhancements, "fix" for bugs, "remove" for deletions)

### Step 4: Commit

Use a HEREDOC for proper formatting:

```bash
git commit -m "$(cat <<'EOF'
feat: description here

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 5: Verify

```bash
git status
```

---

## Rules

- If a pre-commit hook fails, fix the issue, re-stage the affected files, and retry the commit — never use --amend and never skip hooks
- Never use `--no-verify` or `--no-gpg-sign`
- Never push unless explicitly asked
- Never amend unless explicitly asked
- Do not commit files containing secrets
