# Worker Setup

## KWorker (Recommended)

For pure Kotlin applications, use `KWorker` which automatically enables coroutine support. Following the Python/.NET pattern, workflows and activities are passed at construction time via options:

```kotlin
val client = KClient.connect(KClientOptions(target = "localhost:7233"))

// Create worker with workflows and activities specified in options
val worker = KWorker(
    client,
    KWorkerOptions(
        taskQueue = "task-queue",
        workflows = listOf(
            GreetingWorkflowImpl::class,
            OrderWorkflowImpl::class
        ),
        activities = listOf(
            GreetingActivitiesImpl(),  // Kotlin suspend activities
            JavaActivitiesImpl()        // Java activities work too
        ),
        maxConcurrentActivityExecutionSize = 100
    )
)

// Run the worker (blocks until shutdown signal or fatal error)
worker.run()
```

## KWorker API

```kotlin
/**
 * Kotlin worker that provides idiomatic APIs for running
 * Kotlin workflows and suspend activities.
 *
 * Workflows and activities are passed at construction time via KWorkerOptions,
 * following the Python/.NET SDK pattern.
 */
class KWorker(
    client: KClient,
    options: KWorkerOptions
) {
    /** The underlying Java Worker for interop scenarios */
    val worker: Worker

    /**
     * Run the worker, blocking until a shutdown signal is received or a fatal error occurs.
     * This is the recommended way to run a worker.
     *
     * Unlike start()/shutdown(), this method propagates fatal worker-runtime errors
     * rather than silently swallowing them.
     *
     * @throws WorkerException if a fatal error occurs during worker execution
     */
    suspend fun run()

    /**
     * Start the worker without blocking. Use shutdown() to stop.
     * Prefer run() for most use cases as it properly propagates fatal errors.
     */
    fun start()

    /** Gracefully shut down the worker, allowing in-flight tasks to complete. */
    fun shutdown()

    /** Immediately shut down the worker, cancelling in-flight tasks. */
    fun shutdownNow()

    /** Wait for the worker to terminate after shutdown is called. */
    suspend fun awaitTermination(timeout: Duration)
}
```

## KWorkerOptions

```kotlin
/**
 * Options for configuring a KWorker.
 * Workflows and activities are specified at construction time.
 */
data class KWorkerOptions(
    val taskQueue: String,
    val workflows: List<KClass<*>> = emptyList(),
    val activities: List<Any> = emptyList(),
    val workflowImplementationOptions: WorkflowImplementationOptions? = null,
    val maxConcurrentActivityExecutionSize: Int? = null,
    val maxConcurrentWorkflowTaskExecutionSize: Int? = null,
    val maxConcurrentLocalActivityExecutionSize: Int? = null,
    // ... other worker options
)
```

## Multiple Workers

For multiple task queues, create multiple workers and run them concurrently:

```kotlin
val orderWorker = KWorker(
    client,
    KWorkerOptions(
        taskQueue = "orders",
        workflows = listOf(OrderWorkflowImpl::class),
        activities = listOf(OrderActivitiesImpl())
    )
)

val notificationWorker = KWorker(
    client,
    KWorkerOptions(
        taskQueue = "notifications",
        workflows = listOf(NotificationWorkflowImpl::class),
        activities = listOf(NotificationActivitiesImpl())
    )
)

// Run all workers concurrently - blocks until shutdown or fatal error
coroutineScope {
    launch { orderWorker.run() }
    launch { notificationWorker.run() }
}
```

For advanced scenarios where you need manual control:

```kotlin
// Start workers without blocking
orderWorker.start()
notificationWorker.start()

// ... do other work ...

// Graceful shutdown
orderWorker.shutdown()
notificationWorker.shutdown()
orderWorker.awaitTermination(30.seconds)
notificationWorker.awaitTermination(30.seconds)
```

## KotlinJavaWorkerPlugin (For Java Main)

When your main application is written in Java and you need to register Kotlin workflows, use `KotlinJavaWorkerPlugin` explicitly:

```kotlin
// Java main or mixed Java/Kotlin setup
val service = WorkflowServiceStubs.newLocalServiceStubs()
val client = WorkflowClient.newInstance(service)

val factory = WorkerFactory.newInstance(client, WorkerFactoryOptions.newBuilder()
    .addPlugin(KotlinJavaWorkerPlugin())
    .build())

val worker = factory.newWorker("task-queue")

// Register Kotlin workflows - plugin handles suspend functions
worker.registerWorkflowImplementationTypes(KotlinWorkflowImpl::class.java)
```

## Mixed Java and Kotlin

A single worker supports both Java and Kotlin workflows on the same task queue:

```kotlin
val worker = KWorker(
    client,
    KWorkerOptions(
        taskQueue = "mixed-queue",
        workflows = listOf(
            GreetingWorkflowImpl::class,    // Kotlin workflow (coroutine-based)
            OrderWorkflowJavaImpl::class     // Java workflow (thread-based)
        ),
        activities = listOf(
            KotlinActivitiesImpl(),          // Kotlin suspend activities
            JavaActivitiesImpl()             // Java blocking activities
        )
    )
)

// Both run on the same worker - execution model is per-workflow-instance
worker.run()  // Blocks until shutdown or fatal error
```

## Related

- [Interceptors](../configuration/interceptors.md) - Adding cross-cutting concerns
- [Workflows](../workflows/README.md) - Defining workflows to register
- [Activities](../activities/README.md) - Defining activities to register

---

**Next:** [Testing](../testing.md)
