---
name: responsive-design
description: This skill should be used when adapting a React + MUI/Emotion component to different viewports — "make this responsive", "full screen on mobile", "show on mobile only", "hide on desktop", "different layout on small screens", "mobile drawer", "responsive dialog", "useMediaQuery", "useIsPhone", "useIsMobile", "responsive sx", "test mobile rendering", "MUI breakpoints", or when reviewing a `.tsx` view that branches on viewport. Picks the right layer (sx vs hook vs prop), the right hook, and the right test surface. Apply whenever a component must look or behave differently across phone / tablet / desktop, even when the user hasn't mentioned "responsive" explicitly.
---

# Responsive Design (React + MUI / Emotion)

## Overview

Responsive UI in a React + MUI codebase splits cleanly into three layers — **`sx` responsive objects**, **viewport hooks**, and **MUI prop forwarding**. Most responsive bugs come from picking the wrong layer (over-using JS hooks for things CSS already does, or asserting on CSS effects in jsdom where they're invisible). This skill makes the decision deterministic and names the canonical test surfaces.

**Project flavor:** the principles are framework-agnostic for React + CSS-in-JS; examples use a placeholder shared module (`@shared/screenSizes`). When working in a real project, swap those imports for that codebase's viewport-hook module — the pattern names and trade-offs carry over. A project's exact module API belongs in a local `references/<project>-specifics.md` overlay next to this skill.

## The Decision Tree (start here)

Match the change to the smallest layer that fits. Going up the table costs more renders, more code, more test surface.

| What changes across viewports                                                              | Use                                              | Example                                                                       |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------ | ----------------------------------------------------------------------------- |
| Layout-only: padding, gap, grid columns, direction, font size, **show/hide**               | `sx` responsive object `{ xs, sm, md }`          | `sx={{ p: { xs: 2, sm: 4 }, display: { xs: 'none', sm: 'block' } }}`          |
| **A MUI prop value** (`fullScreen`, `variant`, `placement`, `direction`, `size`)           | Viewport hook → prop value                       | `<Dialog fullScreen={isPhone} />`                                                |
| **Different markup / control flow** (Drawer vs Dialog, list vs table, conditional subtree) | Viewport hook → branch in JSX                    | `{isMobile ? <MobileList /> : <DesktopTable />}`                              |

**Rule of thumb:** never reach for a JS hook when an `sx` responsive object works. `sx` runs in CSS, costs zero re-renders, survives SSR, and is invisible to jsdom — which means it doesn't pollute the test surface. Use hooks when the React tree itself must differ.

## Pick the Right Hook

When the project provides a wrapper module of viewport hooks (the `@shared/screenSizes` placeholder below), **always go through that module** — it centralizes breakpoint values and is the only path the project's jest mocks understand. Reaching for `useMediaQuery` directly drifts breakpoint definitions and breaks the standard test pattern.

Typical wrapper hook API (adapt names to the local project):

| Hook                  | True when                          | Use for                                                           |
| --------------------- | ---------------------------------- | ----------------------------------------------------------------- |
| `useIsPhone()`           | width < `sm` (default 600)         | Phone-only adaptations (fullscreen dialog, single-column)         |
| `useIsMobile()`       | width < `md` (default 900)         | Phone + tablet adaptations (collapsed sidebar, hamburger menu)    |
| `useIsTablet()`       | only `sm` (600–900)                | Rare; tablet-only carve-out                                       |
| `useIsDesktop()`      | width ≥ `md`                       | Desktop-only enrichments                                          |
| `useIsLargeDesktop()`  | width ≥ `lg`                       | Wide-screen-only enrichments                                      |

When the project doesn't have a wrapper, **build one** (~10 lines over MUI's `useMediaQuery`) rather than scattering `useMediaQuery(theme.breakpoints.down('sm'))` calls. It pays back the first time anyone writes a jest test against responsive logic. A minimal template lives in `references/breakpoints-api.md`.

### "Mobile" in a ticket is ambiguous — resolve it against the design

`useIsPhone ≠ useIsMobile`, and tickets say "mobile" for both. A "make this full-screen on mobile" ticket almost always means `useIsPhone` (phones, <600); "collapse the sidebar on mobile" almost always means `useIsMobile` (phones + tablets, <900). Cross-check the design rather than the wording — if only a phone frame exists in the mock, use `useIsPhone`.

Note the roster deliberately keeps device words (`phone`, `mobile`, `tablet`, `desktop`) in the convenience hooks and breakpoint tokens (`sm`, `md`, `lg`) in the primitives underneath. A convenience hook named after a token — `useIsXs` and friends <!-- retired-name-ok --> — reintroduces the theme vocabulary the wrapper exists to hide, and silently changes meaning across MUI majors (`down('sm')` was `<= sm` in v4, `< sm` in v5).

## Patterns by Intent

### Show/hide based on viewport

Prefer `sx` — stays in CSS:
```tsx
<Button sx={{ display: { xs: 'none', sm: 'inline-flex' } }} />
```

Only fall back to a hook + conditional render when the element is expensive to mount (heavy controller, fires queries on mount). DOM-level hidden is cheaper than React-level absent for the common case.

### Different padding / gap / columns

Always `sx`:
```tsx
<Box sx={{ p: { xs: 2, sm: 4 }, gridTemplateColumns: { xs: '1fr', sm: '1fr 1fr' } }} />
```

### Adapt a MUI component prop

Hook drives the prop, JSX stays single-branch:
```tsx
const isPhone = useIsPhone();
return <Dialog fullScreen={isPhone} maxWidth={isPhone ? false : 'xs'} {...rest} />;
```

Cleanest pattern when the MUI component already exposes the prop needed.

### Mobile takeover via a shared dialog that lacks `fullScreen`

When the shared dialog component does not expose `fullScreen` (e.g. an in-house wrapper around MUI Dialog), prefer an `sx` override at the call site over modifying the shared component for one consumer's need:

```tsx
const isPhone = useIsPhone();
<SharedDialog
    maxWidth={isPhone ? false : 'xs'}
    sx={isPhone ? {
        '& .MuiDialog-paper': {
            m: 0,
            width: '100%',
            maxWidth: '100%',
            height: '100%',
            maxHeight: '100%',
            borderRadius: 0
        }
    } : undefined}
    {/* ... */}
/>
```

**Trap:** without `maxWidth={false}` the outer MUI Dialog wrapper still clips to `xs` before the Paper override takes effect — the dialog looks broken even though the `sx` is correct.

### Genuinely different component on mobile

Rare. Most apparent "swaps" turn out to be prop adaptations or DOM reordering. Before writing `isMobile ? <A /> : <B />`, ask: is this really two components, or one component with different props? When it truly is two: keep the controller single (one data source, one set of handlers), branch in the view layer only, and ship companion Storybook stories.

## Storybook

Components that branch on viewport SHOULD ship companion stories so reviewers can verify both layouts:

```tsx
export const Desktop: Story = { args: { /* ... */ } };

export const Mobile: Story = {
    args: { /* ... */ },
    parameters: { viewport: { defaultViewport: 'mobile1' } }
};
```

When responsive logic is `sx`-only (no JSX branch), the default story renders both — Storybook's viewport addon lets reviewers toggle without separate stories.

## Testing Responsive Logic

jsdom does not compute CSS, so `sx` effects and emotion classes are invisible to standard assertions. The right pattern depends on **where the branch lives**.

### Pattern 1 — Frozen viewport (most common)

Use when the responsive logic is pure layout (`sx` show/hide, padding, gap). Test the default viewport only:
```ts
jest.mock('@shared/screenSizes', () => ({
    useIsPhone: () => false
}));
```

### Pattern 2 — Toggle the mock per test

Use when the JSX tree itself branches on viewport (drawer vs dialog, list vs table). Both branches need coverage:
```ts
jest.mock('@shared/screenSizes', () => ({
    useIsPhone: jest.fn(() => false)
}));
const screenSizes = jest.requireMock('@shared/screenSizes') as { useIsPhone: jest.Mock };

beforeEach(() => { screenSizes.useIsPhone.mockReturnValue(false); });

it('renders the mobile drawer on xs', () => {
    screenSizes.useIsPhone.mockReturnValue(true);
    /* render + assert on tree differences */
});
```

The `beforeEach` reset is mandatory — without it, mock state leaks between tests.

### Pattern 3 — Passthrough spy on a shared component

Use when the responsive logic produces different **props** for a shared MUI-based component, and the CSS outcome is unobservable in jsdom. Spy on the props your component forwarded — that's the right unit boundary (the shared component owns "does this `sx` actually render full-screen?"; your component owns "did I send the right `sx`?"):

```ts
jest.mock('@shared/ConfirmDialog/ConfirmDialog.view', () => {
    const actual = jest.requireActual(
        '@shared/ConfirmDialog/ConfirmDialog.view'
    );
    return { __esModule: true, ...actual, ConfirmDialog: jest.fn(actual.ConfirmDialog) };
});
const ncdMock = jest.requireMock('@shared/ConfirmDialog/ConfirmDialog.view')
    as { ConfirmDialog: jest.Mock };

it('forwards full-screen sx on xs', () => {
    screenSizes.useIsPhone.mockReturnValue(true);
    render(<MyDialog open />);
    const props = ncdMock.ConfirmDialog.mock.calls.at(-1)![0];
    expect(props.maxWidth).toBe(false);
    expect(props.sx['& .MuiDialog-paper']).toMatchObject({ width: '100%', height: '100%' });
});
```

The `jest.fn(actual.Component)` form is critical: it records props **and still renders the real tree**, so one mock setup serves both behavior tests and contract tests in the same file.

### E2E (Playwright) mobile viewport

```ts
test.describe('Mobile', () => {
    test.use({
        viewport: { width: 390, height: 844 },     // iPhone 13
        storageState: STORAGE_STATE                 // re-attach: viewport override drops auth
    });
});
```

The auth re-attachment is non-obvious — without it the test bounces to the login page. Project-specific helpers and exact paths belong in the local `references/<project>-specifics.md` overlay.

## Anti-Patterns

1. **Calling `useMediaQuery` directly in app code** — bypasses the project's wrapper hook, drifts breakpoint values, breaks the standard jest mock.
2. **Hardcoded `window.innerWidth` checks or `'@media (max-width: 600px)'` strings** — not SSR-safe, ignores the theme, doesn't react to resize.
3. **Mixing `sx` responsive object AND a viewport hook for the same property** — pick one. Mixed gives drift between layout values and JS state.
4. **Asserting on MUI internal classes** (`.MuiDialog-paperFullScreen`, `.Mui-disabled`) — breaks across MUI majors. Use the passthrough spy (Pattern 3) or `aria-disabled` / `data-testid` instead.
5. **Resizing the JSDOM window** to trigger `useMediaQuery` — MUI listens to `matchMedia`, not `resize`. The window-resize trick silently does nothing.
6. **Inventing a component swap** when an `sx` override or `fullScreen={isPhone}` would do.

## Self-Check Before Committing

- [ ] Right layer used (sx > prop > branch — pick smallest that fits)
- [ ] Right hook semantics (`useIsPhone` for phones, `useIsMobile` for phones+tablets)
- [ ] No raw `useMediaQuery` in app code (use the project wrapper)
- [ ] Storybook has Mobile + Desktop stories (or `sx`-only with viewport addon)
- [ ] Tests cover both branches (Pattern 2) OR contract is verified via spy (Pattern 3)
- [ ] No `.MuiXxx-yyy` class assertions in tests

## Additional Resources

### Reference Files

- **`references/breakpoints-api.md`** — MUI breakpoint values, primitive vs convenience hook trade-offs, "build your own wrapper" template, jest mock template.
- **`references/<project>-specifics.md`** — local-only overlay (never committed): the project's exact import paths, hook-module API, shared-dialog example, e2e viewport recipes. Read when one exists for the repo you're in.

### Examples (local-only, when present)

A local `examples/` folder next to this skill may carry project-flavored reference implementations (fullscreen dialog, `sx` show/hide, markup swap, jest patterns) — copy-pasteable for that project, adaptable elsewhere. It is never committed to this repo.
