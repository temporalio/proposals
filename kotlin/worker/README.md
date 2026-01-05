# Worker API

This section covers setting up workers to execute Temporal workflows and activities in Kotlin.

## Overview

The Kotlin SDK provides `KWorkerFactory` and `KWorker` which automatically enable coroutine support for Kotlin workflows and suspend activities.

## Documents

| Document | Description |
|----------|-------------|
| [Setup](./setup.md) | KWorkerFactory, KWorker, KotlinPlugin, registration |

## Quick Reference

### Basic Worker Setup

```kotlin
val service = WorkflowServiceStubs.newLocalServiceStubs()
val client = KWorkflowClient(service)

// KWorkerFactory automatically enables Kotlin coroutine support
val factory = KWorkerFactory(client)
val worker = factory.newWorker("task-queue")

// Register workflows and activities
worker.registerWorkflowImplementationTypes(MyWorkflowImpl::class)
worker.registerActivitiesImplementations(MyActivitiesImpl())

// Start the worker
factory.start()
```

### Key Components

| Component | Purpose |
|-----------|---------|
| `KWorkerFactory` | Creates workers with automatic coroutine support |
| `KWorker` | Registers Kotlin workflows and suspend activities |
| `KotlinPlugin` | Plugin for Java main apps (used automatically by KWorkerFactory) |

## Next Steps

- See [Worker Setup](./setup.md) for detailed configuration options
- Learn about [Interceptors](../configuration/interceptors.md) for cross-cutting concerns
