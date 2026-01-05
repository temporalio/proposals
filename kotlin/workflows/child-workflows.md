# Child Workflows

Child workflows are invoked using direct method references - no stub creation needed.

## Execute and Wait

```kotlin
// Simple case - execute child workflow and wait for result
override suspend fun parentWorkflow(): String {
    return KWorkflow.executeChildWorkflow(
        ChildWorkflow::doWork,
        KChildWorkflowOptions(workflowId = "child-workflow-id"),
        "input"
    )
}

// With retry options
override suspend fun parentWorkflowWithRetry(): String {
    return KWorkflow.executeChildWorkflow(
        ChildWorkflow::doWork,
        KChildWorkflowOptions(
            workflowId = "child-workflow-id",
            workflowExecutionTimeout = 1.hours,
            retryOptions = KRetryOptions(maximumAttempts = 3)
        ),
        "input"
    )
}
```

## Parallel Execution

Use standard `coroutineScope { async {} }` for parallel child workflows:

```kotlin
override suspend fun parentWorkflowParallel(): String = coroutineScope {
    // Start child and activity in parallel using standard Kotlin async
    val childDeferred = async {
        KWorkflow.executeChildWorkflow(
            ChildWorkflow::doWork,
            KChildWorkflowOptions(workflowId = "child-workflow-id"),
            "input"
        )
    }
    val activityDeferred = async {
        KWorkflow.executeActivity(
            SomeActivities::doSomething,
            KActivityOptions(startToCloseTimeout = 30.seconds)
        )
    }

    // Wait for both using standard awaitAll
    val (childResult, activityResult) = awaitAll(childDeferred, activityDeferred)
    "$childResult - $activityResult"
}
```

## Child Workflow Handles

For cases where you need to interact with a child workflow (signal, query, cancel) rather than just wait for its result, use `startChildWorkflow` to get a handle:

```kotlin
// Start child workflow and get handle for interaction
override suspend fun parentWorkflowWithHandle(): String {
    val handle = KWorkflow.startChildWorkflow(
        ChildWorkflow::doWork,
        KChildWorkflowOptions(workflowId = "child-workflow-id"),
        "input"
    )

    // Can signal the child workflow
    handle.signal(ChildWorkflow::updateProgress, 50)

    // Wait for result when ready
    return handle.result()
}

// Parallel child workflows with handles for interaction
override suspend fun parallelChildrenWithHandles(): List<String> = coroutineScope {
    val handles = listOf("child-1", "child-2", "child-3").map { id ->
        KWorkflow.startChildWorkflow(
            ChildWorkflow::doWork,
            KChildWorkflowOptions(workflowId = id),
            "input"
        )
    }

    // Can interact with any child while they're running
    handles.forEach { handle ->
        handle.signal(ChildWorkflow::updatePriority, Priority.HIGH)
    }

    // Wait for all results
    handles.map { async { it.result() } }.awaitAll()
}
```

## KWorkflow Child Workflow Methods

```kotlin
object KWorkflow {
    /**
     * Execute a child workflow and wait for its result.
     * For fire-and-wait cases where you don't need to interact with the child.
     */
    suspend fun <T, A1, R> executeChildWorkflow(
        workflow: KFunction2<T, A1, R>,
        options: KChildWorkflowOptions,
        arg: A1
    ): R

    suspend fun <T, R> executeChildWorkflow(
        workflow: KFunction1<T, R>,
        options: KChildWorkflowOptions
    ): R

    // ... up to 6 arguments

    /**
     * Start a child workflow and return a handle for interaction.
     * Use this when you need to signal, query, or cancel the child workflow.
     * For simple fire-and-wait cases, prefer executeChildWorkflow() instead.
     */
    suspend fun <T, A1, R> startChildWorkflow(
        workflow: KFunction2<T, A1, R>,
        options: KChildWorkflowOptions,
        arg: A1
    ): KChildWorkflowHandle<T, R>

    suspend fun <T, R> startChildWorkflow(
        workflow: KFunction1<T, R>,
        options: KChildWorkflowOptions
    ): KChildWorkflowHandle<T, R>

    suspend fun <T, A1, A2, R> startChildWorkflow(
        workflow: KFunction3<T, A1, A2, R>,
        options: KChildWorkflowOptions,
        arg1: A1,
        arg2: A2
    ): KChildWorkflowHandle<T, R>

    // ... up to 6 arguments
}
```

## KChildWorkflowHandle API

```kotlin
/**
 * Handle for interacting with a started child workflow.
 * Returned by startChildWorkflow() with result type captured from method reference.
 *
 * @param T The child workflow interface type
 * @param R The result type of the child workflow method
 */
interface KChildWorkflowHandle<T, R> {
    /** The child workflow's workflow ID (available immediately) */
    val workflowId: String

    /**
     * Get the child workflow's run ID.
     * Suspends until the child workflow starts.
     */
    suspend fun runId(): String

    /**
     * Wait for the child workflow to complete and return its result.
     * Suspends until the child workflow finishes.
     */
    suspend fun result(): R

    // Signals - type-safe method references
    suspend fun signal(method: KFunction1<T, *>)
    suspend fun <A1> signal(method: KFunction2<T, A1, *>, arg: A1)
    suspend fun <A1, A2> signal(method: KFunction3<T, A1, A2, *>, arg1: A1, arg2: A2)

    /**
     * Request cancellation of the child workflow.
     * The child workflow will receive a CancellationException at its next suspension point.
     */
    suspend fun cancel()
}
```

## KChildWorkflowOptions

```kotlin
// All fields are optional - null values inherit from parent workflow or use Java SDK defaults
KChildWorkflowOptions(
    workflowId = "child-workflow-id",
    taskQueue = "child-queue",                      // Optional: defaults to parent's task queue
    workflowExecutionTimeout = 1.hours,
    workflowRunTimeout = 30.minutes,
    retryOptions = KRetryOptions(
        initialInterval = 1.seconds,
        maximumAttempts = 3
    ),
    parentClosePolicy = ParentClosePolicy.PARENT_CLOSE_POLICY_TERMINATE,  // Optional
    cancellationType = ChildWorkflowCancellationType.WAIT_CANCELLATION_COMPLETED  // Optional
)

// Options are optional - use default KChildWorkflowOptions() when not specified
val result = KWorkflow.executeChildWorkflow(
    ChildWorkflow::processData,
    inputData  // No options needed for simple cases
)
```

> **Note:** For simple parallel execution where you only need the result, use standard `coroutineScope { async { executeChildWorkflow(...) } }`. Use `startChildWorkflow` only when you need to interact with the child workflow while it's running.

## Related

- [Cancellation](./cancellation.md) - How cancellation propagates to child workflows
- [Workflow Definition](./definition.md) - Basic workflow patterns

---

**Next:** [Timers & Parallel Execution](./timers-parallel.md)
