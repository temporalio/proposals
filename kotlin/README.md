# Kotlin SDK API Proposal

This document describes the public API and developer experience for the Temporal Kotlin SDK.

## Overview

The Kotlin SDK provides an idiomatic Kotlin experience for building Temporal workflows using coroutines and suspend functions.

**Key Features:**

* Coroutine-based workflows with `suspend fun`
* Full interoperability with Java SDK
* Kotlin Duration support (`30.seconds`)
* DSL builders for configuration
* Null safety (no `Optional<T>`)

**Requirements:**

* Minimum Kotlin version: 1.8.x
* Coroutines library: kotlinx-coroutines-core 1.7.x+

## Design Principle

**Use idiomatic Kotlin language patterns wherever possible instead of custom APIs.**

The Kotlin SDK should feel natural to Kotlin developers by leveraging standard `kotlinx.coroutines` primitives. Custom APIs should only be introduced when Temporal-specific semantics cannot be achieved through standard patterns.

| Pattern | Standard Kotlin | Temporal Integration |
|---------|-----------------|----------------------|
| Parallel execution | `coroutineScope { async { ... } }` | Works via deterministic dispatcher |
| Await multiple | `awaitAll(d1, d2)` | Standard kotlinx.coroutines |
| Sleep/delay | `delay(duration)` | Intercepted via `Delay` interface |
| Deferred results | `Deferred<T>` | Standard + `Promise<T>.toDeferred()` |

This approach provides:
- **Familiar patterns**: Kotlin developers use patterns they already know
- **IDE support**: Full autocomplete and documentation for standard APIs
- **Ecosystem compatibility**: Works with existing coroutine libraries and utilities
- **Smaller API surface**: Less custom code to learn and maintain

## Documentation Structure

### Core Concepts

- **[Kotlin Idioms](./kotlin-idioms.md)** - Duration, null safety, property syntax for queries
- **[Configuration](./configuration/README.md)** - KOptions classes, data conversion, interceptors

### Building Blocks

- **[Workflows](./workflows/README.md)** - Defining and implementing workflows
  - [Definition](./workflows/definition.md) - Interfaces, suspend methods, Java interop
  - [Signals, Queries & Updates](./workflows/signals-queries.md) - Communication patterns
  - [Child Workflows](./workflows/child-workflows.md) - Orchestrating child workflows
  - [Timers & Parallel Execution](./workflows/timers-parallel.md) - Delays, async patterns
  - [Cancellation](./workflows/cancellation.md) - Handling cancellation, cleanup
  - [Continue-As-New](./workflows/continue-as-new.md) - Long-running workflow patterns

- **[Activities](./activities/README.md)** - Defining and implementing activities
  - [Definition](./activities/definition.md) - Interfaces, typed/string-based execution
  - [Implementation](./activities/implementation.md) - Suspend activities, heartbeating
  - [Local Activities](./activities/local-activities.md) - Short-lived local activities

### Infrastructure

- **[Client](./client/README.md)** - Interacting with workflows
  - [Workflow Client](./client/workflow-client.md) - KWorkflowClient, starting workflows
  - [Workflow Handles](./client/workflow-handle.md) - Signals, queries, results
  - [Advanced Operations](./client/advanced.md) - SignalWithStart, UpdateWithStart

- **[Worker](./worker/README.md)** - Running workflows and activities
  - [Setup](./worker/setup.md) - KWorkerFactory, KWorker, registration

### Reference

- **[Testing](./testing.md)** - Unit testing, mocking activities, time skipping
- **[Migration Guide](./migration.md)** - Migrating from Java SDK
- **[API Parity](./api-parity.md)** - Java SDK comparison, gaps, not-needed APIs
- **[Open Questions](./open-questions.md)** - API design decisions pending discussion

## Quick Start

```kotlin
// Define activity interface
@ActivityInterface
interface GreetingActivities {
    @ActivityMethod
    suspend fun composeGreeting(greeting: String, name: String): String
}

// Implement activity
class GreetingActivitiesImpl : GreetingActivities {
    override suspend fun composeGreeting(greeting: String, name: String): String {
        return "$greeting, $name!"
    }
}

// Define workflow interface
@WorkflowInterface
interface GreetingWorkflow {
    @WorkflowMethod
    suspend fun getGreeting(name: String): String
}

// Implement workflow
class GreetingWorkflowImpl : GreetingWorkflow {
    override suspend fun getGreeting(name: String): String {
        return KWorkflow.executeActivity(
            GreetingActivities::composeGreeting,
            KActivityOptions(startToCloseTimeout = 10.seconds),
            "Hello", name
        )
    }
}

// Start worker (recommended: use run() which blocks and propagates fatal errors)
val factory = KWorkerFactory(client)
val worker = factory.newWorker("greetings")
worker.registerWorkflowImplementationTypes(GreetingWorkflowImpl::class)
worker.registerActivitiesImplementations(GreetingActivitiesImpl())
factory.run()  // Blocks until shutdown, propagates fatal errors

// Alternative for advanced use cases:
// factory.start()  // Returns immediately
// ... do other work ...
// factory.shutdown()

// Execute workflow
val result = client.executeWorkflow(
    GreetingWorkflow::getGreeting,
    KWorkflowOptions(workflowId = "greeting-123", taskQueue = "greetings"),
    "Temporal"
)
```

---

**[Start Review →](./kotlin-idioms.md)**
