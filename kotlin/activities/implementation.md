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
    val startIndex: Int = context.getHeartbeatDetails() ?: 0

    for (i in startIndex until data.size) {
        context.heartbeat(i)
        processItem(data[i])
    }

    return ProcessResult(success = true)
}
```

## Related

- [Activity Definition](./definition.md) - Interface patterns
- [Worker Setup](../worker/setup.md) - Registering activities

---

**Next:** [Local Activities](./local-activities.md)
