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

## KActivity API

`KActivity.context` returns a `KActivityContext`, matching Java SDK's `Activity.getExecutionContext()` pattern:

```kotlin
// In activity implementation

// Get activity context (matches Java's Activity.getExecutionContext())
val context = KActivity.context

// Get activity info
val info = context.info
println("Activity ${info.activityType}, attempt ${info.attempt}")

// Heartbeat for long-running activities
context.heartbeat(progressDetails)

// Get heartbeat details from previous attempt (for retry scenarios)
val previousProgress: Int? = context.getHeartbeatDetails()

// Logging - use activity logger for proper log context
val log = context.logger()  // Uses activity type as logger name
log.info("Processing item")

// Or with custom logger name
val customLog = context.logger("custom.logger")

// Mark activity for async completion
context.doNotCompleteOnReturn()
val taskToken = context.taskToken
```

## KActivityContext Interface

```kotlin
interface KActivityContext {
    val info: KActivityInfo
    fun heartbeat(details: Any? = null)
    fun <T> getHeartbeatDetails(detailsClass: Class<T>): T?
    val taskToken: ByteArray
    fun doNotCompleteOnReturn()
    val isDoNotCompleteOnReturn: Boolean
    fun logger(): Logger
    fun logger(name: String): Logger
    fun logger(clazz: Class<*>): Logger
}

// Reified extension for easier Kotlin usage
inline fun <reified T> KActivityContext.getHeartbeatDetails(): T?
```

## KActivityInfo Interface

```kotlin
interface KActivityInfo {
    val activityId: String
    val activityType: String
    val workflowId: String
    val attempt: Int
    // ... other properties
}
```

> **Note:** `ActivityCompletionClient` for async activity completion uses the same API as the Java SDK.

## Related

- [Activity Definition](./definition.md) - Interface patterns
- [Activity Implementation](./implementation.md) - Full implementation details

---

**Next:** [Client](../client/README.md)
