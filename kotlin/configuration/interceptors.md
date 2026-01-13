# Interceptors

Interceptors allow you to intercept workflow, activity, and client operations to add cross-cutting concerns like logging, metrics, tracing, and custom error handling. The Kotlin SDK provides:

- **KWorkerInterceptor** - Intercepts workflow and activity executions on the worker side
- **KWorkflowClientInterceptor** - Intercepts client-side operations (start, signal, query, update)

All interceptors are suspend-function-aware and integrate naturally with coroutines.

## KWorkerInterceptor

The main entry point for interceptors. Registered with `KWorkerFactory` and called when workflows or activities are instantiated.

```kotlin
/**
 * Intercepts workflow and activity executions.
 *
 * Prefer extending [KWorkerInterceptorBase] and overriding only the methods you need.
 */
interface KWorkerInterceptor {
    /**
     * Called when a workflow is instantiated. May create a [KWorkflowInboundCallsInterceptor].
     * The returned interceptor must forward all calls to [next].
     */
    fun interceptWorkflow(next: KWorkflowInboundCallsInterceptor): KWorkflowInboundCallsInterceptor

    /**
     * Called when an activity task is received. May create a [KActivityInboundCallsInterceptor].
     * The returned interceptor must forward all calls to [next].
     */
    fun interceptActivity(next: KActivityInboundCallsInterceptor): KActivityInboundCallsInterceptor
}

/**
 * Base implementation that passes through all calls. Extend this class and override only needed methods.
 */
open class KWorkerInterceptorBase : KWorkerInterceptor {
    override fun interceptWorkflow(next: KWorkflowInboundCallsInterceptor) = next
    override fun interceptActivity(next: KActivityInboundCallsInterceptor) = next
}
```

## Registering Interceptors

Interceptors are registered via `KWorkerFactory`:

```kotlin
val factory = KWorkerFactory(client) {
    workerInterceptors = listOf(
        LoggingInterceptor()
    )
}

val worker = factory.newWorker("task-queue")
worker.registerWorkflowImplementationTypes<MyWorkflowImpl>()
worker.registerActivitiesImplementations(MyActivitiesImpl())

factory.start()
```

## KWorkflowInboundCallsInterceptor

Intercepts inbound calls to workflow execution (workflow method, signals, queries, updates).

```kotlin
interface KWorkflowInboundCallsInterceptor {
    /** Called when the workflow is instantiated. Use this to wrap the outbound interceptor. */
    suspend fun init(outboundCalls: KWorkflowOutboundCallsInterceptor)

    /** Called when the workflow main method is invoked. */
    suspend fun execute(input: KWorkflowInput): KWorkflowOutput

    /** Called when a signal is delivered to the workflow. */
    suspend fun handleSignal(input: KSignalInput)

    /** Called when a query is made to the workflow. Note: Queries must be synchronous. */
    fun handleQuery(input: KQueryInput): KQueryOutput

    /** Called to validate an update before execution. Throw an exception to reject. */
    fun validateUpdate(input: KUpdateInput)

    /** Called to execute an update after validation passes. */
    suspend fun executeUpdate(input: KUpdateInput): KUpdateOutput
}

/** Base implementation that forwards all calls to the next interceptor. */
open class KWorkflowInboundCallsInterceptorBase(
    protected val next: KWorkflowInboundCallsInterceptor
) : KWorkflowInboundCallsInterceptor {
    override suspend fun init(outboundCalls: KWorkflowOutboundCallsInterceptor) = next.init(outboundCalls)
    override suspend fun execute(input: KWorkflowInput) = next.execute(input)
    override suspend fun handleSignal(input: KSignalInput) = next.handleSignal(input)
    override fun handleQuery(input: KQueryInput) = next.handleQuery(input)
    override fun validateUpdate(input: KUpdateInput) = next.validateUpdate(input)
    override suspend fun executeUpdate(input: KUpdateInput) = next.executeUpdate(input)
}
```

### Input/Output Classes

```kotlin
data class KWorkflowInput(val header: Header, val arguments: Array<Any?>)
data class KWorkflowOutput(val result: Any?)

// Dynamic handlers can use encodedValues to decode raw payloads
data class KSignalInput(
    val signalName: String,
    val arguments: Array<Any?>,
    val encodedValues: KEncodedValues,
    val eventId: Long,
    val header: Header
)
data class KQueryInput(
    val queryName: String,
    val arguments: Array<Any?>,
    val encodedValues: KEncodedValues,
    val header: Header
)
data class KQueryOutput(val result: Any?)
data class KUpdateInput(
    val updateName: String,
    val arguments: Array<Any?>,
    val encodedValues: KEncodedValues,
    val header: Header
)
data class KUpdateOutput(val result: Any?)
```

## KWorkflowOutboundCallsInterceptor

Intercepts outbound calls from workflow code to Temporal APIs (activities, child workflows, timers, etc.).

All async operations are `suspend` functions. For parallel execution, use standard `async { }` pattern.

```kotlin
interface KWorkflowOutboundCallsInterceptor {
    // Activities - suspend, use async {} for parallel execution
    suspend fun <R> executeActivity(input: KActivityInvocationInput<R>): R
    suspend fun <R> executeLocalActivity(input: KLocalActivityInvocationInput<R>): R

    // Child Workflows - returns handle with Deferred result
    suspend fun <T, R> startChildWorkflow(input: KChildWorkflowInvocationInput<R>): KChildWorkflowHandle<T, R>

    // Timers
    suspend fun delay(duration: Duration)

    // Await Conditions
    suspend fun awaitCondition(timeout: Duration, reason: String, condition: () -> Boolean): Boolean
    suspend fun awaitCondition(reason: String, condition: () -> Boolean)

    // Side Effects
    fun <R> sideEffect(resultClass: Class<R>, func: () -> R): R
    fun <R> mutableSideEffect(id: String, resultClass: Class<R>, updated: (R?, R?) -> Boolean, func: () -> R): R

    // Versioning
    fun getVersion(changeId: String, minSupported: Int, maxSupported: Int): Int

    // Continue As New
    fun continueAsNew(input: KContinueAsNewInput): Nothing

    // External Workflow Communication
    suspend fun signalExternalWorkflow(input: KSignalExternalInput)
    suspend fun cancelWorkflow(input: KCancelWorkflowInput)

    // Search Attributes and Memo
    fun upsertTypedSearchAttributes(vararg updates: SearchAttributeUpdate<*>)
    fun upsertMemo(memo: Map<String, Any>)

    // Utilities
    fun newRandom(): Random
    fun randomUUID(): UUID
    fun currentTimeMillis(): Long
}

/**
 * Base implementation that forwards all calls to the next interceptor.
 */
open class KWorkflowOutboundCallsInterceptorBase(
    protected val next: KWorkflowOutboundCallsInterceptor
) : KWorkflowOutboundCallsInterceptor {
    override suspend fun <R> executeActivity(input: KActivityInvocationInput<R>) = next.executeActivity(input)
    override suspend fun <R> executeLocalActivity(input: KLocalActivityInvocationInput<R>) = next.executeLocalActivity(input)
    override suspend fun <T, R> startChildWorkflow(input: KChildWorkflowInvocationInput<R>) = next.startChildWorkflow<T, R>(input)
    override suspend fun delay(duration: Duration) = next.delay(duration)
    override suspend fun awaitCondition(timeout: Duration, reason: String, condition: () -> Boolean) =
        next.awaitCondition(timeout, reason, condition)
    override suspend fun awaitCondition(reason: String, condition: () -> Boolean) =
        next.awaitCondition(reason, condition)
    override fun <R> sideEffect(resultClass: Class<R>, func: () -> R) = next.sideEffect(resultClass, func)
    override fun <R> mutableSideEffect(id: String, resultClass: Class<R>, updated: (R?, R?) -> Boolean, func: () -> R) =
        next.mutableSideEffect(id, resultClass, updated, func)
    override fun getVersion(changeId: String, minSupported: Int, maxSupported: Int) =
        next.getVersion(changeId, minSupported, maxSupported)
    override fun continueAsNew(input: KContinueAsNewInput) = next.continueAsNew(input)
    override suspend fun signalExternalWorkflow(input: KSignalExternalInput) = next.signalExternalWorkflow(input)
    override suspend fun cancelWorkflow(input: KCancelWorkflowInput) = next.cancelWorkflow(input)
    override fun upsertTypedSearchAttributes(vararg updates: SearchAttributeUpdate<*>) =
        next.upsertTypedSearchAttributes(*updates)
    override fun upsertMemo(memo: Map<String, Any>) = next.upsertMemo(memo)
    override fun newRandom() = next.newRandom()
    override fun randomUUID() = next.randomUUID()
    override fun currentTimeMillis() = next.currentTimeMillis()
}
```

### Outbound Input/Output Classes

```kotlin
/**
 * Input for activity invocation.
 */
data class KActivityInvocationInput<R>(
    val activityName: String,
    val resultClass: Class<R>,
    val resultType: Type,
    val arguments: Array<Any?>,
    val options: KActivityOptions,
    val header: Header
)

/**
 * Input for local activity invocation.
 */
data class KLocalActivityInvocationInput<R>(
    val activityName: String,
    val resultClass: Class<R>,
    val resultType: Type,
    val arguments: Array<Any?>,
    val options: KLocalActivityOptions,
    val header: Header
)

/**
 * Input for child workflow invocation.
 */
data class KChildWorkflowInvocationInput<R>(
    val workflowId: String,
    val workflowType: String,
    val resultClass: Class<R>,
    val resultType: Type,
    val arguments: Array<Any?>,
    val options: KChildWorkflowOptions,
    val header: Header
)

/**
 * Input for continue-as-new.
 */
data class KContinueAsNewInput(
    val workflowType: String?,
    val options: KContinueAsNewOptions?,
    val arguments: Array<Any?>,
    val header: Header
)

/**
 * Input for signaling external workflow.
 */
data class KSignalExternalInput(
    val execution: WorkflowExecution,
    val signalName: String,
    val arguments: Array<Any?>,
    val header: Header
)

/**
 * Input for canceling external workflow.
 */
data class KCancelWorkflowInput(
    val execution: WorkflowExecution,
    val reason: String?
)
```

## KActivityInboundCallsInterceptor

Intercepts inbound calls to activity execution.

```kotlin
interface KActivityInboundCallsInterceptor {
    /** Called when activity is initialized. Provides access to the activity execution context. */
    fun init(context: ActivityExecutionContext)

    /** Called when activity method is invoked. This is a suspend function to support suspend activities. */
    suspend fun execute(input: KActivityExecutionInput): KActivityExecutionOutput
}

open class KActivityInboundCallsInterceptorBase(
    protected val next: KActivityInboundCallsInterceptor
) : KActivityInboundCallsInterceptor {
    override fun init(context: ActivityExecutionContext) = next.init(context)
    override suspend fun execute(input: KActivityExecutionInput) = next.execute(input)
}

data class KActivityExecutionInput(val header: Header, val arguments: Array<Any?>)
data class KActivityExecutionOutput(val result: Any?)
```

## Example: Logging Interceptor

```kotlin
class LoggingInterceptor : KWorkerInterceptorBase() {

    override fun interceptWorkflow(
        next: KWorkflowInboundCallsInterceptor
    ): KWorkflowInboundCallsInterceptor {
        return LoggingWorkflowInterceptor(next)
    }

    override fun interceptActivity(
        next: KActivityInboundCallsInterceptor
    ): KActivityInboundCallsInterceptor {
        return LoggingActivityInterceptor(next)
    }
}

private class LoggingWorkflowInterceptor(
    next: KWorkflowInboundCallsInterceptor
) : KWorkflowInboundCallsInterceptorBase(next) {

    private val log = KWorkflow.logger()

    override suspend fun execute(input: KWorkflowInput): KWorkflowOutput {
        log.info("Workflow started with ${input.arguments.size} arguments")
        val startTime = KWorkflow.currentTimeMillis()

        return try {
            val result = next.execute(input)
            val duration = KWorkflow.currentTimeMillis() - startTime
            log.info("Workflow completed in ${duration}ms")
            result
        } catch (e: Exception) {
            val duration = KWorkflow.currentTimeMillis() - startTime
            log.error("Workflow failed after ${duration}ms", e)
            throw e
        }
    }

    override suspend fun handleSignal(input: KSignalInput) {
        log.info("Signal received: ${input.signalName}")
        next.handleSignal(input)
    }

    override fun handleQuery(input: KQueryInput): KQueryOutput {
        log.debug("Query received: ${input.queryName}")
        return next.handleQuery(input)
    }

    override suspend fun executeUpdate(input: KUpdateInput): KUpdateOutput {
        log.info("Update received: ${input.updateName}")
        return try {
            val result = next.executeUpdate(input)
            log.info("Update ${input.updateName} completed")
            result
        } catch (e: Exception) {
            log.error("Update ${input.updateName} failed", e)
            throw e
        }
    }
}

private class LoggingActivityInterceptor(
    next: KActivityInboundCallsInterceptor
) : KActivityInboundCallsInterceptorBase(next) {

    override suspend fun execute(input: KActivityExecutionInput): KActivityExecutionOutput {
        val info = KActivity.info
        val log = KActivity.logger()

        log.info("Activity ${info.activityType} started")
        val startTime = System.currentTimeMillis()

        return try {
            val result = next.execute(input)
            val duration = System.currentTimeMillis() - startTime
            log.info("Activity ${info.activityType} completed in ${duration}ms")
            result
        } catch (e: Exception) {
            val duration = System.currentTimeMillis() - startTime
            log.error("Activity ${info.activityType} failed after ${duration}ms", e)
            throw e
        }
    }
}
```

## KWorkflowClientInterceptor

Client interceptors intercept client-side operations such as starting workflows, sending signals, executing queries, and updates.

```kotlin
/**
 * Intercepts client-side workflow operations.
 *
 * Prefer extending [KWorkflowClientInterceptorBase] and overriding only the methods you need.
 */
interface KWorkflowClientInterceptor {
    /** Called when starting a workflow */
    suspend fun <R> startWorkflow(input: KStartWorkflowInput<R>, next: suspend (KStartWorkflowInput<R>) -> KWorkflowHandleWithResult<*, R>): KWorkflowHandleWithResult<*, R>

    /** Called when signaling a workflow */
    suspend fun signalWorkflow(input: KSignalWorkflowInput, next: suspend (KSignalWorkflowInput) -> Unit)

    /** Called when querying a workflow */
    suspend fun <R> queryWorkflow(input: KQueryWorkflowInput<R>, next: suspend (KQueryWorkflowInput<R>) -> R): R

    /** Called when executing an update on a workflow */
    suspend fun <R> executeUpdate(input: KExecuteUpdateInput<R>, next: suspend (KExecuteUpdateInput<R>) -> R): R

    /** Called when starting an update on a workflow */
    suspend fun <R> startUpdate(input: KStartUpdateInput<R>, next: suspend (KStartUpdateInput<R>) -> KUpdateHandle<R>): KUpdateHandle<R>

    /** Called when canceling a workflow */
    suspend fun cancelWorkflow(input: KCancelWorkflowInput, next: suspend (KCancelWorkflowInput) -> Unit)

    /** Called when terminating a workflow */
    suspend fun terminateWorkflow(input: KTerminateWorkflowInput, next: suspend (KTerminateWorkflowInput) -> Unit)
}

/**
 * Base implementation that passes through all calls.
 */
open class KWorkflowClientInterceptorBase : KWorkflowClientInterceptor {
    override suspend fun <R> startWorkflow(input: KStartWorkflowInput<R>, next: suspend (KStartWorkflowInput<R>) -> KWorkflowHandleWithResult<*, R>) = next(input)
    override suspend fun signalWorkflow(input: KSignalWorkflowInput, next: suspend (KSignalWorkflowInput) -> Unit) = next(input)
    override suspend fun <R> queryWorkflow(input: KQueryWorkflowInput<R>, next: suspend (KQueryWorkflowInput<R>) -> R) = next(input)
    override suspend fun <R> executeUpdate(input: KExecuteUpdateInput<R>, next: suspend (KExecuteUpdateInput<R>) -> R) = next(input)
    override suspend fun <R> startUpdate(input: KStartUpdateInput<R>, next: suspend (KStartUpdateInput<R>) -> KUpdateHandle<R>) = next(input)
    override suspend fun cancelWorkflow(input: KCancelWorkflowInput, next: suspend (KCancelWorkflowInput) -> Unit) = next(input)
    override suspend fun terminateWorkflow(input: KTerminateWorkflowInput, next: suspend (KTerminateWorkflowInput) -> Unit) = next(input)
}
```

### Client Interceptor Input Classes

```kotlin
data class KStartWorkflowInput<R>(
    val workflowId: String,
    val workflowType: String,
    val taskQueue: String,
    val arguments: Array<Any?>,
    val options: KWorkflowOptions,
    val header: Header
)

data class KSignalWorkflowInput(
    val workflowId: String,
    val runId: String?,
    val signalName: String,
    val arguments: Array<Any?>,
    val header: Header
)

data class KQueryWorkflowInput<R>(
    val workflowId: String,
    val runId: String?,
    val queryName: String,
    val arguments: Array<Any?>,
    val resultClass: Class<R>,
    val header: Header
)

data class KExecuteUpdateInput<R>(
    val workflowId: String,
    val runId: String?,
    val updateName: String,
    val arguments: Array<Any?>,
    val options: KUpdateOptions,
    val resultClass: Class<R>,
    val header: Header
)

data class KStartUpdateInput<R>(
    val workflowId: String,
    val runId: String?,
    val updateName: String,
    val arguments: Array<Any?>,
    val options: KStartUpdateOptions,
    val resultClass: Class<R>,
    val header: Header
)

data class KCancelWorkflowInput(
    val workflowId: String,
    val runId: String?
)

data class KTerminateWorkflowInput(
    val workflowId: String,
    val runId: String?,
    val reason: String?
)
```

### Registering Client Interceptors

```kotlin
val client = KWorkflowClient.connect(
    KWorkflowClientOptions(
        target = "localhost:7233",
        namespace = "default",
        interceptors = listOf(
            TracingClientInterceptor()
        )
    )
)
```

## Related

- [KOptions](./koptions.md) - Configuration options
- [Worker Setup](../worker/setup.md) - Registering interceptors

---

**Next:** [Workflows](../workflows/README.md)
