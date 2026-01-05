# Activity Implementation

There are two approaches for activity implementation, depending on whether you need Java interoperability.

## Option A: Pure Kotlin (Recommended)

For pure Kotlin codebases, define interfaces with `suspend` methods directly:

```kotlin
@ActivityInterface
interface GreetingActivities {
    @ActivityMethod
    suspend fun composeGreeting(greeting: String, name: String): String

    @ActivityMethod
    suspend fun sendEmail(email: Email): SendResult
}

class GreetingActivitiesImpl(
    private val emailService: EmailService
) : GreetingActivities {

    override suspend fun composeGreeting(greeting: String, name: String): String {
        // Full coroutine support - use withContext, async I/O, etc.
        return withContext(Dispatchers.IO) {
            "$greeting, $name!"
        }
    }

    override suspend fun sendEmail(email: Email): SendResult {
        // Suspend functions for async I/O
        return emailService.send(email)
    }
}

// In workflow - direct method reference, no stub needed
val greeting = KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,
    KActivityOptions(startToCloseTimeout = 30.seconds),
    "Hello", "World"
)
```

## Option B: Java Interoperability (Parallel Interface Pattern)

When you need to share activity interfaces with Java code (e.g., activities implemented in Java, or interfaces defined in a shared Java module), use the parallel interface pattern:

```kotlin
// Interface for workflow calls - non-suspend for Java compatibility
// This interface can be defined in Java or Kotlin
@ActivityInterface
interface OrderActivities {
    @ActivityMethod
    fun validateOrder(order: Order): Boolean

    @ActivityMethod
    fun chargePayment(order: Order): PaymentResult
}

// Parallel suspend interface for Kotlin implementation
// Linked to the original interface via annotation
@KActivityImpl(activities = OrderActivities::class)
interface OrderActivitiesSuspend {
    suspend fun validateOrder(order: Order): Boolean
    suspend fun chargePayment(order: Order): PaymentResult
}

// Kotlin implementation uses the suspend interface
class OrderActivitiesImpl(
    private val paymentService: PaymentService
) : OrderActivitiesSuspend {

    override suspend fun validateOrder(order: Order): Boolean {
        return order.items.isNotEmpty() && order.total > 0
    }

    override suspend fun chargePayment(order: Order): PaymentResult {
        // Full suspend support for async operations
        return paymentService.charge(order)
    }
}

// In workflow - use the non-suspend interface for method references
val isValid = KWorkflow.executeActivity(
    OrderActivities::validateOrder,
    KActivityOptions(startToCloseTimeout = 10.seconds),
    order
)
```

## When to Use Which

| Scenario | Approach |
|----------|----------|
| Pure Kotlin codebase | Option A - suspend interfaces |
| Calling Java-defined activities | Option A works (executeActivity handles it) |
| Kotlin activities with Java-defined interface | Option B - parallel interface |
| Shared interface library with Java | Option B - parallel interface |

## Registering Activities

```kotlin
// Option A: Register suspend implementation directly
worker.registerActivitiesImplementations(GreetingActivitiesImpl(emailService))

// Option B: Register implementation - binding inferred from @KActivityImpl annotation
worker.registerActivitiesImplementations(OrderActivitiesImpl(paymentService))
```

## Heartbeating

For long-running activities, use heartbeating to report progress and detect cancellation:

```kotlin
class LongRunningActivitiesImpl : LongRunningActivities {
    override suspend fun processLargeFile(filePath: String): ProcessResult {
        val context = KActivity.getContext()
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
    val context = KActivity.getContext()

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
