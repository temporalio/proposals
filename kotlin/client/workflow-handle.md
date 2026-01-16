# Workflow Handles

For interacting with existing workflows (signals, queries, results, cancellation), use a typed or untyped handle.

## Handle Type Hierarchy

```kotlin
KWorkflowHandleUntyped                           // Untyped base
KWorkflowHandle<T> : KWorkflowHandleUntyped      // Typed workflow, untyped result
KWorkflowHandleWithResult<T, R> : KWorkflowHandle<T>  // Fully typed
```

## Update Options

```kotlin
/**
 * Options for executing updates.
 */
data class KUpdateOptions(
    /** Optional update ID for idempotency */
    val updateId: String? = null
)

/**
 * Options for starting updates (not waiting for completion).
 * Note: waitForStage is required with no default value.
 */
data class KStartUpdateOptions(
    /** Stage to wait for before returning (required) */
    val waitForStage: WorkflowUpdateStage,  // No default - must be specified

    /** Optional update ID for idempotency */
    val updateId: String? = null
)
```

## Typed Handles

```kotlin
// Get typed handle for existing workflow by ID
val handle = client.workflowHandle<OrderWorkflow>("order-123")

// Send signal - method reference provides type safety
handle.signal(OrderWorkflow::updatePriority, Priority.HIGH)

// Query - method reference with compile-time type checking
val status = handle.query(OrderWorkflow::status)
val count = handle.query(OrderWorkflow::getItemCount)

// Get result (suspends until workflow completes) - must specify type
val result = handle.result<OrderResult>()

// Or get handle with known result type
val typedHandle = client.workflowHandle<OrderWorkflow, OrderResult>("order-123")
val result = typedHandle.result()  // Type already known

// Updates - execute and wait for result
val updateResult = handle.executeUpdate(
    OrderWorkflow::addItem,
    newItem,
    KUpdateOptions(updateId = "add-item-1")  // Options always last
)

// Updates - start and get handle (don't wait for completion)
val updateHandle = handle.startUpdate(
    OrderWorkflow::addItem,
    newItem,
    KStartUpdateOptions(waitForStage = WorkflowUpdateStage.ACCEPTED)  // waitForStage required
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

All handle types (`KWorkflowHandleUntyped`, `KWorkflowHandle`, `KWorkflowHandleWithResult`, `KUpdateHandle`, `KChildWorkflowHandle`) are **classes** rather than interfaces. This design choice enables:

1. **Reified type parameters** - `inline fun <reified T>` methods directly on handle types
2. **Better IDE discoverability** - Methods appear directly in autocomplete
3. **No extension function workarounds** - No need for separate extension functions for reified generics
4. **Full testing support** - mockk and other frameworks can mock classes

## KWorkflowHandleUntyped API

```kotlin
// Base untyped handle - returned by untypedWorkflowHandle(id)
open class KWorkflowHandleUntyped(
    val workflowId: String,
    val runId: String?,
    val execution: WorkflowExecution,
    // ... internal state
) {
    // Result - requires explicit type since we don't know it
    suspend fun <R> result(resultClass: Class<R>): R
    inline suspend fun <reified R> result(): R  // Reified version

    // Signals by name
    suspend fun signal(signalName: String, vararg args: Any?)

    // Queries by name (suspend for network I/O)
    suspend fun <R> query(queryName: String, resultClass: Class<R>, vararg args: Any?): R
    inline suspend fun <reified R> query(queryName: String, vararg args: Any?): R  // Reified version

    // Updates by name
    suspend fun <R> executeUpdate(
        updateName: String,
        resultClass: Class<R>,
        vararg args: Any?,
        options: KUpdateOptions = KUpdateOptions()
    ): R
    inline suspend fun <reified R> executeUpdate(
        updateName: String,
        vararg args: Any?,
        options: KUpdateOptions = KUpdateOptions()
    ): R

    suspend fun <R> startUpdate(
        updateName: String,
        resultClass: Class<R>,
        vararg args: Any?,
        options: KStartUpdateOptions  // waitForStage is required - no default
    ): KUpdateHandle<R>
    inline suspend fun <reified R> startUpdate(
        updateName: String,
        vararg args: Any?,
        options: KStartUpdateOptions
    ): KUpdateHandle<R>

    // Get handle for existing update by ID
    fun <R> updateHandle(updateId: String, resultClass: Class<R>): KUpdateHandle<R>
    inline fun <reified R> updateHandle(updateId: String): KUpdateHandle<R>  // Reified version

    // Lifecycle
    suspend fun cancel()
    suspend fun terminate(reason: String? = null)
    suspend fun describe(): KWorkflowExecutionDescription

    // Java SDK interop
    fun toStub(): WorkflowStub
}
```

## KWorkflowHandle API

```kotlin
// Typed handle - returned by workflowHandle<T>(id)
// Result type is unknown, must specify when calling result<R>()
open class KWorkflowHandle<T>(
    workflowId: String,
    runId: String?,
    execution: WorkflowExecution,
    // ... internal state
) : KWorkflowHandleUntyped(workflowId, runId, execution) {

    // Signals - type-safe method references
    // Note: Signal handlers can be either suspend or non-suspend functions
    suspend fun signal(method: KFunction1<T, Unit>)
    suspend fun <A1> signal(method: KFunction2<T, A1, Unit>, arg: A1)
    suspend fun <A1, A2> signal(method: KFunction3<T, A1, A2, Unit>, arg1: A1, arg2: A2)

    // Queries - type-safe method references (suspend for network I/O)
    suspend fun <R> query(method: KFunction1<T, R>): R
    suspend fun <R, A1> query(method: KFunction2<T, A1, R>, arg: A1): R

    // Updates - execute and wait for result (options always last)
    suspend fun <R> executeUpdate(
        method: KSuspendFunction1<T, R>,
        options: KUpdateOptions = KUpdateOptions()
    ): R
    suspend fun <R, A1> executeUpdate(
        method: KSuspendFunction2<T, A1, R>,
        arg: A1,
        options: KUpdateOptions = KUpdateOptions()
    ): R
    // ... up to 6 arguments

    // Updates - start and return handle (waitForStage required in options)
    suspend fun <R> startUpdate(
        method: KSuspendFunction1<T, R>,
        options: KStartUpdateOptions  // waitForStage required - no default
    ): KUpdateHandle<R>
    suspend fun <R, A1> startUpdate(
        method: KSuspendFunction2<T, A1, R>,
        arg: A1,
        options: KStartUpdateOptions
    ): KUpdateHandle<R>
    // ... up to 6 arguments
}
```

**Note on query methods:** Although queries are synchronous within the workflow, client-side query calls involve network I/O to the Temporal service, which is why they are `suspend` functions following idiomatic Kotlin patterns.

## KWorkflowHandleWithResult

Extended handle returned by `startWorkflow()` or `workflowHandle<T, R>()` - result type R is known:

```kotlin
class KWorkflowHandleWithResult<T, R>(
    workflowId: String,
    runId: String?,
    execution: WorkflowExecution,
    // ... internal state
) : KWorkflowHandle<T>(workflowId, runId, execution) {
    // Result type is known - no type parameter needed
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
): KWorkflowHandleWithResult<T, R>  // R is preserved in return type

// Usage - result type is inferred
val handle = client.startWorkflow(
    OrderWorkflow::processOrder,  // KSuspendFunction2<OrderWorkflow, Order, OrderResult>
    options,
    order
)
val result: OrderResult = handle.result()  // No type parameter needed!

// workflowHandle with one type param doesn't know result type
val existingHandle = client.workflowHandle<OrderWorkflow>(workflowId)
val result = existingHandle.result<OrderResult>()  // Must specify type

// workflowHandle with two type params knows result type
val typedHandle = client.workflowHandle<OrderWorkflow, OrderResult>(workflowId)
val result = typedHandle.result()  // Type already known
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

## KWorkflowExecutionInfo and KWorkflowExecutionDescription

Base class `KWorkflowExecutionInfo` is returned by `listWorkflows()`. Extended class `KWorkflowExecutionDescription` is returned by `describe()`:

```kotlin
// Base class returned by listWorkflows()
open class KWorkflowExecutionInfo(
    val execution: WorkflowExecution,
    val workflowType: String,
    val taskQueue: String,
    val startTime: Instant,
    val status: WorkflowExecutionStatus
    // ... lighter set of fields
)

// Extended class returned by describe()
class KWorkflowExecutionDescription(
    execution: WorkflowExecution,
    workflowType: String,
    taskQueue: String,
    startTime: Instant,
    status: WorkflowExecutionStatus,
    // Additional fields from describe()
    val executionTime: Instant,
    val closeTime: Instant?,
    val historyLength: Long,
    val parentNamespace: String?,
    val parentExecution: WorkflowExecution?,
    val rootExecution: WorkflowExecution?,
    val firstRunId: String?,
    val executionDuration: Duration?,
    val searchAttributes: SearchAttributes,
    // ... additional detail fields
) : KWorkflowExecutionInfo(execution, workflowType, taskQueue, startTime, status) {

    // Reified memo access
    inline fun <reified T> memo(key: String): T?
    inline fun <reified T> memo(key: String, genericType: Type): T?

    // Experimental properties
    @Experimental val staticSummary: String?
    @Experimental val staticDetails: String?

    // Raw response for advanced use cases
    val rawDescription: DescribeWorkflowExecutionResponse
}
```

**Usage:**
```kotlin
// From describe() - full details
val description = handle.describe()
println("Type: ${description.workflowType}")
println("Status: ${description.status}")
val config: MyConfig? = description.memo("config")

// From listWorkflows() - lighter weight
client.listWorkflows("WorkflowType = 'OrderWorkflow'").collect { info ->
    println("${info.workflowType}: ${info.status}")
}
```

## Untyped Handles

For cases where you don't know the workflow type at compile time, use `KWorkflowHandleUntyped` (see API definition above):

```kotlin
// Untyped handle - signal/query by string name
val untypedHandle = client.untypedWorkflowHandle("order-123")

// Operations use string names instead of method references
untypedHandle.signal("updatePriority", Priority.HIGH)
val status = untypedHandle.query<OrderStatus>("status")
val result = untypedHandle.result<OrderResult>()

// Updates by name - options always last, waitForStage required for startUpdate
val updateResult = untypedHandle.executeUpdate<Boolean>("addItem", newItem)
val updateHandle = untypedHandle.startUpdate<Boolean>(
    "addItem",
    newItem,
    options = KStartUpdateOptions(waitForStage = WorkflowUpdateStage.ACCEPTED)
)

// Cancel/terminate work the same
untypedHandle.cancel()
```

This pattern matches Python SDK's `WorkflowHandle` with the same method names (`signal`, `query`, `result`, `cancel`, `terminate`, `execute_update`).

## Related

- [Workflow Client](./workflow-client.md) - Creating clients
- [Signals, Queries & Updates](../workflows/signals-queries.md) - Handler definitions

---

**Next:** [Advanced Operations](./advanced.md)
