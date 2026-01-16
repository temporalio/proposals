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
val client = KClient.connect(KClientOptions(target = "localhost:7233"))

// Create worker with workflows and activities at construction time
val worker = KWorker(
    client,
    KWorkerOptions(
        taskQueue = "task-queue",
        workflows = listOf(MyWorkflowImpl::class),
        activities = listOf(MyActivitiesImpl())
    )
)

// Run the worker (blocks until shutdown or fatal error)
worker.run()
```

### Key Components

| Component | Purpose |
|-----------|---------|
| `KWorker` | Creates and runs workers with automatic coroutine support |
| `KWorkerOptions` | Configuration including workflows and activities |
| `KotlinJavaWorkerPlugin` | Plugin for Java main apps using Kotlin workflows |

## Related

- [Interceptors](../configuration/interceptors.md) - Cross-cutting concerns
- [Workflows](../workflows/README.md) - Defining workflows to register
- [Activities](../activities/README.md) - Defining activities to register

---

**Next:** [Worker Setup](./setup.md)
