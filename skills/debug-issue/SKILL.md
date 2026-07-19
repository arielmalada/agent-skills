---
name: debug-issue
description: This skill should be used when root-causing a bug, regression, or unexpected behavior — "debug this", "why is this broken", "investigate this bug", "find the root cause", "fix this bug", a bug-type ticket, "regression on a deployed env", "this used to work", "can't reproduce", "users report X but I see Y", "the e2e test started failing", or when the user pastes an error message / stack trace / failing network call without saying "debug". Orchestrates reproduce-first debugging: evidence before hypotheses, hypothesis fan-out with falsification, adversarial root-cause verification, and a minimal root-cause fix with regression coverage (via author-tests). Do NOT use for plain feature implementation with no defect involved (implement-feature), for validating a finished change against its ticket (validate-change), or for test authoring with no defect to root-cause (author-tests).
---

# Debug Issue (root-cause orchestration)

## Overview

Debugging fails in predictable ways: reading code before reproducing (confirmation bias picks the first plausible-looking line), forming hypotheses before gathering evidence (anchoring on a guess), fixing where the symptom appears instead of where the cause lives, and declaring victory on a green test without re-running the original reproduction. This skill sequences the work so each failure mode is structurally blocked:

**reproduce → evidence → hypothesis fan-out (falsification) → adversarial root-cause verification → characterization spec → minimal fix → re-reproduce**

You are the conductor. Keep conclusions in the main context; push page snapshots, long transcripts, and file dumps into subagents. Invoke existing skills by name rather than re-doing their job.

Project facts (env URLs, run commands, seeding traps, tooling traps) live in a local `references/<project>-specifics.md` overlay next to this skill — read it at intake (Phase 0) when one exists for the repo you're in (it also carries tracker-handling tips and the skill-name roster); otherwise derive the equivalents from the project's rules. Runnable Workflow-tool scripts for the fan-out phases live in `references/workflow-templates.md` — Claude Code only; read it only if the user has opted into the Workflow tool AND the tool is present in the session (see Phase 3).

## Phase map

| Phase | Goal | Primary tools |
| ----- | ---- | ------------- |
| 0 Intake | Ticket facts, verified against code | The project's ticket-fetch + feature-context skills (specifics roster) |
| 1 Reproduce | Observe the bug yourself, on the right surface | `playwright-qa` agent, the app's e2e run skill, jest |
| 2 Evidence | Error, network, commit range, flags/permissions | git, Explore agents |
| 3 Hypotheses | Fan out investigators with falsification tests | Agent fan-out (or Workflow, opt-in) |
| 4 Verify cause | Refuters attack the surviving candidate | Agent fan-out |
| 5 Characterize | Failing spec first, without the Jira-key trap | `write-e2e-test`, `unit-test`, `test-layer-review` |
| 6 Fix | Minimal change at the root; regression + re-repro | `author-tests` (or `unit-test`/`write-e2e-test`), `verify`, `commit` |

## Phase 0 — Intake

- Fetch the ticket with the project's inline ticket-fetch skill (named in the specifics roster; typically a ~2s CLI fetch) — never a heavyweight tracker subagent for a routine fetch.
- **Distrust ticket prose; verify claims against code.** Real tickets have named permissions that don't exist, quoted stale UI labels, and assumed router APIs the codebase doesn't have. Grep the actual catalog/translation/code before building on any such claim (concrete lookup paths in the specifics reference).
- When the project ships a feature-context skill for the touched area (specifics roster), invoke it before reading further — it loads the feature's architecture and business rules.
- Branch: ticket key from the default branch; never commit on the default branch. Note the ticket's feature env if one is deployed — it changes where you reproduce.

## Phase 1 — Reproduce FIRST, before reading code

Reading code first means you'll find *a* bug, not necessarily *the* bug. Reproduction gives you the exact error, the network traffic, and the falsifiable baseline every later phase depends on.

Pick the reproduction surface:

| Symptom shape | Reproduce via | Why |
| ------------- | ------------- | --- |
| User-visible flow on a deployed env | `playwright-qa` agent (cost-isolated) driving the env | Page snapshots are huge; keep them out of the main thread |
| Regression in an area with existing e2e coverage | Run the relevant spec via the app's e2e run skill (commands in specifics) | The spec already encodes the expected behavior |
| Pure function / adapter / formatting / date logic | Unit-level repro (jest, next to the source) | Fastest loop; no env dependency |

Pick the environment:

- **Default: the project's default repro env** — the specifics env table also records the user's vocabulary mapping (some teams say **"staging" for the dev env** — never assume tier names).
- **Feature env** when the ticket ships one — the URL pattern and its API-path gotcha are in the specifics reference.
- Exact URLs, run commands, and the login injection block for the `playwright-qa` prompt are in the specifics reference (which points to the canonical browser-QA block).

### "It won't reproduce" IS a finding

Do not stop, and do not fake it. Run the **discriminating fresh-data experiment**: seed a fresh, well-formed instance of the entity via the API helper and drive the reported flow.

| Outcome | Classification | Action |
| ------- | -------------- | ------ |
| Fresh data also breaks | General bug | Proceed to Phase 2 with the repro in hand |
| Fresh data works; bug reported on old records | Legacy-data-gated | Report honestly: classification + the code site that silently mishandles the malformed shape + a manual-test note; optionally add a positive happy-path regression |
| Neither reproduces anywhere | Env/config/user-specific | Diff the environments: user permissions, brand, locale, flags |

**Never mock or hand-craft the malformed state to force a green "bug" test** — that asserts an invented condition, not the bug. This is doctrine from a real case: a "template copy loses the appendix" bug reproduced only for legacy records with null content; the fresh-data experiment classified it in minutes and the honest finding was worth more than a fabricated red test.

## Phase 2 — Evidence before hypotheses

Hypotheses formed without evidence degenerate into whole-codebase reading. Collect, in this order of leverage:

1. **Exact error** — full text, stack, and the request ID if the API client surfaces one. "It errors" is not evidence.
2. **Network traffic** — the failing request/response pair (status, body, headers). A 401 vs a 200-with-wrong-shape point at entirely different layers.
3. **Commit range** — `git log --oneline -- <feature-dir>` since the last-known-good date; `git blame` the suspect lines. A regression with a two-commit window barely needs Phase 3.
4. **Who is affected** — permissions, brand/tenant variant, locale, and user role (the project's axes are in the specifics overlay; brand carve-outs and multi-locale setups are common blind spots). Verify any named permission against the code catalog (specifics reference) — ticket wording is unreliable.
5. **Data shape** — fresh vs legacy records (feeds the Phase 1 experiment).

Fan out 1–3 Explore agents for code-location questions, each with a precise scope and "report paths + key excerpts". Spot-check the load-bearing claims yourself — Explore locates code, it does not judge it.

## Phase 3 — Hypothesis fan-out with falsification

Enumerate 3–6 plausible causes from the evidence. For each, write the **falsification test before dispatching**: what specific evidence, if found, kills this hypothesis? A hypothesis without a falsification test is a hunch — sharpen it or drop it.

Where the harness supports subagents, dispatch one investigator per hypothesis (a read-only exploration agent for pure code-reading questions — Claude Code: `Explore`; a general agent when it must run git/tests). Launch them concurrently (Claude Code: multiple Agent calls in one message). Without subagents, investigate the hypotheses yourself in falsification-test order, cheapest kill first. Each dispatched prompt must contain (subagents inherit nothing from your conversation):

- The bug, the evidence summary, and the ONE hypothesis with its falsification test
- Absolute repo paths; read-only mandate; the project's do-not-touch list from the specifics overlay (e.g. shared auth-state files a subagent must never regenerate or modify)
- Verdict contract: `FALSIFIED` (killing evidence found — cite it), `SURVIVED` (actively hunted the killing evidence, absent, AND the causal chain to the symptom is complete), `INCONCLUSIVE`. Return structured findings, not prose.

A hypothesis that **survives an honest falsification attempt** graduates to root-cause candidate. Two survivors means the falsification tests were too weak — design a discriminating experiment that only one can pass, and iterate.

**Workflow tool note (Claude Code only):** the Workflow tool requires explicit user opt-in AND presence in the session's tool inventory (verify at use time — subagent sessions in particular lack it); direct subagent fan-out is the default and covers the same ground. For audit-scale investigations (4+ hypotheses, multi-stage refutation, resumability matters) with opt-in, see `references/workflow-templates.md` — full gating details there.

## Phase 4 — Adversarially verify the root cause before fixing

A surviving hypothesis is a candidate, not a verdict. Attack it with 3–4 refuter lenses — subagent refuters where the harness supports them, explicit sequential passes yourself otherwise — keeping the lenses **distinct** (identical refuters converge on identical blind spots). Pick 3 of the 4 below for routine bugs — fix-location is mandatory; use all 4 when the fix touches money or permission flows:

- **Symptom coverage** — does this cause explain *every* observed symptom? One unexplained symptom means a second bug or the wrong cause.
- **Timeline** — does the commit that introduced the cause predate the first report? If the code predates the bug, what else changed (data, env, dependency)?
- **Alternative mechanism** — construct a different cause producing the same symptoms; check the code for it.
- **Fix-location check** — if the proposed fix site changed, would ALL symptoms disappear? Trace the data flow forward from the fix site to each symptom.

Half or more of the refuters killing it kills the candidate (ties kill — doubt at that level means the cause isn't verified); go back to Phase 3 with the refuters' evidence added. Only a candidate that survives refutation is worth a fix. This step feels expensive; it is cheaper than shipping a symptom-patch and re-opening the ticket.

## Phase 5 — Characterization spec (failing test first)

When feasible, write the failing spec **before** the fix: it proves the bug is observable, and later proves the fix. Unsure of the layer? Invoke `test-layer-review`. E2E regression → `write-e2e-test` (specs live in the issues folder — path in specifics). Unit-level → `unit-test`.

**The ticket-automation trap (canonical write-up in the `author-tests` skill's specifics overlay).** In projects with tracker↔VCS automation (e.g. a GitHub↔Jira integration), never put the bug ticket's key in the **commit subject, branch name, or PR title** of a spec-only commit. The integration keys purely on the ticket ID (PR opened → In Peer Review, merged → Ready for Testing) — it marches the ticket forward **with no fix shipped**. Reference the ticket only *inside the spec file* (header comment / test title), which does not trigger the workflow. Corollary: "Ready for Testing" on a ticket is not proof a fix deployed — re-confirm the bug is gone before testing-as-fixed. When the spec is for your own ticket and lands in the same PR as the fix, the key in the branch is fine — the transition is then truthful.

## Phase 6 — Fix minimally at the root cause

- **Alignment gate first** (hard user preference): for any non-trivial fix, present a short plan — root cause, fix site, files, trade-offs — and wait for sign-off. Only obvious one-liners skip this.
- **Fix the cause, not the symptom.** Guarding the render site against `undefined` when an adapter upstream produces the `undefined` fixes one symptom and leaves the others; Phase 4's fix-location check already told you where all symptoms converge.
- Keep the fix small; separate commits for spec vs fix vs opportunistic cleanup (and prefer no opportunistic cleanup in a bug PR).
- **Regression coverage:** invoke the `author-tests` skill — it runs the test gate and sequences `write-e2e-test` / `unit-test` / `test-layer-review` for you. If unavailable, invoke those three directly.
- **Re-run the original reproduction** — same env, same steps, same user as Phase 1. A green new test proves the test passes; only the original repro closing proves the bug is fixed.
- For a runtime end-to-end confirmation of the change itself, invoke the `exercise-change` skill (beware name-alike shell commands — some projects ship a MUTATING `verify` script; the read-only gate is in the specifics overlay). For full ticket-level validation before a PR, invoke `validate-change`.
- Per-edit and pre-commit verification commands are auto-loaded project rules; the tooling traps that make them lie (OOM, ambient-type false positives, formatter mismatch) are in the specifics reference.
- **Report honestly**: what reproduced, what didn't, classification, skipped steps named as skipped, failing output included. If validating the fix in a live browser, delegate to `playwright-qa` (via `playwright-qa-validate`) rather than driving the browser in the main thread.

## Subagent prompting rules (all phases)

Subagents do not inherit your conversation, project rules, or memory. Every dispatched prompt must embed: the branch name (if the agent commits), absolute paths, the environment + login injection block (for browser agents), the project's locale trap (for spec-writing agents), an explicit do-not-touch list, and a structured-return contract (schema or "return raw JSON"). A subagent that guesses conventions produces work you must redo.

## References

- `references/<project>-specifics.md` — local, per-project overlay (env URLs, run commands, seeding/auth/locale/tooling traps, skill-name roster); never committed to this repo. **Read at intake (Phase 0)** when one exists for the repo you're in.
- `references/workflow-templates.md` — runnable Workflow scripts (Claude Code only) for hypothesis fan-out and root-cause adversarial verification. **Read only when the user has opted into the Workflow tool and the tool is available in the session.**
