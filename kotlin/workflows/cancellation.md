# Cancellation

Kotlin's built-in coroutine cancellation replaces Java SDK's `CancellationScope`. This provides a more idiomatic experience while maintaining full Temporal semantics.

## How Cancellation Works

When a workflow is cancelled (from the server or programmatically), the Kotlin SDK translates this into coroutine cancellation. Cancellation is **cooperative**—it's checked at suspension points (`delay`, activity execution, child workflow execution, etc.):

```kotlin
override suspend fun processOrder(order: Order): OrderResult = coroutineScope {
    // Cancellation is checked at each suspension point
    val validated = KWorkflow.executeActivity(...)  // ← cancellation checked here
    delay(5.minutes)                                 // ← cancellation checked here
    val result = KWorkflow.executeActivity(...)      // ← cancellation checked here
    result
}
```

## Explicit Cancellation Checks

In rare cases where workflow code doesn't have suspension points (e.g., tight loops), you can check cancellation explicitly using `isActive` or `ensureActive()`. However, CPU-bound work should typically be delegated to activities.

## Parallel Execution and Cancellation

`coroutineScope` provides structured concurrency—if one child fails or the scope is cancelled, all children are automatically cancelled.

**Note:** This is standard Kotlin `coroutineScope` exception propagation behavior, not Temporal-specific:
- When one child fails with an exception, `coroutineScope` cancels all other children
- This is automatic Kotlin structured concurrency behavior

```kotlin
override suspend fun parallelWorkflow(): String = coroutineScope {
    val a = async { KWorkflow.executeActivity(...) }
    val b = async { KWorkflow.executeActivity(...) }

    // If either activity fails, the other is cancelled (standard Kotlin behavior)
    // If workflow is cancelled, both activities are cancelled
    "${a.await()} - ${b.await()}"
}
```

## Detached Scopes (Cleanup Logic)

Use `withContext(NonCancellable)` for cleanup code that must run even when the workflow is cancelled:

```kotlin
override suspend fun processOrder(order: Order): OrderResult {
    try {
        return doProcessOrder(order)
    } catch (e: CancellationException) {
        // Cleanup runs even though workflow is cancelled
        withContext(NonCancellable) {
            KWorkflow.executeActivity(
                OrderActivities::releaseReservation,
                KActivityOptions(startToCloseTimeout = 30.seconds),
                order
            )
        }
        throw e  // Re-throw to propagate cancellation
    }
}
```

This is equivalent to Java's `Workflow.newDetachedCancellationScope()`.

## Cancellation with Timeout

Use `withTimeout` to cancel a block after a duration:

```kotlin
override suspend fun processWithDeadline(order: Order): OrderResult {
    return withTimeout(1.hours) {
        // Everything in this block is cancelled if it takes > 1 hour
        val validated = KWorkflow.executeActivity(...)
        val charged = KWorkflow.executeActivity(...)
        OrderResult(success = true)
    }
}

// Or use withTimeoutOrNull to get null instead of exception
override suspend fun tryProcess(order: Order): OrderResult? {
    return withTimeoutOrNull(30.minutes) {
        KWorkflow.executeActivity(...)
    }
}
```

## Complete Cleanup Example

```kotlin
class OrderWorkflowImpl : OrderWorkflow {
    private var paymentCharged = false
    private var reservedItems = mutableListOf<OrderItem>()

    override suspend fun processOrder(order: Order): OrderResult {
        return try {
            doProcessOrder(order)
        } catch (e: CancellationException) {
            // Workflow was cancelled - run cleanup in detached scope
            withContext(NonCancellable) {
                cleanup(order)
            }
            throw e  // Re-throw to complete workflow as cancelled
        }
    }

    private suspend fun cleanup(order: Order) {
        // Release any reserved inventory
        for (item in reservedItems) {
            try {
                KWorkflow.executeActivity(
                    OrderActivities::releaseInventory,
                    KActivityOptions(startToCloseTimeout = 30.seconds),
                    item
                )
            } catch (e: Exception) {
                // Log but continue cleanup
            }
        }

        // Refund payment if it was charged
        if (paymentCharged) {
            try {
                KWorkflow.executeActivity(
                    OrderActivities::refundPayment,
                    KActivityOptions(startToCloseTimeout = 30.seconds),
                    order
                )
            } catch (e: Exception) {
                // Log but continue cleanup
            }
        }
    }
}
```

## Comparison with Java SDK

| Java SDK | Kotlin SDK |
|----------|------------|
| `Workflow.newCancellationScope(() -> { ... })` | `coroutineScope { ... }` |
| `Workflow.newDetachedCancellationScope(() -> { ... })` | `withContext(NonCancellable) { ... }` |
| `CancellationScope.cancel()` | `job.cancel()` |
| `CancellationScope.isCancelRequested()` | `!isActive` |
| `CancellationScope.throwCanceled()` | `ensureActive()` |
| `scope.run()` with timeout | `withTimeout(duration) { ... }` |

## Related

- [Timers & Parallel](./timers-parallel.md) - Timeout patterns
- [Child Workflows](./child-workflows.md) - Cancellation propagation to children

---

**Next:** [Continue-As-New](./continue-as-new.md)
