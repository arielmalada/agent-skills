---
name: unit-test
description: This skill should be used when the user asks to "write tests", "write unit tests", "add tests to this file", "test this function", "test this component", "create a test file", "add test coverage", "improve test coverage", "review test coverage", "how should I test this", asks about "testing strategy", or says "update test", "update tests", "update the test". Applies Equivalence Partitioning methodology to produce focused, maintainable Jest and React Testing Library tests for TypeScript/React codebases.
argument-hint: "[file-path]"
---

# Unit Test

Write unit tests for a file using Equivalence Partitioning methodology.

## Input

`$ARGUMENTS` — path to the source file to test, or a function/component name.

## Workflow

### 1. Read the Source File

- Understand the function/component to test
- Identify all input parameters and their types
- Note any dependencies that need mocking

### 2. Analyze Input Domains (Equivalence Partitioning)

Create partitions for each parameter:

| Partition Type | Examples                              |
| -------------- | ------------------------------------- |
| Valid typical  | Normal expected values                |
| Valid boundary | Min/max values, edge of ranges        |
| Empty/null     | `null`, `undefined`, `''`, `[]`, `{}` |
| Invalid type   | Wrong data type                       |
| Invalid value  | Out of range, malformed               |

Select ONE representative test case per partition.

### 3. Boundary Value Analysis

Always test values at and around boundaries:

| Boundary                   | Test Values                         |
| -------------------------- | ----------------------------------- |
| Array length               | 0, 1, typical, max                  |
| Numeric range (e.g. 1-100) | 0, 1, 50, 100, 101                  |
| String length limits       | empty, 1 char, at limit, over limit |

```typescript
// Example: function clamp(value: number, min: number, max: number): number
describe('clamp', () => {
    it('returns min when value is below range', () => expect(clamp(0, 1, 100)).toBe(1));
    it('returns value at lower boundary', () => expect(clamp(1, 1, 100)).toBe(1));
    it('returns value within range', () => expect(clamp(50, 1, 100)).toBe(50));
    it('returns value at upper boundary', () => expect(clamp(100, 1, 100)).toBe(100));
    it('returns max when value is above range', () => expect(clamp(101, 1, 100)).toBe(100));
});
```

### 4. Write Tests

- ONE test per equivalence partition
- Follow AAA pattern (Arrange, Act, Assert)
- Use semantic queries for React components (prefer `getByRole` > `getByLabelText` > `getByText` > `getByTestId`)

File naming:

- All test files: `.jest.tsx` suffix (project convention)

Place test file next to source file.

```typescript
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

describe('ComponentName', () => {
    it('should render correctly', () => {
        render(<Component {...defaultProps} />);
        expect(screen.getByRole('button', { name: /submit/i })).toBeInTheDocument();
    });

    it('should handle user interaction', async () => {
        const user = userEvent.setup();
        const onSubmit = jest.fn();
        render(<Component onSubmit={onSubmit} />);
        await user.click(screen.getByRole('button', { name: /submit/i }));
        expect(onSubmit).toHaveBeenCalledTimes(1);
    });
});
```

### 5. Mock Guidelines

- Mock external dependencies (API calls, modules), not the function under test
- Use `jest.fn()` for function mocks
- Use `jest.spyOn()` when you need to preserve original implementation
- Reset mocks in `beforeEach` or use `jest.clearAllMocks()`

### 6. Execute with Coverage

```bash
yarn jest $ARGUMENTS --coverage
```

### 7. What NOT to Test

- Implementation details (internal state, private methods)
- Third-party library internals
- Styling/CSS (unless it drives behavior)
- Trivial code (pass-through props, constants, type definitions)
- Snapshot tests (avoid — low signal, break on any change)

Focus on **user-observable behavior** only.