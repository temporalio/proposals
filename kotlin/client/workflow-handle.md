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

// Updates - start and get handle (don't wait for completion)
val updateHandle = handle.startUpdate(
    OrderWorkflow::addItem,
    waitForStage = WorkflowUpdateStage.ACCEPTED,
    arg = newItem
)
// ... do other work ...
val result = updateHandle.result()  // Wait for result when needed

// Cancel or terminate
handle.cancel()
handle.terminate("No longer needed")

// Workflow metadata
val description = handle.describe()
println("Workflow ID: ${handle.workflowId}, Run ID: ${handle.runId}")
println("Status: ${description.status}")
```

## Architectural Note: Classes vs Interfaces

All handle types (`KWorkflowHandle`, `KTypedWorkflowHandle`, `KUpdateHandle`, `WorkflowHandle`, `KChildWorkflowHandle`) are **classes** rather than interfaces. This design choice enables:

1. **Reified type parameters** - `inline fun <reified T>` methods directly on handle types
2. **Better IDE discoverability** - Methods appear directly in autocomplete
3. **No extension function workarounds** - No need for separate extension functions for reified generics
4. **Full testing support** - mockk and other frameworks can mock classes

## KWorkflowHandle API

```kotlin
// Base handle - returned by getWorkflowHandle<T>(id)
// Result type is unknown, must specify when calling result<R>()
open class KWorkflowHandle<T>(
    val workflowId: String,
    val runId: String?,
    val execution: WorkflowExecution,
    // ... internal state
) {
    // Result - requires explicit type since we don't know it
    suspend fun <R> result(resultClass: Class<R>): R
    inline suspend fun <reified R> result(): R  // Reified version

    // Signals - type-safe method references
    // Note: Signal handlers can be either suspend or non-suspend functions
    suspend fun signal(method: KFunction1<T, Unit>)
    suspend fun <A1> signal(method: KFunction2<T, A1, Unit>, arg: A1)
    suspend fun <A1, A2> signal(method: KFunction3<T, A1, A2, Unit>, arg1: A1, arg2: A2)

    // Queries - type-safe method references (suspend for network I/O)
    suspend fun <R> query(method: KFunction1<T, R>): R
    suspend fun <R, A1> query(method: KFunction2<T, A1, R>, arg: A1): R

    // Updates - execute and wait for result (suspend functions)
    suspend fun <R> executeUpdate(method: KSuspendFunction1<T, R>): R
    suspend fun <R, A1> executeUpdate(method: KSuspendFunction2<T, A1, R>, arg: A1): R
    suspend fun <R, A1, A2> executeUpdate(method: KSuspendFunction3<T, A1, A2, R>, arg1: A1, arg2: A2): R
    // ... up to 6 arguments

    // Updates - start and return handle without waiting for completion
    suspend fun <R> startUpdate(
        method: KSuspendFunction1<T, R>,
        waitForStage: WorkflowUpdateStage = WorkflowUpdateStage.ACCEPTED,
        updateId: String? = null
    ): KUpdateHandle<R>
    suspend fun <R, A1> startUpdate(
        method: KSuspendFunction2<T, A1, R>,
        waitForStage: WorkflowUpdateStage = WorkflowUpdateStage.ACCEPTED,
        updateId: String? = null,
        arg: A1
    ): KUpdateHandle<R>
    suspend fun <R, A1, A2> startUpdate(
        method: KSuspendFunction3<T, A1, A2, R>,
        waitForStage: WorkflowUpdateStage = WorkflowUpdateStage.ACCEPTED,
        updateId: String? = null,
        arg1: A1,
        arg2: A2
    ): KUpdateHandle<R>
    // ... up to 6 arguments

    // Get handle for existing update by ID
    fun <R> getUpdateHandle(updateId: String, resultClass: Class<R>): KUpdateHandle<R>
    inline fun <reified R> getUpdateHandle(updateId: String): KUpdateHandle<R>  // Reified version

    // Lifecycle
    suspend fun cancel()
    suspend fun terminate(reason: String? = null)
    suspend fun describe(): KWorkflowExecutionDescription

    // Java SDK interop
    fun toStub(): WorkflowStub
}
```

**Note on query methods:** Although queries are synchronous within the workflow, client-side query calls involve network I/O to the Temporal service, which is why they are `suspend` functions following idiomatic Kotlin patterns.

## KTypedWorkflowHandle

Extended handle returned by `startWorkflow()` - result type R is captured from the workflow method reference:

```kotlin
class KTypedWorkflowHandle<T, R>(
    workflowId: String,
    runId: String?,
    execution: WorkflowExecution,
    // ... internal state
) : KWorkflowHandle<T>(...) {
    // Result type is known from method reference - no type parameter needed
    suspend fun result(): R
    suspend fun result(timeout: java.time.Duration): R
}
```

**How result type is captured:**

```kotlin
// startWorkflow captures result type from method reference
suspend fun <T, A1, R> startWorkflow(
    workflow: KSuspendFunction2<T, A1, R>,  // R is captured here
    options: KWorkflowOptions,
    arg: A1
): KTypedWorkflowHandle<T, R>  // R is preserved in return type

// Usage - result type is inferred
val handle = client.startWorkflow(
    OrderWorkflow::processOrder,  // KSuspendFunction2<OrderWorkflow, Order, OrderResult>
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
class KUpdateHandle<R>(
    val updateId: String,
    val execution: WorkflowExecution,
    // ... internal state
) {
    suspend fun result(): R
    suspend fun result(timeout: java.time.Duration): R
}
```

## KWorkflowExecutionDescription

Kotlin wrapper for workflow execution description with idiomatic API:

```kotlin
class KWorkflowExecutionDescription(
    private val delegate: WorkflowExecutionDescription
) {
    // Properties from WorkflowExecutionMetadata
    val execution: WorkflowExecution
    val workflowType: String
    val taskQueue: String
    val startTime: Instant
    val executionTime: Instant
    val closeTime: Instant?
    val status: WorkflowExecutionStatus
    val historyLength: Long
    val parentNamespace: String?
    val parentExecution: WorkflowExecution?
    val rootExecution: WorkflowExecution?
    val firstRunId: String?
    val executionDuration: Duration?
    val typedSearchAttributes: SearchAttributes

    // Reified memo access
    inline fun <reified T> memo(key: String): T?
    inline fun <reified T> memo(key: String, genericType: Type): T?

    // Experimental properties
    @Experimental val staticSummary: String?
    @Experimental val staticDetails: String?

    // Raw response for advanced use cases
    val rawDescription: DescribeWorkflowExecutionResponse

    // Java interop
    fun toWorkflowExecutionDescription(): WorkflowExecutionDescription
}
```

**Usage:**
```kotlin
val description = handle.describe()
println("Type: ${description.workflowType}")
println("Status: ${description.status}")
val config: MyConfig? = description.memo("config")
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

// Updates by name
val updateResult = untypedHandle.executeUpdate<Boolean>("addItem", newItem)
val updateHandle = untypedHandle.startUpdate<Boolean>("addItem", arg = newItem)

// Cancel/terminate work the same
untypedHandle.cancel()
```

```kotlin
class WorkflowHandle(
    val workflowId: String,
    val runId: String?,
    val execution: WorkflowExecution,
    // ... internal state
) {
    suspend fun <R> result(resultClass: Class<R>): R
    inline suspend fun <reified R> result(): R  // Reified version

    suspend fun signal(signalName: String, vararg args: Any?)

    suspend fun <R> query(queryName: String, resultClass: Class<R>, vararg args: Any?): R
    inline suspend fun <reified R> query(queryName: String, vararg args: Any?): R  // Reified version

    suspend fun <R> executeUpdate(updateName: String, resultClass: Class<R>, vararg args: Any?): R
    inline suspend fun <reified R> executeUpdate(updateName: String, vararg args: Any?): R  // Reified version

    suspend fun <R> startUpdate(
        updateName: String,
        resultClass: Class<R>,
        waitForStage: WorkflowUpdateStage = WorkflowUpdateStage.ACCEPTED,
        updateId: String? = null,
        vararg args: Any?
    ): KUpdateHandle<R>
    inline suspend fun <reified R> startUpdate(
        updateName: String,
        waitForStage: WorkflowUpdateStage = WorkflowUpdateStage.ACCEPTED,
        updateId: String? = null,
        vararg args: Any?
    ): KUpdateHandle<R>  // Reified version

    suspend fun cancel()
    suspend fun terminate(reason: String? = null)
    suspend fun describe(): KWorkflowExecutionDescription

    // Java SDK interop
    fun toStub(): WorkflowStub
}
```

This pattern matches Python SDK's `WorkflowHandle` with the same method names (`signal`, `query`, `result`, `cancel`, `terminate`, `execute_update`).

## Related

- [Workflow Client](./workflow-client.md) - Creating clients
- [Signals, Queries & Updates](../workflows/signals-queries.md) - Handler definitions

---

**Next:** [Advanced Operations](./advanced.md)
