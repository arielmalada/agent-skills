---
name: polish-code
description: This skill should be used for a post-implementation cleanup pass over changed code — "clean this up", "simplify my change", "polish before PR", "any simplification wins here", after an implementation is functionally complete. Reviews the diff for reuse, simplification, efficiency, and altitude improvements and APPLIES the safe ones, behavior-preserving only. Do NOT use for bug-hunting (adversarial-review), runtime verification (exercise-change), or ticket validation (validate-change); quality cleanup only.
---

# Polish Code

A cleanup pass over the change you just made — applied, not just reported. Strictly behavior-preserving: anything that would change behavior is not a cleanup, it is an `adversarial-review` finding.

## Preconditions

- Scope = the diff vs its true merge base ONLY (resolve the base the same way `adversarial-review` does — PR base ref, else merge-base with the default branch). **Never drive-by refactor untouched code**; if you spot a big win outside the diff, propose it, don't apply it.
- The change's tests/gates must be green before starting — polishing a broken change buries the breakage.

## Dimensions (in priority order)

1. **Reuse** — the diff reimplements something that already exists: a shared helper, a sibling feature's component, an existing hook. When a conductor skill invoked this pass, its project specifics may list the reuse-search locations (shared packages, sibling features); search there before accepting new code as necessary. Replacing a reimplementation with the existing thing is the highest-value polish.
2. **Simplification** — dead branches, needless intermediate state, over-abstraction (an interface with one implementer, a prop that is always the same value), conditionals that flatten, code that a library already in the project does better.
3. **Efficiency** — clear wins only: an O(n²) loop over data that can be large, repeated network calls that batch. **Respect the no-memoize-by-default convention**: adding `useMemo`/`useCallback` to cheap computations is anti-polish and gets removed, not added.
4. **Altitude** — logic sitting at the wrong layer (formatting in the controller, fetching in the view), duplicated literals that should be one constant, comments restating what the code says (delete them), naming that lies about behavior.

## Process

1. Read the full diff; shortlist candidates with a one-line justification each ("reimplements `formatPrice` from shared/utils").
2. Apply **smallest-first, one logical unit per edit** — a reviewer must be able to see each polish as an obviously-safe step.
3. After each unit: run the project's fast lint gate on the touched files, and the affected tests when they exist.
4. Anything risky, taste-based, or behavior-adjacent goes in the report as **proposed, not applied** — with the reason you held back.

## Guardrails

- Behavior-preserving only. If you cannot argue in one sentence why observable behavior is identical, don't apply it.
- Don't chase symmetry for its own sake — match the surrounding code's idiom, comment density, and naming rather than imposing a new style.
- Don't pad. Zero worthwhile polish is a valid outcome; say so instead of inventing churn.

## Report

- **Applied** — each unit with its one-line justification.
- **Proposed but not applied** — with reasons (risky, outside diff, taste).
- **Verification** — the gates/tests run after the last unit, with their result.
