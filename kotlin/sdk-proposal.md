# Kotlin SDK Proposal

The Kotlin SDK proposal is split into two documents:

## [SDK API](./sdk-api.md)

Public API and developer experience documentation including:

- Kotlin idioms (Duration, null safety, coroutines)
- Workflow definition with suspend functions
- Activity definition and stubs
- Client API
- Worker API
- Data conversion
- Interceptors
- Testing
- Migration guide from Java SDK
- Complete examples

## [SDK Implementation](./sdk-implementation.md)

Internal architecture and implementation details including:

- Relationship to Java SDK
- Repository and package strategy
- Existing and new classes
- Unified worker architecture
- Java SDK refactoring for pluggability
- `WorkflowImplementationFactory` interface
- `KotlinCoroutineDispatcher` implementation
- `KotlinReplayWorkflow` implementation
- Decision justifications
- Open questions

## Phases

* **Phase 1** - Coroutine-based workflows, untyped activity stubs, pluggable WorkflowImplementationFactory, core Kotlin idioms (Duration, null safety)
* **Phase 2** - Typed activity stubs with suspend functions, signals/queries/updates, child workflows, property queries
* **Phase 3** - Testing framework

> **Note:** Nexus support is a separate project and will be addressed independently.

## Quick Links

- [Kotlin Coroutines Prototype PR #1792](https://github.com/temporalio/sdk-java/pull/1792)
- [Existing temporal-kotlin Module](https://github.com/temporalio/sdk-java/tree/master/temporal-kotlin)
