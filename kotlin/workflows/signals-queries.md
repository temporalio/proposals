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

For workflows that need to handle signals, queries, or updates dynamically (without annotations), use the registration APIs.

### KEncodedValues

All dynamic handlers receive arguments as `KEncodedValues`, a Kotlin-idiomatic wrapper around the Java SDK's `EncodedValues`:

```kotlin
class KEncodedValues(private val delegate: EncodedValues) {
    val size: Int
    fun isEmpty(): Boolean

    // Primary API - reified generics
    inline fun <reified T> get(index: Int = 0): T
    inline fun <reified T> get(index: Int, genericType: Type): T

    // KClass-based access
    fun <T : Any> get(index: Int, type: KClass<T>): T

    // Destructuring support
    inline operator fun <reified T> component1(): T
    inline operator fun <reified T> component2(): T
    inline operator fun <reified T> component3(): T

    // Java interop
    fun toEncodedValues(): EncodedValues
}
```

### Dynamic Handler Examples

```kotlin
class DynamicWorkflowImpl : DynamicWorkflow {
    private var state = mutableMapOf<String, Any>()

    override suspend fun execute(input: String): String {
        // Register a named update handler with validator
        KWorkflow.registerUpdateHandler(
            "updateState",
            validator = { args: KEncodedValues ->
                val key: String = args.get(0)
                require(key.isNotBlank()) { "Key cannot be blank" }
            },
            handler = { args: KEncodedValues ->
                val key: String = args.get(0)
                val value: Any = args.get(1)
                state[key] = value
                "Updated $key"
            }
        )

        // Register a named signal handler
        KWorkflow.registerSignalHandler("notify") { args: KEncodedValues ->
            val message: String = args.get()  // index defaults to 0
            println("Received: $message")
        }

        // Register a named query handler
        KWorkflow.registerQueryHandler("getState") { args: KEncodedValues ->
            val key: String = args.get()
            state[key]
        }

        // Register dynamic handlers for unknown names (catch-all)
        KWorkflow.registerDynamicUpdateHandler { updateName, args ->
            "Handled unknown update: $updateName"
        }

        KWorkflow.registerDynamicSignalHandler { signalName, args ->
            println("Unknown signal: $signalName")
        }

        // Dynamic query handler - 2 parameters (name and args)
        KWorkflow.registerDynamicQueryHandler { queryName, args ->
            "Unknown query: $queryName"
        }

        // Validate all unknown updates
        KWorkflow.registerDynamicUpdateValidator { updateName, args ->
            require(updateName.startsWith("custom_")) { "Unknown update: $updateName" }
        }

        // Wait for completion signal
        KWorkflow.awaitCondition { state["done"] == true }
        return "Completed"
    }
}
```

### Using Destructuring

```kotlin
KWorkflow.registerDynamicUpdateHandler { updateName, args ->
    // Destructuring for multiple arguments
    val (name: String, value: Int) = args
    update(name, value)
    "Updated"
}
```

### Dynamic Handler API Reference

```kotlin
// Named handlers with KEncodedValues
fun registerSignalHandler(signalName: String, handler: suspend (KEncodedValues) -> Unit)
fun registerQueryHandler(queryName: String, handler: (KEncodedValues) -> Any?)
fun registerUpdateHandler(updateName: String, handler: suspend (KEncodedValues) -> Any?)
fun registerUpdateHandler(
    updateName: String,
    validator: (KEncodedValues) -> Unit,
    handler: suspend (KEncodedValues) -> Any?
)

// Catch-all dynamic handlers
fun registerDynamicSignalHandler(handler: suspend (signalName: String, args: KEncodedValues) -> Unit)
fun registerDynamicQueryHandler(handler: (queryName: String, args: KEncodedValues) -> Any?)
fun registerDynamicUpdateHandler(handler: suspend (updateName: String, args: KEncodedValues) -> Any?)
fun registerDynamicUpdateValidator(validator: (updateName: String, args: KEncodedValues) -> Unit)
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
