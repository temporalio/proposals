# Activity Implementation

Activity interfaces can have both suspend and non-suspend methods. The worker handles both automatically.

## Defining Activities

```kotlin
@ActivityInterface
interface OrderActivities {
    // Suspend method - uses coroutines
    @ActivityMethod
    suspend fun chargePayment(order: Order): PaymentResult

    // Non-suspend method - runs on thread pool
    @ActivityMethod
    fun validateOrder(order: Order): Boolean
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

For long-running activities, use heartbeating to report progress and detect cancellation:

```kotlin
class LongRunningActivitiesImpl : LongRunningActivities {
    override suspend fun processLargeFile(filePath: String): ProcessResult {
        val context = KActivity.context
        val lines = File(filePath).readLines()

        lines.forEachIndexed { index, line ->
            context.heartbeat(index)

            // Process line...
            processLine(line)
        }

        return ProcessResult(linesProcessed = lines.size)
    }
}
```

## Heartbeat Details Recovery

Retrieve heartbeat details from a previous failed attempt:

```kotlin
override suspend fun resumableProcess(data: List<Item>): ProcessResult {
    val context = KActivity.context

    // Get progress from previous attempt if available
    val startIndex = context.heartbeatDetails<Int>() ?: 0

    for (i in startIndex until data.size) {
        context.heartbeat(i)
        processItem(data[i])
    }

    return ProcessResult(success = true)
}
```

## KActivity API

`KActivity.context` provides access to the activity execution context for both regular and local activities:

```kotlin
// In activity implementation
val context = KActivity.context

// Get activity info (works for both regular and local activities)
val info = context.info
println("Activity ${info.activityType}, attempt ${info.attempt}")
println("Is local: ${info.isLocal}")

// Heartbeat for long-running activities (no-op for local activities)
context.heartbeat(progressDetails)

// Get heartbeat details from previous attempt (empty for local activities)
val previousProgress = context.heartbeatDetails<Int>()

// Logging (works for both)
val log = context.logger()

// Regular activities only - throws UnsupportedOperationException for local activities
context.doNotCompleteOnReturn()
val taskToken = context.taskToken
```

## KActivityContext Interface

```kotlin
interface KActivityContext {
    val info: KActivityInfo
    fun heartbeat(details: Any? = null)  // No-op for local activities
    fun <T> heartbeatDetails(detailsClass: Class<T>): T?  // Empty for local activities
    val taskToken: ByteArray  // Throws for local activities
    fun doNotCompleteOnReturn()  // Throws for local activities
    val isDoNotCompleteOnReturn: Boolean
    fun logger(): Logger
    fun logger(name: String): Logger
    fun logger(clazz: Class<*>): Logger
}

// Reified extension for easier Kotlin usage
inline fun <reified T> KActivityContext.heartbeatDetails(): T?
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

    // Heartbeat state
    val heartbeatDetails: Any?

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
