# Advanced Client Operations

Both SignalWithStart and UpdateWithStart use `KWithStartWorkflowOperation` for consistency.

## KWithStartWorkflowOperation

```kotlin
/**
 * Represents a workflow start operation for use with signal-with-start or update-with-start.
 * Created via KWorkflowClient.withStartWorkflowOperation().
 */
interface KWithStartWorkflowOperation<T, R> {
    /** The workflow ID from the options. */
    val workflowId: String

    /** Suspends until the workflow completes and returns its result. */
    suspend fun result(): R
}
```

## SignalWithStart

Atomically start a workflow and send a signal. If the workflow already exists, only the signal is sent:

```kotlin
val startOp = client.withStartWorkflowOperation(
    OrderWorkflow::processOrder,
    KWorkflowOptions(
        workflowId = "order-123",
        taskQueue = "orders"
    ),
    order
)

val handle = client.signalWithStart(
    startOp,
    OrderWorkflow::updatePriority,
    Priority.HIGH
)

// Can use typed handle for queries/signals
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
val startOp = client.withStartWorkflowOperation(
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
    startOp,
    OrderWorkflow::addItem,
    KUpdateWithStartOptions(),
    newItem
)

// Access workflow result if needed
val workflowResult: OrderResult = startOp.result()
```

### Start Async (Don't Wait for Completion)

```kotlin
val startOp = client.withStartWorkflowOperation(
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
    startOp,
    OrderWorkflow::addItem,
    KUpdateWithStartOptions(waitForStage = WorkflowUpdateStage.ACCEPTED),
    newItem
)

// Later: get the update result
val result = updateHandle.result()
```

## KWorkflowClient API for Advanced Operations

```kotlin
class KWorkflowClient {
    /**
     * Create a workflow start operation for use with signal-with-start or update-with-start.
     */
    fun <T, R> withStartWorkflowOperation(
        workflow: KFunction1<T, R>,
        options: KWorkflowOptions
    ): KWithStartWorkflowOperation<T, R>

    fun <T, A1, R> withStartWorkflowOperation(
        workflow: KFunction2<T, A1, R>,
        options: KWorkflowOptions,
        arg1: A1
    ): KWithStartWorkflowOperation<T, R>

    /**
     * Atomically start a workflow and send a signal.
     * If the workflow already exists, only the signal is sent.
     */
    suspend fun <T, R, SA1> signalWithStart(
        startOp: KWithStartWorkflowOperation<T, R>,
        signal: KFunction2<T, SA1, *>,
        signalArg: SA1
    ): KTypedWorkflowHandle<T, R>

    /**
     * Atomically start a workflow and execute an update, waiting for completion.
     */
    suspend fun <T, R, UR> executeUpdateWithStart(
        startOp: KWithStartWorkflowOperation<T, R>,
        update: KSuspendFunction1<T, UR>,
        options: KUpdateWithStartOptions = KUpdateWithStartOptions()
    ): UR

    suspend fun <T, R, UA1, UR> executeUpdateWithStart(
        startOp: KWithStartWorkflowOperation<T, R>,
        update: KSuspendFunction2<T, UA1, UR>,
        options: KUpdateWithStartOptions = KUpdateWithStartOptions(),
        updateArg: UA1
    ): UR

    /**
     * Atomically start a workflow and send an update, returning immediately after
     * the update reaches the specified wait stage.
     */
    suspend fun <T, R, UR> startUpdateWithStart(
        startOp: KWithStartWorkflowOperation<T, R>,
        update: KSuspendFunction1<T, UR>,
        options: KUpdateWithStartOptions = KUpdateWithStartOptions()
    ): KUpdateHandle<UR>

    suspend fun <T, R, UA1, UR> startUpdateWithStart(
        startOp: KWithStartWorkflowOperation<T, R>,
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
