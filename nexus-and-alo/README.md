# Nexus & ALOs

## What is being proposed? (TL;DR;)

1. New platform agnostic standard - **Arbitrary Length Operations** (ALO). An ALO describes a request/response style interaction which runs for an arbitrary length period of time. Due to the inherent unpredictability of an ALO, special considerations must be taken when handling them. We are proposing standardization of the ALO concept which would enable Workflow-esque calling semantics even outside of Temporal.

1. **Nexus** a standardized primitive supported by Temporal which enables users to define their Temporal APIs as they see fit without being limited to the implementation specifics of Workflows and Activities. A Nexus acts as a protocol independent routing layer. Users can map incoming payloads to Workflows, Activities and their methods.

## Resources

[Problem statements](./problem-statements.md)

[Usage scenarios](./usage-scenarios.md)

[All milestones](./milestones.md)

## Proposal

It's highly recommended to read the ALO strawman before reading the Nexus strawman!

1. [ALO strawman](./alo-strawman.md)

1. [Nexus strawman](./nexus-strawman.md)


## What is the current milestone?

### The current milestone phase is - MVP 0 (Namespace to Namespace)

**Rationale:** Keeps requirements as minimal as possible and makes the primary focus unblocking X-Namespace calls.

**Requirements:**

* Existing Temporal users
* Only target scenarios where Temporal Namespace is calling to another Temporal Namespace
* Minimum additional authentication and authorization requirements
* Relatively latency insensitive use cases
* Works in single and cross cluster scenarios

## What is the rough working timeline?

- **August 20 - September 16**: high level proposal on product requirements and experience
- **September 19 - October 14**: technical design
- **October 17 - October 21st**: planning
- **October 24 - December 15th**: mvp implementation