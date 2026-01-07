# Worker Setup

## KWorkerFactory (Recommended)

For pure Kotlin applications, use `KWorkerFactory` which automatically enables coroutine support:

```kotlin
val service = WorkflowServiceStubs.newLocalServiceStubs()
val client = KWorkflowClient(service) { ... }

// KWorkerFactory automatically enables Kotlin coroutine support
val factory = KWorkerFactory(client)

val worker: KWorker = factory.newWorker("task-queue") {
    maxConcurrentActivityExecutionSize = 100
}

// Register Kotlin coroutine workflows
worker.registerWorkflowImplementationTypes(
    GreetingWorkflowImpl::class,
    OrderWorkflowImpl::class
)

// Register activities - suspend functions handled automatically
worker.registerActivitiesImplementations(
    GreetingActivitiesImpl(),  // Kotlin suspend activities
    JavaActivitiesImpl()        // Java activities work too
)

// Start the worker
factory.start()
```

## KWorkerFactory API

```kotlin
/**
 * Kotlin worker factory that automatically enables coroutine support.
 * Wraps WorkerFactory with KotlinPlugin pre-configured.
 */
class KWorkerFactory(
    client: KWorkflowClient,
    options: WorkerFactoryOptions.Builder.() -> Unit = {}
) {
    /** The underlying WorkerFactory for advanced use cases */
    val workerFactory: WorkerFactory

    fun newWorker(taskQueue: String, options: WorkerOptions.Builder.() -> Unit = {}): KWorker
    fun start()
    fun shutdown()
    fun shutdownNow()
    suspend fun awaitTermination(timeout: Duration)
}
```

## KWorker API

```kotlin
/**
 * Kotlin worker that provides idiomatic APIs for registering
 * Kotlin workflows and suspend activities.
 *
 * Use KWorker for pure Kotlin implementations. For mixed Java/Kotlin
 * scenarios, access the underlying Worker via the [worker] property.
 */
class KWorker {
    /** The underlying Java Worker for interop scenarios */
    val worker: Worker

    /** Register Kotlin workflow implementation types using reified generics */
    inline fun <reified T : Any> registerWorkflowImplementationTypes()

    /** Register Kotlin workflow implementation types using KClass */
    fun registerWorkflowImplementationTypes(vararg workflowClasses: KClass<*>)

    /** Register Kotlin workflow implementation types with options */
    fun registerWorkflowImplementationTypes(
        options: WorkflowImplementationOptions,
        vararg workflowClasses: KClass<*>
    )

    /** Register activity implementations (automatically detects suspend functions) */
    fun registerActivitiesImplementations(vararg activities: Any)

    /** Register suspend activity implementations explicitly */
    fun registerSuspendActivities(vararg activities: Any)

    /** Register Nexus service implementations */
    fun registerNexusServiceImplementations(vararg services: Any)
}
```

**When to use KWorker vs Worker:**
- Use `KWorker` for pure Kotlin implementations (recommended)
- Use `Worker` (via `kworker.worker`) when mixing Java and Kotlin workflows/activities on the same worker

## KotlinPlugin (For Java Main)

When your main application is written in Java and you need to register Kotlin workflows, use `KotlinPlugin` explicitly:

```kotlin
// Java main or mixed Java/Kotlin setup
val service = WorkflowServiceStubs.newLocalServiceStubs()
val client = WorkflowClient.newInstance(service)

val factory = WorkerFactory.newInstance(client, WorkerFactoryOptions.newBuilder()
    .addPlugin(KotlinPlugin())
    .build())

val worker = factory.newWorker("task-queue")

// Register Kotlin workflows - plugin handles suspend functions
worker.registerWorkflowImplementationTypes(KotlinWorkflowImpl::class.java)
```

## Mixed Java and Kotlin

A single worker supports both Java and Kotlin workflows on the same task queue:

```kotlin
// Java workflows (thread-based)
worker.registerWorkflowImplementationTypes(
    OrderWorkflowJavaImpl::class.java
)

// Kotlin workflows (coroutine-based) - same method, plugin handles execution
worker.registerWorkflowImplementationTypes(
    GreetingWorkflowImpl::class
)

// Both run on the same worker - execution model is per-workflow-instance
factory.start()
```

## Related

- [Interceptors](../configuration/interceptors.md) - Adding cross-cutting concerns
- [Workflows](../workflows/README.md) - Defining workflows to register
- [Activities](../activities/README.md) - Defining activities to register

---

**Next:** [Migration Guide](../migration.md)
