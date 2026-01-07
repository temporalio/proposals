# Local Activities

Local activities use the same stub-less pattern as regular activities.

## Local Activity Execution

```kotlin
@ActivityInterface
interface ValidationActivities {
    fun validate(input: String): Boolean
    fun sanitize(input: String): String
}

val isValid = KWorkflow.executeLocalActivity(
    ValidationActivities::validate,
    KLocalActivityOptions(startToCloseTimeout = 5.seconds),
    input
)

val sanitized = KWorkflow.executeLocalActivity(
    ValidationActivities::sanitize,
    KLocalActivityOptions(startToCloseTimeout = 1.seconds),
    input
)
```

## KWorkflow Local Activity Methods

```kotlin
object KWorkflow {
    /**
     * Execute a local activity with type-safe method reference.
     */
    suspend fun <T, A1, R> executeLocalActivity(
        activity: KFunction2<T, A1, R>,
        options: KLocalActivityOptions,
        arg1: A1
    ): R

    suspend fun <T, R> executeLocalActivity(
        activity: KFunction1<T, R>,
        options: KLocalActivityOptions
    ): R

    // ... up to 6 arguments
}
```

## KLocalActivityOptions

```kotlin
/**
 * Kotlin-native local activity options.
 */
data class KLocalActivityOptions(
    val startToCloseTimeout: Duration? = null,
    val scheduleToCloseTimeout: Duration? = null,
    val localRetryThreshold: Duration? = null,
    val retryOptions: KRetryOptions? = null
)
```

## When to Use Local Activities

Local activities are best for:
- Short-lived operations (< 10 seconds)
- Operations that don't need to survive worker restarts
- High-frequency operations where scheduling overhead matters

Use regular activities for:
- Long-running operations
- Operations that need heartbeating
- Operations that must survive worker failures

## Related

- [Activity Definition](./definition.md) - Interface patterns
- [Activity Implementation](./implementation.md) - Full implementation details

---

**Next:** [Client](../client/README.md)
