# Plan Change Skill

Create a detailed implementation plan for a single change from a phase plan.

## Usage

```
/plan-change <phase>.<change>
```

Examples:
- `/plan-change 1.1.1` - Plan Phase 1.1, Change 1
- `/plan-change 2.3.5` - Plan Phase 2.3, Change 5

## Behavior

1. Read the phase plan from `kotlin/phases/phase-X.Y-detailed.md`
2. Read SDK proposal docs and relevant source code
3. Validate the change is feasible
4. Design the simplest, most readable implementation
5. Specify complete test coverage
6. Write output to `kotlin/phases/changes/phase-X.Y-change-N.md`

## Output Contents

The implementation plan includes:

- **Feasibility validation** - Confirm change is possible
- **File changes** - Exact files to create/modify with code skeletons
- **Test specifications** - Complete unit test definitions
- **Acceptance criteria** - Checklist for completion
- **Implementation notes** - Gotchas, patterns, references

## Requirements

The output must be **self-contained**. A developer should be able to implement the change using only:
- This document
- The SDK source code

No need to consult proposal documents or other planning materials.
