# Worker Setup

## KWorker (Recommended)

For pure Kotlin applications, use `KWorker` which automatically enables coroutine support. Following the Python/.NET pattern, workflows and activities are passed at construction time via options:

```kotlin
val service = WorkflowServiceStubs.newLocalServiceStubs()
val client = KWorkflowClient(service) { ... }

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

// Start the worker
worker.start()
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
    client: KWorkflowClient,
    options: KWorkerOptions
) {
    /** The underlying Java Worker for interop scenarios */
    val worker: Worker

    fun start()
    fun shutdown()
    fun shutdownNow()
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

For multiple task queues, create multiple workers:

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

// Start all workers
orderWorker.start()
notificationWorker.start()
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
worker.start()
```

## Related

- [Interceptors](../configuration/interceptors.md) - Adding cross-cutting concerns
- [Workflows](../workflows/README.md) - Defining workflows to register
- [Activities](../activities/README.md) - Defining activities to register

---

**Next:** [Testing](../testing.md)
