# Client

## Creating a Client

Use `KClient.connect()` to create a client (unified client like Python/.NET SDKs):

```kotlin
// Connect to Temporal (like Python/.NET SDKs)
val client = KClient.connect(
    KClientOptions(
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

## KClient

`KClient` is a unified client (like Python's `Client` and .NET's `TemporalClient`) providing Kotlin-specific APIs with suspend functions for workflows, schedules, and async activity completion:

```kotlin
/**
 * Unified Kotlin client providing suspend functions and type-safe APIs
 * for workflows, schedules, and async activity completion.
 */
class KClient private constructor(...) {
    companion object {
        /**
         * Connect to Temporal service and create a client.
         */
        suspend fun connect(options: KClientOptions): KClient
    }

    /** The underlying WorkflowServiceStubs for advanced use cases */
    val workflowService: WorkflowServiceStubs

    // ==================== Workflow Operations ====================

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

    // Overloads for 2+ arguments using kargs()...

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

    // Overloads for 2+ arguments using kargs()...

    /**
     * Get a typed handle for an existing workflow by ID.
     */
    inline fun <reified T> workflowHandle(workflowId: String): KWorkflowHandle<T>
    inline fun <reified T> workflowHandle(workflowId: String, runId: String): KWorkflowHandle<T>

    /**
     * Get a typed handle with known result type for an existing workflow by ID.
     */
    inline fun <reified T, reified R> workflowHandle(workflowId: String): KWorkflowHandleWithResult<T, R>
    inline fun <reified T, reified R> workflowHandle(workflowId: String, runId: String): KWorkflowHandleWithResult<T, R>

    /**
     * Get an untyped handle for an existing workflow by ID.
     */
    fun untypedWorkflowHandle(workflowId: String): KWorkflowHandleUntyped
    fun untypedWorkflowHandle(workflowId: String, runId: String): KWorkflowHandleUntyped

    // ==================== Schedule Operations ====================

    /**
     * Create a new schedule.
     */
    suspend fun createSchedule(
        scheduleId: String,
        schedule: KSchedule,
        options: KScheduleOptions = KScheduleOptions()
    ): KScheduleHandle

    /**
     * Get a handle to an existing schedule.
     */
    fun scheduleHandle(scheduleId: String): KScheduleHandle

    /**
     * List all schedules.
     */
    fun listSchedules(): Flow<KScheduleListEntry>

    // ==================== Async Activity Completion ====================

    /**
     * Get a handle for async activity completion using task token.
     */
    fun activityCompletionHandle(taskToken: ByteArray): KActivityCompletionHandle
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

## KClientOptions

```kotlin
data class KClientOptions(
    val target: String = "localhost:7233",
    val namespace: String = "default",
    val identity: String? = null,
    val dataConverter: DataConverter? = null,
    val interceptors: List<KClientInterceptor> = emptyList(),
    // ... other options
)
```

## KWorkflowOptions

See [KOptions](../configuration/koptions.md#kworkflowoptions) for the full `KWorkflowOptions` reference.

## Related

- [Advanced Operations](./advanced.md) - SignalWithStart, UpdateWithStart
- [KOptions](../configuration/koptions.md) - KWorkflowOptions reference
- [Schedules](./schedules.md) - Schedule operations

---

**Next:** [Workflow Handles](./workflow-handle.md)
