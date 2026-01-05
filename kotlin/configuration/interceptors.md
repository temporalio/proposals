# Interceptors

Interceptors allow you to intercept workflow and activity executions to add cross-cutting concerns like logging, metrics, tracing, and custom error handling. The Kotlin SDK provides suspend-function-aware interceptors that integrate naturally with coroutines.

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
        LoggingInterceptor(),
        MetricsInterceptor(),
        TracingInterceptor()
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
data class KSignalInput(val signalName: String, val arguments: Array<Any?>, val eventId: Long, val header: Header)
data class KQueryInput(val queryName: String, val arguments: Array<Any?>, val header: Header)
data class KQueryOutput(val result: Any?)
data class KUpdateInput(val updateName: String, val arguments: Array<Any?>, val header: Header)
data class KUpdateOutput(val result: Any?)
```

## KWorkflowOutboundCallsInterceptor

Intercepts outbound calls from workflow code to Temporal APIs (activities, child workflows, timers, etc.).

```kotlin
interface KWorkflowOutboundCallsInterceptor {
    // Activities
    fun <R> executeActivity(input: KActivityInvocationInput<R>): Deferred<R>
    fun <R> executeLocalActivity(input: KLocalActivityInvocationInput<R>): Deferred<R>

    // Child Workflows
    fun <R> executeChildWorkflow(input: KChildWorkflowInvocationInput<R>): KChildWorkflowInvocationOutput<R>

    // Timers and Delays
    suspend fun delay(duration: Duration)
    fun newTimer(duration: Duration): Deferred<Unit>

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
    fun signalExternalWorkflow(input: KSignalExternalInput): Deferred<Unit>
    fun cancelWorkflow(input: KCancelWorkflowInput): Deferred<Unit>

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
    override fun <R> executeActivity(input: KActivityInvocationInput<R>) = next.executeActivity(input)
    override fun <R> executeLocalActivity(input: KLocalActivityInvocationInput<R>) = next.executeLocalActivity(input)
    override fun <R> executeChildWorkflow(input: KChildWorkflowInvocationInput<R>) = next.executeChildWorkflow(input)
    override suspend fun delay(duration: Duration) = next.delay(duration)
    override fun newTimer(duration: Duration) = next.newTimer(duration)
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
    override fun signalExternalWorkflow(input: KSignalExternalInput) = next.signalExternalWorkflow(input)
    override fun cancelWorkflow(input: KCancelWorkflowInput) = next.cancelWorkflow(input)
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
 * Output from child workflow start.
 */
data class KChildWorkflowInvocationOutput<R>(
    val result: Deferred<R>,
    val workflowExecution: Deferred<WorkflowExecution>
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
        return try {
            next.execute(input)
        } catch (e: Exception) {
            log.error("Workflow failed", e)
            throw e
        } finally {
            log.info("Workflow completed")
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
}

private class LoggingActivityInterceptor(
    next: KActivityInboundCallsInterceptor
) : KActivityInboundCallsInterceptorBase(next) {

    override suspend fun execute(input: KActivityExecutionInput): KActivityExecutionOutput {
        val info = KActivity.getInfo()
        val log = KActivity.logger()

        log.info("Activity ${info.activityType} started")
        val startTime = System.currentTimeMillis()

        return try {
            next.execute(input)
        } finally {
            val duration = System.currentTimeMillis() - startTime
            log.info("Activity ${info.activityType} completed in ${duration}ms")
        }
    }
}
```

## Example: Metrics Interceptor

```kotlin
class MetricsInterceptor(
    private val meterProvider: MeterProvider
) : KWorkerInterceptorBase() {

    private val meter = meterProvider.get("temporal.sdk")
    private val workflowCounter = meter.counterBuilder("workflow.executions").build()
    private val activityCounter = meter.counterBuilder("activity.executions").build()
    private val activityDuration = meter.histogramBuilder("activity.duration").build()

    override fun interceptWorkflow(
        next: KWorkflowInboundCallsInterceptor
    ): KWorkflowInboundCallsInterceptor {
        return object : KWorkflowInboundCallsInterceptorBase(next) {
            override suspend fun execute(input: KWorkflowInput): KWorkflowOutput {
                val workflowType = KWorkflow.getInfo().workflowType
                workflowCounter.add(1, Attributes.of(
                    AttributeKey.stringKey("workflow.type"), workflowType
                ))
                return next.execute(input)
            }
        }
    }

    override fun interceptActivity(
        next: KActivityInboundCallsInterceptor
    ): KActivityInboundCallsInterceptor {
        return object : KActivityInboundCallsInterceptorBase(next) {
            override suspend fun execute(input: KActivityExecutionInput): KActivityExecutionOutput {
                val info = KActivity.getInfo()
                val startTime = System.nanoTime()

                return try {
                    val result = next.execute(input)
                    activityCounter.add(1, Attributes.of(
                        AttributeKey.stringKey("activity.type"), info.activityType,
                        AttributeKey.stringKey("status"), "success"
                    ))
                    result
                } catch (e: Exception) {
                    activityCounter.add(1, Attributes.of(
                        AttributeKey.stringKey("activity.type"), info.activityType,
                        AttributeKey.stringKey("status"), "failure"
                    ))
                    throw e
                } finally {
                    val durationMs = (System.nanoTime() - startTime) / 1_000_000.0
                    activityDuration.record(durationMs, Attributes.of(
                        AttributeKey.stringKey("activity.type"), info.activityType
                    ))
                }
            }
        }
    }
}
```

## Example: Tracing with OpenTelemetry

```kotlin
class TracingInterceptor(
    private val tracer: Tracer
) : KWorkerInterceptorBase() {

    override fun interceptWorkflow(
        next: KWorkflowInboundCallsInterceptor
    ): KWorkflowInboundCallsInterceptor {
        return TracingWorkflowInboundInterceptor(next, tracer)
    }
}

private class TracingWorkflowInboundInterceptor(
    next: KWorkflowInboundCallsInterceptor,
    private val tracer: Tracer
) : KWorkflowInboundCallsInterceptorBase(next) {

    private lateinit var outboundInterceptor: TracingWorkflowOutboundInterceptor

    override suspend fun init(outboundCalls: KWorkflowOutboundCallsInterceptor) {
        // Wrap the outbound interceptor to trace outgoing calls
        outboundInterceptor = TracingWorkflowOutboundInterceptor(outboundCalls, tracer)
        next.init(outboundInterceptor)
    }

    override suspend fun execute(input: KWorkflowInput): KWorkflowOutput {
        // Extract trace context from header
        val parentContext = extractContext(input.header)

        val span = tracer.spanBuilder("workflow.execute")
            .setParent(parentContext)
            .setAttribute("workflow.type", KWorkflow.getInfo().workflowType)
            .startSpan()

        return try {
            withContext(span.asContextElement()) {
                next.execute(input)
            }
        } catch (e: Exception) {
            span.recordException(e)
            span.setStatus(StatusCode.ERROR)
            throw e
        } finally {
            span.end()
        }
    }
}

private class TracingWorkflowOutboundInterceptor(
    next: KWorkflowOutboundCallsInterceptor,
    private val tracer: Tracer
) : KWorkflowOutboundCallsInterceptorBase(next) {

    override fun <R> executeActivity(input: KActivityInvocationInput<R>): Deferred<R> {
        val span = tracer.spanBuilder("activity.schedule")
            .setAttribute("activity.name", input.activityName)
            .startSpan()

        // Inject trace context into header
        val headerWithTrace = injectContext(input.header, span.context)
        val inputWithTrace = input.copy(header = headerWithTrace)

        span.end()
        return next.executeActivity(inputWithTrace)
    }

    override fun <R> executeChildWorkflow(
        input: KChildWorkflowInvocationInput<R>
    ): KChildWorkflowInvocationOutput<R> {
        val span = tracer.spanBuilder("child_workflow.start")
            .setAttribute("workflow.type", input.workflowType)
            .setAttribute("workflow.id", input.workflowId)
            .startSpan()

        val headerWithTrace = injectContext(input.header, span.context)
        val inputWithTrace = input.copy(header = headerWithTrace)

        span.end()
        return next.executeChildWorkflow(inputWithTrace)
    }
}
```

## Example: Authentication Interceptor

```kotlin
class AuthInterceptor(
    private val authService: AuthService
) : KWorkerInterceptorBase() {

    override fun interceptWorkflow(
        next: KWorkflowInboundCallsInterceptor
    ): KWorkflowInboundCallsInterceptor {
        return object : KWorkflowInboundCallsInterceptorBase(next) {

            override suspend fun handleSignal(input: KSignalInput) {
                val authToken = input.header["authorization"]?.firstOrNull()
                if (authToken != null && !authService.isAuthorized(authToken, "signal:${input.signalName}")) {
                    throw IllegalAccessException("Unauthorized signal: ${input.signalName}")
                }
                next.handleSignal(input)
            }

            override suspend fun executeUpdate(input: KUpdateInput): KUpdateOutput {
                val authToken = input.header["authorization"]?.firstOrNull()
                if (authToken != null && !authService.isAuthorized(authToken, "update:${input.updateName}")) {
                    throw IllegalAccessException("Unauthorized update: ${input.updateName}")
                }
                return next.executeUpdate(input)
            }
        }
    }
}
```

## Next Steps

- [KOptions](./koptions.md) - Configuration options
- [Worker Setup](../worker/setup.md) - Registering interceptors
