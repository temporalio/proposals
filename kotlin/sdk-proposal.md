# Kotlin SDK Proposal

The Kotlin SDK will be implemented in three loosely defined phases:

* Phase 1 - Coroutine-based workflows, untyped activity stubs, KotlinWorkerFactory
* Phase 2 - Typed activity stubs with suspend functions, signals/queries, child workflows
* Phase 3 - Updates, Nexus, testing framework, advanced features

This proposal covers the overall design. Individual phases may have separate detailed proposals.

Notes for this proposal:

* Intentionally loosely defined, everything subject to change
* Some decisions are justified at the end
* Code examples may not be valid Kotlin but use `/* ... */` for brevity

## Overview

The Kotlin SDK will extend the existing Java SDK, utilizing Kotlin coroutines for workflow execution instead of Java's thread-based approach. A custom `TemporalCoroutineDispatcher` ensures deterministic execution.

The high-level goals for the Kotlin SDK are:

* Provide idiomatic Kotlin experience with coroutines and suspend functions
* Maintain full interoperability with the Java SDK
* Support existing Java-defined workflows and activities from Kotlin code
* Enable gradual migration from Java SDK patterns
* Minimum Kotlin version: 1.8.x
* Coroutines library: kotlinx-coroutines-core 1.7.x+

## Relationship to Java SDK

The Kotlin SDK builds on top of the Java SDK rather than replacing it:

* **Shared infrastructure**: Uses the same gRPC client, data conversion, and service client
* **Interoperability**: Kotlin workflows can call Java activities and vice versa
* **Gradual adoption**: Teams can mix Java and Kotlin workers in the same application
* **Existing module**: Extends the existing `temporal-kotlin` module which already provides DSL extensions

## Relationship to Existing Kotlin Classes

The `temporal-kotlin` module already provides Kotlin extensions for the Java SDK. The Kotlin SDK will build on this foundation:

### Existing Classes (Retained)

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

### New Classes (Kotlin SDK)

| Class | Purpose |
|-------|---------|
| `KotlinWorkerFactory` | Worker factory for coroutine-based workflows |
| `KotlinWorkerFactoryOptions` | Options specific to Kotlin worker factory |
| `KotlinWorkflow` | Entry point for workflow APIs (like `Workflow` in Java) |
| `KotlinWorkflowContext` | Internal workflow execution context |
| `KotlinActivityStub` | Suspend-function activity stub interface |
| `TemporalCoroutineDispatcher` | Deterministic coroutine dispatcher |
| `KotlinWorkerInterceptor` | Interceptor interface with suspend functions |
| `KotlinWorkflowImplementationFactory` | Creates coroutine-based workflow instances |

### Worker Factory Distinction

The SDK will have **two worker factory types**:

```
┌─────────────────────────────────────┐
│       BaseWorkerFactory             │  ← Abstract base (in Java SDK)
│  - Common worker lifecycle          │
│  - Worker registration              │
│  - Start/shutdown management        │
└──────────────┬──────────────────────┘
               │
       ┌───────┴───────┐
       │               │
       ▼               ▼
┌──────────────┐  ┌──────────────────────┐
│ WorkerFactory│  │ KotlinWorkerFactory  │
│ (Java SDK)   │  │ (Kotlin SDK)         │
│              │  │                      │
│ Thread-based │  │ Coroutine-based      │
│ workflows    │  │ workflows            │
│              │  │                      │
│ Uses:        │  │ Uses:                │
│ - DeterministicRunner              │  │ - TemporalCoroutineDispatcher      │
│ - POJOWorkflowImplementationFactory│  │ - KotlinWorkflowImplementationFactory │
└──────────────┘  └──────────────────────┘
```

**When to use which:**

| Use Case | Worker Factory |
|----------|----------------|
| Java workflows (blocking) | `WorkerFactory` |
| Kotlin workflows without coroutines (blocking) | `WorkerFactory` |
| Kotlin workflows with suspend functions | `KotlinWorkerFactory` |
| Mixed: Java workflows + Kotlin activities | `WorkerFactory` |
| Mixed: Kotlin coroutine workflows + Java activities | `KotlinWorkerFactory` |

**Important:** A single application can use both factory types for different task queues if needed.

## Java SDK Refactoring for Pluggability

To support the Kotlin coroutine-based execution model, the Java SDK requires refactoring to make the workflow execution dispatcher pluggable. The [prototype PR #1792](https://github.com/temporalio/sdk-java/pull/1792) demonstrates these changes.

### Required Changes to `temporal-sdk`

#### 1. Extract `BaseWorkerFactory` Abstract Class

**File:** `io.temporal.worker.BaseWorkerFactory` (new)

Extract common functionality from `WorkerFactory` into an abstract base class:

```java
public abstract class BaseWorkerFactory {
    protected final Scope metricsScope;
    private final WorkflowClient workflowClient;
    private final WorkerFactoryOptions factoryOptions;
    private final WorkflowExecutorCache cache;
    private final Map<String, Worker> workers = new HashMap<>();

    // Common lifecycle: start(), shutdown(), awaitTermination()
    // Common worker management: newWorker(), getWorker()
    // Common registration with WorkflowClient

    // Abstract method for pluggable workflow factory
    protected abstract ReplayWorkflowFactory newReplayWorkflowFactory(
        WorkerOptions workerOptions,
        WorkflowClientOptions clientOptions,
        WorkflowExecutorCache cache
    );
}
```

#### 2. Modify `WorkerFactory` to Extend Base

**File:** `io.temporal.worker.WorkerFactory`

```java
public final class WorkerFactory extends BaseWorkerFactory {
    private final ThreadPoolExecutor workflowThreadPool;
    private final WorkflowThreadExecutor workflowThreadExecutor;

    @Override
    protected ReplayWorkflowFactory newReplayWorkflowFactory(
        WorkerOptions workerOptions,
        WorkflowClientOptions clientOptions,
        WorkflowExecutorCache cache
    ) {
        // Return the existing POJO-based factory
        return new POJOWorkflowImplementationFactory(
            clientOptions,
            workerOptions,
            workflowThreadExecutor,
            cache,
            // ... other dependencies
        );
    }
}
```

#### 3. Extend `ReplayWorkflowFactory` Interface

**File:** `io.temporal.internal.replay.ReplayWorkflowFactory`

Add workflow registration methods to the interface:

```java
public interface ReplayWorkflowFactory {
    // Existing
    ReplayWorkflow getWorkflow(WorkflowType workflowType, WorkflowExecution workflowExecution);
    boolean isAnyTypeSupported();

    // New: Allow registration through the factory
    void registerWorkflowImplementationTypes(
        WorkflowImplementationOptions options,
        Class<?>[] workflowImplementationTypes
    );

    <R> void addWorkflowImplementationFactory(
        WorkflowImplementationOptions options,
        Class<R> clazz,
        Functions.Func<R> factory
    );
}
```

#### 4. Update Client Registry to Accept Base Type

**File:** `io.temporal.internal.client.WorkflowClientInternal`

```java
public interface WorkflowClientInternal {
    // Change from WorkerFactory to BaseWorkerFactory
    void registerWorkerFactory(BaseWorkerFactory workerFactory);
}
```

**File:** `io.temporal.internal.client.WorkerFactoryRegistry`

```java
public class WorkerFactoryRegistry {
    // Change from WorkerFactory to BaseWorkerFactory
    public synchronized void register(BaseWorkerFactory workerFactory) { ... }
    public synchronized void deregister(BaseWorkerFactory workerFactory) { ... }
}
```

#### 5. Update `EagerWorkflowTaskDispatcher`

**File:** `io.temporal.internal.client.EagerWorkflowTaskDispatcher`

Update to work with `BaseWorkerFactory` instead of `WorkerFactory`.

### Files Changed Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `BaseWorkerFactory.java` | **New** | Abstract base class extracted from WorkerFactory |
| `WorkerFactory.java` | **Modified** | Now extends BaseWorkerFactory |
| `ReplayWorkflowFactory.java` | **Modified** | Added registration methods |
| `POJOWorkflowImplementationFactory.java` | **Modified** | Implements new interface methods |
| `WorkflowClientInternal.java` | **Modified** | Accept BaseWorkerFactory |
| `WorkflowClientInternalImpl.java` | **Modified** | Accept BaseWorkerFactory |
| `WorkerFactoryRegistry.java` | **Modified** | Work with BaseWorkerFactory |
| `EagerWorkflowTaskDispatcher.java` | **Modified** | Work with BaseWorkerFactory |
| `Worker.java` | **Minor** | Adjust for base class changes |
| `SyncWorkflowWorker.java` | **Minor** | Adjust for interface changes |

### Kotlin SDK Classes Using This Infrastructure

Once the Java SDK refactoring is complete, the Kotlin SDK adds:

```kotlin
// Extends the base factory
class KotlinWorkerFactory(
    workflowClient: WorkflowClient,
    factoryOptions: KotlinWorkerFactoryOptions?
) : BaseWorkerFactory(workflowClient, factoryOptions) {

    override fun newReplayWorkflowFactory(
        workerOptions: WorkerOptions,
        clientOptions: WorkflowClientOptions,
        cache: WorkflowExecutorCache
    ): ReplayWorkflowFactory {
        // Return Kotlin-specific factory that uses coroutines
        return KotlinWorkflowImplementationFactory(
            clientOptions,
            workerOptions,
            cache
        )
    }
}
```

```kotlin
// Kotlin-specific workflow factory
internal class KotlinWorkflowImplementationFactory(
    private val clientOptions: WorkflowClientOptions,
    private val workerOptions: WorkerOptions,
    private val cache: WorkflowExecutorCache
) : ReplayWorkflowFactory {

    override fun getWorkflow(
        workflowType: WorkflowType,
        workflowExecution: WorkflowExecution
    ): ReplayWorkflow {
        // Returns KotlinWorkflow which uses TemporalCoroutineDispatcher
        return KotlinWorkflow(
            namespace,
            workflowExecution,
            workflowDefinition,
            // ... uses coroutine-based execution
        )
    }
}
```

### Backward Compatibility

These changes maintain full backward compatibility:

* `WorkerFactory` API remains unchanged for existing users
* Existing Java workflows continue to work without modification
* The refactoring is purely internal restructuring
* No breaking changes to public APIs

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

## Workflow Definition

### Basic Example

```kotlin
@WorkflowInterface
interface GreetingWorkflow {
    @WorkflowMethod
    suspend fun getGreeting(name: String): String
}

class GreetingWorkflowImpl : GreetingWorkflow {
    override suspend fun getGreeting(name: String): String = coroutineScope {
        val activities = KotlinWorkflow.newUntypedActivityStub(
            ActivityOptions {
                setStartToCloseTimeout(Duration.ofSeconds(10))
            }
        )

        // Execute activities in parallel using coroutines
        val hello = async {
            activities.execute("greet", String::class.java, "Hello", name)
        }
        val goodbye = async {
            activities.execute("greet", String::class.java, "Goodbye", name)
        }

        "${hello.await()}\n${goodbye.await()}"
    }
}
```

### Key Characteristics

* Workflow methods are `suspend fun` instead of regular functions
* Use `coroutineScope`, `async`, `launch` for concurrent execution
* Use `delay()` instead of `Workflow.sleep()` for timers
* The `@WorkflowInterface` and `@WorkflowMethod` annotations are reused from Java SDK
* Data classes work naturally for workflow parameters and results

### Signals and Queries (Phase 2)

```kotlin
@WorkflowInterface
interface OrderWorkflow {
    @WorkflowMethod
    suspend fun processOrder(order: Order): OrderResult

    @SignalMethod
    suspend fun cancelOrder(reason: String)

    @QueryMethod
    fun getOrderStatus(): OrderStatus
}
```

Notes:
* Signal methods are `suspend fun` since they may trigger workflow logic
* Query methods remain non-suspend as they are read-only and synchronous

### Child Workflows (Phase 2)

```kotlin
override suspend fun parentWorkflow(): String = coroutineScope {
    val child = KotlinWorkflow.newChildWorkflowStub<ChildWorkflow>(
        ChildWorkflowOptions {
            setWorkflowId("child-workflow-id")
        }
    )

    // Start child workflow asynchronously
    val result = async { child.doWork("input") }

    // Do other work...

    result.await()
}
```

## Activity Definition

### Phase 1: Untyped Activity Stubs

In Phase 1, activities are invoked through untyped stubs:

```kotlin
val activities = KotlinWorkflow.newUntypedActivityStub(
    ActivityOptions {
        setStartToCloseTimeout(Duration.ofSeconds(30))
        setRetryOptions {
            setInitialInterval(Duration.ofSeconds(1))
            setMaximumAttempts(3)
        }
    }
)

val result = activities.execute("activityName", String::class.java, arg1, arg2)
```

### Phase 2: Typed Activity Stubs with Suspend Functions

```kotlin
@ActivityInterface
interface GreetingActivities {
    @ActivityMethod
    suspend fun composeGreeting(greeting: String, name: String): String

    @ActivityMethod
    suspend fun sendEmail(email: Email): SendResult
}

// In workflow:
val activities = KotlinWorkflow.newActivityStub<GreetingActivities>(
    ActivityOptions {
        setStartToCloseTimeout(Duration.ofSeconds(30))
    }
)

val greeting = activities.composeGreeting("Hello", "World")
```

### Activity Implementation

Activities can be implemented as regular Kotlin classes:

```kotlin
class GreetingActivitiesImpl : GreetingActivities {
    override suspend fun composeGreeting(greeting: String, name: String): String {
        // Can use suspend functions for I/O
        return "$greeting, $name!"
    }

    override suspend fun sendEmail(email: Email): SendResult {
        // Async I/O with coroutines
        return emailService.send(email)
    }
}
```

### Local Activities (Phase 2)

```kotlin
val localActivities = KotlinWorkflow.newLocalActivityStub<ValidationActivities>(
    LocalActivityOptions {
        setStartToCloseTimeout(Duration.ofSeconds(5))
    }
)
```

## Client API

### Workflow Client Extensions

Building on existing `temporal-kotlin` extensions:

```kotlin
// Create client with DSL
val client = WorkflowClient(service) {
    setNamespace("default")
    setDataConverter(myConverter)
}

// Start workflow with reified types
val workflow = client.newWorkflowStub<GreetingWorkflow> {
    setWorkflowId("greeting-123")
    setTaskQueue("greeting-queue")
}

// Execute workflow
val result = workflow.getGreeting("Temporal")

// Or start async and get handle
val handle = WorkflowClient.start { workflow.getGreeting("Temporal") }
val result = handle.getResult<String>()
```

### Signal and Query from Client

```kotlin
// Get existing workflow
val workflow = client.newWorkflowStub<OrderWorkflow>("order-123")

// Send signal
workflow.cancelOrder("Customer request")

// Query
val status = workflow.getOrderStatus()
```

## Worker API

### KotlinWorkerFactory

A specialized worker factory for Kotlin coroutine-based workflows:

```kotlin
val service = WorkflowServiceStubs.newLocalServiceStubs()
val client = WorkflowClient.newInstance(service)

val factory = KotlinWorkerFactory(client) {
    setMaxWorkflowThreadCount(800)
}

val worker = factory.newWorker("task-queue") {
    setMaxConcurrentActivityExecutionSize(100)
}

// Register Kotlin workflow implementations
worker.registerWorkflowImplementationTypes(
    GreetingWorkflowImpl::class.java,
    OrderWorkflowImpl::class.java
)

// Register activity implementations (can be Java or Kotlin)
worker.registerActivitiesImplementations(
    GreetingActivitiesImpl(),
    OrderActivitiesImpl()
)

factory.start()
```

### TemporalCoroutineDispatcher

The custom dispatcher ensures deterministic execution of coroutines:

* Executes coroutines in a controlled, deterministic order
* Integrates with Temporal's replay mechanism
* Supports `delay()` by mapping to Temporal timers
* Handles cancellation scopes properly

```kotlin
// Internal implementation - users don't interact with this directly
internal class TemporalCoroutineDispatcher(
    private val workflowContext: KotlinWorkflowContext
) : CoroutineDispatcher() {

    override fun dispatch(context: CoroutineContext, block: Runnable) {
        // Queue for deterministic execution
        workflowContext.schedule(block)
    }

    fun eventLoop(deadlockDetectionTimeout: Long) {
        // Process queued coroutines deterministically
    }
}
```

## Data Conversion

### Kotlin Serialization Support

Support for `kotlinx.serialization` as an alternative to Jackson:

```kotlin
@Serializable
data class Order(
    val id: String,
    val items: List<OrderItem>,
    val status: OrderStatus
)

@Serializable
data class OrderItem(
    val productId: String,
    val quantity: Int
)
```

### Jackson Kotlin Module

The existing `KotlinObjectMapperFactory` continues to be supported:

```kotlin
val converter = DefaultDataConverter.newDefaultInstance().withPayloadConverterOverrides(
    JacksonJsonPayloadConverter(
        KotlinObjectMapperFactory.new()
    )
)
```

### Data Classes Best Practices

* Use `data class` for workflow parameters and results
* Ensure all properties have default values or are nullable for deserialization
* Consider using `@Serializable` annotation for kotlinx.serialization

## Interceptors

### Kotlin-Native Interceptor Interfaces

```kotlin
interface KotlinWorkerInterceptor {
    fun interceptWorkflow(next: WorkflowInboundCallsInterceptor): WorkflowInboundCallsInterceptor {
        return next
    }

    fun interceptActivity(next: ActivityInboundCallsInterceptor): ActivityInboundCallsInterceptor {
        return next
    }
}

interface WorkflowInboundCallsInterceptor {
    suspend fun init(outboundCalls: WorkflowOutboundCallsInterceptor)

    suspend fun execute(input: WorkflowInput): WorkflowOutput

    suspend fun handleSignal(input: SignalInput)

    fun handleQuery(input: QueryInput): QueryOutput
}

interface WorkflowOutboundCallsInterceptor {
    suspend fun <R> executeActivity(input: ActivityInput<R>): ActivityOutput<R>

    suspend fun <R> executeChildWorkflow(input: ChildWorkflowInput<R>): ChildWorkflowOutput<R>

    // ... other outbound calls
}
```

### Example: Logging Interceptor

```kotlin
class LoggingInterceptor : KotlinWorkerInterceptor {
    override fun interceptWorkflow(
        next: WorkflowInboundCallsInterceptor
    ): WorkflowInboundCallsInterceptor {
        return object : WorkflowInboundCallsInterceptorBase(next) {
            override suspend fun execute(input: WorkflowInput): WorkflowOutput {
                log.info("Workflow started: ${input.workflowType}")
                return try {
                    super.execute(input)
                } finally {
                    log.info("Workflow completed: ${input.workflowType}")
                }
            }
        }
    }
}
```

## Testing

### Workflow Testing with Coroutines (Phase 3)

```kotlin
class GreetingWorkflowTest {
    @Test
    fun testGreetingWorkflow() = runTest {
        val testEnv = TestWorkflowEnvironment.newInstance()
        val worker = testEnv.newWorker("test-queue")

        worker.registerWorkflowImplementationTypes(GreetingWorkflowImpl::class.java)
        worker.registerActivitiesImplementations(MockGreetingActivities())

        testEnv.start()

        val client = testEnv.workflowClient
        val workflow = client.newWorkflowStub<GreetingWorkflow> {
            setTaskQueue("test-queue")
        }

        val result = workflow.getGreeting("Test")

        assertEquals("Hello, Test!", result)

        testEnv.close()
    }
}
```

### Activity Testing

```kotlin
class GreetingActivitiesTest {
    @Test
    fun testComposeGreeting() = runTest {
        val context = TestActivityEnvironment.newInstance().activityContext

        val activities = GreetingActivitiesImpl()

        // Test with activity context
        val result = context.run {
            activities.composeGreeting("Hello", "World")
        }

        assertEquals("Hello, World!", result)
    }
}
```

### Mocking Activities in Workflows

```kotlin
@Test
fun testWorkflowWithMockedActivities() = runTest {
    val mockActivities = mockk<GreetingActivities>()
    coEvery { mockActivities.composeGreeting(any(), any()) } returns "Mocked greeting"

    // Configure test environment with mocked activities
    worker.registerActivitiesImplementations(mockActivities)

    // ... run workflow
}
```

## Migration Guide

### From Java SDK Workflows

```java
// Java workflow
@WorkflowInterface
public interface GreetingWorkflow {
    @WorkflowMethod
    String getGreeting(String name);
}

public class GreetingWorkflowImpl implements GreetingWorkflow {
    @Override
    public String getGreeting(String name) {
        ActivityStub activities = Workflow.newUntypedActivityStub(...);
        return activities.execute("greet", String.class, name);
    }
}
```

```kotlin
// Kotlin equivalent
@WorkflowInterface
interface GreetingWorkflow {
    @WorkflowMethod
    suspend fun getGreeting(name: String): String
}

class GreetingWorkflowImpl : GreetingWorkflow {
    override suspend fun getGreeting(name: String): String {
        val activities = KotlinWorkflow.newUntypedActivityStub(...)
        return activities.execute("greet", String::class.java, name)!!
    }
}
```

### Key Migration Differences

| Java SDK | Kotlin SDK |
|----------|------------|
| `Workflow.sleep(duration)` | `delay(duration.toMillis())` |
| `Async.function(...)` | `async { ... }` |
| `Promise<T>` | `Deferred<T>` (from coroutines) |
| `Workflow.await(condition)` | Custom `awaitCondition { }` or channels |
| Thread-based execution | Coroutine-based execution |

### Interoperability

Kotlin workflows can call Java activities:

```kotlin
// Kotlin workflow calling Java activity
override suspend fun processOrder(order: Order): String {
    // JavaActivities is a Java @ActivityInterface
    val javaActivities = KotlinWorkflow.newActivityStub<JavaActivities>(options)
    return javaActivities.process(order)
}
```

Java workflows can be invoked from Kotlin clients:

```kotlin
// Calling Java workflow from Kotlin client
val javaWorkflow = client.newWorkflowStub<JavaWorkflowInterface>(options)
val result = javaWorkflow.execute(input)
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

## Open Questions

1. **Workflow versioning**: How do `Workflow.getVersion()` semantics work with coroutines?
2. **CancellationScope mapping**: Best way to map Kotlin's structured concurrency to Temporal's cancellation scopes?
3. **Flow support**: Should we support Kotlin Flow for streaming results?
4. **Multiplatform**: Any consideration for Kotlin Multiplatform in the future?
5. **DSL vs Annotations**: Should we provide a pure DSL alternative to annotations?

## References

* [Kotlin Coroutines Prototype PR #1792](https://github.com/temporalio/sdk-java/pull/1792)
* [Existing temporal-kotlin Module](https://github.com/temporalio/sdk-java/tree/master/temporal-kotlin)
* [.NET SDK Proposal - Phase 1](../dotnet/sdk-phase-1.md)
* [.NET SDK Proposal - Phase 2](../dotnet/sdk-phase-2.md)
