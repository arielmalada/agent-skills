---
name: adversarial-review
description: This skill should be used to review a working diff or branch for correctness bugs and quality findings — "review this diff", "review my change/branch", "code review this", "find bugs in my change", "review before PR". Resolves the true merge base, reviews across dimensions, adversarially verifies every finding before reporting, and returns a severity-ranked markdown report; applies confirmed fixes only on explicit request. Do NOT use for ticket-level validation against acceptance criteria (validate-change), for applying cleanup/simplification (polish-code), or for runtime end-to-end confirmation (exercise-change).
---

# Adversarial Review

Review the working diff for defects, verify every finding adversarially before it reaches the report, and rank what survives. The core discipline: **an unverified finding costs more trust than a missed one** — plausible-but-wrong findings burn the reader's time and credibility.

## Step 1 — Resolve the true scope

Never assume the diff is `HEAD` vs the default branch:

1. If a PR exists: `gh pr view --json baseRefName` — stacked PRs make the default branch the wrong base.
2. Otherwise: merge-base with the default branch (`git merge-base HEAD origin/<default>`).
3. Diff three-dot from that base (`git diff <base>...HEAD`) plus uncommitted changes when reviewing the working tree.
4. Subtract known diff noise — when a conductor skill invoked this review, its project specifics may list intentional local dev-hacks that must never be flagged; honor that list.

## Step 2 — Pick the effort level

| Level | When | Shape |
| --- | --- | --- |
| Routine | Small single-feature diff, few files | Review inline, correctness-first, report only high-confidence findings |
| Thorough (default when subagents exist and the diff is non-trivial) | Multi-file diff, high stakes (money, permissions), or the user asked for depth | Multi-agent: parallel finders per dimension + parallel refuters per finding (see Orchestration below); may include unconfirmed findings, explicitly labeled PLAUSIBLE |

**Default to the multi-agent shape whenever the harness supports subagents** — parallel review agents are faster wall-clock and each finder reads with one lens instead of skimming with eight. Drop to inline routine mode only for genuinely small diffs, or when the harness has no subagents (then run the dimensions as sequential passes yourself).

## Multi-agent orchestration (thorough mode)

1. **Fan out finders in parallel** — one subagent per dimension from Step 3, all dispatched concurrently (Claude Code: multiple Agent calls in one message). Each finder prompt embeds: the exact diff command (base ref resolved in Step 1), "read every touched file IN FULL", its ONE dimension, the diff-noise ignore-list, and the structured output contract below.
2. **Finders are coverage-first, never self-filtering** — prompt them to "report everything, tag confidence + severity; do NOT filter to only-confirmed" (cheap models follow "only report confirmed" literally and recall collapses). Filtering is the verifier's job, not the finder's.
3. **Fan out refuters in parallel** — for every finding, dispatch the distinct verification lenses from Step 4 concurrently (they don't depend on each other). A finding dies when half or more of its refuters break it.
4. **Model routing** (where per-dispatch model selection exists): finders and refuters on a cheaper model; the merge, the kill decisions, and the final severity ranking stay with YOU on the session model — a wrong verdict propagates, a missed finder finding doesn't.
5. **Dead agents are skipped coverage, not clean results** — a finder that returns nothing usable means that dimension was NOT reviewed; say so in the report rather than folding it into "no findings".
6. Subagents inherit nothing: every prompt carries the branch, base ref, absolute paths, and relevant traps from the invoking conductor's overlay.

## Step 3 — Dimensions

- **Correctness / data-flow** — wrong values, broken state transitions, unhandled `undefined`/null paths that actually reach rendering or persistence
- **Error and edge handling** — empty lists, boundary values, failed requests, race-y async (stale closures, unawaited promises, double-fires)
- **API-contract misuse** — calling conventions, param shapes, response-shape assumptions
- **Coverage symmetry** — if one variant got the change, did its siblings? (The invoking conductor may inject project axes: locales, brands, entity types, party types.)
- **Regression blast radius** — untouched callers of changed shared code; changed props/types rippling into other features
- **Test adequacy** — would the diff's tests actually fail if the new logic broke?
- **Security-sensitive deltas** — new inputs reaching queries/HTML/shell, auth checks removed or weakened

Finders (or your passes) must output structured findings: `file, line, summary, severity, concrete failure scenario`. A finding without a concrete failure scenario ("inputs/state → wrong outcome") is not a finding yet.

## Step 4 — Adversarially verify EVERY finding

Before a finding reaches the report, attack it with distinct lenses (parallel subagent refuters in thorough mode — see Orchestration; your own explicit second pass in routine mode):

- **Trace the data flow end-to-end.** If the field is `undefined` for the suspect case and the JSX/logic guards it (`{field && (...)}`), the failure never manifests — kill the finding. Only flag when there is no guard AND the bad value flows through.
- **Construct the exact failing input.** If you cannot name concrete inputs/state that trigger the failure, downgrade to PLAUSIBLE or kill it.

Findings that survive get `CONFIRMED`; plausible-but-unproven ones appear only in thorough mode, labeled `PLAUSIBLE`, after the confirmed list.

## Reviewer calibration (apply to every finding, every mode)

- **Separate actually-broken from could-be-better.** Real defects lead; stylistic/architectural notes go last, explicitly marked non-blocking.
- **Match architectural rigor to actual complexity** — don't SOLID-audit a flat read-only view.
- **Do not flag missing `useMemo`/`useCallback` on cheap computations.** The standing convention is NOT to memoize by default; memoization findings are valid only for genuinely expensive computation, `React.memo`-child props, or dep-array-driven loops.
- **Don't flag premature-optimization "fixes"** — be honest about whether a change provides real benefit or just adds complexity.

## Step 5 — Report

Plain markdown, most severe first:

```
## Confirmed findings
1. **[severity] file:line — one-sentence claim**
   Failure: <concrete inputs/state → wrong outcome>
   Fix: <suggested change>

## Plausible (thorough mode only, unverified)
...

## Non-blocking notes
...
```

No findings surviving verification is a valid result — say so plainly rather than padding with nitpicks. Post findings as PR comments (via `gh`) only when explicitly asked.

## Apply-fixes mode (opt-in only)

When the user explicitly asks to apply the findings:

- Fix smallest-first, one logical unit per edit.
- Run the project's fast lint gate on touched files after each fix.
- Never apply simplification/cleanup findings here — hand those to `polish-code`.
- Re-report each finding's outcome: fixed / skipped (with reason).
