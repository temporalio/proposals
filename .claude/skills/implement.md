# Implement Skill

Fully implement a change from a phase plan, orchestrating planning and implementation.

## Usage

```
/implement <phase>.<change>
```

Examples:
- `/implement 1.1.1` - Implement Phase 1.1, Change 1
- `/implement 2.3.5` - Implement Phase 2.3, Change 5

## Behavior

This skill orchestrates the full implementation workflow:

1. **Validate** - Check dependencies are met
2. **Plan** - Generate detailed implementation plan (change-planner)
3. **Review** - Verify plan is feasible and complete
4. **Implement** - Write code and tests (change-implementer)
5. **Verify** - Ensure compilation and tests pass
6. **Retry** - Replan or fix if issues encountered

## Automatic Recovery

The orchestrator handles failures automatically:

| Issue | Action |
|-------|--------|
| Plan incomplete | Replan with feedback (up to 2x) |
| Compilation error | Fix and retry (up to 3x) |
| Test failure | Diagnose and fix or replan |
| Blocking issue | Stop and report |

## Output

- Completed implementation with passing tests
- Change plan document at `kotlin/phases/changes/phase-X.Y-change-N.md`
- Summary of files created/modified
- Verification report

## Prerequisites

- Phase plan must exist at `kotlin/phases/phase-X.Y-detailed.md`
- Prior changes in the phase should be complete

## Workflow Visualization

```
/implement 1.1.3
     │
     ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Plan Change │ ──▶ │ Implement   │ ──▶ │ Verify      │
│             │     │             │     │             │
└─────────────┘     └─────────────┘     └─────────────┘
     ▲                    │                    │
     │                    │                    │
     └────── replan ──────┴─────── fix ────────┘
```
