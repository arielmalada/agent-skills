---
name: create-pr
description: This skill should be used when the user asks to "create a PR", "create pull request", "open a PR", "make a PR", "submit PR", "push and create PR", "update PR description", "update the PR", or "/create-pr". Creates or updates GitHub pull requests using gh CLI with proper issue-tracker linking and reviewer assignment.
---

# Create / Update Pull Request

Create or update GitHub pull requests with proper issue-tracker linking, test environment URLs, and reviewer assignment using the `gh` CLI.

Project-specific facts (reviewer roster, tracker URLs, title format, test-env URL pattern, tracker etiquette) live in a local `references/<project>-specifics.md` overlay next to this skill — read the one matching the repo you are in before creating a PR, when it exists. Otherwise fall back to the generic defaults below and ask when unsure.

## Step 1: Detect Mode — Create or Update?

First, check if a PR already exists for the current branch:

```bash
gh pr view --json number,baseRefName,title,body,url 2>/dev/null || echo "NO_PR"
```

- **If a PR exists** → follow the [Update path](#update-path)
- **If no PR exists** → follow the [Create path](#create-path)

---

## Update Path

Use this when a PR already exists and needs its description refreshed (e.g. after new commits, review feedback, or when the description is stale).

### U1: Get the Real Base Branch

The base branch comes from the existing PR — never assume `master`. You already have it from Step 1 (`baseRefName`).

```bash
git fetch origin <baseRefName> --quiet
git log origin/<baseRefName>..HEAD --oneline
git diff origin/<baseRefName>...HEAD --stat
```

Extract the ticket ID from the branch name.

### U2: Assess Review Effort

Using the diff from U1, assign a review effort level (see rubric below). Then search for files that import/reference the changed functions, hooks, or components but were **not** modified — list these as "Potentially affected files".

### U3: Update the PR Body

Use `gh pr edit` with a HEREDOC:

```bash
gh pr edit <number> --body "$(cat <<'EOF'
<body using the template below>
EOF
)"
```

Skip asking for title and reviewers — they are already set.

---

## Create Path

Use this when no PR exists yet.

### C1: Gather Context

```bash
git branch --show-current
git status
```

Determine the base branch. Check if the branch was cut from `master` or from another feature branch:

```bash
git fetch origin master --quiet
# Is master the actual base, or is this stacked on another branch?
# Check if a parent ticket branch exists and this branch diverged from it
git log origin/master..HEAD --oneline
```

If this is a stacked PR (branched off a parent ticket branch, not master), identify the correct base. When in doubt, ask the user.

Extract the ticket ID from the branch name.

### C2: Check Remote State and Push

```bash
git rev-list --left-right --count origin/$(git branch --show-current)...HEAD 2>/dev/null || echo "no upstream"
```

If unpushed commits or no upstream:

```bash
git push -u origin $(git branch --show-current)
```

### C3: Fetch Base and Diff

```bash
git fetch origin <base-branch> --quiet
git log origin/<base-branch>..HEAD --oneline
git diff origin/<base-branch>...HEAD --stat
```

### C4: Ask User for PR Details

Collect from the user:

- **PR title** — Ask for a description. Clean it up if rough, but preserve meaning
- **PR description** — Ask for what changed and why. Format properly in markdown
- **Testing instructions** — Ask how to test. Do not accept vague instructions; ask again if insufficient
- **Reviewers** — Ask which reviewers to assign. Always offer "Skip / no reviewers" as an option. Offer the project's reviewer roster from the specifics file when one exists; otherwise ask for GitHub handles.

### C5: Assess Review Effort

Analyze the diff and assign a review effort level. Then search for files that import/reference the changed functions, hooks, or components but were **not** modified — list these as "Potentially affected files".

### C6: Create the PR

```bash
gh pr create --title "<per the project's title convention — see specifics; default: 'TICKET-123 Short description'>" --body "$(cat <<'EOF'
<body using the template below>
EOF
)" --reviewer "reviewer1,reviewer2"
```

Omit `--reviewer` if user chose to skip.

### C7: Tracker Linking Etiquette

Follow the project's tracker-linking etiquette from the specifics file. Some projects want a ticket comment with the PR link and testing instructions; others have tracker↔VCS automation that already links the PR (and where an extra comment can nudge automation) — for those, **skip the comment**. When no specifics file covers the repo, ask the user.

### C8: Open in Browser and Follow Up

```bash
gh pr view --web
```

Remind the user to add a screenshot to the PR — it helps reviewers orientate.

---

## PR Body Template

```
TICKET-123

<tracker link line — format in specifics>
<test env line — only if the project ships per-ticket test environments; URL pattern in specifics>

## Review effort: <Trivial|Light|Medium|Heavy>

<1-2 sentence justification>

### Potentially affected files (not modified)
- `path/to/file.tsx` — brief reason

## What changed

<formatted description>

## How to test

<formatted testing instructions>
```

If this is a stacked PR (has a parent ticket), also include a `Parent: <tracker link>` line.

---

## Review Effort Rubric

| Level | Criteria |
|-------|----------|
| **Trivial** | 1-2 files, purely mechanical changes. Typo fixes, translation-only, renaming, config tweaks. No logic changes. |
| **Light** | Small scope with straightforward logic. Few files, clear intent, mostly prop threading or simple conditionals. No architectural decisions needed. |
| **Medium** | Multiple files with meaningful logic. New components, adapters, or hooks. May involve business rules, state management, or API integration. Requires understanding context. |
| **Heavy** | Large scope or complex logic. Architectural changes, new features spanning multiple layers, complex state flows, or risky refactors. Requires deep context and careful review. |

Factors to consider: diff size, logic complexity, blast radius, context required, risk.

IMPORTANT: Exclude mechanical bulk files from file count and insertion count when assessing effort — generated files, lockfiles, translation/locale JSONs (project-specific list in specifics). They are mechanical additions that don't reflect logic complexity.

---

## Rules

- ALWAYS check for an existing PR first — never assume create mode
- NEVER assume `master`/`main` as base branch — get it from `gh pr view --json baseRefName` (update) or detect stacking (create)
- Always extract the ticket ID from the branch name
- Always include the tracker link (and test environment URL where the project has one) in the body
- Do not accept poor testing instructions — ask again if vague
- Always offer "Skip / no reviewers" when asking about reviewers
- If `gh` CLI is not installed, guide installation: `brew install gh` then `gh auth login`
- Return the PR URL when done
