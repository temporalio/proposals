# Activities

This section covers defining and implementing Temporal activities in Kotlin.

## Overview

Activities are the building blocks for interacting with external systems. The Kotlin SDK provides type-safe activity execution with suspend function support.

## Documents

| Document | Description |
|----------|-------------|
| [Definition](./definition.md) | Activity interfaces, typed and string-based execution |
| [Implementation](./implementation.md) | Implementing activities with suspend functions |
| [Local Activities](./local-activities.md) | Short-lived local activities, KActivity API |

## Quick Reference

### Basic Activity

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
```

### Calling Activities from Workflows

```kotlin
// Type-safe method reference
val greeting = KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,
    KActivityOptions(startToCloseTimeout = 30.seconds),
    "Hello", "World"
)

// String-based (for cross-language interop)
val result = KWorkflow.executeActivity<String>(
    "composeGreeting",
    KActivityOptions(startToCloseTimeout = 30.seconds),
    "Hello", "World"
)
```

### Key Patterns

| Pattern | API |
|---------|-----|
| Execute activity | `KWorkflow.executeActivity(Interface::method, options, args)` |
| Execute by name | `KWorkflow.executeActivity<R>("name", options, args)` |
| Local activity | `KWorkflow.executeLocalActivity(Interface::method, options, args)` |
| Heartbeat | `KActivity.getContext().heartbeat(details)` |

## Related

- [Implementation](./implementation.md) - Suspend activity patterns
- [Local Activities](./local-activities.md) - Short-lived activities

---

**Next:** [Activity Definition](./definition.md)
