- Start Date: 2020-05-29
- RFC PR:
- Issue:

# Summary

The current CLI was designed seemingly for the internal use and the good UX wasn't among the top priorities in the initial implementation.
The UX lacks in the number of areas such as consistency, semantics, commands discoverability, no integration with bash/zsh, few flags are global when they arguably shouldn't be, no default configs file support, UI that could do a better job helping users to "scan" though the `help` output

### Goals

- Improve commands discoverability

# Detailed design

### Improve commands discoverability

Problem: As a user i want to easily find commands i'm interested in. Less nesting leads to easier discovery.

Commands discoverability can be improved by limiting CLI commands to a maximum of 2 levels nesting.

Before 
``` bash
tctl workflow activity complete {flags}
```
After 
``` bash
tctl activity complete {flags}
```


# Adoption strategy

This change was prior to Release v1.0.0

Since it was prior to the release v1, the breaking changes were expected.