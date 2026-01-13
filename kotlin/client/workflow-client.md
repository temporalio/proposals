# Workflow Client

## Creating a Client

Use `KWorkflowClient.connect()` to create a client:

```kotlin
// Connect to Temporal (like newer SDKs)
val client = KWorkflowClient.connect(
    KWorkflowClientOptions(
        target = "localhost:7233",
        namespace = "default"
    )
)

// Access raw gRPC services when needed
val workflowService = client.workflowService

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
 */
class KWorkflowClient private constructor(...) {
    companion object {
        /**
         * Connect to Temporal service and create a client.
         */
        suspend fun connect(options: KWorkflowClientOptions): KWorkflowClient
    }

    /** The underlying WorkflowServiceStubs for advanced use cases */
    val workflowService: WorkflowServiceStubs

    /** The underlying WorkflowClient for advanced use cases */
    val workflowClient: WorkflowClient

    /**
     * Start a workflow and return a handle for interaction.
     * Does not wait for the workflow to complete.
     */
    suspend fun <T, R> startWorkflow(
        workflow: KSuspendFunction1<T, R>,
        options: KWorkflowOptions
    ): KWorkflowHandleWithResult<T, R>

    suspend fun <T, A1, R> startWorkflow(
        workflow: KSuspendFunction2<T, A1, R>,
        options: KWorkflowOptions,
        arg: A1
    ): KWorkflowHandleWithResult<T, R>

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
    inline fun <reified T> workflowHandle(workflowId: String): KWorkflowHandle<T>
    inline fun <reified T> workflowHandle(workflowId: String, runId: String): KWorkflowHandle<T>

    /**
     * Get a typed handle with known result type for an existing workflow by ID.
     * Use when you know both the workflow type and result type at compile time.
     */
    inline fun <reified T, reified R> workflowHandle(workflowId: String): KWorkflowHandleWithResult<T, R>
    inline fun <reified T, reified R> workflowHandle(workflowId: String, runId: String): KWorkflowHandleWithResult<T, R>

    /**
     * Get an untyped handle for an existing workflow by ID.
     * Use when you don't know the workflow type at compile time.
     */
    fun untypedWorkflowHandle(workflowId: String): KWorkflowHandleUntyped
    fun untypedWorkflowHandle(workflowId: String, runId: String): KWorkflowHandleUntyped
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

// Get handle for existing workflow
val existingHandle = client.workflowHandle<GreetingWorkflow>("greeting-123")
val result = existingHandle.result<String>()  // Must specify result type

// Or with result type known
val typedHandle = client.workflowHandle<GreetingWorkflow, String>("greeting-123")
val result = typedHandle.result()  // Result type already known
```

## KWorkflowOptions

See [KOptions](../configuration/koptions.md#kworkflowoptions) for the full `KWorkflowOptions` reference.

## Related

- [Advanced Operations](./advanced.md) - SignalWithStart, UpdateWithStart
- [KOptions](../configuration/koptions.md) - KWorkflowOptions reference

---

**Next:** [Workflow Handles](./workflow-handle.md)
