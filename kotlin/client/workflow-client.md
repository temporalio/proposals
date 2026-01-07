# Workflow Client

## Creating a Client

```kotlin
val service = WorkflowServiceStubs.newLocalServiceStubs()

// Create KWorkflowClient with DSL configuration
val client = KWorkflowClient(service) {
    setNamespace("default")
    setDataConverter(myConverter)
}

// For blocking calls from non-suspend contexts, use runBlocking
val result = runBlocking {
    client.executeWorkflow(MyWorkflow::process, options, input)
}
```

## KWorkflowClient

`KWorkflowClient` provides Kotlin-specific APIs with suspend functions for starting and interacting with workflows:

```kotlin
/**
 * Kotlin workflow client providing suspend functions and type-safe workflow APIs.
 *
 * @param service The WorkflowServiceStubs to connect to
 * @param options DSL builder for WorkflowClientOptions
 */
class KWorkflowClient(
    service: WorkflowServiceStubs,
    options: WorkflowClientOptions.Builder.() -> Unit = {}
) {
    /** The underlying WorkflowClient for advanced use cases */
    val workflowClient: WorkflowClient

    /**
     * Start a workflow and return a handle for interaction.
     * Does not wait for the workflow to complete.
     */
    suspend fun <T, R> startWorkflow(
        workflow: KSuspendFunction1<T, R>,
        options: KWorkflowOptions
    ): KTypedWorkflowHandle<T, R>

    suspend fun <T, A1, R> startWorkflow(
        workflow: KSuspendFunction2<T, A1, R>,
        options: KWorkflowOptions,
        arg: A1
    ): KTypedWorkflowHandle<T, R>

    // Overloads for 2-6 arguments...

    /**
     * Start a workflow and wait for its result.
     * Suspends until the workflow completes.
     */
    suspend fun <T, R> executeWorkflow(
        workflow: KSuspendFunction1<T, R>,
        options: KWorkflowOptions
    ): R

    suspend fun <T, A1, R> executeWorkflow(
        workflow: KSuspendFunction2<T, A1, R>,
        options: KWorkflowOptions,
        arg: A1
    ): R

    // Overloads for 2-6 arguments...

    /**
     * Get a typed handle for an existing workflow by ID.
     * Use this to signal, query, or get results from a workflow started elsewhere.
     */
    inline fun <reified T> getWorkflowHandle(workflowId: String): KWorkflowHandle<T>
    inline fun <reified T> getWorkflowHandle(workflowId: String, runId: String): KWorkflowHandle<T>

    /**
     * Get an untyped handle for an existing workflow by ID.
     * Use when you don't know the workflow type at compile time.
     */
    fun getUntypedWorkflowHandle(workflowId: String): WorkflowHandle
    fun getUntypedWorkflowHandle(workflowId: String, runId: String): WorkflowHandle
}
```

## Starting Workflows

```kotlin
// Execute workflow and wait for result (suspend function)
val result = client.executeWorkflow(
    GreetingWorkflow::getGreeting,
    KWorkflowOptions(
        workflowId = "greeting-123",
        taskQueue = "greeting-queue",
        workflowExecutionTimeout = 1.hours
    ),
    "Temporal"
)

// Or start async and get handle
val handle = client.startWorkflow(
    GreetingWorkflow::getGreeting,
    KWorkflowOptions(
        workflowId = "greeting-123",
        taskQueue = "greeting-queue"
    ),
    "Temporal"
)
val result = handle.result()  // Type inferred as String from method reference
```

## KWorkflowOptions

```kotlin
/**
 * Kotlin-native workflow options for client execution.
 * workflowId and taskQueue are optional - if not provided, will use defaults or generate UUID.
 */
data class KWorkflowOptions(
    val workflowId: String? = null,
    val workflowIdReusePolicy: WorkflowIdReusePolicy? = null,
    val workflowIdConflictPolicy: WorkflowIdConflictPolicy? = null,
    val workflowRunTimeout: Duration? = null,
    val workflowExecutionTimeout: Duration? = null,
    val workflowTaskTimeout: Duration? = null,
    val taskQueue: String? = null,
    val retryOptions: KRetryOptions? = null,
    val cronSchedule: String? = null,
    val memo: Map<String, Any>? = null,
    val typedSearchAttributes: SearchAttributes? = null,
    val disableEagerExecution: Boolean = true,
    val startDelay: Duration? = null,
    val staticSummary: String? = null,
    val staticDetails: String? = null,
    val priority: Priority? = null
)
```

## Related

- [Advanced Operations](./advanced.md) - SignalWithStart, UpdateWithStart
- [KOptions](../configuration/koptions.md) - KWorkflowOptions reference

---

**Next:** [Workflow Handles](./workflow-handle.md)
