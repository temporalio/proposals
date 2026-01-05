# Kotlin Idioms

The SDK leverages Kotlin-specific language features for an idiomatic experience. The design principle is to use **standard Kotlin patterns** wherever possible instead of custom APIs.

## Suspend Functions

Workflows and activities use `suspend fun` for natural coroutine integration:

```kotlin
// Workflow interface - suspend methods
@WorkflowInterface
interface OrderWorkflow {
    @WorkflowMethod
    suspend fun processOrder(order: Order): OrderResult

    @SignalMethod
    suspend fun updatePriority(priority: Priority)

    @UpdateMethod
    suspend fun addItem(item: OrderItem): Boolean

    @QueryMethod  // Queries are NOT suspend - they must be synchronous
    val status: OrderStatus
}

// Activity interface - suspend methods
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
    val validationDeferred = async {
        KWorkflow.executeActivity(OrderActivities::validateOrder, options, order)
    }
    val inventoryDeferred = async {
        KWorkflow.executeActivity(OrderActivities::checkInventory, options, order)
    }

    // Wait for all - standard awaitAll
    val (isValid, hasInventory) = awaitAll(validationDeferred, inventoryDeferred)

    if (!isValid || !hasInventory) {
        return@coroutineScope OrderResult(success = false)
    }

    // Sequential execution
    val charged = KWorkflow.executeActivity(OrderActivities::chargePayment, options, order)
    val shipped = KWorkflow.executeActivity(OrderActivities::shipOrder, options, order)

    OrderResult(success = true, trackingNumber = shipped)
}
```

| Kotlin Pattern | Temporal Equivalent |
|----------------|---------------------|
| `coroutineScope { async { } }` | Parallel execution |
| `awaitAll(d1, d2)` | Wait for multiple operations |
| `delay(duration)` | Temporal timer (deterministic) |
| `Deferred<T>` | `Promise<T>.toDeferred()` |
| `CompletableDeferred<T>` | `Workflow.newPromise()` |

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
| `try { } catch (e: CancellationException)` | `CancellationScope` callback |
| `withContext(NonCancellable) { }` | `Workflow.newDetachedCancellationScope()` |
| `coroutineScope { }` | `Workflow.newCancellationScope()` |
| `isActive` / `ensureActive()` | `CancellationScope.isCancelRequested()` |

## Timeouts

Use `withTimeout` for deadline-based cancellation:

```kotlin
override suspend fun processWithDeadline(order: Order): OrderResult {
    return withTimeout(1.hours) {
        // Everything here is cancelled if it takes > 1 hour
        KWorkflow.executeActivity(OrderActivities::validateOrder, options, order)
        KWorkflow.executeActivity(OrderActivities::chargePayment, options, order)
        OrderResult(success = true)
    }
}

// Or use withTimeoutOrNull to get null instead of exception
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

// Activity options with Duration
val options = KActivityOptions(
    startToCloseTimeout = 30.seconds,
    scheduleToCloseTimeout = 5.minutes,
    heartbeatTimeout = 10.seconds
)

// Timers - standard kotlinx.coroutines delay (intercepted for determinism)
delay(1.hours)

// Timeouts
withTimeout(30.minutes) { ... }
```

## Null Safety

Nullable types replace `Optional<T>` throughout the API. The following Java SDK types have Kotlin equivalents with null-safe APIs:

| Java SDK | Kotlin SDK |
|----------|------------|
| `io.temporal.workflow.Workflow` | `KWorkflow` object |
| `io.temporal.workflow.WorkflowInfo` | `KWorkflowInfo` |
| `io.temporal.workflow.Promise<T>` | Standard `Deferred<T>` via `Promise<T>.toDeferred()` |
| `io.temporal.activity.Activity` | `KActivity` object |
| `io.temporal.activity.ActivityExecutionContext` | `KActivityContext` |
| `io.temporal.activity.ActivityInfo` | `KActivityInfo` |
| `io.temporal.client.WorkflowStub` | `KWorkflowHandle<T>` / `KTypedWorkflowHandle<T, R>` |

```kotlin
// KWorkflowInfo - nullable instead of Optional
interface KWorkflowInfo {
    val workflowId: String
    val runId: String
    val parentWorkflowId: String?          // Optional in Java
    val parentRunId: String?               // Optional in Java
    fun getMemo(key: String): String?      // Optional in Java
    fun getSearchAttribute(key: String): Any?
    // ... other properties
}

// Access via KWorkflow object
val info: KWorkflowInfo = KWorkflow.getInfo()
val parentId: String? = info.parentWorkflowId  // null if no parent

// Activity heartbeat details - nullable instead of Optional
val progress: Int? = KActivity.getContext().getHeartbeatDetails()
val startIndex = progress ?: 0  // Kotlin's elvis operator
```

This eliminates `.orElse(null)`, `.isPresent`, and other Optional ceremony.

## Property Syntax for Queries

Queries can be defined as Kotlin properties in the workflow interface:

```kotlin
@WorkflowInterface
interface OrderWorkflow {
    @QueryMethod
    val status: OrderStatus  // Property syntax

    @QueryMethod
    fun getItemCount(): Int  // Method syntax
}

// Client usage via typed handle (using KWorkflowClient)
val handle = client.getWorkflowHandle<OrderWorkflow>("order-123")
val status = handle.query(OrderWorkflow::status)
val count = handle.query(OrderWorkflow::getItemCount)
```

## Related

- [KOptions Classes](./configuration/koptions.md) - Kotlin-native configuration
- [Workflow Definition](./workflows/definition.md) - Using these idioms in workflows
- [Activity Definition](./activities/definition.md) - Using these idioms in activities

---

**Next:** [Configuration](./configuration/)
