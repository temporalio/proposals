# Signals, Queries, and Updates

Signals and updates follow the same suspend/non-suspend pattern as workflow methods. Queries are always synchronous (never suspend) and can be defined as properties.

## Defining Handlers

```kotlin
@WorkflowInterface
interface OrderWorkflow {
    @WorkflowMethod
    suspend fun processOrder(order: Order): OrderResult

    @SignalMethod
    suspend fun cancelOrder(reason: String)

    @UpdateMethod
    suspend fun addItem(item: OrderItem): Boolean

    @UpdateValidatorMethod(updateMethod = "addItem")
    fun validateAddItem(item: OrderItem)

    // Queries - always synchronous, can use property syntax
    @QueryMethod
    val status: OrderStatus

    @QueryMethod
    fun getItemCount(): Int
}
```

## Dynamic Handler Registration

For workflows that need to handle signals, queries, or updates dynamically (without annotations), use the registration APIs:

```kotlin
class DynamicWorkflowImpl : DynamicWorkflow {
    private var state = mutableMapOf<String, Any>()

    override suspend fun execute(input: String): String {
        // Register a named update handler with validator
        KWorkflow.registerUpdateHandler(
            "updateState",
            validator = { args ->
                val key = args.get(0, String::class.java)
                require(key.isNotBlank()) { "Key cannot be blank" }
            },
            handler = { args ->
                val key = args.get(0, String::class.java)
                val value = args.get(1, Any::class.java)
                state[key] = value
                "Updated $key"
            }
        )

        // Register a named signal handler
        KWorkflow.registerSignalHandler("notify") { args ->
            val message = args.get(0, String::class.java)
            println("Received: $message")
        }

        // Register a named query handler
        KWorkflow.registerQueryHandler("getState") { args ->
            val key = args.get(0, String::class.java)
            state[key]
        }

        // Register dynamic handlers for unknown names (catch-all)
        KWorkflow.registerDynamicUpdateHandler { updateName, args ->
            "Handled unknown update: $updateName"
        }

        KWorkflow.registerDynamicSignalHandler { signalName, args ->
            println("Unknown signal: $signalName")
        }

        KWorkflow.registerDynamicQueryHandler { queryName, args, resultClass ->
            "Unknown query: $queryName"
        }

        // Wait for completion signal
        KWorkflow.awaitCondition { state["done"] == true }
        return "Completed"
    }
}
```

## Client-Side Interaction

### Sending Signals

```kotlin
val handle = client.getWorkflowHandle<OrderWorkflow>("order-123")

// Type-safe signal using method reference
handle.signal(OrderWorkflow::cancelOrder, "Customer request")
```

### Querying Workflows

```kotlin
val handle = client.getWorkflowHandle<OrderWorkflow>("order-123")

// Query using property reference
val status = handle.query(OrderWorkflow::status)

// Query using method reference
val count = handle.query(OrderWorkflow::getItemCount)
```

### Executing Updates

```kotlin
val handle = client.getWorkflowHandle<OrderWorkflow>("order-123")

// Execute update and wait for result
val added = handle.executeUpdate(OrderWorkflow::addItem, newItem)

// Or start update async and get handle
val updateHandle = handle.startUpdate(OrderWorkflow::addItem, newItem)
val result = updateHandle.result()
```

## Update Validation

Update validators run synchronously before the update handler. They can reject updates by throwing exceptions:

```kotlin
@UpdateValidatorMethod(updateMethod = "addItem")
fun validateAddItem(item: OrderItem) {
    require(item.quantity > 0) { "Quantity must be positive" }
    require(item.price >= BigDecimal.ZERO) { "Price cannot be negative" }
    require(_status == OrderStatus.PENDING) { "Cannot add items after processing started" }
}

@UpdateMethod
suspend fun addItem(item: OrderItem): Boolean {
    // Validator already passed - safe to proceed
    _items.add(item)
    return true
}
```

## Related

- [Client API](../client/workflow-handle.md) - More on workflow handles
- [Workflow Definition](./definition.md) - Basic workflow patterns

---

**Next:** [Child Workflows](./child-workflows.md)
