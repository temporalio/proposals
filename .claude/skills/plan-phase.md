# Plan Phase Skill

Break down a phase of the Kotlin SDK implementation into detailed, self-contained changes.

## Usage

```
/plan-phase <phase>
```

Examples:
- `/plan-phase 1.1` - Plan "Java SDK Refactoring"
- `/plan-phase 2.1` - Plan "Typed Activity Stubs"

## Behavior

1. Read the implementation plan from `kotlin/implementation-plan.md`
2. Read context from `kotlin/sdk-api.md` and `kotlin/sdk-implementation.md`
3. For the specified phase, produce a detailed breakdown where each item:
   - Is a self-contained, submittable PR
   - Includes full test coverage
   - Has clear dependencies on prior items
   - Can be reviewed and merged independently

## Output Format

Write the detailed plan to `kotlin/phases/phase-X.Y-detailed.md` with this structure:

```markdown
# Phase X.Y: [Name] - Detailed Plan

## Overview
Brief description of what this phase accomplishes.

## Prerequisites
Any required setup or prior phases.

## Changes

### Change 1: [Title]
**Summary:** One-line description

**Scope:**
- Files to add/modify
- Public API changes (if any)

**Tests:**
- Unit tests required
- Integration tests required

**Dependencies:** None | Change N

---
(repeat for each change)
```

## Guidelines

- **Atomic**: Each change does ONE thing
- **Testable**: Every change includes tests
- **Ordered**: Dependencies flow forward only
- **Compilable**: Code compiles after each change
- **No Design**: Don't go into implementation details - just scope and structure
