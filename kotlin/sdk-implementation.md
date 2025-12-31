# Kotlin SDK Implementation Details

This document describes the internal architecture and implementation details for the Temporal Kotlin SDK.

For public API and developer experience, see [sdk-api.md](./sdk-api.md).

## Phases

* **Phase 1** - Coroutine-based workflows, untyped activity stubs, pluggable WorkflowImplementationFactory, core Kotlin idioms (Duration, null safety)
* **Phase 2** - Typed activity stubs with suspend functions, signals/queries/updates, child workflows, property queries
* **Phase 3** - Testing framework

> **Note:** Nexus support is a separate project and will be addressed independently.

## Relationship to Java SDK

The Kotlin SDK builds on top of the Java SDK rather than replacing it:

* **Shared infrastructure**: Uses the same gRPC client, data conversion, and service client
* **Interoperability**: Kotlin workflows can call Java activities and vice versa
* **Gradual adoption**: Teams can mix Java and Kotlin workflows in the same worker
* **Existing module**: Extends the existing `temporal-kotlin` module which already provides DSL extensions

## Repository/Package Strategy

### Repository

The Kotlin SDK will continue to live in the `temporal-kotlin` module within the `sdk-java` repository:

* Pros:
  * Shared build infrastructure
  * Easier to maintain version compatibility
  * Single release process
* Cons:
  * Ties Kotlin SDK releases to Java SDK releases

### Package Naming

* Core workflow APIs: `io.temporal.kotlin.workflow`
* Worker APIs: `io.temporal.kotlin.worker`
* Interceptors: `io.temporal.kotlin.interceptors`
* Existing extensions remain in their current packages (e.g., `io.temporal.client`)

### Maven Artifacts

```xml
<dependency>
  <groupId>io.temporal</groupId>
  <artifactId>temporal-kotlin</artifactId>
  <version>N.N.N</version>
</dependency>
```

Additional dependency on kotlinx-coroutines:
```xml
<dependency>
  <groupId>org.jetbrains.kotlinx</groupId>
  <artifactId>kotlinx-coroutines-core</artifactId>
  <version>1.7.x</version>
</dependency>
```

## Existing Kotlin Classes (Retained)

The `temporal-kotlin` module already provides Kotlin extensions for the Java SDK:

| File | Purpose | Status |
|------|---------|--------|
| `TemporalDsl.kt` | `@DslMarker` for type-safe builders | **Keep as-is** |
| `*OptionsExt.kt` (15 files) | DSL builders for all Options classes | **Keep as-is** |
| `WorkflowClientExt.kt` | Reified `newWorkflowStub<T>()`, DSL extensions | **Keep as-is** |
| `WorkflowStubExt.kt` | Reified `getResult<T>()` | **Keep as-is** |
| `WorkerFactoryExt.kt` | `WorkerFactory()` constructor-like DSL | **Keep as-is** |
| `WorkerExt.kt` | Reified `registerWorkflowImplementationType<T>()` | **Keep as-is** |
| `WorkflowMetadata.kt` | `workflowName<T>()`, `workflowSignalName()` | **Keep as-is** |
| `ActivityMetadata.kt` | `activityName(Interface::method)` | **Keep as-is** |
| `KotlinObjectMapperFactory.kt` | Jackson ObjectMapper for Kotlin | **Keep as-is** |
| `KotlinMethodReferenceDisassemblyService.kt` | Kotlin method references in `Async` | **Keep as-is** |

## New Classes (Kotlin SDK)

| Class | Purpose |
|-------|---------|
| **Core Workflow** | |
| `KWorkflow` | Entry point for workflow APIs (like `Workflow` in Java) |
| `KotlinWorkflowContext` | Internal workflow execution context |
| `KotlinCoroutineDispatcher` | Deterministic coroutine dispatcher with `Delay` implementation |
| `KWorkerInterceptor` | Interceptor interface with suspend functions |
| **Factory/Registration** | |
| `KotlinPlugin` | Plugin for enabling coroutine support and registering interceptors |
| `KotlinWorkflowImplementationFactory` | Implements `WorkflowImplementationFactory` for coroutine workflows |
| `KotlinWorkflowDefinition` | Metadata about a Kotlin workflow type |
| `KotlinReplayWorkflow` | Implements `ReplayWorkflow` using coroutines |
| `WorkerExt.kt` (additions) | Extension `registerKotlinWorkflowImplementationTypes()` |
| **Kotlin Wrappers** | |
| `KWorkflowInfo` | Kotlin wrapper for WorkflowInfo with nullable types |
| `KActivityInfo` | Kotlin wrapper for ActivityInfo with nullable types |
| `KActivityContext` | Kotlin wrapper for ActivityExecutionContext |
| `WorkflowHandle` | Untyped workflow handle (string-based signals/queries) |
| `KWorkflowHandle<T>` | Typed workflow handle for signals/queries/updates |
| `KTypedWorkflowHandle<T, R>` | Extends KWorkflowHandle with typed result (returned by startWorkflow) |
| `KUpdateHandle<R>` | Handle for async update execution |
| **Extensions** | |
| `DurationExt.kt` | Conversions between `kotlin.time.Duration` and `java.time.Duration` |
| `PromiseExt.kt` | `Promise<T>.toDeferred()` to bridge Java SDK to standard coroutines |

> **Note:** We deliberately **do not** have `KActivityHandle<R>` or `KChildWorkflowHandle<R>`. Instead, users use standard `coroutineScope { async { } }` with `Deferred<T>` for parallel execution. This follows the design principle of using idiomatic Kotlin patterns instead of custom APIs.

## Unified Worker Architecture

The SDK uses a **single unified `WorkerFactory`** that supports both Java and Kotlin workflows. The execution model (thread-based vs coroutine-based) is determined **per workflow instance**, not per worker. This is achieved through a pluggable `WorkflowImplementationFactory` interface.

```
┌─────────────────────────────────────────────────────────┐
│                   WorkerFactory                         │
│                                                         │
│  registerWorkflowImplementationTypes(...)  ─────────┐   │
│  registerWorkflowImplementationFactory(...)         │   │
│                                                     ▼   │
│  ┌─────────────────────────────────────────────────┐   │
│  │     WorkflowImplementationFactory Registry      │   │
│  │                                                 │   │
│  │  ┌─────────────────┐  ┌──────────────────────┐ │   │
│  │  │ POJOWorkflow    │  │ KotlinWorkflow       │ │   │
│  │  │ Implementation  │  │ Implementation       │ │   │
│  │  │ Factory         │  │ Factory              │ │   │
│  │  │ (Java SDK)      │  │ (temporal-kotlin)    │ │   │
│  │  └────────┬────────┘  └──────────┬───────────┘ │   │
│  └───────────┼──────────────────────┼─────────────┘   │
└──────────────┼──────────────────────┼─────────────────┘
               │                      │
               ▼                      ▼
┌──────────────────────┐  ┌──────────────────────────────┐
│ Java workflow task   │  │ Kotlin workflow task         │
│                      │  │                              │
│ → DeterministicRunner│  │ → KotlinCoroutineDispatcher│
│ → Thread-based exec  │  │ → Coroutine-based exec       │
└──────────────────────┘  └──────────────────────────────┘
```

**Key benefits:**

| Benefit | Description |
|---------|-------------|
| Single worker type | No need for separate `KotlinWorkerFactory` |
| Mixed workflows | Java and Kotlin workflows on the same task queue |
| Gradual migration | Convert workflows one at a time |
| No Kotlin in Java SDK | All coroutine code stays in `temporal-kotlin` |
| Per-instance execution | Dispatcher is per workflow instance, not per worker |

## Java SDK Refactoring for Pluggability

To support the Kotlin coroutine-based execution model, the Java SDK requires refactoring to make workflow execution pluggable. The key principle is that the Java SDK remains **completely Kotlin-agnostic**—it only provides extension points that the `temporal-kotlin` module can use.

### Required Changes to `temporal-sdk`

#### 1. New `WorkflowImplementationFactory` Interface

**File:** `io.temporal.worker.WorkflowImplementationFactory` (new)

A pluggable interface for creating workflow instances with different execution models:

```java
/**
 * Factory for creating workflow implementations. Different implementations
 * can provide different execution models (e.g., thread-based, coroutine-based).
 */
public interface WorkflowImplementationFactory {
    /**
     * Returns true if this factory handles the given workflow implementation type.
     * Used to route workflow registration to the appropriate factory.
     */
    boolean supportsType(Class<?> workflowImplementationType);

    /**
     * Register workflow implementation types with this factory.
     */
    void registerWorkflowImplementationTypes(
        WorkflowImplementationOptions options,
        Class<?>... workflowImplementationTypes
    );

    /**
     * Register a workflow implementation factory function.
     */
    <R> void addWorkflowImplementationFactory(
        WorkflowImplementationOptions options,
        Class<R> workflowInterface,
        Functions.Func<R> factory
    );

    /**
     * Create a ReplayWorkflow instance for the given workflow type.
     * Returns null if this factory doesn't handle the given type.
     */
    @Nullable
    ReplayWorkflow createWorkflow(
        WorkflowType workflowType,
        WorkflowExecution workflowExecution
    );

    /**
     * Returns the set of workflow types registered with this factory.
     */
    Set<String> getRegisteredWorkflowTypes();
}
```

#### 2. Update `Worker` to Support Multiple Factories

**File:** `io.temporal.worker.Worker`

```java
public final class Worker {
    // Default factory for Java workflows (existing behavior)
    private final POJOWorkflowImplementationFactory defaultFactory;

    // Additional factories (e.g., for Kotlin coroutine workflows)
    private final List<WorkflowImplementationFactory> additionalFactories = new ArrayList<>();

    /**
     * Register a custom workflow implementation factory.
     * The factory will be consulted for workflow types it supports.
     */
    public void registerWorkflowImplementationFactory(WorkflowImplementationFactory factory) {
        additionalFactories.add(factory);
    }

    // Existing method unchanged - uses default POJO factory
    public void registerWorkflowImplementationTypes(Class<?>... workflowImplementationTypes) {
        defaultFactory.registerWorkflowImplementationTypes(options, workflowImplementationTypes);
    }
}
```

#### 3. Update `SyncWorkflowWorker` to Use Factory Registry

**File:** `io.temporal.internal.worker.SyncWorkflowWorker`

Modify to consult all registered factories when creating workflow instances:

```java
class CompositeReplayWorkflowFactory implements ReplayWorkflowFactory {
    private final POJOWorkflowImplementationFactory defaultFactory;
    private final List<WorkflowImplementationFactory> additionalFactories;

    @Override
    public ReplayWorkflow getWorkflow(WorkflowType workflowType, WorkflowExecution execution) {
        // First, check additional factories
        for (WorkflowImplementationFactory factory : additionalFactories) {
            ReplayWorkflow workflow = factory.createWorkflow(workflowType, execution);
            if (workflow != null) {
                return workflow;
            }
        }
        // Fall back to default POJO factory
        return defaultFactory.getWorkflow(workflowType, execution);
    }

    @Override
    public boolean isAnyTypeSupported() {
        return defaultFactory.isAnyTypeSupported() ||
            additionalFactories.stream().anyMatch(f -> !f.getRegisteredWorkflowTypes().isEmpty());
    }
}
```

#### 4. Expose Required Internal Classes

Some internal classes need to be accessible for custom `WorkflowImplementationFactory` implementations:

**File:** `io.temporal.internal.replay.ReplayWorkflow` → Move to SPI package or make accessible

```java
// Either move to io.temporal.worker.spi or document as semi-public API
public interface ReplayWorkflow {
    void start(HistoryEvent event, ReplayWorkflowContext context);
    boolean eventLoop() throws Throwable;
    WorkflowExecutionResult getOutput();
    void cancel(String reason);
    void close();
    // ... other methods
}
```

**File:** `io.temporal.internal.replay.ReplayWorkflowContext` → Similar treatment

The exact approach (SPI package vs `@InternalApi` annotation) is discussed in [Open Question #6: SPI Stability](#6-spi-stability).

#### 5. Add Async Version of `Workflow.await()`

**File:** `io.temporal.workflow.Async`

The existing `Workflow.await()` is blocking with no `Promise`-based equivalent. To support Kotlin coroutines, we need an async version in the `Async` class (consistent with `Async.function()`, `Async.procedure()`, etc.):

```java
public final class Async {
    // Existing methods
    public static <R> Promise<R> function(Functions.Func<R> func);
    public static Promise<Void> procedure(Functions.Proc proc);
    // ...

    // New async await methods for coroutine support
    public static Promise<Void> await(Supplier<Boolean> condition);
    public static Promise<Boolean> await(Duration timeout, Supplier<Boolean> condition);
}
```

This allows Kotlin to wrap it as a suspend function in `KWorkflow`:

```kotlin
/**
 * Suspends until the condition becomes true.
 *
 * This is the Kotlin equivalent of Java's [Workflow.await].
 * The condition is re-evaluated after each workflow event.
 */
suspend fun condition(condition: () -> Boolean) {
    Async.await { condition() }.await()  // Promise.await() suspends
}

/**
 * Suspends until the condition becomes true or timeout expires.
 *
 * This is the Kotlin equivalent of Java's [Workflow.await] with timeout.
 *
 * @return true if condition became true, false if timed out
 */
suspend fun awaitCondition(timeout: Duration, condition: () -> Boolean): Boolean {
    return Async.await(timeout.toJava()) { condition() }.await()
}
```

**Implementation notes:**
- **Prerequisite:** `Async.await()` does not currently exist in the Java SDK and must be added before `KWorkflow.awaitCondition()` can be implemented.
- Under the hood, this uses `Async.await()` which returns a `Promise` that completes when the condition becomes true. The condition is re-evaluated after each workflow event (signals, activity completions, timers, etc.).
- The async version should integrate with the same condition-tracking mechanism used by the blocking `Workflow.await()`, completing the Promise when the condition becomes true or timeout expires.

### Files Changed Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `WorkflowImplementationFactory.java` | **New** | Pluggable factory interface |
| `Worker.java` | **Modified** | Add `registerWorkflowImplementationFactory()` method |
| `SyncWorkflowWorker.java` | **Modified** | Use composite factory for workflow creation |
| `ReplayWorkflow.java` | **Modified** | Make accessible for SPI implementations |
| `ReplayWorkflowContext.java` | **Modified** | Make accessible for SPI implementations |
| `POJOWorkflowImplementationFactory.java` | **Modified** | Implement new interface |
| `Async.java` | **Modified** | Add `await()` methods returning `Promise` |

### Backward Compatibility

These changes maintain full backward compatibility:

* `Worker.registerWorkflowImplementationTypes()` unchanged for existing users
* Existing Java workflows continue to work without modification
* New `registerWorkflowImplementationFactory()` is purely additive
* No Kotlin dependencies in `temporal-sdk` module
* No breaking changes to public APIs

## Kotlin Module Implementation

The `temporal-kotlin` module provides the coroutine-based implementation:

```kotlin
// In temporal-kotlin module
class KotlinWorkflowImplementationFactory(
    private val clientOptions: WorkflowClientOptions,
    private val workerOptions: WorkerOptions,
    private val cache: WorkflowExecutorCache
) : WorkflowImplementationFactory {

    private val registeredTypes = mutableMapOf<String, KotlinWorkflowDefinition>()

    override fun supportsType(type: Class<*>): Boolean {
        // Check if workflow methods are suspend functions (have Continuation parameter)
        return type.methods.any { method ->
            method.isAnnotationPresent(WorkflowMethod::class.java) &&
            method.parameterTypes.any { it.name == "kotlin.coroutines.Continuation" }
        }
    }

    override fun registerWorkflowImplementationTypes(
        options: WorkflowImplementationOptions,
        vararg types: Class<*>
    ) {
        for (type in types) {
            require(supportsType(type)) {
                "Class ${type.name} does not have suspend workflow methods"
            }
            val definition = KotlinWorkflowDefinition(type, options)
            registeredTypes[definition.workflowType] = definition
        }
    }

    override fun createWorkflow(
        workflowType: WorkflowType,
        workflowExecution: WorkflowExecution
    ): ReplayWorkflow? {
        val definition = registeredTypes[workflowType.name] ?: return null
        return KotlinReplayWorkflow(
            definition,
            workflowExecution,
            KotlinCoroutineDispatcher()
        )
    }

    override fun getRegisteredWorkflowTypes(): Set<String> = registeredTypes.keys
}
```

```kotlin
// Kotlin extension for ergonomic registration
fun Worker.registerKotlinWorkflowImplementationTypes(vararg types: KClass<*>) {
    val factory = KotlinWorkflowImplementationFactory(/* obtain from worker */)
    for (type in types) {
        factory.registerWorkflowImplementationTypes(
            WorkflowImplementationOptions.getDefaultInstance(),
            type.java
        )
    }
    registerWorkflowImplementationFactory(factory)
}
```

## KotlinCoroutineDispatcher

The custom dispatcher ensures deterministic execution of coroutines and implements the `Delay` interface to intercept standard `kotlinx.coroutines.delay()` calls:

* Executes coroutines in a controlled, deterministic order (FIFO queue)
* Integrates with Temporal's replay mechanism
* **Implements `Delay` interface** - standard `delay()` is automatically routed through Temporal timers
* Handles cancellation scopes properly
* All coroutines launched with this dispatcher inherit deterministic behavior

```kotlin
internal class KotlinCoroutineDispatcher(
    private val workflowContext: KotlinWorkflowContext
) : CoroutineDispatcher(), Delay {

    private val readyQueue = ArrayDeque<Runnable>()
    private var inEventLoop = false

    override fun dispatch(context: CoroutineContext, block: Runnable) {
        // Queue for deterministic execution
        readyQueue.addLast(block)

        // If we're already in the event loop, the block will be picked up
        // Otherwise, we need to signal the workflow to continue
        if (!inEventLoop) {
            workflowContext.signalReady()
        }
    }

    /**
     * Intercept standard delay() calls and route through Temporal timer.
     * This allows users to write `delay(5.seconds)` and have it work deterministically.
     */
    override fun scheduleResumeAfterDelay(
        timeMillis: Long,
        continuation: CancellableContinuation<Unit>
    ) {
        workflowContext.scheduleTimer(timeMillis) {
            continuation.resume(Unit)
        }
    }

    /**
     * Process queued coroutines deterministically.
     * Called by the replay machinery during workflow task processing.
     */
    fun eventLoop(deadlockDetectionTimeout: Long): Boolean {
        inEventLoop = true
        try {
            val deadline = System.currentTimeMillis() + deadlockDetectionTimeout

            while (readyQueue.isNotEmpty()) {
                if (System.currentTimeMillis() > deadline) {
                    throw PotentialDeadlockException("Workflow thread stuck")
                }

                val runnable = readyQueue.removeFirst()
                runnable.run()
            }

            return workflowContext.hasMoreWork()
        } finally {
            inEventLoop = false
        }
    }
}
```

### Delay Implementation

The `Delay` interface implementation is integrated directly into `KotlinCoroutineDispatcher` (shown above). This allows standard `kotlinx.coroutines.delay()` to work deterministically:

```kotlin
// Users write standard Kotlin:
delay(5.seconds)

// The dispatcher's scheduleResumeAfterDelay is called automatically,
// which routes through Temporal's deterministic timer mechanism
```

**Why this works:**
- When a coroutine calls `delay()`, kotlinx.coroutines checks if the dispatcher implements `Delay`
- If it does, `scheduleResumeAfterDelay` is called instead of blocking
- Our implementation schedules a Temporal timer that resumes the continuation when fired
- This is completely transparent to user code - no custom `KWorkflow.delay()` needed

## KotlinReplayWorkflow

Implements the `ReplayWorkflow` interface using coroutines:

```kotlin
internal class KotlinReplayWorkflow(
    private val definition: KotlinWorkflowDefinition,
    private val workflowExecution: WorkflowExecution,
    private val dispatcher: KotlinCoroutineDispatcher
) : ReplayWorkflow {

    private var workflowJob: Job? = null
    private var result: WorkflowExecutionResult? = null
    private lateinit var context: KotlinWorkflowContext

    override fun start(event: HistoryEvent, replayContext: ReplayWorkflowContext) {
        context = KotlinWorkflowContext(replayContext)

        // Create coroutine scope with our deterministic dispatcher
        val scope = CoroutineScope(
            dispatcher +
            KotlinDelay(context) +
            SupervisorJob()
        )

        // Start the workflow coroutine
        workflowJob = scope.launch {
            try {
                val instance = definition.createInstance()
                val output = definition.invokeWorkflowMethod(instance, event.arguments)
                result = WorkflowExecutionResult.completed(output)
            } catch (e: CancellationException) {
                result = WorkflowExecutionResult.canceled(e.message)
            } catch (e: Throwable) {
                result = WorkflowExecutionResult.failed(e)
            }
        }
    }

    override fun eventLoop(): Boolean {
        return dispatcher.eventLoop(deadlockDetectionTimeout)
    }

    override fun getOutput(): WorkflowExecutionResult? = result

    override fun cancel(reason: String) {
        workflowJob?.cancel(CancellationException(reason))
    }

    override fun close() {
        workflowJob?.cancel()
    }
}
```

## KotlinWorkflowContext

Provides workflow APIs to the coroutine-based workflow:

```kotlin
internal class KotlinWorkflowContext(
    private val replayContext: ReplayWorkflowContext
) {
    fun createTimer(duration: Duration): CompletableFuture<Void> {
        return replayContext.createTimer(duration)
    }

    fun executeActivity(
        name: String,
        options: ActivityOptions,
        args: Array<Any?>
    ): CompletableFuture<Any?> {
        return replayContext.executeActivity(name, options, args)
    }

    fun executeChildWorkflow(
        type: String,
        options: ChildWorkflowOptions,
        args: Array<Any?>
    ): CompletableFuture<Any?> {
        return replayContext.executeChildWorkflow(type, options, args)
    }

    fun sideEffect(func: () -> Any?): Any? {
        return replayContext.sideEffect(func)
    }

    fun getVersion(changeId: String, minSupported: Int, maxSupported: Int): Int {
        return replayContext.getVersion(changeId, minSupported, maxSupported)
    }

    fun currentTime(): Instant = replayContext.currentTimeMillis().let {
        Instant.ofEpochMilli(it)
    }

    // ... other workflow APIs
}
```

## Activity Execution Implementation

### String-based Activity Execution

String-based activity execution is implemented directly in `KWorkflow` using **reified generics** to provide a clean API without requiring explicit `Class<*>` parameters or casts:

```kotlin
object KWorkflow {
    /**
     * Execute an activity by name with reified return type.
     *
     * Usage: KWorkflow.executeActivity<String>("activityName", options, arg1, arg2)
     *
     * The `inline` + `reified` combination allows access to R::class.java at runtime.
     * At each call site, the compiler substitutes the actual type.
     */
    inline suspend fun <reified R> executeActivity(
        activityName: String,
        options: ActivityOptions,
        vararg args: Any?
    ): R {
        return executeActivityInternal(activityName, R::class.java, options, args) as R
    }

    /**
     * Internal implementation that receives the actual Class for DataConverter.
     */
    @PublishedApi
    internal suspend fun executeActivityInternal(
        activityName: String,
        resultType: Class<*>,
        options: ActivityOptions,
        args: Array<out Any?>
    ): Any? {
        val context = currentContext()
        val future = context.executeActivity(activityName, resultType, options, args)
        return future.await()  // Suspends until activity completes
    }
}
```

**Parallel Execution:** Instead of a custom `startActivity` method returning a handle, users use standard Kotlin patterns:

```kotlin
// Parallel activities using standard coroutineScope { async { } }
val results = coroutineScope {
    val d1 = async { KWorkflow.executeActivity<Int>("add", options, 1, 2) }
    val d2 = async { KWorkflow.executeActivity<Int>("add", options, 3, 4) }
    awaitAll(d1, d2)  // Standard Deferred<Int> instances
}
```

This approach uses standard `Deferred<T>` instead of a custom `KActivityHandle<R>`, following the design principle of using idiomatic Kotlin patterns.

**Why `inline` + `reified`?**

Kotlin generics are erased at runtime (like Java). Without `reified`, we cannot access `R::class.java`:

```kotlin
// Does NOT work - R is erased at runtime
suspend fun <R> executeActivity(activityName: String, options: ActivityOptions, vararg args: Any?): R {
    val resultType = R::class.java  // Compile error: Cannot use 'R' as reified type parameter
}

// WORKS - inline + reified captures type at compile time
inline suspend fun <reified R> executeActivity(activityName: String, options: ActivityOptions, vararg args: Any?): R {
    val resultType = R::class.java  // OK: compiler substitutes actual type at call site
}
```

**How it works at the call site:**

```kotlin
// User writes:
val result = KWorkflow.executeActivity<String>("greet", options, name)

// Compiler inlines to (conceptually):
val result = KWorkflow.executeActivityInternal("greet", String::class.java, options, arrayOf(name)) as String
```

**Notes:**
- `@PublishedApi` is required for `internal` functions called from `inline` functions
- `inline suspend fun` is supported since Kotlin 1.3.70
- Cannot be overridden (inline functions are not virtual)
- Cannot be called from Java (inlined at Kotlin call sites only)

### Return Type for DataConverter

The DataConverter needs the return type to deserialize the activity result. With `reified` generics, we can capture the type at compile time:

```kotlin
inline suspend fun <reified R> executeActivity(...): R {
    // Simple approach - works for non-generic types
    val resultType = R::class.java  // String::class.java, Int::class.java, etc.

    // Full generic type info using typeOf (Kotlin 1.6+)
    val kType: KType = typeOf<R>()  // Preserves List<String>, Map<String, Int>, etc.
}
```

**Limitation with `R::class.java`:**

```kotlin
// Works fine for simple types
executeActivity<String>("greet", options, name)  // R::class.java = String::class.java

// Loses type parameter for generic types
executeActivity<List<String>>("getNames", options)  // R::class.java = List::class.java (loses String)
```

**Solution using `typeOf<R>()`:**

Kotlin's `typeOf<R>()` (introduced in Kotlin 1.6) preserves full generic type information:

```kotlin
inline suspend fun <reified R> executeActivity(
    activityName: String,
    options: ActivityOptions,
    vararg args: Any?
): R {
    val kType: KType = typeOf<R>()  // Preserves full generic info
    val javaType = kType.javaType   // Converts to java.lang.reflect.Type

    return executeActivityInternal(activityName, javaType, options, args) as R
}

// Internal method accepts java.lang.reflect.Type (handles ParameterizedType)
@PublishedApi
internal suspend fun executeActivityInternal(
    activityName: String,
    resultType: java.lang.reflect.Type,  // Can be Class or ParameterizedType
    options: ActivityOptions,
    args: Array<out Any?>
): Any? {
    val context = currentContext()
    val future = context.executeActivity(activityName, resultType, options, args)
    return future.await()
}
```

This allows the DataConverter to properly deserialize generic types:

```kotlin
// Now works correctly
val names: List<String> = KWorkflow.executeActivity<List<String>>("getNames", options)
val mapping: Map<String, Int> = KWorkflow.executeActivity<Map<String, Int>>("getMapping", options)
```

### CompletableFuture to Suspend Extension

```kotlin
// Extension to convert CompletableFuture to suspend
private suspend fun <T> CompletableFuture<T>.await(): T {
    return suspendCancellableCoroutine { cont ->
        this.whenComplete { result, error ->
            if (error != null) {
                cont.resumeWithException(error)
            } else {
                cont.resume(result)
            }
        }
        cont.invokeOnCancellation {
            this.cancel(true)
        }
    }
}
```

### Method Reference-based Activity Execution (Phase 2)

The typed activity API uses `KFunction` references to extract metadata (interface class, method name) without requiring proxy creation:

```kotlin
object KWorkflow {
    /**
     * Execute activity using method reference.
     * Uses KFunction to extract activity name and return type.
     */
    suspend fun <T, A1, R> executeActivity(
        activity: KFunction2<T, A1, R>,
        options: ActivityOptions,
        arg1: A1
    ): R {
        val activityName = extractActivityName(activity)
        val resultType = extractReturnType(activity)
        val context = currentContext()
        val future = context.executeActivity(activityName, resultType, options, arrayOf(arg1))
        return future.await() as R
    }

    /**
     * Extract activity name from KFunction.
     * Uses @ActivityMethod annotation name if present, otherwise method name.
     */
    private fun extractActivityName(function: KFunction<*>): String {
        val method = function.javaMethod
            ?: throw IllegalArgumentException("Cannot get Java method from function")

        val annotation = method.getAnnotation(ActivityMethod::class.java)
        return if (annotation != null && annotation.name.isNotEmpty()) {
            annotation.name
        } else {
            method.name
        }
    }

    /**
     * Extract return type from KFunction for DataConverter.
     */
    private fun extractReturnType(function: KFunction<*>): Class<*> {
        val method = function.javaMethod
            ?: throw IllegalArgumentException("Cannot get Java method from function")
        return method.returnType
    }
}
```

**How `KFunction` works:**

```kotlin
// User writes:
val result = KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,  // KFunction2<GreetingActivities, String, String>
    options,
    name
)

// At runtime:
// - activity.javaMethod gives us the Method object
// - Method.name gives us "composeGreeting"
// - Method.declaringClass gives us GreetingActivities
// - Method.returnType gives us String.class
```

## Duration Extensions

```kotlin
// DurationExt.kt
package io.temporal.kotlin

import java.time.Duration as JavaDuration
import kotlin.time.Duration as KotlinDuration
import kotlin.time.toJavaDuration
import kotlin.time.toKotlinDuration

/**
 * Convert Kotlin Duration to Java Duration for interop with Java SDK.
 */
fun KotlinDuration.toJava(): JavaDuration = this.toJavaDuration()

/**
 * Convert Java Duration to Kotlin Duration.
 */
fun JavaDuration.toKotlin(): KotlinDuration = this.toKotlinDuration()

/**
 * DSL property that accepts Kotlin Duration and converts to Java Duration.
 */
var ActivityOptions.Builder.startToCloseTimeout: KotlinDuration
    @Deprecated("Write-only property", level = DeprecationLevel.HIDDEN)
    get() = throw UnsupportedOperationException()
    set(value) { setStartToCloseTimeout(value.toJava()) }

// Similar extensions for other timeout properties...
```

## Decision Justifications

### Why Coroutines Instead of Extending Java Thread Model?

* **Idiomatic Kotlin**: Coroutines are the standard concurrency model in Kotlin
* **Structured concurrency**: `coroutineScope`, `async`, `launch` provide clear parent-child relationships
* **Cancellation**: Coroutine cancellation maps naturally to Temporal's cancellation scopes
* **Performance**: Lightweight compared to threads, though this is less relevant in workflow context
* **Ecosystem**: Integrates with Kotlin ecosystem (Flow, channels, etc.)

### Why Suspend Functions for Workflows?

* **Natural async**: Workflow operations (activities, timers) are inherently async
* **Sequential code**: Suspend functions allow sequential-looking code for async operations
* **Error handling**: Standard try-catch works with suspend functions
* **Testing**: Coroutine test utilities work well with suspend functions

### Why Keep Compatibility with Java SDK?

* **Gradual migration**: Teams can adopt Kotlin incrementally
* **Ecosystem leverage**: Benefits from Java SDK's stability and features
* **Reduced maintenance**: Shared infrastructure reduces duplication
* **Activity reuse**: Existing Java activities work without modification

### Why Untyped Stubs First in Phase 1?

* **Complexity management**: Typed stub generation requires more infrastructure
* **Proof of concept**: Validates coroutine-based execution model first
* **Faster iteration**: Can release usable SDK sooner
* **Java interop**: Untyped stubs work with any activity implementation

### Why Custom CoroutineDispatcher?

* **Determinism**: Standard dispatchers are non-deterministic
* **Replay support**: Must execute coroutines in same order during replay
* **Timer integration**: `delay()` must map to Temporal timers, not actual time
* **Deadlock detection**: Can implement workflow-aware deadlock detection

### Why Unified Worker Instead of Separate KotlinWorkerFactory?

* **Per-instance execution**: The dispatcher is per workflow instance, not per worker—there's no technical reason to separate workers
* **Simpler API**: One worker type is easier to understand and use
* **Mixed task queues**: Java and Kotlin workflows can share the same task queue
* **Easier migration**: Convert workflows one at a time without changing infrastructure
* **No Kotlin in Java SDK**: The pluggable `WorkflowImplementationFactory` keeps all Kotlin code in `temporal-kotlin`

### Why Invest in Kotlin Idioms?

* **Developer expectations**: Kotlin developers expect null safety and kotlin.time.Duration
* **Null safety**: Nullable types replace `Optional<T>` throughout the API
* **Readability**: `30.seconds` is more readable than `Duration.ofSeconds(30)`
* **Coroutines**: `suspend fun` for natural async workflows and activities
* **IDE support**: Kotlin idioms provide better autocomplete and error detection
* **Differentiation**: Makes the Kotlin SDK feel native, not just a wrapper around Java

## Open Questions

### Workflow Versioning with Coroutines

How do `Workflow.getVersion()` semantics work with coroutines?

- **Version marker ordering**: Version checks record markers in the event history. With coroutines suspending and resuming, need to ensure markers are recorded in deterministic order during replay.
- **Suspension points**: If `getVersion()` is called before a suspension point, does the version marker position remain stable across code changes?
- **Expected behavior**: Likely works the same as Java since version markers are recorded synchronously before any suspension. Needs validation during implementation.

## Resolved Decisions

### CancellationScope Mapping

Kotlin's built-in coroutine cancellation replaces Java SDK's `CancellationScope`. The `KotlinCoroutineDispatcher` already provides deterministic execution, so standard Kotlin cancellation patterns work correctly with Temporal's replay mechanism.

| Java SDK | Kotlin SDK | Notes |
|----------|------------|-------|
| `Workflow.newCancellationScope(() -> {...})` | `coroutineScope { ... }` | Parent cancellation propagates to children |
| `Workflow.newDetachedCancellationScope(() -> {...})` | `withContext(NonCancellable) { ... }` | For cleanup code that must run |
| `CancellationScope.cancel()` | `job.cancel()` | Explicit cancellation |
| `CancellationScope.isCancelRequested()` | `!isActive` | Check without throwing |
| `CancellationScope.throwCanceled()` | `ensureActive()` | Throws if cancelled |
| `scope.run()` with timeout | `withTimeout(duration) { ... }` | Built-in timeout support |

**Why this works:**
- Server cancellation triggers coroutine cancellation via root `Job`
- Cancellation state is recorded in workflow history for deterministic replay
- `withContext(NonCancellable)` maps directly to detached scope semantics
- No custom API needed—Kotlin's structured concurrency matches Temporal's model

### DSL vs Annotations

**Decision**: Keep annotations (`@WorkflowMethod`, `@SignalMethod`) as the primary approach for consistency with Java SDK. Consider DSL as optional alternative in future phases if there's demand.

### SPI Stability

**Decision**: Start with `@InternalApi` annotation for Phase 1. The affected interfaces (`WorkflowImplementationFactory`, `ReplayWorkflow`, `ReplayWorkflowContext`) will be promoted to a stable SPI package once they stabilize after real-world usage (likely post-Phase 3).

## Future Considerations

### Kotlin Flow Support

Streaming results via Kotlin Flow is deferred to post-Phase 3. Existing patterns (heartbeat details, signals) cover most use cases. Flow integration requires careful handling of backpressure, cancellation, and replay determinism.

### Kotlin Multiplatform

Not a near-term priority. The SDK is JVM-only due to Java SDK dependency. May revisit if sdk-core provides C bindings that Kotlin/Native could use.

## References

* [Kotlin Coroutines Prototype PR #1792](https://github.com/temporalio/sdk-java/pull/1792) - Early prototype; this proposal uses a different architecture (pluggable factory vs separate worker factory)
* [Existing temporal-kotlin Module](https://github.com/temporalio/sdk-java/tree/master/temporal-kotlin)
* [.NET SDK Proposal - Phase 1](../dotnet/sdk-phase-1.md)
* [.NET SDK Proposal - Phase 2](../dotnet/sdk-phase-2.md)
