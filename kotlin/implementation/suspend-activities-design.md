# Design: Suspend Function Support for Kotlin Activities (Revised)

## Overview

This document proposes adding support for Kotlin suspend functions as activity implementations. This enables activities to use Kotlin's coroutine-based async I/O libraries (Ktor, R2DBC, etc.) without blocking threads.

## Current State

### Activity Execution Model

Activities in the Java SDK are **thread-based**:

```
Worker Thread Pool
       ↓
ActivityTaskHandlerImpl.handle()
       ↓
POJOActivityTaskExecutor.execute()
       ↓
Method.invoke() [blocking]
       ↓
Return result → sendReply() [blocking gRPC]
       ↓
Release slot permit
```

- Activities run on dedicated threads from a thread pool
- Context is stored in thread-local storage (`ActivityInternal.currentActivityExecutionContext`)
- Activities can block the thread (e.g., HTTP calls, database queries)
- Result is sent to server via **blocking** gRPC call

### Existing Async Pattern: Local Manual Completion

The Java SDK already supports async activity completion via `useLocalManualCompletion()`:

```java
public int execute() {
    ActivityExecutionContext context = Activity.getExecutionContext();
    ManualActivityCompletionClient client = context.useLocalManualCompletion();

    // Offload to thread pool - activity method returns immediately
    ForkJoinPool.commonPool().execute(() -> {
        try {
            // Async work happens here
            Object result = doAsyncWork();
            client.complete(result);  // Complete when done
        } catch (Exception e) {
            client.fail(e);  // Or fail on error
        }
    });

    return 0;  // Return immediately, thread is freed
}
```

**Key properties:**
- `useLocalManualCompletion()` marks activity for manual completion
- Returns `ManualActivityCompletionClient` for completing later
- Respects `maxConcurrentActivityExecutionSize` limit (slot stays reserved)
- Releases slot permit when `complete()`, `fail()`, or `reportCancellation()` is called

### Problem

Using `runBlocking` in a suspend activity wrapper defeats the purpose - it still ties up the thread pool thread during the entire coroutine execution. We need truly non-blocking execution.

## Proposed Design

### Key Insight

Leverage the existing `useLocalManualCompletion()` pattern to achieve truly async suspend activities without modifying the core Java SDK.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Activity Task Arrives                             │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│               SuspendActivityTaskExecutor                            │
│                                                                      │
│  1. Get ManualActivityCompletionClient via useLocalManualCompletion()│
│  2. Launch coroutine on CoroutineDispatcher                          │
│  3. Return immediately (thread freed)                                │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
        ┌───────────────────────┴───────────────────────┐
        │                                               │
        ▼                                               ▼
┌─────────────────────┐                    ┌─────────────────────────┐
│ Thread Pool Thread  │                    │  Coroutine Dispatcher   │
│ (freed immediately) │                    │                         │
└─────────────────────┘                    │  Execute suspend fun    │
                                           │       │                  │
                                           │       ▼                  │
                                           │  On I/O suspend:        │
                                           │  Thread released!       │
                                           │       │                  │
                                           │       ▼                  │
                                           │  Resume on I/O complete │
                                           │       │                  │
                                           │       ▼                  │
                                           │  Complete via client    │
                                           └─────────────────────────┘
                                                    │
                                                    ▼
                                           ┌─────────────────────────┐
                                           │ ManualActivityCompletion│
                                           │ Client.complete(result) │
                                           │                         │
                                           │ - Sends result to server│
                                           │ - Releases slot permit  │
                                           └─────────────────────────┘
```

### Component 1: SuspendActivityInvoker

A wrapper that intercepts suspend activity method invocations:

```kotlin
// io.temporal.kotlin.internal.SuspendActivityInvoker

internal class SuspendActivityInvoker(
    private val activityInstance: Any,
    private val method: KFunction<*>,
    private val dispatcher: CoroutineDispatcher,
    private val heartbeatInterval: Duration? = null  // Optional auto-heartbeat
) {
    /**
     * Called by the activity framework. Returns immediately after launching coroutine.
     */
    fun invoke(
        context: ActivityExecutionContext,
        args: Array<Any?>
    ): Any? {
        // Get manual completion client - marks activity for async completion
        val completionClient = context.useLocalManualCompletion()

        // Create cancellation-aware scope
        val job = SupervisorJob()
        val scope = CoroutineScope(dispatcher + job)

        // Launch coroutine - this returns immediately!
        scope.launch {
            // Create activity context element for coroutine
            val kContext = KActivityExecutionContext(context, completionClient, job)

            withContext(KActivityExecutionContextElement(kContext)) {
                try {
                    // Start auto-heartbeat if configured
                    val heartbeatJob = heartbeatInterval?.let { interval ->
                        launch { autoHeartbeat(completionClient, interval, job) }
                    }

                    // Execute the suspend function
                    val result = method.callSuspend(activityInstance, *args)

                    // Cancel heartbeat job
                    heartbeatJob?.cancel()

                    // Complete successfully (uses Dispatchers.IO for blocking gRPC)
                    withContext(Dispatchers.IO) {
                        completionClient.complete(result)
                    }
                } catch (e: CancellationException) {
                    // Coroutine was cancelled (activity cancellation or timeout)
                    withContext(Dispatchers.IO + NonCancellable) {
                        completionClient.reportCancellation(null)
                    }
                } catch (e: Throwable) {
                    // Activity failed
                    withContext(Dispatchers.IO + NonCancellable) {
                        completionClient.fail(e)
                    }
                }
            }
        }

        // Return immediately - actual result sent via completion client
        return null
    }

    /**
     * Background job that sends heartbeats and monitors for cancellation.
     */
    private suspend fun autoHeartbeat(
        client: ManualActivityCompletionClient,
        interval: Duration,
        parentJob: Job
    ) {
        while (isActive) {
            delay(interval)
            try {
                // recordHeartbeat throws CanceledFailure if activity is cancelled
                withContext(Dispatchers.IO) {
                    client.recordHeartbeat(null)
                }
            } catch (e: CanceledFailure) {
                // Activity was cancelled - cancel the parent job
                parentJob.cancel(CancellationException("Activity cancelled", e))
                break
            }
        }
    }
}
```

### Component 2: KActivityExecutionContext (Coroutine-aware)

Activity context accessible from within coroutines:

```kotlin
// io.temporal.kotlin.internal.KActivityExecutionContext

internal class KActivityExecutionContext(
    private val javaContext: ActivityExecutionContext,
    private val completionClient: ManualActivityCompletionClient,
    private val parentJob: Job
) {
    val info: ActivityInfo get() = javaContext.info
    val taskToken: ByteArray get() = javaContext.taskToken

    /**
     * Sends a heartbeat. This is a suspend function that doesn't block.
     * Throws CancellationException if the activity has been cancelled.
     */
    suspend fun heartbeat(details: Any? = null) {
        try {
            withContext(Dispatchers.IO) {
                completionClient.recordHeartbeat(details)
            }
        } catch (e: CanceledFailure) {
            // Convert to coroutine cancellation
            parentJob.cancel(CancellationException("Activity cancelled", e))
            throw CancellationException("Activity cancelled", e)
        }
    }

    /**
     * Gets heartbeat details from a previous attempt.
     */
    inline fun <reified T> getHeartbeatDetails(): T? {
        return javaContext.getHeartbeatDetails(T::class.java).orElse(null)
    }
}

// Coroutine context element
internal class KActivityExecutionContextElement(
    val context: KActivityExecutionContext
) : AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<KActivityExecutionContextElement>
}
```

### Component 3: KActivity Public API

```kotlin
// io.temporal.kotlin.activity.KActivity

public object KActivity {

    /**
     * Gets activity info for the current execution.
     * Works in both suspend and regular activities.
     */
    public fun getInfo(): KActivityInfo {
        // Try coroutine context first (suspend activities)
        val kContext = currentCoroutineContextOrNull()?.get(KActivityExecutionContextElement)?.context
        if (kContext != null) {
            return KActivityInfo(kContext.info)
        }
        // Fall back to thread-local (regular activities)
        return KActivityInfo(Activity.getExecutionContext().info)
    }

    /**
     * Sends a heartbeat with optional details.
     * In suspend activities, this is non-blocking.
     *
     * @throws CancellationException if the activity has been cancelled
     */
    public suspend fun <T> heartbeat(details: T? = null) {
        val kContext = coroutineContext[KActivityExecutionContextElement]?.context
            ?: throw IllegalStateException("heartbeat() must be called from within an activity")
        kContext.heartbeat(details)
    }

    /**
     * Gets heartbeat details from a previous attempt.
     */
    public inline fun <reified T> getHeartbeatDetails(): T? {
        val kContext = currentCoroutineContextOrNull()?.get(KActivityExecutionContextElement)?.context
        if (kContext != null) {
            return kContext.getHeartbeatDetails<T>()
        }
        return Activity.getExecutionContext()
            .getHeartbeatDetails(T::class.java)
            .orElse(null)
    }

    /**
     * Gets the task token for external completion scenarios.
     */
    public fun getTaskToken(): ByteArray {
        val kContext = currentCoroutineContextOrNull()?.get(KActivityExecutionContextElement)?.context
        if (kContext != null) {
            return kContext.taskToken
        }
        return Activity.getExecutionContext().taskToken
    }
}

// Helper to get coroutine context without throwing
private fun currentCoroutineContextOrNull(): CoroutineContext? {
    return try {
        // This works if we're in a coroutine
        runBlocking { coroutineContext }
    } catch (e: Exception) {
        null
    }
}
```

### Component 4: Activity Registration

Detect suspend functions at registration and create appropriate invokers:

```kotlin
// io.temporal.kotlin.worker.KWorkerFactory (enhanced)

public class KWorkerFactory(client: KWorkflowClient) {

    private val activityDispatcher: CoroutineDispatcher = Dispatchers.Default
    private val defaultHeartbeatInterval: Duration? = null  // Optional

    /**
     * Configure the dispatcher for suspend activities.
     */
    public fun setActivityDispatcher(dispatcher: CoroutineDispatcher) {
        this.activityDispatcher = dispatcher
    }

    /**
     * Register activity implementations.
     * Automatically detects suspend functions and creates appropriate handlers.
     */
    public fun registerActivitiesImplementations(vararg activityImplementations: Any) {
        for (impl in activityImplementations) {
            val activityInterfaces = findActivityInterfaces(impl::class)

            for (iface in activityInterfaces) {
                for (method in iface.memberFunctions) {
                    if (isActivityMethod(method)) {
                        if (method.isSuspend) {
                            // Create suspend-aware invoker
                            val invoker = SuspendActivityInvoker(
                                activityInstance = impl,
                                method = method,
                                dispatcher = activityDispatcher,
                                heartbeatInterval = defaultHeartbeatInterval
                            )
                            registerSuspendActivity(method, invoker)
                        } else {
                            // Use existing POJO registration
                            registerPOJOActivity(method, impl)
                        }
                    }
                }
            }
        }
    }

    private fun registerSuspendActivity(method: KFunction<*>, invoker: SuspendActivityInvoker) {
        // Create a wrapper that the Java SDK can invoke
        val wrapper = object : ActivityMethod {
            fun execute(context: ActivityExecutionContext, args: Array<Any?>): Any? {
                return invoker.invoke(context, args)
            }
        }
        // Register with Java SDK's activity registry
        // ... registration logic
    }
}
```

## Thread/Coroutine Flow Diagram

```
Timeline:
─────────────────────────────────────────────────────────────────────────────►

Thread Pool Thread #1:
│
├─ Poll for task ─────────────────────────────────────────────────────────────
│   │
│   ├─ Receive activity task
│   │   │
│   │   ├─ Call SuspendActivityInvoker.invoke()
│   │   │   │
│   │   │   ├─ Get ManualActivityCompletionClient
│   │   │   ├─ Launch coroutine (async!)
│   │   │   └─ Return immediately
│   │   │
│   │   └─ Thread freed! ◄─────────────────────
│   │
│   └─ Poll for next task ────────────────────────────────────────────────────

Coroutine on Dispatcher:
                    │
                    ├─ Start executing suspend fun
                    │   │
                    │   ├─ Await HTTP call (suspend)
                    │   │   │
                    │   │   └─ Thread released while waiting
                    │   │
                    │   ├─ Resume on HTTP response
                    │   │   │
                    │   │   └─ Continue processing
                    │   │
                    │   └─ Return result
                    │
                    ├─ Call client.complete(result)
                    │   │
                    │   └─ gRPC to server (on Dispatchers.IO)
                    │
                    └─ Slot permit released
```

## Usage Examples

### Example 1: Basic Suspend Activity

```kotlin
@ActivityInterface
interface HttpActivities {
    suspend fun fetchUser(userId: String): User
}

class HttpActivitiesImpl(
    private val client: HttpClient  // Ktor client
) : HttpActivities {

    override suspend fun fetchUser(userId: String): User {
        // Non-blocking HTTP call - thread is released during I/O wait
        return client.get("https://api.example.com/users/$userId").body()
    }
}
```

### Example 2: Activity with Heartbeat

```kotlin
@ActivityInterface
interface BatchActivities {
    suspend fun processBatch(items: List<Item>): BatchResult
}

class BatchActivitiesImpl : BatchActivities {

    override suspend fun processBatch(items: List<Item>): BatchResult {
        val results = mutableListOf<ItemResult>()

        for ((index, item) in items.withIndex()) {
            // Process item asynchronously
            val result = processItem(item)
            results.add(result)

            // Non-blocking heartbeat - throws CancellationException if cancelled
            KActivity.heartbeat(Progress(index + 1, items.size))
        }

        return BatchResult(results)
    }

    private suspend fun processItem(item: Item): ItemResult {
        // Async processing using Ktor, R2DBC, etc.
        delay(100)  // Simulated async work
        return ItemResult(item.id, "processed")
    }
}
```

### Example 3: Mixed Activities (Suspend and Regular)

```kotlin
@ActivityInterface
interface MixedActivities {
    // Regular activity - runs on thread pool, blocks during execution
    fun computeHash(data: ByteArray): String

    // Suspend activity - thread freed during I/O
    suspend fun fetchRemoteData(url: String): ByteArray
}

class MixedActivitiesImpl : MixedActivities {

    // CPU-bound work - regular function is fine (uses thread pool)
    override fun computeHash(data: ByteArray): String {
        return MessageDigest.getInstance("SHA-256")
            .digest(data)
            .toHexString()
    }

    // I/O-bound work - suspend function for efficiency
    override suspend fun fetchRemoteData(url: String): ByteArray {
        return httpClient.get(url).body()
    }
}
```

### Example 4: Database Activity with R2DBC

```kotlin
@ActivityInterface
interface DatabaseActivities {
    suspend fun findUser(id: Long): User?
    suspend fun saveUser(user: User): Long
}

class DatabaseActivitiesImpl(
    private val connectionFactory: ConnectionFactory  // R2DBC
) : DatabaseActivities {

    override suspend fun findUser(id: Long): User? {
        return connectionFactory.create().awaitSingle().use { conn ->
            conn.createStatement("SELECT * FROM users WHERE id = $1")
                .bind("$1", id)
                .execute()
                .awaitFirst()
                .map { row -> row.toUser() }
                .awaitFirstOrNull()
        }
    }

    override suspend fun saveUser(user: User): Long {
        return connectionFactory.create().awaitSingle().use { conn ->
            conn.createStatement(
                "INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id"
            )
                .bind("$1", user.name)
                .bind("$2", user.email)
                .execute()
                .awaitFirst()
                .map { row -> row.get("id", Long::class.java)!! }
                .awaitFirst()
        }
    }
}
```

### Example 5: Parallel Async Operations

```kotlin
@ActivityInterface
interface AggregatorActivities {
    suspend fun aggregateData(sources: List<String>): AggregatedResult
}

class AggregatorActivitiesImpl : AggregatorActivities {

    override suspend fun aggregateData(sources: List<String>): AggregatedResult {
        // Fetch from all sources in parallel - truly concurrent!
        val results = coroutineScope {
            sources.map { source ->
                async {
                    fetchFromSource(source)
                }
            }.awaitAll()
        }

        return AggregatedResult(results)
    }

    private suspend fun fetchFromSource(source: String): SourceData {
        return httpClient.get(source).body()
    }
}
```

## Cancellation Handling

### Cancellation Flow

```
Server sends cancellation
         │
         ▼
┌─────────────────────────────────────┐
│ Heartbeat throws CanceledFailure     │
│ (either auto-heartbeat or manual)    │
└───────────────────┬─────────────────┘
                    │
                    ▼
┌─────────────────────────────────────┐
│ parentJob.cancel() called            │
│ - Cancels main coroutine             │
│ - Cancels all child coroutines       │
└───────────────────┬─────────────────┘
                    │
                    ▼
┌─────────────────────────────────────┐
│ CancellationException propagates     │
│ through coroutine hierarchy          │
└───────────────────┬─────────────────┘
                    │
                    ▼
┌─────────────────────────────────────┐
│ Caught in SuspendActivityInvoker     │
│ - Reports cancellation to server     │
│ - Releases slot permit               │
└─────────────────────────────────────┘
```

### Cancellation Detection Options

1. **Auto-heartbeat** (recommended for long-running activities):
   - Configure heartbeat interval at registration
   - Background job periodically heartbeats
   - Cancellation detected within heartbeat interval

2. **Manual heartbeat**:
   - Activity explicitly calls `KActivity.heartbeat()`
   - Cancellation detected at heartbeat points

3. **Polling check** (for tight loops):
   ```kotlin
   suspend fun processItems(items: List<Item>) {
       for (item in items) {
           ensureActive()  // Check for cancellation
           process(item)
       }
   }
   ```

## Coroutine Dispatcher: Thread Model

### Where Do Coroutine Threads Come From?

When a suspend activity is invoked, the coroutine runs on threads provided by a `CoroutineDispatcher`.
This is a **separate thread pool** from the Java SDK's activity executor thread pool.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        JAVA SDK THREAD POOL                                  │
│                    (ActivityWorker's executor)                               │
│                                                                              │
│   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐                        │
│   │Thread-1 │  │Thread-2 │  │Thread-3 │  │Thread-4 │  ...                   │
│   └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘                        │
│        │            │            │            │                              │
│        │ poll()     │ poll()     │ poll()     │ poll()                       │
│        │            │            │            │                              │
│        ▼            │            │            │                              │
│   invoke() ─────────┼────────────┼────────────┼──────────────────────┐      │
│        │            │            │            │                      │      │
│        │ launch()   │            │            │                      │      │
│        │            │            │            │                      │      │
│        ▼            │            │            │                      │      │
│   return (FREE!)    │            │            │                      │      │
│        │            │            │            │                      │      │
│        ▼            │            │            │                      │      │
│   poll() again      │            │            │                      │      │
│                     │            │            │                      │      │
└─────────────────────┼────────────┼────────────┼──────────────────────┼──────┘
                      │            │            │                      │
                      │            │            │                      │
┌─────────────────────┼────────────┼────────────┼──────────────────────┼──────┐
│                     │            │            │                      │      │
│              COROUTINE DISPATCHER THREAD POOL                        │      │
│                    (Kotlin coroutine threads)                        │      │
│                                                                      │      │
│   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐                │      │
│   │ Coro-1  │  │ Coro-2  │  │ Coro-3  │  │ Coro-4  │  ...           │      │
│   └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘                │      │
│        │            │            │            │                      │      │
│        ◄────────────┼────────────┼────────────┼──────────────────────┘      │
│        │            │            │            │                              │
│        ▼            │            │            │                              │
│   Execute suspend   │            │            │                              │
│   function          │            │            │                              │
│        │            │            │            │                              │
│   (suspend on I/O)  │            │            │                              │
│        │            │            │            │                              │
│        ▼            │            │            │                              │
│   Thread released   │            │            │                              │
│        .            │            │            │                              │
│        .            │            │            │                              │
│        . (waiting)  │            │            │                              │
│        .            │            │            │                              │
│        ▼            │            │            │                              │
│   Resume on Coro-3 ─┼────────────►            │                              │
│                     │            │            │                              │
│                     │            ▼            │                              │
│                     │   Continue execution    │                              │
│                     │            │            │                              │
│                     │            ▼            │                              │
│                     │   complete(result)      │                              │
│                     │            │            │                              │
└─────────────────────┴────────────┴────────────┴──────────────────────────────┘
```

**Key point**: The coroutine can start on one thread (Coro-1), suspend, and resume on a completely
different thread (Coro-3). This is normal Kotlin coroutine behavior.

### Built-in Dispatchers

Kotlin provides several built-in dispatchers:

| Dispatcher | Thread Pool | Size | Best For |
|------------|-------------|------|----------|
| `Dispatchers.Default` | Shared, fixed | CPU cores (min 2) | CPU-bound + async I/O |
| `Dispatchers.IO` | Shared, elastic | Up to 64+ threads | Blocking I/O calls |
| `Dispatchers.Unconfined` | Caller's thread | N/A | Testing only |

```kotlin
// Dispatchers.Default - recommended for most cases
// Backed by a shared ForkJoinPool
val dispatcher = Dispatchers.Default

// Dispatchers.IO - for blocking calls within suspend functions
// Shares threads with Default but can grow larger
val dispatcher = Dispatchers.IO

// Limited parallelism - caps concurrent coroutines
val dispatcher = Dispatchers.Default.limitedParallelism(100)
```

### Custom Dispatcher from Java Executor

You can create a dispatcher from any Java `Executor` or `ExecutorService`:

```kotlin
import kotlinx.coroutines.asCoroutineDispatcher
import java.util.concurrent.Executors

// From a fixed thread pool
val executor = Executors.newFixedThreadPool(50)
val dispatcher = executor.asCoroutineDispatcher()

// From a cached thread pool (elastic)
val executor = Executors.newCachedThreadPool()
val dispatcher = executor.asCoroutineDispatcher()

// From a custom ThreadPoolExecutor
val executor = ThreadPoolExecutor(
    10,      // core pool size
    100,     // max pool size
    60L,     // keep-alive time
    TimeUnit.SECONDS,
    LinkedBlockingQueue()
)
val dispatcher = executor.asCoroutineDispatcher()

// IMPORTANT: Remember to close the dispatcher when done
dispatcher.close()  // Also shuts down the executor
```

### Configuration API

```kotlin
// Option 1: Use built-in dispatcher (simplest)
val worker = factory.newWorker("my-task-queue") {
    suspendActivityDispatcher = Dispatchers.Default
}

// Option 2: Limited parallelism for backpressure
val worker = factory.newWorker("my-task-queue") {
    // Max 100 concurrent suspend activities
    suspendActivityDispatcher = Dispatchers.Default.limitedParallelism(100)
}

// Option 3: Custom executor for full control
val activityExecutor = Executors.newFixedThreadPool(200)
val worker = factory.newWorker("my-task-queue") {
    suspendActivityDispatcher = activityExecutor.asCoroutineDispatcher()
}

// Option 4: Match Java SDK's activity thread pool size
val worker = factory.newWorker("my-task-queue") {
    val maxConcurrent = workerOptions.maxConcurrentActivityExecutionSize
    suspendActivityDispatcher = Dispatchers.Default.limitedParallelism(maxConcurrent)
}
```

### Dispatcher Lifecycle Management

```kotlin
class KWorkerFactory(client: KWorkflowClient) : Closeable {

    private var customDispatcher: CloseableCoroutineDispatcher? = null

    fun newWorker(taskQueue: String, configure: WorkerConfig.() -> Unit): KWorker {
        val config = WorkerConfig().apply(configure)

        // Track custom dispatchers for cleanup
        if (config.suspendActivityDispatcher is CloseableCoroutineDispatcher) {
            customDispatcher = config.suspendActivityDispatcher
        }

        // ...
    }

    override fun close() {
        // Clean up custom dispatchers
        customDispatcher?.close()
        // ...
    }
}
```

### Thread Flow Example

```
Time ──────────────────────────────────────────────────────────────────────────►

Java SDK Thread Pool (4 threads):
┌──────────────────────────────────────────────────────────────────────────────┐
│ T1: [poll]──[invoke]──[return]──[poll]──[invoke]──[return]──[poll]──...     │
│ T2: [poll]──────────────────────[invoke]──[return]──[poll]──...             │
│ T3: [poll]──[invoke]──[return]──[poll]──...                                 │
│ T4: [poll]──────────────────────────────[invoke]──[return]──[poll]──...     │
└──────────────────────────────────────────────────────────────────────────────┘
         │         │                   │                   │
         │ launch  │ launch            │ launch            │ launch
         ▼         ▼                   ▼                   ▼

Coroutine Dispatcher (separate pool):
┌──────────────────────────────────────────────────────────────────────────────┐
│ C1: [run]─[suspend]─────────────[resume]─[complete]                         │
│ C2:       [run]─[suspend]───────────────────────[resume]─[suspend]─[resume] │
│ C3:                      [run]─[complete]                                    │
│ C4:                             [run]─[suspend]─────────[resume]─[complete]  │
└──────────────────────────────────────────────────────────────────────────────┘

Legend:
- [poll]    = Waiting for activity task from server
- [invoke]  = Calling SuspendActivityInvoker.invoke()
- [return]  = Method returns, thread freed
- [launch]  = Coroutine scheduled on dispatcher
- [run]     = Coroutine executing code
- [suspend] = Coroutine suspended (waiting for I/O)
- [resume]  = Coroutine resumed after I/O
- [complete]= Activity completed via ManualActivityCompletionClient
```

### Recommendations

1. **Start with `Dispatchers.Default`** - It's well-tuned for most workloads

2. **Use `limitedParallelism()` for backpressure** - Prevents unbounded coroutine growth:
   ```kotlin
   Dispatchers.Default.limitedParallelism(maxConcurrentActivities)
   ```

3. **Use `Dispatchers.IO` for blocking calls** - If your suspend activity must call blocking APIs:
   ```kotlin
   suspend fun myActivity() {
       withContext(Dispatchers.IO) {
           // Blocking call here won't block Default dispatcher
           legacyBlockingApi.call()
       }
   }
   ```

4. **Custom executor for isolation** - If you need suspend activities isolated from other coroutines:
   ```kotlin
   val dedicatedExecutor = Executors.newFixedThreadPool(50)
   val dedicatedDispatcher = dedicatedExecutor.asCoroutineDispatcher()
   ```

## Heartbeat Configuration

```kotlin
val worker = factory.newWorker("my-task-queue") {
    // Dispatcher for suspend activities
    suspendActivityDispatcher = Dispatchers.Default.limitedParallelism(100)

    // Auto-heartbeat interval for suspend activities (optional)
    // If set, a background coroutine sends heartbeats automatically
    suspendActivityHeartbeatInterval = 30.seconds
}

// Per-activity configuration via annotation (future enhancement)
@SuspendActivityOptions(
    heartbeatInterval = "10s"
)
suspend fun myActivity(): Result
```

## Implementation Plan

### Phase 1: Core Infrastructure
1. Create `SuspendActivityInvoker` class
2. Create `KActivityExecutionContext` with coroutine support
3. Create `KActivityExecutionContextElement` for coroutine context
4. Implement basic suspend activity execution

### Phase 2: Cancellation Handling
1. Implement auto-heartbeat background job
2. Map `CanceledFailure` to coroutine cancellation
3. Ensure proper cleanup on cancellation

### Phase 3: Activity Registration
1. Detect suspend functions at registration time
2. Create `SuspendActivityInvoker` for suspend methods
3. Register with Java SDK's activity framework

### Phase 4: API and Configuration
1. Update `KActivity` API for coroutine support
2. Add dispatcher configuration options
3. Add heartbeat interval configuration

### Phase 5: Testing
1. Unit tests for suspend activity execution
2. Integration tests with real async I/O (Ktor)
3. Cancellation handling tests
4. Concurrent execution tests

## Comparison: Old Design vs New Design

| Aspect | Old Design (runBlocking) | New Design (useLocalManualCompletion) |
|--------|--------------------------|---------------------------------------|
| Thread during suspend | **Blocked** | **Free** |
| I/O efficiency | Low | High |
| Concurrent activities | Limited by threads | Limited by coroutines (much higher) |
| Java SDK changes | None needed | None needed |
| Complexity | Lower | Moderate |
| Cancellation | Immediate | Within heartbeat interval |

## Considerations

### Dispatcher Selection

**Dispatchers.Default** (recommended):
- Shared thread pool sized to CPU cores
- Good for mixed CPU/IO workloads
- Can be limited with `limitedParallelism(n)`

**Dispatchers.IO**:
- Elastic thread pool for blocking I/O
- Overhead of thread creation
- Use if calling blocking APIs from suspend context

**Custom dispatcher**:
- Full control over thread pool
- Can match `maxConcurrentActivityExecutionSize` for parity

### Heartbeat Timing

The cancellation detection latency equals the heartbeat interval. For activities that need fast cancellation response:
- Use shorter heartbeat intervals (e.g., 5 seconds)
- Or call `KActivity.heartbeat()` explicitly at key points

### Error Handling

| Exception Type | Handling |
|----------------|----------|
| Regular exception | `client.fail(e)` - Activity fails, may retry |
| `CancellationException` | `client.reportCancellation(null)` - Clean cancellation |
| Error during completion | Logged, slot released, activity marked failed |

### Structured Concurrency

Activities can use `coroutineScope` for structured concurrency:
```kotlin
suspend fun processInParallel(items: List<Item>): List<Result> {
    return coroutineScope {
        items.map { async { process(it) } }.awaitAll()
    }
}
```

All child coroutines are cancelled if the activity is cancelled.

## Open Questions

1. **Default heartbeat interval**: Should we have a default auto-heartbeat interval for suspend activities, or require explicit configuration?

2. **Exception translation**: Should we map specific Kotlin exceptions (e.g., `TimeoutCancellationException`) to specific Temporal failures?

3. **Context propagation**: How to propagate MDC/tracing context through coroutines?

4. **Metrics**: Should we expose coroutine-specific metrics (active coroutines, suspension points)?

## Conclusion

This design leverages the existing `useLocalManualCompletion()` pattern in the Java SDK to achieve truly non-blocking suspend activities. Key benefits:

- **No thread blocking**: Executor thread is freed immediately after launching coroutine
- **High concurrency**: Can run many more concurrent I/O-bound activities than threads
- **No Java SDK changes**: Works with existing infrastructure
- **Kotlin-idiomatic**: Uses standard coroutine patterns and context
- **Backward compatible**: Regular (non-suspend) activities continue to work unchanged

The approach provides efficient async I/O support while maintaining Temporal's reliability guarantees for activity execution, retries, and timeouts.
