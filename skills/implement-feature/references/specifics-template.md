# Specifics template for `implement-feature`

Copy this to `references/<project>-specifics.md` next to the skill and fill it in. That filename is
gitignored, so your project's real commands and paths stay local while this template ships.

**Why this file decides whether the skill is worth anything.** `SKILL.md` is deliberately vague — it
says "run the project's fast lint gate", not `yarn lint:files`. That vagueness is what makes it
portable, and also what makes it inert on its own: a capable model already verifies ticket claims,
reuses code before writing new, slices small commits, and hands off to tests before a PR. Those
behaviours are largely emergent. What a model *cannot* derive by reading your repo is that your
formatter flip-flops, that your e2e suite runs in a different locale than your UI, or that hand-editing
locale JSON is forbidden here. **This file is where the skill's actual value lives.** An
`implement-feature` install without one degrades to roughly unaided behaviour.

Fill sections in the order given — they are ordered by observed payoff, not by the order the skill
body reads them. Sections 1–4 are the minimum for the skill to beat baseline. Delete this preamble
and any section that genuinely doesn't apply; a confidently wrong entry is worse than an absent one,
because subagents are handed these facts as binding.

Open with a scope header so the file can't leak into the wrong repo:

```markdown
# <PROJECT> Specifics for implement-feature
Project-specific facts for <repo path>, app at <package path>.
**Ignore this file outside that repo.** Facts verified <YYYY-MM-DD>; paths rot — trust the repo
over this file when they disagree.
```

That last clause matters. These files age, and a stale path that reads authoritatively will send a
subagent editing a file that moved. Dating it tells a reader how much to trust it.

---

## 1. Translation / copy tooling — REQUIRED

The single highest-value section. In benchmarking, routing translations through project tooling was
the one rule that a model never got right unaided — every unaided run proposed hand-editing the
locale JSON, which is exactly the failure this section prevents.

| Slot | Fill with | How to find it |
| --- | --- | --- |
| Tooling | MCP tool names and/or skills that add/change copy | `ls ~/.claude/skills \| grep -i "translat\|i18n"`; check the MCP server list |
| Hand-edit rule | Whether editing locale files directly is forbidden | look for a rules/ doc or CI check on locale files |
| Locale set | Every locale that must be kept in sync | `ls <app>/translations/` or `**/locales/` |
| Key convention | The key-naming shape | open any locale file and read 3 real keys |
| Consistency check | Command to run after key changes | `grep -iE "intl\|i18n\|locale" package.json` |

State the forbidden action explicitly, not just the allowed one — "never hand-edit the locale JSONs"
is the sentence that survives being pasted into a subagent prompt.

If the project has no translation layer, say so outright. "Copy is inline English, no i18n" stops the
skill from inventing a step.

## 2. Verification commands — REQUIRED

Every command the skill's per-unit loop refers to. Include the traps: a command that *silently*
misbehaves costs more than a missing one, because the model trusts a green exit.

| When | Command | Notes / traps |
| --- | --- | --- |
| After every edit | | the fast gate — must be seconds, not minutes |
| Type check | | note OOM/heap flags if it needs them |
| Format before commit | | note non-idempotence, and which tool is authoritative on conflict |
| Final-commit order | | exact order if formatters disagree with each other |
| Full pre-PR gate | | read-only variant only; name the one that mutates so it's avoided |

Find these in `package.json` scripts, the CI workflow (the real source of truth for what must pass),
and any pre-commit hook config. Prefer what CI actually runs over what the README claims.

Two trap classes worth hunting for, because both produce confidently wrong results:
- **Non-idempotent or repo-wide formatters** — a `format` script that ignores file arguments and
  rewrites everything, or two formatters that each undo the other. Record the exact order that
  converges.
- **Resource-hungry commands** — anything that OOMs or can wedge the machine. Record the guard
  (a RAM check, a heap flag) and say plainly that the command should be skipped and reported as
  skipped rather than run past the guard.

## 3. Distrust-the-ticket verification targets — REQUIRED

The skill tells the model not to trust ticket prose. This table tells it *where* to check. Map each
kind of claim a ticket makes by string to the file that settles it.

| Ticket claims a... | Verify against |
| --- | --- |
| permission / role / feature flag | the constants file that enumerates them |
| UI label or status text | the locale files |
| router or framework API | the actual installed major version — check the lockfile, not the docs |
| API shape / endpoint | the generated client or schema, not the ticket prose |

Include a real past miss if you have one — "a ticket said `PRO_TRADE`; the real gate was
`PRO_CLEARING`" teaches the failure mode far better than the abstract rule.

One caveat: if a past miss is already documented in a code comment, the model will find it by
grepping and this row adds nothing. The rows that earn their place are the ones where the truth is
*not* discoverable by searching for the wrong name — API major versions especially, since the wrong
API simply doesn't appear anywhere.

## 4. Skill / agent roster — REQUIRED

`SKILL.md` refers to collaborators by role. This resolves each role to a real installed name, and is
what lets the body stay project-agnostic.

| Role in the skill body | This project's name |
| --- | --- |
| Ticket-fetch skill | |
| Feature-context skill | |
| AC-verify skill | |
| Translation skills | |
| Story-authoring skill | |
| E2E run skill | |
| Package-scoped PR skill | |
| Quality-gate agent | |

`ls ~/.claude/skills` plus the repo's `.claude/skills/` gives the candidates. Two things worth
recording beyond the names:

- **Which name wins when several claim the same trigger.** Crowded namespaces are common; if the
  repo ships three ticket skills, say which one this pipeline should use and which are decoys.
- **Roles with no local implementation.** Name the built-in substitute rather than leaving the row
  blank, so the body's reference doesn't dead-end.

## 5. Ticket tracker

- **Routine fetch**: the cheap inline command. Flag the expensive path explicitly if one exists —
  dispatching a heavyweight tracker agent for a 2-second fetch is a common, costly mistake.
- **Parsing**: if the tracker returns a rich-text AST or dumps over ~100KB, include a working parse
  snippet. Reading raw tracker JSON wastes an enormous amount of context.
- **Status checks**: the command for a blocker's real status. A "blocked by backend" note is often
  already resolved, and that changes scope.
- **Automation traps**: if a tracker↔VCS integration auto-transitions tickets from branch names,
  commit subjects, or PR titles, **say so here in the strongest terms**. Putting another ticket's key
  in a branch or commit subject can march an unrelated ticket to done with nothing shipped, silently.
- **Etiquette**: whether to comment the PR link back, or whether the integration already does it.

## 6. Design tool

Exact tool/MCP names for reading designs, and the cheap-vs-expensive routing. Worth recording:

- The tool names, so they can be called without guessing.
- **What never to do** — e.g. opening the design tool in a browser instead of via its API. Browser
  snapshots of a canvas are unreadable and burn enormous context.
- Where designs actually live relative to features (a canvas often sits on a different page than the
  feature it describes).
- What to do when the design tool is unavailable: inspect inline, or proceed and flag.

## 7. Reuse-search locations

Where to look before writing anything new — the shared packages, the sibling-feature directory, the
utility locations. This is what turns "search for existing implementations" from advice into an action.

Be specific about **competing implementations**, since this is where a plausible-looking choice goes
wrong: if two components do the same job, give the import counts and the rule for choosing
("match whichever the sibling features around your change use"). Note the import-layering rule if one
exists, and any package that must never be imported directly in favour of a wrapper.

Counts date quickly — write the date next to them, or express the rule so it survives the numbers
going stale.

## 8. Test-suite traps

Point at the canonical copy if another skill owns it; don't fork it. Repeat only the facts a subagent
prompt cannot go without — for example:

- **The locale the test suite runs in**, if it differs from the primary UI locale. Text selectors
  written against the wrong locale fail in ways that look like product bugs.
- **Shared state a parallel agent can clobber** — auth fixtures, seeded data, snapshot baselines.
  Name what must never be run concurrently.
- Tags, run commands, and any lint scope that excludes the test directory.

## 9. PR mechanics

- Base-branch resolution, if the project stacks PRs — never assume the default branch.
- Title/body conventions, and where the ticket key does and does not belong.
- Reviewer assignment habits.

## 10. Other landmines

A short list of "looks fine, is not" facts with no natural home above. Good candidates: generated
files that are hand-edited in practice despite a do-not-edit header (and the build command that would
revert those edits), config that must not be regenerated, environment naming that differs from what
people say out loud.

Each entry should name the wrong action and its consequence. "Never run `build:tokens` for a token
tweak — it reverts hand-edits" is usable. "Be careful with tokens" is not.

---

## Keeping this file honest

- **Date it, and re-verify when something surprises you.** The failure mode is a stale path that
  reads authoritatively.
- **Write the wrong action, not just the right one.** Subagents inherit none of your context; the
  prohibition is the part that travels.
- **Delete rather than guess.** An absent section makes the model investigate. A wrong one makes it
  confidently break something.
- **Prefer rules over counts.** "Match the sibling features" outlives "56 vs 37 importers".
