# MUI Breakpoint Reference & Wrapper Hook Template

Generic reference for any React + MUI project. Project-specific module APIs belong in a local `references/<project>-specifics.md` overlay next to this skill.

## MUI Default Breakpoints

`theme.breakpoints.values` in a default MUI theme:

| Breakpoint | Min width | Typical devices                                 |
| ---------- | --------- | ----------------------------------------------- |
| `xs`       | 0         | Phones portrait                                 |
| `sm`       | 600       | Phones landscape, small tablets                 |
| `md`       | 900       | Tablets, small laptops                          |
| `lg`       | 1200      | Desktops                                        |
| `xl`       | 1536      | Large desktops, ultrawide                       |

Older codebases or projects on MUI v4 may use 960 for `md` — read the actual theme values rather than hardcoding.

## MUI's `useMediaQuery` Primitive

```ts
import useMediaQuery from '@mui/material/useMediaQuery';
import { useTheme } from '@mui/material/styles';

const theme = useTheme();
const isXs = useMediaQuery(theme.breakpoints.down('sm'));   // width < sm (< 600)
const isMd = useMediaQuery(theme.breakpoints.up('md'));     // width >= md (>= 900)
const isOnlySm = useMediaQuery(theme.breakpoints.only('sm'));// only sm (600–900)
```

`useMediaQuery` listens to `matchMedia`, returns `boolean`, and re-renders on viewport change. SSR-safe.

## Why Wrap `useMediaQuery`

Calling `useMediaQuery(theme.breakpoints.down('sm'))` directly across many components produces three problems:

1. **Drift** — different files target slightly different breakpoints over time. `down('sm')` here, `down('md')` there, `'@media (max-width: 600px)'` somewhere else.
2. **Untestable** — there's no single module to `jest.mock` for stubbing viewport state in tests.
3. **Verbose** — `theme + useMediaQuery + breakpoints.down('sm')` is four import lines and three identifiers for "is mobile".

A wrapper module (~10 lines) solves all three.

## Wrapper Hook Template

Drop this into a project that doesn't yet have one (e.g. `src/utils/screenSizes.ts`):

```ts
import useMediaQuery from '@mui/material/useMediaQuery';
import { useTheme, Theme } from '@mui/material/styles';

type Breakpoint = 'xs' | 'sm' | 'md' | 'lg' | 'xl';

export const useScreenSizeUp = (bp: Breakpoint) =>
    useMediaQuery((t: Theme) => t.breakpoints.up(bp));

export const useScreenSizeDown = (bp: Breakpoint) =>
    useMediaQuery((t: Theme) => t.breakpoints.down(bp));

export const useScreenSizeOnly = (bp: Breakpoint) =>
    useMediaQuery((t: Theme) => t.breakpoints.only(bp));

// Convenience hooks — most components should reach for these first
export const useIsXs        = () => useScreenSizeDown('sm');  // phones
export const useIsMobile    = () => useScreenSizeDown('md');  // phones + tablets
export const useIsTablet    = () => useScreenSizeOnly('sm');
export const useIsDesktop   = () => useScreenSizeUp('md');
export const useIsDesktopWide = () => useScreenSizeUp('lg');
```

Notice the function-style `useMediaQuery((t) => ...)` form — it avoids needing a separate `useTheme()` call at each site.

## Choosing Between Convenience Hooks

| Decision criterion                                            | Pick                                |
| ------------------------------------------------------------- | ----------------------------------- |
| Figma mocks show only a phone-sized mobile breakpoint         | `useIsXs`                           |
| Change is destructive (fullscreen takeover, drawer-vs-dialog) | `useIsXs`                           |
| Sidebar collapses on tablets too                              | `useIsMobile`                       |
| Hamburger menu appears for tablets and below                  | `useIsMobile`                       |
| Wide-screen-only enrichment (extra column, supplementary nav) | `useIsDesktopWide`                  |
| Tablet-only carve-out genuinely required                      | `useIsTablet` (rare — verify first) |

### `useIsTablet` is rarely the right answer

Tablet-only logic almost always means "the desktop layout doesn't fit but the phone layout is too cramped". Express it as `useIsMobile() && !useIsXs()` only if the spec genuinely demands a third unique layout — otherwise pick desktop or mobile as the closer match.

## Jest Mock Template (generic)

Top of a test file that exercises responsive logic:

```ts
jest.mock('<your-project>/utils/screenSizes', () => ({
    useIsXs: jest.fn(() => false),
    useIsMobile: jest.fn(() => false),
    useIsTablet: jest.fn(() => false),
    useIsDesktop: jest.fn(() => true),
    useIsDesktopWide: jest.fn(() => false),
    useScreenSizeUp: jest.fn(() => false),
    useScreenSizeDown: jest.fn(() => false),
    useScreenSizeOnly: jest.fn(() => false)
}));

const screenSizes = jest.requireMock('<your-project>/utils/screenSizes') as {
    useIsXs: jest.Mock;
};

beforeEach(() => {
    screenSizes.useIsXs.mockReturnValue(false);
});
```

Include only the hooks the component under test actually imports — over-mocking is harmless but noisy.

## Adding a New Convenience Hook

If a viewport range is used in 3+ places and isn't covered by the existing hooks, add a new convenience hook in `screenSizes.ts` rather than copy-pasting `useScreenSizeUp/Down` calls. Update mock blocks in every importing test file accordingly.

## Anti-Patterns

1. **`useMediaQuery` direct in app code** — breaks the mock pattern and drifts breakpoint values. Always go through the wrapper.
2. **Hardcoded `window.innerWidth` checks** — not SSR-safe, doesn't react to resize.
3. **Hardcoded pixel constants** in `sx` (`'@media (max-width: 600px)'`) — bypasses the theme; if breakpoints change in the theme, your component drifts.
4. **Composing multiple hooks for a simple range** — `useIsMobile() && !useIsXs()` when "tablet" is the intent; use `useIsTablet()` instead.
