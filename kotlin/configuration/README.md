# Configuration

This section covers configuration options for the Kotlin SDK.

## Documents

| Document | Description |
|----------|-------------|
| [KOptions](./koptions.md) | Kotlin-native option classes (Activity, Workflow, Retry, etc.) |
| [Data Conversion](./data-conversion.md) | kotlinx.serialization, Jackson configuration |
| [Interceptors](./interceptors.md) | Worker, Workflow, Activity interceptors |

## Overview

The Kotlin SDK provides native Kotlin configuration classes that:
- Accept `kotlin.time.Duration` directly
- Use named parameters with default values
- Follow immutable data class patterns
- Support `copy()` for creating variants

## Quick Reference

### KOptions Classes

```kotlin
// Activity options
KActivityOptions(
    startToCloseTimeout = 30.seconds,
    retryOptions = KRetryOptions(maximumAttempts = 3)
)

// Local activity options
KLocalActivityOptions(
    startToCloseTimeout = 5.seconds,
    localRetryThreshold = 10.seconds
)

// Child workflow options
KChildWorkflowOptions(
    workflowId = "child-123",
    workflowExecutionTimeout = 1.hours
)

// Workflow options (for client)
KWorkflowOptions(
    workflowId = "order-123",
    taskQueue = "orders",
    workflowExecutionTimeout = 24.hours
)
```

### Data Conversion

```kotlin
// kotlinx.serialization (default)
@Serializable
data class Order(val id: String, val items: List<OrderItem>)

// Jackson (for Java interop)
val converter = DefaultDataConverter.newDefaultInstance().withPayloadConverterOverrides(
    JacksonJsonPayloadConverter(KotlinObjectMapperFactory.new())
)
```

## Next Steps

- [KOptions](./koptions.md) - Full options reference
- [Data Conversion](./data-conversion.md) - Serialization configuration
- [Interceptors](./interceptors.md) - Cross-cutting concerns
