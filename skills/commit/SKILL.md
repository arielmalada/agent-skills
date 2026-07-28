---
name: commit
description: This skill should be used when the user asks to "commit", "commit changes", "create a commit", "commit my work", "commit this", "stage and commit", "git commit", "make a commit", or "/commit" — and whenever a conductor skill needs one pre-sliced unit committed. Creates conventional commits (feat:/fix:/chore:, no ticket id in the subject), refuses to slip feature work onto the default branch, runs the project's format/lint gate before committing, and refreshes an open PR description afterwards. Splits into one commit per unit when a slice plan was handed over or the user asks for separate commits.
---

# Git Commit

Conventional commits with the four guards that actually catch mistakes: the right branch, formatted code, no secrets, no ticket ids in subjects.

This is a high-frequency skill — it runs many times per feature. Its cost is paid on every unit of work, so the fast path below exists to keep it cheap. Spend the full workflow only when something is genuinely undecided.

## Fast path

When **all** of these hold, go straight to Step 4 (gate → message → commit → verify) and skip the rest:

- the changes are already staged, **or** a conductor skill named the exact files to stage
- they form one logical unit
- the current branch is not the repo's default branch

A conductor handing over a file list has already made every decision this skill would ask about — `implement-feature` commits one pre-sliced unit at a time and the slice names its files. Asking again stalls the pipeline once per unit.

## Step 1 — Gather context

Run in parallel:

```bash
git branch --show-current
git status --short
git diff --staged --stat
git diff --stat
git log --oneline -5
```

Read the `--stat` output first, then pull full hunks (`git diff -- <path>`) only for files whose intent isn't already obvious from the path and change size. A bare `git diff` on a large change buries the signal in noise and costs context you'll want later.

`git log -5` is for matching the repo's existing subject style — tense, capitalisation, whether scopes are used.

If the tree is clean, say so and stop. There is nothing to commit and no message worth inventing.

## Step 2 — Branch guard

Compare the current branch against the repo's default:

```bash
git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||'
```

If that returns nothing, fall back to whichever of `main`/`master` exists.

**On the default branch, the prefix decides:**

- `chore:` work — repo maintenance, config, docs, tooling — commit directly. Plenty of repos take these on trunk, and blocking here is pure friction.
- `feat:` or `fix:` work — **stop and confirm before committing.** Feature and fix work belongs on its own branch: it needs review, it needs to be revertable as a unit, and once it's on the default branch neither is cheap.

When you stop, offer the branch rather than just raising the problem. Uncommitted changes follow you across `git switch -c <name>`, so the fix is one command and loses nothing. Name it after the tracker key if the work has a ticket, otherwise `chore/<short-description>`.

If the user has already said to commit on the default branch, that's their call — proceed.

## Step 3 — Stage changes

- Conductor named the files → stage exactly those.
- Already staged → keep that staging. Someone chose it deliberately, possibly hunk by hunk.
- Nothing staged → ask what to stage, unless the diff is unambiguously one unit and the user just said "commit" (then propose the file list and proceed).
- "All" / "everything" → stage the changed files **by name**.

Avoid `git add -A` and `git add .`. They sweep in whatever else is in the tree — build output, unrelated WIP, a scratch file, anything a stale `.gitignore` doesn't cover — and the failure is silent: the commit looks fine and the junk ships with it.

Never stage credential files (`.env`, `.env.local`, `credentials.json`, `*.pem`, keystores). If a diff *adds* something shaped like a live secret — a long random token, a private key block, a connection string with a password — stop and flag it even when the filename looks harmless. Secrets are cheap to catch here and expensive to remove from history.

## Step 4 — Run the project's gate

Formatting and lint belong **before** the commit, not after: a formatter run afterwards produces a second no-op commit, and lint failures found later mean a fixup commit or a force-push.

- If `references/<project>-specifics.md` exists, it names the exact format and lint-changed commands and any ordering traps (some formatters aren't idempotent, so the order matters). Follow it verbatim.
- Otherwise derive the commands from the repo itself — its rules file (`CLAUDE.md`, `AGENTS.md`), `package.json` scripts, or the pre-commit config. Prefer the changed-files variant; whole-repo runs are slow enough that people skip them.
- If the repo has no such commands, skip this step and say so. Don't invent a command that might not exist.

**Formatting mutates files, so re-stage the formatted paths afterwards** — otherwise you commit the pre-format content and the formatter's own diff stays behind in the working tree.

Keep whole-repo typecheck and full CI verification out of this step. Those are PR-gate concerns, they're slow, and on large monorepos they're memory-hungry enough to take the machine down mid-commit.

## Step 5 — Write the message

```
feat: description of changes
fix: description of changes
chore: description of changes
```

**Prefixes:**
- `feat:` — new features or functionality
- `fix:` — bug fixes
- `chore:` — everything non-functional: config, docs, translations, refactoring, cleanup, tooling

**Subject:** one line, concise, focused on the *why* rather than restating the diff. Match the verb to what actually happened — "add" for new, "update" for enhancements, "fix" for bugs, "remove" for deletions. A subject that says "update file" wastes the one line a reader skimming `git log` will actually see.

**No tracker ids in the subject** — and this one holds even when a project convention explicitly asks for them. The branch name already carries the key, and tracker↔VCS integrations parse commit subjects to auto-transition tickets: a key in the subject can march a ticket to Done before the work ships, and *someone else's* key marches their ticket for them. That risk outweighs the convention. Reference other tickets in file contents or the PR body, never the subject.

**Body:** only when the why doesn't fit the subject — a non-obvious trade-off, a constraint that forced the approach, a follow-up someone will need. Skip it otherwise; a body that paraphrases the subject is noise.

## Step 6 — Commit

Use a HEREDOC so multi-line messages survive shell quoting:

```bash
git commit -m "$(cat <<'EOF'
feat: description here

Co-Authored-By: <trailer the harness prescribes>
EOF
)"
```

Use the co-author trailer the current harness specifies — it names a particular model and changes over time, so read it from the active instructions rather than reusing a remembered string. If no trailer is prescribed, omit it.

## Step 7 — Verify and propagate

```bash
git status --short
```

Then, if the branch has an open PR, refresh its description via the `create-pr` skill so it reflects this commit. A PR body that describes only the first commit misleads every reviewer who trusts it:

```bash
gh pr view --json state,number 2>/dev/null
```

## Multiple commits

Split into one commit per unit when either signal is present:

- a conductor handed over a **slice plan** (a list of units, each with its own message and files), or
- the user asked for separate commits — "one commit per task", "split this up", "separate commits for each".

Don't infer it from a task-list tool. Those lists come from multi-agent orchestration and may have nothing to do with the diff in front of you; a stale one produces confidently wrong slicing.

When splitting, read `references/multi-commit.md` for the mapping and sequencing mechanics — including what to do when one file belongs to two units, which is the case that most often goes wrong.

## Rules

- **Pre-commit hook fails** → fix the cause, re-stage, retry. The hook encodes a gate the repo agreed on; bypassing it just moves the failure to CI or a reviewer.
- **Never `--no-verify` or `--no-gpg-sign`** — same reason, and unsigned commits can fail branch protection.
- **Never amend or force-push unless explicitly asked.** Amending rewrites history someone may have already pulled, and it silently destroys the previous commit's content if the staging was wrong.
- **Never push unless explicitly asked.** Committing is local and recoverable; pushing isn't.
