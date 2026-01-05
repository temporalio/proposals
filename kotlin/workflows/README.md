# Workflows

This section covers defining and implementing Temporal workflows in Kotlin.

## Overview

Kotlin workflows use coroutines and suspend functions for an idiomatic async experience while maintaining Temporal's determinism guarantees.

## Documents

| Document | Description |
|----------|-------------|
| [Definition](./definition.md) | Workflow interfaces, suspend methods, Java interop patterns |
| [Signals, Queries & Updates](./signals-queries.md) | Communication with running workflows |
| [Child Workflows](./child-workflows.md) | Orchestrating child workflow execution |
| [Timers & Parallel Execution](./timers-parallel.md) | Delays, async patterns, await conditions |
| [Cancellation](./cancellation.md) | Handling cancellation, cleanup with NonCancellable |
| [Continue-As-New](./continue-as-new.md) | Long-running workflow patterns |

## Quick Reference

### Basic Workflow

```kotlin
@WorkflowInterface
interface GreetingWorkflow {
    @WorkflowMethod
    suspend fun getGreeting(name: String): String
}

class GreetingWorkflowImpl : GreetingWorkflow {
    override suspend fun getGreeting(name: String): String {
        return KWorkflow.executeActivity(
            GreetingActivities::composeGreeting,
            KActivityOptions(startToCloseTimeout = 10.seconds),
            "Hello", name
        )
    }
}
```

### Key Patterns

| Pattern | Kotlin SDK |
|---------|------------|
| Execute activity | `KWorkflow.executeActivity(Interface::method, options, args)` |
| Execute child workflow | `KWorkflow.executeChildWorkflow(Interface::method, options, args)` |
| Timer/delay | `delay(duration)` - standard kotlinx.coroutines |
| Wait for condition | `KWorkflow.awaitCondition { condition }` |
| Parallel execution | `coroutineScope { async { ... } }.awaitAll()` |
| Cancellation cleanup | `withContext(NonCancellable) { ... }` |

## Complete Example

This example demonstrates a full order processing workflow with activities, cancellation handling, updates, and queries.

```kotlin
// === Domain Types ===

@Serializable
data class Order(
    val id: String,
    val customerId: String,
    val items: List<OrderItem>,
    val priority: Priority = Priority.NORMAL
) {
    val total: BigDecimal get() = items.sumOf { it.price * it.quantity.toBigDecimal() }
}

@Serializable
data class OrderItem(
    val productId: String,
    val quantity: Int,
    val price: BigDecimal
)

@Serializable
data class OrderResult(val success: Boolean, val trackingNumber: String?)

enum class OrderStatus { PENDING, PROCESSING, SHIPPED, CANCELED }
enum class Priority { LOW, NORMAL, HIGH }

// === Workflow Interface ===

@WorkflowInterface
interface OrderWorkflow {
    @WorkflowMethod
    suspend fun processOrder(order: Order): OrderResult

    @UpdateMethod
    suspend fun addItem(item: OrderItem): Boolean

    @UpdateValidatorMethod(updateMethod = "addItem")
    fun validateAddItem(item: OrderItem)

    @QueryMethod
    val status: OrderStatus

    @QueryMethod
    val progress: Int
}

// === Activity Interface ===

@ActivityInterface
interface OrderActivities {
    @ActivityMethod
    suspend fun validateOrder(order: Order): Boolean

    @ActivityMethod
    suspend fun reserveInventory(item: OrderItem): Boolean

    @ActivityMethod
    suspend fun releaseInventory(item: OrderItem): Boolean

    @ActivityMethod
    suspend fun chargePayment(order: Order): Boolean

    @ActivityMethod
    suspend fun refundPayment(order: Order): Boolean

    @ActivityMethod
    suspend fun shipOrder(order: Order): String

    @ActivityMethod
    suspend fun notifyCustomer(customerId: String, message: String)
}

// === Workflow Implementation ===

class OrderWorkflowImpl : OrderWorkflow {
    private var _status = OrderStatus.PENDING
    private var _progress = 0
    private var _order: Order? = null
    private var paymentCharged = false
    private var reservedItems = mutableListOf<OrderItem>()

    override val status get() = _status
    override val progress get() = _progress

    // Reusable options for common cases
    private val defaultOptions = KActivityOptions(
        startToCloseTimeout = 30.seconds,
        retryOptions = KRetryOptions(
            initialInterval = 1.seconds,
            maximumAttempts = 3
        )
    )

    override suspend fun processOrder(order: Order): OrderResult {
        _order = order
        _status = OrderStatus.PROCESSING

        return try {
            doProcessOrder(order)
        } catch (e: CancellationException) {
            // Workflow was cancelled - run cleanup in detached scope
            withContext(NonCancellable) {
                cleanup(order)
            }
            _status = OrderStatus.CANCELED
            throw e
        }
    }

    private suspend fun doProcessOrder(order: Order): OrderResult = coroutineScope {
        // Validate order
        _progress = 10
        val isValid = KWorkflow.executeActivity(
            OrderActivities::validateOrder,
            KActivityOptions(startToCloseTimeout = 10.seconds),
            order
        )
        if (!isValid) {
            return@coroutineScope OrderResult(success = false, trackingNumber = null)
        }

        // Reserve inventory for all items in parallel
        _progress = 30
        order.items.map { item ->
            async {
                val reserved = KWorkflow.executeActivity(
                    OrderActivities::reserveInventory,
                    defaultOptions,
                    item
                )
                if (reserved) {
                    reservedItems.add(item)
                }
                reserved
            }
        }.awaitAll()

        _progress = 60

        // Charge payment with timeout
        val charged = withTimeout(2.minutes) {
            KWorkflow.executeActivity(
                OrderActivities::chargePayment,
                KActivityOptions(
                    startToCloseTimeout = 2.minutes,
                    retryOptions = KRetryOptions(maximumAttempts = 5)
                ),
                order
            )
        }
        if (!charged) {
            return@coroutineScope OrderResult(success = false, trackingNumber = null)
        }
        paymentCharged = true

        _progress = 80

        // Ship order
        val trackingNumber = KWorkflow.executeActivity(
            OrderActivities::shipOrder,
            defaultOptions,
            order
        )

        _status = OrderStatus.SHIPPED
        _progress = 100

        OrderResult(success = true, trackingNumber = trackingNumber)
    }

    private suspend fun cleanup(order: Order) {
        // Release any reserved inventory
        for (item in reservedItems) {
            try {
                KWorkflow.executeActivity(
                    OrderActivities::releaseInventory,
                    defaultOptions,
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
                    defaultOptions,
                    order
                )
            } catch (e: Exception) {
                // Log but continue cleanup
            }
        }

        // Notify customer of cancellation
        try {
            KWorkflow.executeActivity(
                OrderActivities::notifyCustomer,
                defaultOptions,
                order.customerId, "Your order has been cancelled"
            )
        } catch (e: Exception) {
            // Best effort notification
        }
    }

    override fun validateAddItem(item: OrderItem) {
        require(item.quantity > 0) { "Quantity must be positive" }
        require(item.price >= BigDecimal.ZERO) { "Price cannot be negative" }
        require(_status == OrderStatus.PENDING) { "Cannot add items after processing started" }
    }

    override suspend fun addItem(item: OrderItem): Boolean {
        return true
    }
}
```

## Related

- [Activities](../activities/README.md) - What workflows orchestrate
- [Client](../client/README.md) - Starting and interacting with workflows

---

**Next:** [Workflow Definition](./definition.md)
