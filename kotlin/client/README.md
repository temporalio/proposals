# Client API

This section covers the Kotlin client API for interacting with Temporal workflows.

## Overview

The Kotlin SDK provides `KWorkflowClient` with suspend functions and type-safe workflow APIs for starting and interacting with workflows.

## Documents

| Document | Description |
|----------|-------------|
| [Workflow Client](./workflow-client.md) | KWorkflowClient, starting workflows |
| [Workflow Handles](./workflow-handle.md) | Typed/Untyped handles, signals, queries, results |
| [Advanced Operations](./advanced.md) | SignalWithStart, UpdateWithStart |

## Quick Reference

### Creating a Client

```kotlin
val client = KWorkflowClient.connect(
    KWorkflowClientOptions(
        target = "localhost:7233",
        namespace = "default"
    )
)
```

### Starting Workflows

```kotlin
// Execute and wait for result
val result = client.executeWorkflow(
    GreetingWorkflow::getGreeting,
    KWorkflowOptions(
        workflowId = "greeting-123",
        taskQueue = "greetings"
    ),
    "Temporal"
)

// Start async and get handle
val handle = client.startWorkflow(
    GreetingWorkflow::getGreeting,
    KWorkflowOptions(
        workflowId = "greeting-123",
        taskQueue = "greetings"
    ),
    "Temporal"
)
val result = handle.result()
```

### Interacting with Workflows

```kotlin
val handle = client.workflowHandle<OrderWorkflow>("order-123")

// Signal
handle.signal(OrderWorkflow::updatePriority, Priority.HIGH)

// Query
val status = handle.query(OrderWorkflow::status)

// Update
val result = handle.executeUpdate(OrderWorkflow::addItem, newItem)

// Cancel
handle.cancel()
```

### Key Patterns

| Pattern | API |
|---------|-----|
| Execute workflow | `client.executeWorkflow(Interface::method, options, args)` |
| Start workflow | `client.startWorkflow(Interface::method, options, args)` |
| Get handle by ID | `client.workflowHandle<T>(workflowId)` |
| Signal with start | `client.signalWithStart(...)` |
| Update with start | `client.executeUpdateWithStart(...)` |

## Related

- [Workflow Handles](./workflow-handle.md) - Interacting with running workflows
- [Advanced Operations](./advanced.md) - Atomic operations

---

**Next:** [Workflow Client](./workflow-client.md)
