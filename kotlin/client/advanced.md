# Advanced Client Operations

## SignalWithStart

Atomically start a workflow and send a signal. If the workflow already exists, only the signal is sent:

```kotlin
// Returns KTypedWorkflowHandle<OrderWorkflow, OrderResult> - result type captured from method reference
val handle = client.signalWithStart(
    workflow = OrderWorkflow::processOrder,
    options = KWorkflowOptions(
        workflowId = "order-123",
        taskQueue = "orders"
    ),
    workflowArg = order,
    signal = OrderWorkflow::updatePriority,
    signalArg = Priority.HIGH
)

// Can use typed handle for queries/signals
val status = handle.query(OrderWorkflow::status)
val result = handle.result()  // Type inferred as OrderResult
```

## UpdateWithStart

Atomically start a workflow and send an update. Behavior depends on `workflowIdConflictPolicy`:
- `USE_EXISTING`: sends update to existing workflow
- `FAIL`: throws exception if workflow already exists

### Supporting Types

```kotlin
/**
 * Represents a workflow start operation for use with update-with-start.
 * Created via KWorkflowClient.withStartWorkflowOperation().
 */
class KWithStartWorkflowOperation<T, R> {
    /** Suspends until the workflow completes and returns its result. */
    suspend fun result(): R
}

/**
 * Options for update-with-start operations.
 * Bundles the start operation with update-specific options.
 */
data class KUpdateWithStartOptions<T, R, UR>(
    /** The workflow start operation (required) */
    val startWorkflowOperation: KWithStartWorkflowOperation<T, R>,

    /** Stage to wait for before returning (required for startUpdateWithStart) */
    val waitForStage: WorkflowUpdateStage = WorkflowUpdateStage.ACCEPTED,

    /** Optional update ID for idempotency */
    val updateId: String? = null
)
```

### Execute and Wait for Completion

```kotlin
// Step 1: Create the workflow start operation
val startOp = client.withStartWorkflowOperation(
    OrderWorkflow::processOrder,
    KWorkflowOptions(
        workflowId = "order-123",
        taskQueue = "orders",
        workflowIdConflictPolicy = WorkflowIdConflictPolicy.USE_EXISTING  // Required
    ),
    order
)

// Step 2: Execute update with start (waits for update completion)
val updateResult: Boolean = client.executeUpdateWithStart(
    OrderWorkflow::addItem,  // Must be suspend function
    KUpdateWithStartOptions(startWorkflowOperation = startOp),
    newItem
)
println("Item added: $updateResult")

// Step 3: Access workflow result if needed (suspends until workflow completes)
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
    OrderWorkflow::addItem,
    KUpdateWithStartOptions(
        startWorkflowOperation = startOp,
        waitForStage = WorkflowUpdateStage.ACCEPTED
    ),
    newItem
)

// Later: get the update result
val result = updateHandle.result()
```

### No Arguments

```kotlin
val startOp = client.withStartWorkflowOperation(
    GreetingWorkflow::greet,
    KWorkflowOptions(
        workflowId = "greeting-789",
        taskQueue = "greetings",
        workflowIdConflictPolicy = WorkflowIdConflictPolicy.USE_EXISTING
    )
)

val status: String = client.executeUpdateWithStart(
    GreetingWorkflow::getStatus,  // suspend fun getStatus(): String
    KUpdateWithStartOptions(startWorkflowOperation = startOp)
)
```

## KWorkflowClient API for Advanced Operations

```kotlin
class KWorkflowClient {
    /**
     * Atomically start a workflow and send a signal.
     * If the workflow already exists, only the signal is sent.
     */
    suspend fun <T, A1, R, SA1> signalWithStart(
        workflow: KFunction2<T, A1, R>,
        options: KWorkflowOptions,
        workflowArg: A1,
        signal: KFunction2<T, SA1, *>,
        signalArg: SA1
    ): KTypedWorkflowHandle<T, R>

    /**
     * Create a workflow start operation for use with update-with-start.
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
     * Atomically start a workflow and send an update, returning immediately after
     * the update reaches the specified wait stage.
     */
    suspend fun <T, R, UR> startUpdateWithStart(
        update: KSuspendFunction1<T, UR>,
        options: KUpdateWithStartOptions<T, R, UR>
    ): KUpdateHandle<UR>

    suspend fun <T, R, UA1, UR> startUpdateWithStart(
        update: KSuspendFunction2<T, UA1, UR>,
        options: KUpdateWithStartOptions<T, R, UR>,
        updateArg1: UA1
    ): KUpdateHandle<UR>

    /**
     * Atomically start a workflow and execute an update, waiting for completion.
     */
    suspend fun <T, R, UR> executeUpdateWithStart(
        update: KSuspendFunction1<T, UR>,
        options: KUpdateWithStartOptions<T, R, UR>
    ): UR

    suspend fun <T, R, UA1, UR> executeUpdateWithStart(
        update: KSuspendFunction2<T, UA1, UR>,
        options: KUpdateWithStartOptions<T, R, UR>,
        updateArg1: UA1
    ): UR
}
```

## Related

- [Workflow Client](./workflow-client.md) - Basic client operations
- [Workflow Handles](./workflow-handle.md) - Interacting with workflows

---

**Next:** [Worker](../worker/README.md)
