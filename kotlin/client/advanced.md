# Advanced Client Operations

Both SignalWithStart and UpdateWithStart use `withStartWorkflowOperation` to create a handle that becomes usable after the atomic operation completes.

## SignalWithStart

Atomically start a workflow and send a signal. If the workflow already exists, only the signal is sent:

```kotlin
// Create handle (not yet started)
val handle = client.withStartWorkflowOperation(
    OrderWorkflow::processOrder,
    KWorkflowOptions(
        workflowId = "order-123",
        taskQueue = "orders"
    ),
    order
)

// Atomically start workflow and send signal
client.signalWithStart(handle, OrderWorkflow::updatePriority, Priority.HIGH)

// Handle is now usable for queries/signals/result
val status = handle.query(OrderWorkflow::status)
val result = handle.result()  // Type inferred as OrderResult
```

## UpdateWithStart

Atomically start a workflow and send an update. Behavior depends on `workflowIdConflictPolicy`:
- `USE_EXISTING`: sends update to existing workflow
- `FAIL`: throws exception if workflow already exists

### KUpdateWithStartOptions

```kotlin
/**
 * Options for update-with-start operations.
 */
data class KUpdateWithStartOptions(
    /** Stage to wait for before returning (required for startUpdateWithStart) */
    val waitForStage: WorkflowUpdateStage = WorkflowUpdateStage.ACCEPTED,

    /** Optional update ID for idempotency */
    val updateId: String? = null
)
```

### Execute and Wait for Completion

```kotlin
// Create handle (not yet started)
val handle = client.withStartWorkflowOperation(
    OrderWorkflow::processOrder,
    KWorkflowOptions(
        workflowId = "order-123",
        taskQueue = "orders",
        workflowIdConflictPolicy = WorkflowIdConflictPolicy.USE_EXISTING
    ),
    order
)

// Execute update with start (waits for update completion)
val updateResult: Boolean = client.executeUpdateWithStart(
    handle,
    OrderWorkflow::addItem,
    KUpdateWithStartOptions(),
    newItem
)

// Handle is now usable
val workflowResult: OrderResult = handle.result()
```

### Start Async (Don't Wait for Completion)

```kotlin
// Create handle (not yet started)
val handle = client.withStartWorkflowOperation(
    OrderWorkflow::processOrder,
    KWorkflowOptions(
        workflowId = "order-456",
        taskQueue = "orders",
        workflowIdConflictPolicy = WorkflowIdConflictPolicy.FAIL
    ),
    order
)

// Start update and return immediately after it's accepted
val updateHandle: KUpdateHandle<Boolean> = client.startUpdateWithStart(
    handle,
    OrderWorkflow::addItem,
    KUpdateWithStartOptions(waitForStage = WorkflowUpdateStage.ACCEPTED),
    newItem
)

// Handle is now usable, get workflow result
val workflowResult = handle.result()

// Get update result when needed
val updateResult = updateHandle.result()
```

## KWorkflowClient API for Advanced Operations

```kotlin
class KWorkflowClient {
    /**
     * Create a workflow handle for use with signal-with-start or update-with-start.
     * The handle is not usable until signalWithStart or an update-with-start method is called.
     */
    fun <T, R> withStartWorkflowOperation(
        workflow: KSuspendFunction1<T, R>,
        options: KWorkflowOptions
    ): KTypedWorkflowHandle<T, R>

    fun <T, A1, R> withStartWorkflowOperation(
        workflow: KSuspendFunction2<T, A1, R>,
        options: KWorkflowOptions,
        arg1: A1
    ): KTypedWorkflowHandle<T, R>

    /**
     * Atomically start a workflow and send a signal.
     * If the workflow already exists, only the signal is sent.
     * After this call, the handle becomes usable.
     */
    suspend fun <T, R, SA1> signalWithStart(
        handle: KTypedWorkflowHandle<T, R>,
        signal: KSuspendFunction2<T, SA1, *>,
        signalArg: SA1
    )

    /**
     * Atomically start a workflow and execute an update, waiting for completion.
     * After this call, the handle becomes usable.
     */
    suspend fun <T, R, UR> executeUpdateWithStart(
        handle: KTypedWorkflowHandle<T, R>,
        update: KSuspendFunction1<T, UR>,
        options: KUpdateWithStartOptions = KUpdateWithStartOptions()
    ): UR

    suspend fun <T, R, UA1, UR> executeUpdateWithStart(
        handle: KTypedWorkflowHandle<T, R>,
        update: KSuspendFunction2<T, UA1, UR>,
        options: KUpdateWithStartOptions = KUpdateWithStartOptions(),
        updateArg: UA1
    ): UR

    /**
     * Atomically start a workflow and send an update, returning immediately after
     * the update reaches the specified wait stage.
     * After this call, the handle becomes usable.
     */
    suspend fun <T, R, UR> startUpdateWithStart(
        handle: KTypedWorkflowHandle<T, R>,
        update: KSuspendFunction1<T, UR>,
        options: KUpdateWithStartOptions = KUpdateWithStartOptions()
    ): KUpdateHandle<UR>

    suspend fun <T, R, UA1, UR> startUpdateWithStart(
        handle: KTypedWorkflowHandle<T, R>,
        update: KSuspendFunction2<T, UA1, UR>,
        options: KUpdateWithStartOptions = KUpdateWithStartOptions(),
        updateArg: UA1
    ): KUpdateHandle<UR>
}
```

## Related

- [Workflow Client](./workflow-client.md) - Basic client operations
- [Workflow Handles](./workflow-handle.md) - Interacting with workflows

---

**Next:** [Worker](../worker/README.md)
