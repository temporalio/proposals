# Kotlin Idioms

The Kotlin SDK uses **standard Kotlin patterns** wherever possible instead of custom APIs.

| Java SDK | Kotlin SDK |
|----------|------------|
| `void method()` | `suspend fun method()` |
| `Async.function(() -> ...)` | `async { ... }` |
| `Promise.allOf(...).get()` | `awaitAll(d1, d2)` |
| `Workflow.sleep(duration)` | `delay(duration)` |
| `Workflow.newDetachedCancellationScope()` | `withContext(NonCancellable)` |
| `Duration.ofSeconds(30)` | `30.seconds` |
| `Optional<T>` | `T?` |

## Suspend Functions

Workflows and activities use `suspend fun` for natural coroutine integration:

```kotlin
@WorkflowInterface
interface OrderWorkflow {
    @WorkflowMethod
    suspend fun processOrder(order: Order): OrderResult

    @SignalMethod
    suspend fun updatePriority(priority: Priority)

    @UpdateMethod
    suspend fun addItem(item: OrderItem): Boolean

    @QueryMethod  // Queries are NOT suspend - must be synchronous
    val status: OrderStatus
}

@ActivityInterface
interface OrderActivities {
    @ActivityMethod
    suspend fun validateOrder(order: Order): Boolean

    @ActivityMethod
    suspend fun chargePayment(order: Order): PaymentResult
}
```

> **Note:** Query methods are never `suspend` because queries must return immediately without blocking.

## Coroutines and Concurrency

Use standard `kotlinx.coroutines` patterns for parallel execution:

```kotlin
override suspend fun processOrder(order: Order): OrderResult = coroutineScope {
    // Parallel execution using standard async
    val validation = async { KWorkflow.executeActivity(OrderActivities::validateOrder, options, order) }
    val inventory = async { KWorkflow.executeActivity(OrderActivities::checkInventory, options, order) }

    // Wait for all - standard awaitAll
    val (isValid, hasInventory) = awaitAll(validation, inventory)

    if (!isValid || !hasInventory) {
        return@coroutineScope OrderResult(success = false)
    }

    // Sequential execution
    val charged = KWorkflow.executeActivity(OrderActivities::chargePayment, options, order)
    val shipped = KWorkflow.executeActivity(OrderActivities::shipOrder, options, order)

    OrderResult(success = true, trackingNumber = shipped)
}
```

| Kotlin Pattern | Purpose |
|----------------|---------|
| `coroutineScope { }` | Structured concurrency - if one fails, all cancel |
| `async { }` | Start parallel operation, returns `Deferred<T>` |
| `awaitAll(d1, d2)` | Wait for multiple deferreds |
| `delay(duration)` | Temporal timer (deterministic) |

## Cancellation

Use standard Kotlin cancellation patterns:

```kotlin
override suspend fun processOrder(order: Order): OrderResult {
    return try {
        doProcessOrder(order)
    } catch (e: CancellationException) {
        // Workflow was cancelled - run cleanup in non-cancellable context
        withContext(NonCancellable) {
            KWorkflow.executeActivity(OrderActivities::releaseInventory, options, order)
            KWorkflow.executeActivity(OrderActivities::refundPayment, options, order)
        }
        throw e  // Re-throw to propagate cancellation
    }
}
```

| Kotlin Pattern | Java SDK Equivalent |
|----------------|---------------------|
| `catch (e: CancellationException)` | `CancellationScope` failure callback |
| `withContext(NonCancellable) { }` | `Workflow.newDetachedCancellationScope()` |
| `coroutineScope { }` | `Workflow.newCancellationScope()` |
| `isActive` / `ensureActive()` | `CancellationScope.isCancelRequested()` |

## Timeouts

Use `withTimeout` for deadline-based cancellation:

```kotlin
override suspend fun processWithDeadline(order: Order): OrderResult {
    return withTimeout(1.hours) {
        // Everything here cancels if it takes > 1 hour
        KWorkflow.executeActivity(OrderActivities::validateOrder, options, order)
        KWorkflow.executeActivity(OrderActivities::chargePayment, options, order)
        OrderResult(success = true)
    }
}

// Or get null instead of exception
val result = withTimeoutOrNull(30.minutes) {
    KWorkflow.executeActivity(OrderActivities::slowOperation, options, data)
}
```

## Kotlin Duration

Use `kotlin.time.Duration` for readable time expressions:

```kotlin
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.hours

val options = KActivityOptions(
    startToCloseTimeout = 30.seconds,
    scheduleToCloseTimeout = 5.minutes,
    heartbeatTimeout = 10.seconds
)

delay(1.hours)
withTimeout(30.minutes) { ... }
```

## Null Safety

Nullable types replace `Optional<T>`:

```kotlin
// KWorkflowInfo uses nullable instead of Optional
val info = KWorkflow.getInfo()
val parentId: String? = info.parentWorkflowId  // null if no parent

// Activity heartbeat details
val progress: Int? = KActivity.getContext().getHeartbeatDetails()
val startIndex = progress ?: 0  // Elvis operator for default
```

This eliminates `.orElse(null)`, `.isPresent`, and other Optional ceremony.

## Data Classes

Use Kotlin data classes with `@Serializable` for workflow inputs/outputs:

```kotlin
@Serializable
data class Order(
    val id: String,
    val customerId: String,
    val items: List<OrderItem>,
    val priority: Priority = Priority.NORMAL
)

@Serializable
data class OrderResult(
    val success: Boolean,
    val trackingNumber: String? = null,
    val errorMessage: String? = null
)

@Serializable
enum class Priority { LOW, NORMAL, HIGH }
```

Data classes provide:
- Automatic `equals()`, `hashCode()`, `toString()`
- `copy()` for creating modified instances
- Destructuring: `val (id, customerId) = order`

## Related

- [KOptions Classes](./configuration/koptions.md) - Kotlin-native configuration
- [Workflow Definition](./workflows/definition.md) - Using these idioms in workflows
- [Activity Definition](./activities/definition.md) - Using these idioms in activities

---

**Next:** [Configuration](./configuration/README.md)
