# Multi-commit mechanics

Read this when the `commit` skill's multi-commit signal fired: a conductor handed over a slice plan, or the user asked for separate commits.

The goal is a history where each commit is one reviewable idea that builds and passes on its own. That's worth some care — badly split commits are worse than one honest large commit, because a reviewer trusts the boundaries and a bisect trusts that each one works.

## 1. Gather with staged changes included

```bash
git branch --show-current
git status --short
git diff --staged --stat
git diff --stat
git log --oneline -5
```

`--staged` matters here specifically: if someone pre-staged part of the work, that content is invisible to `git diff` alone, so it silently drops out of the mapping and lands in whichever commit happens to `git add` it last.

## 2. Map files to units

For each unit, in the order the plan gives (earlier units usually set up later ones):

1. Read the unit's description — what it was supposed to accomplish.
2. Decide which changed paths deliver it.
3. Confirm each path only after looking at the change, not the filename. A file's path suggests its purpose; the diff proves it.

Keep the plan's ordering. Committing a unit before the one it depends on produces an intermediate commit that doesn't build, which defeats the point of splitting.

## 3. Handle files that belong to two units

This is the case that breaks naive splitting, and it's common: one view touched by both the styling slice and the wiring slice, one barrel file that exports two new modules.

Pick by whether the hunks are independent:

- **Hunks are cleanly separable and each side is meaningful alone** → split with `git add -p` (or `git add -N` then patch-stage), taking only that unit's hunks. Verify what you actually staged with `git diff --staged -- <path>` before committing; interactive staging is easy to get subtly wrong.
- **Hunks are interleaved, or one side wouldn't compile without the other** → don't split. Merge the two units into one commit and write a message covering both. An honest combined commit beats two commits where the first is broken.

Never resolve an overlap by committing the file twice with partial content and "fixing it up" in the later commit. That leaves a commit in history that doesn't work, and bisect will land on it.

## 4. Commit each unit

Per unit: stage its paths → run the project's format/lint gate → re-stage anything the formatter rewrote → commit with that unit's message → `git status --short`.

Run the gate per unit rather than once at the end. Formatting a file after its commit has already landed means either a stray no-op commit or an amend.

Each message follows the same conventions as a single commit: `feat:`/`fix:`/`chore:`, why over what, no tracker id in the subject.

## 5. Sweep the remainder

Changed files that belong to no unit are a signal, not a nuisance — usually either scope that crept in beyond the plan, or a unit nobody wrote down.

Look at what they are before deciding. If they're a coherent piece of work, commit them as their own unit with an accurate message. If they're incidental (a stray console log, a debug edit, a reverted experiment), say so and let the user decide whether they belong in the history at all. Don't sweep unexamined leftovers into a vague catch-all commit — that's where unrelated changes and stray secrets hide.

## 6. Verify the series

```bash
git status --short
git log --oneline -<number of commits created>
```

Read the log back as a reviewer would: does each subject describe one idea, and does the sequence tell the story of the change? If two adjacent commits only make sense together, the split was wrong — say so rather than leaving a misleading history.

Then refresh the PR description via `create-pr` if the branch has an open PR, once for the whole series rather than per commit.
