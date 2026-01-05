# Workflows

This section covers defining and implementing Temporal workflows in Kotlin.

## Overview

Kotlin workflows use coroutines and suspend functions for an idiomatic async experience while maintaining Temporal's determinism guarantees.

## Documents

| Document | Description |
|----------|-------------|
| [Definition](./definition.md) | Workflow interfaces, suspend methods, Java interop patterns |
| [Signals, Queries & Updates](./signals-queries.md) | Communication with running workflows |
| [Child Workflows](./child-workflows.md) | Orchestrating child workflow execution |
| [Timers & Parallel Execution](./timers-parallel.md) | Delays, async patterns, await conditions |
| [Cancellation](./cancellation.md) | Handling cancellation, cleanup with NonCancellable |
| [Continue-As-New](./continue-as-new.md) | Long-running workflow patterns |

## Quick Reference

### Basic Workflow

```kotlin
@WorkflowInterface
interface GreetingWorkflow {
    @WorkflowMethod
    suspend fun getGreeting(name: String): String
}

class GreetingWorkflowImpl : GreetingWorkflow {
    override suspend fun getGreeting(name: String): String {
        return KWorkflow.executeActivity(
            GreetingActivities::composeGreeting,
            KActivityOptions(startToCloseTimeout = 10.seconds),
            "Hello", name
        )
    }
}
```

### Key Patterns

| Pattern | Kotlin SDK |
|---------|------------|
| Execute activity | `KWorkflow.executeActivity(Interface::method, options, args)` |
| Execute child workflow | `KWorkflow.executeChildWorkflow(Interface::method, options, args)` |
| Timer/delay | `delay(duration)` - standard kotlinx.coroutines |
| Wait for condition | `KWorkflow.awaitCondition { condition }` |
| Parallel execution | `coroutineScope { async { ... } }.awaitAll()` |
| Cancellation cleanup | `withContext(NonCancellable) { ... }` |

## Related

- [Activities](../activities/README.md) - What workflows orchestrate
- [Client](../client/README.md) - Starting and interacting with workflows

---

**Next:** [Workflow Definition](./definition.md)
