---
name: validate-change
description: This skill should be used to validate an implementation (current branch or a PR) against its ticket — "validate this change", "is this ticket done", "does this branch/PR satisfy the AC", "check the PR against TICKET-123", "are we ready for review", "did I miss anything in the ticket". Orchestrates four angles: AC matrix (Met/Partial/Not Met with evidence), adversarial code review, verification command gates, and an honest outcome-first report. Runs AFTER author-tests has closed the test gate. Do NOT use to author tests (author-tests), to root-cause the defects it finds (debug-issue), or for an AC-matrix-only check (use the project's AC-verify skill directly). Invoke proactively when an implementation is about to be declared complete, or before create-pr.
---

# Validate Change (multi-angle, honest)

## Overview

An implementation is not "done" when the diff looks right — it is done when every AC is
demonstrably met, the code survives adversarial review, the repo's gates pass, and the report
says so honestly (including what was skipped). This skill is a **conductor**: it decides
sequence, fan-out, and verification depth, then invokes existing skills and agents by name.
It does not re-implement them.

When a local `references/<project>-specifics.md` overlay exists for the repo you're in,
read it **before Phase 0** — it holds the verified commands with their caveats, the
project gap axes, the skill-name roster, and the diff noise to ignore. Otherwise derive
the equivalents from the project's rules.

## Scale the validation to the change

| Change                                                          | Angles to run                                                                  |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Copy/translation/config-only                                    | Gates (3) + a one-pass AC check.                                               |
| Single-feature ticket, few files                                | AC matrix (1) + `adversarial-review` in routine mode (2) + gates (3)           |
| Multi-file feature, or high-stakes (money flow, permission gate) | Full: AC fan-out, dimension-fanned adversarial review, gates                   |
| Audit / release-scale sweep AND user opted into workflows        | `references/workflow-templates.md` — the Workflow-tool templates (Claude Code only) |

## Phase 0 — Resolve the true scope

1. **Fetch the ticket with the project's ticket-fetch skill** (named in the specifics
   roster; typically inline, ~2s). Never dispatch a heavyweight tracker subagent for a
   routine fetch — it costs minutes for the same data.
2. **Distrust ticket prose.** Real tickets have named permissions that don't exist, quoted
   stale UI labels, and assumed the wrong router API. Verify every load-bearing claim
   (permission names, label text, API shape) against the code before scoring AC against it.
3. **Diff against the real merge base.** In projects with stacked PRs,
   assuming the default branch inflates the diff with the parent branch's work and
   misrepresents scope. Resolve the real base and diff from the merge base — exact recipe
   (gh command + three-dot diff) in the specifics file.
4. **Subtract known diff noise** (the specifics file lists an intentional local dev-hack that
   must never be flagged, restored, or committed).
5. If the ticket links Figma, pull the screenshot/metadata now — the AC matrix needs it. When
   Figma and ticket AC conflict, the AC wins; flag the conflict for the PO in the report.

## Angle 1 — AC matrix

Invoke the project's AC-verify skill (named in the specifics roster) for the report shape
(requirement-by-requirement Met / Partial / Not Met, with evidence as file/function and
concerns). This skill adds two things on top:

**The subtle-gap hunt.** Black-box testing verifies the happy path the author already tested.
The gaps that reach production are the symmetric variants nobody exercised. For every AC row,
also ask:

| Gap class            | Question                                                                              |
| -------------------- | ------------------------------------------------------------------------------------- |
| Locale parity        | New key present in every supported locale (project set + file locations in the specifics file)? Translation-consistency check clean? |
| Brand/tenant variant | Does the project have per-brand UI carve-outs on the touched screen (project axes in the specifics overlay)? |
| Party/actor type     | Works for every actor type the domain supports (project axes in specifics — e.g. person vs organization party)? |
| Entity symmetry      | If one entity variant got the change, did its siblings — or was the AC explicit about single-variant scope (project axes in specifics)? |
| Permission gates     | Behavior correct for gated AND ungated users? Gate verified against the real catalog?  |
| Responsive           | Does the AC imply a mobile variant the diff never touches? (Flag it in the report.)      |
| Test coverage        | Is there a spec/unit test guarding the AC? If not, hand off to `author-tests`.         |

**Fan-out for big tickets.** When the AC has 8+ criteria and the harness supports
subagents, cluster them (3–6 per cluster, plus one cross-cutting cluster from the table
above) and run one agent per cluster concurrently (Claude Code: multiple Agent calls in a
single message). Merge the rows
yourself; re-verify any Not Met/Partial row before reporting it — negatives drive PO flags
and rework, so they must be solid — and spot-check any suspicious Met row (a false "Met"
ships a gap).

## Angle 2 — Adversarial code review

Invoke the **`adversarial-review`** skill — it owns the canonical pipeline (**dimensions →
find → adversarially verify → report only confirmed findings, most severe first**), the
effort-level choice (routine inline vs thorough fan-out), and the reviewer-calibration
rules (data-flow tracing before flagging rendering bugs, actually-broken vs
could-be-better, the no-memoize convention). Do not re-derive that pipeline here.

What this conductor adds to the dispatch: pass the **project gap axes** from the specifics
file as extra coverage-symmetry dimensions (locales, brand variants, entity/party
symmetry, permission gates), and the known-diff-noise list so intentional dev-hacks are
never flagged.

## Angle 3 — Verification command gates

Run these in the main thread; they are cheap relative to a bounced PR. The exact commands
and their traps (OOM, formatter conflicts, false positives) live ONLY in the specifics
file — run them exactly as given there; the table below names the gates, not the commands.

| When                        | Gate                                                                       |
| --------------------------- | --------------------------------------------------------------------------- |
| After every edit            | Fast lint gate on the changed files                                          |
| Multi-file type check       | TS gate — has a silent-OOM trap; use the specifics file's exact invocation   |
| Before commit               | Formatter gate — the specifics file says which formatter to trust for TS     |
| Translation keys touched    | Translation-consistency gate                                                 |
| Before PR                   | Full read-only CI gate — never skip; never the mutating variant              |
| View component changed     | Storybook story exists/updated (where the project mandates them) + dispatch the `ui-design-reviewer` agent with the injection block from the specifics file |
| e2e spec touched            | The e2e-scoped lint where the project splits it from root lint               |
| After the PR is open        | Dispatch the project's quality-gate agent (named in the specifics roster)    |

Quote failing output verbatim in the report — "lint failed" without the error is
unactionable.

## Angle 4 — Honest reporting

- **Outcome first**: one-line verdict (Ready / Needs work / Blocked), then per-angle detail.
- **Failing output quoted**, not summarized.
- **Every skipped check named as skipped** with the reason. A report that omits what wasn't
  run is a false green.
- **AC deviations flagged for the PO** explicitly — anything the implementation does
  differently from the ticket (including Figma-vs-AC conflicts resolved in AC's favor).
- **No fake-green.** If a behavior is gated on legacy data you can't seed on dev, run the
  discriminating fresh-data experiment to classify it (general vs legacy-only), then report
  the honest finding plus a manual-test note. Never mock the malformed state to force a
  green result — that asserts an invented condition.
- **Confirmed defects that need root-causing** (symptom observed, cause unclear): hand off to
  the `debug-issue` skill rather than patching the symptom inline. Missing test coverage
  found in Angle 1 hands off to `author-tests`.
- Tracker etiquette (whether status transitions and PR comments are wanted) is in the specifics overlay.

## Orchestration mechanics

- **Default: direct subagent fan-out** where the harness supports it (Claude Code:
  multiple Agent calls in one message run concurrently) — that covers AC-cluster fan-out,
  finder+refuter review, and parallel AC/review for routine tickets. Without subagents,
  run the same angles as sequential passes yourself.
- **The Workflow tool is Claude Code-only, requires explicit user opt-in** ("use a
  workflow", "ultracode", or a skill that mandates it), **and must be present in the
  session's tool inventory** — verify at use time; subagent sessions in particular lack it,
  and when it is absent the templates' prompts work as plain subagent prompts. Reach for it for
  audit/migration/review-scale validation with opt-in; otherwise briefly offer it and
  proceed with direct fan-out. Templates: `references/workflow-templates.md`.
- **Subagent prompts must carry their own context** — subagents do not inherit the
  conversation, the auto-loaded rules, or the user's memory. Every dispatch embeds: the
  branch and base ref, absolute paths, the relevant conventions and traps from the
  specifics file (locale set, the project's locale trap, what NOT to touch), and a demand
  for a structured return (schema-forced where the tool supports it). Treat a dead/silent
  agent as a skipped check, not a pass.
- Read-only lookups ("where is X handled") go to read-only exploration subagents
  (Claude Code: `Explore`); judgment stays with you.

## References

- **`references/<project>-specifics.md`** — local, per-project overlay (verified commands
  + caveats, project gap axes, ui-design-reviewer injection block, diff-noise, tracker
  etiquette, skill/agent roster); never committed to this repo. Read before Phase 0 when
  one exists for the repo you're in.
- **`references/workflow-templates.md`** — two runnable Workflow scripts (Claude Code
  only: adversarial review pipeline, AC-matrix fan-out) with when/when-not guidance. Read
  only when the Workflow tool is in play.
