# Implement Change Skill

Implement a change based on a detailed plan from the change-planner agent.

## Usage

```
/implement-change <phase>.<change>
```

Examples:
- `/implement-change 1.1.1` - Implement Phase 1.1, Change 1
- `/implement-change 2.3.5` - Implement Phase 2.3, Change 5

## Behavior

1. Read the change plan from `kotlin/phases/changes/phase-X.Y-change-N.md`
2. Verify dependencies are met
3. Create new files as specified
4. Modify existing files as specified
5. Implement all unit tests
6. Verify code compiles and tests pass
7. Report summary of changes

## Prerequisites

The change plan must exist. Run `/plan-change X.Y.N` first if needed.

## Output

- Production code files (created/modified)
- Test files
- Summary of what was done
- Any deviations from plan with justification

## Quality Gates

The agent will verify:
- Code compiles without warnings
- All new tests pass
- Existing tests still pass
- Acceptance criteria from plan are met
