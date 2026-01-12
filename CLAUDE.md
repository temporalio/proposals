# Claude Instructions for Kotlin SDK Proposals

## Repository Purpose

This repository contains API proposals and design documentation for the Temporal Kotlin SDK.

## Adding Open Questions

When proposing new API features that need discussion before implementation:

1. **Add to the central document**: Add a new section to `kotlin/open-questions.md` with:
   - Clear problem statement
   - Proposed solution with code examples
   - Benefits and trade-offs
   - Status marked as "Decision needed"

2. **Add inline sections**: In the relevant proposal document (e.g., `activities/definition.md`), add an "Open Questions (Decision Needed)" section at the end with:
   - Brief summary of the proposal
   - Link to full discussion: `[Full discussion](../open-questions.md#section-anchor)`

3. **Update the README**: Ensure `kotlin/open-questions.md` is linked in the Reference section of `kotlin/README.md`

### Example Format

In `open-questions.md`:
```markdown
## Feature Name

**Status:** Decision needed

### Problem Statement
[Describe what problem this solves]

### Proposal
[Code examples showing proposed API]

### Benefits
- [List benefits]

### Trade-offs
- [List trade-offs]

### Related Sections
- [Link to relevant proposal docs]
```

In the relevant proposal doc:
```markdown
## Open Questions (Decision Needed)

### Feature Name

**Status:** Decision needed | [Full discussion](../open-questions.md#feature-name)

[Brief summary and code example]
```

## Commit Style

Follow concise commit message style:
- First line: Brief summary of change
- Body: Additional context if needed
