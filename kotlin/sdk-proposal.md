# Kotlin SDK Proposal

The Kotlin SDK proposal is split into two documents:

## Design Principle

**Use idiomatic Kotlin language patterns wherever possible instead of custom APIs.**

The Kotlin SDK should feel natural to Kotlin developers by leveraging standard `kotlinx.coroutines` primitives. Custom APIs should only be introduced when Temporal-specific semantics cannot be achieved through standard patterns.

| Pattern | Standard Kotlin | Temporal Integration |
|---------|-----------------|----------------------|
| Parallel execution | `coroutineScope { async { ... } }` | Works via deterministic dispatcher |
| Await multiple | `awaitAll(d1, d2)` | Standard kotlinx.coroutines |
| Sleep/delay | `delay(duration)` | Intercepted via `Delay` interface |
| Deferred results | `Deferred<T>` | Standard + `Promise<T>.toDeferred()` |

## [SDK API](./sdk-api.md)

Public API and developer experience documentation including:

- Design principle: idiomatic Kotlin patterns
- Kotlin idioms (Duration, null safety, standard coroutines)
- Workflow definition with suspend functions
- Activity definition (no stubs - options per call)
- Client API (leverages existing DSL extensions)
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
- Existing DSL extensions (ActivityOptions, WorkflowOptions, etc.)
- New classes (KWorkflow, KotlinCoroutineDispatcher, etc.)
- Unified worker architecture
- Java SDK refactoring for pluggability
- `WorkflowImplementationFactory` interface
- `KotlinCoroutineDispatcher` with `Delay` implementation
- `KotlinReplayWorkflow` implementation
- Decision justifications
- Open questions

## Phases

* **Phase 1** - Coroutine-based workflows, untyped activity execution, pluggable WorkflowImplementationFactory, core Kotlin idioms (Duration, null safety, standard delay/async)
* **Phase 2** - Typed activity execution with method references, signals/queries/updates, child workflows, property queries
* **Phase 3** - Testing framework

> **Note:** Nexus support is a separate project and will be addressed independently.

## Quick Links

- [Kotlin Coroutines Prototype PR #1792](https://github.com/temporalio/sdk-java/pull/1792)
- [Existing temporal-kotlin Module](https://github.com/temporalio/sdk-java/tree/master/temporal-kotlin)
