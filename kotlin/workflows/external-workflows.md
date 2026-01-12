# External Workflows

External workflows allow you to signal or cancel workflows running in separate executions. Use `KWorkflow.getExternalWorkflowHandle()` to get a handle for interaction.

## Typed Handle

```kotlin
// Get typed handle for external workflow
val handle = KWorkflow.getExternalWorkflowHandle<OrderWorkflow>("order-123")

// Signal using method reference (type-safe)
handle.signal(OrderWorkflow::updatePriority, Priority.HIGH)

// Cancel the external workflow
handle.cancel()
```

## With Run ID

```kotlin
// Target a specific execution
val handle = KWorkflow.getExternalWorkflowHandle<OrderWorkflow>(
    workflowId = "order-123",
    runId = "abc-run-456"
)

handle.signal(OrderWorkflow::cancelOrder, "Duplicate order")
```

## Untyped Handle

When the workflow type is unknown at compile time:

```kotlin
// Get untyped handle
val handle = KWorkflow.getExternalWorkflowHandle("order-123")

// Signal by name
handle.signal("updatePriority", Priority.HIGH)

// Cancel
handle.cancel()
```

## KExternalWorkflowHandle API

```kotlin
/**
 * Handle for interacting with an external workflow (workflow in a different execution).
 * Obtained via KWorkflow.getExternalWorkflowHandle().
 *
 * @param T The external workflow interface type (for type-safe signals)
 */
class KExternalWorkflowHandle<T>(
    val workflowId: String,
    val runId: String?
) {
    // Signals - type-safe method references
    suspend fun signal(method: KFunction1<T, *>)
    suspend fun <A1> signal(method: KFunction2<T, A1, *>, arg: A1)
    suspend fun <A1, A2> signal(method: KFunction3<T, A1, A2, *>, arg1: A1, arg2: A2)
    // ... up to 6 arguments

    /** Request cancellation of the external workflow. */
    suspend fun cancel()
}
```

## ExternalWorkflowHandle (Untyped)

```kotlin
/**
 * Untyped handle for external workflows.
 * Use when workflow type is unknown at compile time.
 */
class ExternalWorkflowHandle(
    val workflowId: String,
    val runId: String?
) {
    suspend fun signal(signalName: String, vararg args: Any?)
    suspend fun cancel()
}
```

## KWorkflow API

```kotlin
object KWorkflow {
    /** Get typed handle for external workflow */
    inline fun <reified T> getExternalWorkflowHandle(workflowId: String): KExternalWorkflowHandle<T>
    inline fun <reified T> getExternalWorkflowHandle(workflowId: String, runId: String): KExternalWorkflowHandle<T>

    /** Get untyped handle for external workflow */
    fun getExternalWorkflowHandle(workflowId: String): ExternalWorkflowHandle
    fun getExternalWorkflowHandle(workflowId: String, runId: String): ExternalWorkflowHandle
}
```

## Limitations

| Operation | Supported |
|-----------|-----------|
| Signal | ✓ |
| Cancel | ✓ |
| Query | ✗ (queries are synchronous, only available via client) |
| Get Result | ✗ (cannot await external workflow results from within a workflow) |

## Related

- [Child Workflows](./child-workflows.md) - Workflows started by the current workflow
- [Signals, Queries & Updates](./signals-queries.md) - Signal handler definitions

---

**Next:** [Timers & Parallel Execution](./timers-parallel.md)
