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
| `KotlinCoroutineDispatcher` | Deterministic coroutine dispatcher |
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
| `KActivityHandle<R>` | Handle for async activity execution |
| `KUpdateHandle<R>` | Handle for async update execution |
| **Extensions** | |
| `DurationExt.kt` | Conversions between `kotlin.time.Duration` and `java.time.Duration` |

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
suspend fun condition(timeout: Duration, condition: () -> Boolean): Boolean {
    return Async.await(timeout.toJava()) { condition() }.await()
}
```

**Implementation notes:**
- **Prerequisite:** `Async.await()` does not currently exist in the Java SDK and must be added before `KWorkflow.condition()` can be implemented.
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

The custom dispatcher ensures deterministic execution of coroutines:

* Executes coroutines in a controlled, deterministic order
* Integrates with Temporal's replay mechanism
* Supports `delay()` by mapping to Temporal timers
* Handles cancellation scopes properly

```kotlin
internal class KotlinCoroutineDispatcher(
    private val workflowContext: KotlinWorkflowContext
) : CoroutineDispatcher() {

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

The `delay()` function is intercepted to create Temporal timers:

```kotlin
internal class KotlinDelay : Delay {
    override fun scheduleResumeAfterDelay(
        timeMillis: Long,
        continuation: CancellableContinuation<Unit>
    ) {
        val timer = workflowContext.createTimer(Duration.ofMillis(timeMillis))

        timer.thenAccept {
            continuation.resume(Unit)
        }

        continuation.invokeOnCancellation {
            timer.cancel()
        }
    }
}
```

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
     * Usage: KWorkflow.executeActivity<String>("activityName", arg1, arg2, options)
     *
     * The `inline` + `reified` combination allows access to R::class.java at runtime.
     * At each call site, the compiler substitutes the actual type.
     */
    inline suspend fun <reified R> executeActivity(
        activityName: String,
        vararg args: Any?,
        options: ActivityOptions
    ): R {
        return executeActivityInternal(activityName, R::class.java, args, options) as R
    }

    /**
     * Start an activity by name (async).
     */
    inline fun <reified R> startActivity(
        activityName: String,
        vararg args: Any?,
        options: ActivityOptions
    ): KActivityHandle<R> {
        return startActivityInternal(activityName, R::class.java, args, options)
    }

    /**
     * Internal implementation that receives the actual Class for DataConverter.
     */
    @PublishedApi
    internal suspend fun executeActivityInternal(
        activityName: String,
        resultType: Class<*>,
        args: Array<out Any?>,
        options: ActivityOptions
    ): Any? {
        val context = currentContext()
        val future = context.executeActivity(activityName, resultType, options, args)
        return future.await()  // Suspends until activity completes
    }

    @PublishedApi
    internal fun <R> startActivityInternal(
        activityName: String,
        resultType: Class<*>,
        args: Array<out Any?>,
        options: ActivityOptions
    ): KActivityHandle<R> {
        val context = currentContext()
        val future = context.executeActivity(activityName, resultType, options, args)
        return KActivityHandleImpl(future)
    }
}
```

**Why `inline` + `reified`?**

Kotlin generics are erased at runtime (like Java). Without `reified`, we cannot access `R::class.java`:

```kotlin
// Does NOT work - R is erased at runtime
suspend fun <R> executeActivity(activityName: String, vararg args: Any?, options: ActivityOptions): R {
    val resultType = R::class.java  // Compile error: Cannot use 'R' as reified type parameter
}

// WORKS - inline + reified captures type at compile time
inline suspend fun <reified R> executeActivity(activityName: String, vararg args: Any?, options: ActivityOptions): R {
    val resultType = R::class.java  // OK: compiler substitutes actual type at call site
}
```

**How it works at the call site:**

```kotlin
// User writes:
val result = KWorkflow.executeActivity<String>("greet", name, options)

// Compiler inlines to (conceptually):
val result = KWorkflow.executeActivityInternal("greet", String::class.java, arrayOf(name), options) as String
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
executeActivity<String>("greet", name, options)  // R::class.java = String::class.java

// Loses type parameter for generic types
executeActivity<List<String>>("getNames", options)  // R::class.java = List::class.java (loses String)
```

**Solution using `typeOf<R>()`:**

Kotlin's `typeOf<R>()` (introduced in Kotlin 1.6) preserves full generic type information:

```kotlin
inline suspend fun <reified R> executeActivity(
    activityName: String,
    vararg args: Any?,
    options: ActivityOptions
): R {
    val kType: KType = typeOf<R>()  // Preserves full generic info
    val javaType = kType.javaType   // Converts to java.lang.reflect.Type

    return executeActivityInternal(activityName, javaType, args, options) as R
}

// Internal method accepts java.lang.reflect.Type (handles ParameterizedType)
@PublishedApi
internal suspend fun executeActivityInternal(
    activityName: String,
    resultType: java.lang.reflect.Type,  // Can be Class or ParameterizedType
    args: Array<out Any?>,
    options: ActivityOptions
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
        arg1: A1,
        options: ActivityOptions
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
    name,
    options
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

### 1. Workflow Versioning with Coroutines

How do `Workflow.getVersion()` semantics work with coroutines?

- **Version marker ordering**: Version checks record markers in the event history. With coroutines suspending and resuming, need to ensure markers are recorded in deterministic order during replay.
- **Suspension points**: If `getVersion()` is called before a suspension point, does the version marker position remain stable across code changes?
- **Recommendation**: Likely works the same as Java since version markers are recorded synchronously before any suspension. Needs validation during implementation.

### 2. CancellationScope Mapping

Best way to map Kotlin's structured concurrency to Temporal's cancellation scopes?

- **Semantic mismatch**: Kotlin's `coroutineScope {}` fails if any child fails, while Temporal's `CancellationScope` allows explicit cancellation handling.
- **SupervisorJob patterns**: Kotlin's `supervisorScope {}` isolates child failures. How does this map to Temporal's cancellation model?
- **Options**:
  - A) `coroutineScope {}` creates implicit Temporal CancellationScope
  - B) Require explicit `KWorkflow.cancellationScope {}` for Temporal semantics
  - C) Hybrid approach with configuration
- **Recommendation**: Start with Option B (explicit) to avoid surprising behavior, consider Option A for future phases.

### 3. Kotlin Flow Support

Should we support Kotlin Flow for streaming results?

- **Use cases**: Streaming activity progress, signal batching, continuous query results
- **Complexity**: Flow integration requires careful handling of backpressure, cancellation, and replay determinism
- **Alternatives**: Existing patterns (heartbeat details, signals) cover most use cases
- **Recommendation**: Defer to post-Phase 3. Evaluate demand and complexity once core SDK is stable.

### 4. Kotlin Multiplatform

Any consideration for Kotlin Multiplatform in the future?

- **Current state**: SDK is JVM-only due to Java SDK dependency
- **Potential targets**: Kotlin/Native (server-side), Kotlin/JS (less relevant for workflows)
- **Blockers**: Core SDK (Rust) would need different bindings; significant effort
- **Recommendation**: Not a near-term priority. Document as potential future direction. May revisit if sdk-core provides C bindings that Kotlin/Native could use.

### 5. DSL vs Annotations

Should we provide a pure DSL alternative to annotations for workflow/activity definitions?

- **Current approach**: Annotations (`@WorkflowMethod`, `@SignalMethod`) following Java SDK pattern
- **DSL alternative**: Builder-style registration without annotations
  ```kotlin
  worker.registerWorkflow<OrderWorkflow> {
      workflowMethod(OrderWorkflow::processOrder)
      signalMethod(OrderWorkflow::cancelOrder)
      queryMethod(OrderWorkflow::status)
  }
  ```
- **Trade-offs**:
  - Annotations: Familiar to Java developers, IDE support, compile-time validation
  - DSL: More flexible, no annotation processing, but less discoverable
- **Recommendation**: Keep annotations as primary approach for consistency with Java SDK. Consider DSL as optional alternative in future phase if there's demand.

### 6. SPI Stability

What's the right level of API stability for `WorkflowImplementationFactory` and related interfaces?

- **Affected interfaces**:
  - `WorkflowImplementationFactory`
  - `ReplayWorkflow`
  - `ReplayWorkflowContext`
- **Options**:
  - A) **SPI package** (`io.temporal.worker.spi`): Explicit extension point, semver guarantees
  - B) **@InternalApi annotation**: Accessible but no stability guarantees
  - C) **Hybrid**: SPI for stable interfaces, @InternalApi for evolving ones
- **Considerations**:
  - Third parties may want to build alternative execution models
  - Premature stability commitments limit evolution
  - Java SDK precedent: Most internal APIs are not stable
- **Recommendation**: Start with Option B (@InternalApi) for Phase 1. Promote to SPI package once interfaces stabilize after real-world usage (likely post-Phase 3).

## References

* [Kotlin Coroutines Prototype PR #1792](https://github.com/temporalio/sdk-java/pull/1792) - Early prototype; this proposal uses a different architecture (pluggable factory vs separate worker factory)
* [Existing temporal-kotlin Module](https://github.com/temporalio/sdk-java/tree/master/temporal-kotlin)
* [.NET SDK Proposal - Phase 1](../dotnet/sdk-phase-1.md)
* [.NET SDK Proposal - Phase 2](../dotnet/sdk-phase-2.md)
