# Workflow Handles

For interacting with existing workflows (signals, queries, results, cancellation), use a typed or untyped handle.

## Typed Handles

```kotlin
// Get typed handle for existing workflow by ID
val handle = client.getWorkflowHandle<OrderWorkflow>("order-123")

// Send signal - method reference provides type safety
handle.signal(OrderWorkflow::updatePriority, Priority.HIGH)

// Query - method reference with compile-time type checking
val status = handle.query(OrderWorkflow::status)
val count = handle.query(OrderWorkflow::getItemCount)

// Get result (suspends until workflow completes)
val result = handle.result<OrderResult>()

// Updates - execute and wait for result
val updateResult = handle.executeUpdate(OrderWorkflow::addItem, newItem)

// Or start update async and get handle
val updateHandle = handle.startUpdate(OrderWorkflow::addItem, newItem)
val asyncResult = updateHandle.result()

// Cancel or terminate
handle.cancel()
handle.terminate("No longer needed")

// Workflow metadata
val info = handle.describe()
println("Workflow ID: ${handle.workflowId}, Run ID: ${handle.runId}")
```

## KWorkflowHandle API

```kotlin
// Base handle - returned by getWorkflowHandle<T>(id)
// Result type is unknown, must specify when calling result<R>()
interface KWorkflowHandle<T> {
    val workflowId: String
    val runId: String?

    // Result - requires explicit type since we don't know it
    suspend fun <R> result(): R

    // Signals - type-safe method references
    suspend fun signal(method: KFunction1<T, *>)
    suspend fun <A1> signal(method: KFunction2<T, A1, *>, arg: A1)
    suspend fun <A1, A2> signal(method: KFunction3<T, A1, A2, *>, arg1: A1, arg2: A2)

    // Queries - type-safe method references
    fun <R> query(method: KFunction1<T, R>): R
    fun <R, A1> query(method: KFunction2<T, A1, R>, arg: A1): R

    // Updates - execute and wait for result
    suspend fun <R> executeUpdate(method: KFunction1<T, R>): R
    suspend fun <R, A1> executeUpdate(method: KFunction2<T, A1, R>, arg: A1): R

    // Updates - start and get handle for async result
    suspend fun <R> startUpdate(method: KFunction1<T, R>): KUpdateHandle<R>
    suspend fun <R, A1> startUpdate(method: KFunction2<T, A1, R>, arg: A1): KUpdateHandle<R>

    // Get handle for existing update by ID
    fun <R> getKUpdateHandle(updateId: String): KUpdateHandle<R>

    // Lifecycle
    suspend fun cancel()
    suspend fun terminate(reason: String? = null)
    fun describe(): WorkflowExecutionInfo
}
```

## KTypedWorkflowHandle

Extended handle returned by `startWorkflow()` - result type R is captured from the workflow method reference:

```kotlin
interface KTypedWorkflowHandle<T, R> : KWorkflowHandle<T> {
    // Result type is known from method reference - no type parameter needed
    suspend fun result(): R
}
```

**How result type is captured:**

```kotlin
// startWorkflow captures result type from method reference
suspend fun <T, A1, R> startWorkflow(
    workflow: KFunction2<T, A1, R>,  // R is captured here
    options: WorkflowOptions,
    arg: A1
): KTypedWorkflowHandle<T, R>  // R is preserved in return type

// Usage - result type is inferred
val handle = client.startWorkflow(
    OrderWorkflow::processOrder,  // KFunction2<OrderWorkflow, Order, OrderResult>
    options,
    order
)
val result: OrderResult = handle.result()  // No type parameter needed!

// getWorkflowHandle doesn't know result type
val existingHandle = client.getWorkflowHandle<OrderWorkflow>(workflowId)
val result = existingHandle.result<OrderResult>()  // Must specify type
```

## KUpdateHandle

```kotlin
interface KUpdateHandle<R> {
    val updateId: String
    suspend fun result(): R
}
```

## Untyped Handles

For cases where you don't know the workflow type at compile time:

```kotlin
// Untyped handle - signal/query by string name
val untypedHandle = client.getUntypedWorkflowHandle("order-123")

// Operations use string names instead of method references
untypedHandle.signal("updatePriority", Priority.HIGH)
val status = untypedHandle.query<OrderStatus>("status")
val result = untypedHandle.result<OrderResult>()

// Cancel/terminate work the same
untypedHandle.cancel()
```

```kotlin
interface WorkflowHandle {
    val workflowId: String
    val runId: String?

    suspend fun <R> result(): R
    suspend fun signal(signalName: String, vararg args: Any?)
    fun <R> query(queryName: String, vararg args: Any?): R
    suspend fun executeUpdate(updateName: String, vararg args: Any?): Any?
    suspend fun cancel()
    suspend fun terminate(reason: String? = null)
    fun describe(): WorkflowExecutionInfo
}
```

This pattern matches Python SDK's `WorkflowHandle` with the same method names (`signal`, `query`, `result`, `cancel`, `terminate`, `execute_update`, `start_update`).

## Related

- [Workflow Client](./workflow-client.md) - Creating clients
- [Signals, Queries & Updates](../workflows/signals-queries.md) - Handler definitions

---

**Next:** [Advanced Operations](./advanced.md)
