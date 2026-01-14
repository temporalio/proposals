# Activity Implementation

Activity interfaces can have both suspend and non-suspend methods. The worker handles both automatically.

## Defining Activities

```kotlin
@ActivityInterface
interface OrderActivities {
    // Suspend method - uses coroutines
    suspend fun chargePayment(order: Order): PaymentResult

    // Non-suspend method - runs on thread pool
    fun validateOrder(order: Order): Boolean
}

// Use @ActivityMethod only when customizing the activity name
@ActivityInterface
interface CustomOrderActivities {
    @ActivityMethod(name = "charge-payment")
    suspend fun chargePayment(order: Order): PaymentResult
}

class OrderActivitiesImpl(
    private val paymentService: PaymentService
) : OrderActivities {

    override suspend fun chargePayment(order: Order): PaymentResult {
        // Full coroutine support - use withContext, async I/O, etc.
        return paymentService.charge(order)
    }

    override fun validateOrder(order: Order): Boolean {
        return order.items.isNotEmpty() && order.total > 0
    }
}
```

## Calling Activities from Workflows

```kotlin
// Kotlin workflows use method references
val isValid = KWorkflow.executeActivity(
    OrderActivities::validateOrder,
    KActivityOptions(startToCloseTimeout = 10.seconds),
    order
)

val payment = KWorkflow.executeActivity(
    OrderActivities::chargePayment,
    KActivityOptions(startToCloseTimeout = 30.seconds),
    order
)
```

## Java Interoperability

Java workflows call Kotlin activities using string-based activity names:

```java
// Java workflow calling Kotlin activity
String result = Workflow.newActivityStub(ActivityOptions.newBuilder()
        .setStartToCloseTimeout(Duration.ofSeconds(30))
        .build())
    .execute("chargePayment", PaymentResult.class, order);
```

This mirrors how Java workflows call Kotlin workflows - using string names for cross-language interop.

## Registering Activities

```kotlin
worker.registerActivitiesImplementations(OrderActivitiesImpl(paymentService))
```

## Heartbeating

For long-running activities, use heartbeating to report progress. **Heartbeat throws `CancellationException`** when the activity is cancelled, ensuring activities don't continue running and consuming worker slots.

```kotlin
class LongRunningActivitiesImpl : LongRunningActivities {
    override suspend fun processLargeFile(filePath: String): ProcessResult {
        val context = KActivity.executionContext
        val lines = File(filePath).readLines()

        lines.forEachIndexed { index, line ->
            // Heartbeat throws CancellationException if activity is cancelled
            context.heartbeat(index)

            // Process line...
            processLine(line)
        }

        return ProcessResult(linesProcessed = lines.size)
    }
}
```

**Rationale:** Throwing on cancellation prevents activities from eating worker slots when developers forget to check cancellation. This aligns with Java SDK behavior and ensures consistent cancellation handling.

## Heartbeat Details Recovery

Retrieve heartbeat details from a previous failed attempt:

```kotlin
override suspend fun resumableProcess(data: List<Item>): ProcessResult {
    val context = KActivity.executionContext

    // Get progress from previous attempt if available
    val startIndex = context.heartbeatDetails<Int>() ?: 0

    for (i in startIndex until data.size) {
        context.heartbeat(i)
        processItem(data[i])
    }

    return ProcessResult(success = true)
}
```

## Activity Cancellation

Activity cancellation is delivered via `heartbeat()` - when an activity is cancelled, the next heartbeat call throws `CancellationException`. This works consistently for both suspend and non-suspend activities.

### Cancellation via Heartbeat

```kotlin
override suspend fun processItems(items: List<Item>): ProcessResult {
    val context = KActivity.executionContext
    for (item in items) {
        // CancellationException thrown here if activity is cancelled
        context.heartbeat()
        processItem(item)
    }
    return ProcessResult(success = true)
}

// With cleanup on cancellation
override suspend fun processWithCleanup(items: List<Item>): ProcessResult {
    val context = KActivity.executionContext
    return try {
        for (item in items) {
            context.heartbeat()
            processItem(item)
        }
        ProcessResult(success = true)
    } catch (e: CancellationException) {
        // Cleanup on cancellation
        cleanup()
        throw e  // Re-throw to complete as cancelled
    }
}
```

### Non-Suspend Activities

Non-suspend activities also receive cancellation via heartbeat:

```kotlin
override fun processItemsBlocking(items: List<Item>): ProcessResult {
    val context = KActivity.executionContext
    for (item in items) {
        // CancellationException thrown here if activity is cancelled
        context.heartbeat()
        processItem(item)
    }
    return ProcessResult(success = true)
}
```

> **TODO:** `KActivity.cancellationFuture()` will be added when cancellation can be delivered without requiring heartbeat calls (e.g., server-push cancellation). This will return a `CompletableFuture<CancellationDetails>` for activities that need cancellation notification without heartbeating.

## KActivity API

`KActivity.executionContext` provides access to the activity execution context for both regular and local activities:

```kotlin
// In activity implementation
val context = KActivity.executionContext

// Get activity info (works for both regular and local activities)
val info = context.info
println("Activity ${info.activityType}, attempt ${info.attempt}")
println("Is local: ${info.isLocal}")

// Heartbeat for long-running activities (no-op for local activities)
// Throws CancellationException if activity is cancelled
context.heartbeat(progressDetails)

// Get heartbeat details from previous attempt (empty for local activities)
val previousProgress = context.heartbeatDetails<Int>()

// Regular activities only - throws UnsupportedOperationException for local activities
context.doNotCompleteOnReturn()
val taskToken = context.taskToken
```

### KActivity Static Methods

```kotlin
object KActivity {
    /** Get the execution context for the current activity */
    val executionContext: KActivityExecutionContext
}
```

## KActivityExecutionContext Interface

```kotlin
interface KActivityExecutionContext {
    val info: KActivityInfo

    /**
     * Send a heartbeat with optional progress details.
     * Throws CancellationException if the activity has been cancelled.
     * No-op for local activities.
     */
    fun heartbeat(details: Any? = null)

    /** Get heartbeat details from previous attempt. Empty for local activities. */
    fun <T> heartbeatDetails(detailsClass: Class<T>): T?

    /** Task token for async completion. Throws for local activities. */
    val taskToken: ByteArray

    /** Mark activity for manual completion. Throws for local activities. */
    fun doNotCompleteOnReturn()

    val isDoNotCompleteOnReturn: Boolean
}

// Reified extension for easier Kotlin usage
inline fun <reified T> KActivityExecutionContext.heartbeatDetails(): T?
```

## KActivityInfo Interface

```kotlin
interface KActivityInfo {
    // Core identifiers
    val activityId: String
    val activityType: String
    val workflowId: String
    val runId: String
    val namespace: String

    // Execution context
    val taskQueue: String
    val attempt: Int
    val isLocal: Boolean

    // Timing information
    val scheduledTime: Instant?
    val startedTime: Instant?
    val scheduleToCloseTimeout: Duration?
    val startToCloseTimeout: Duration?
    val heartbeatTimeout: Duration?

    // Task token for async completion (throws for local activities)
    val taskToken: ByteArray
}
```

> **Note:** `ActivityCompletionClient` for async activity completion uses the same API as the Java SDK. Async completion is not supported for local activities.

## Related

- [Activity Definition](./definition.md) - Interface patterns
- [Worker Setup](../worker/setup.md) - Registering activities

---

**Next:** [Local Activities](./local-activities.md)
