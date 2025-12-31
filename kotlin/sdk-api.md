# Kotlin SDK API Proposal

This document describes the public API and developer experience for the Temporal Kotlin SDK.

For implementation details, see [sdk-implementation.md](./sdk-implementation.md).

## Overview

The Kotlin SDK provides an idiomatic Kotlin experience for building Temporal workflows using coroutines and suspend functions.

**Key Features:**

* Coroutine-based workflows with `suspend fun`
* Full interoperability with Java SDK
* Kotlin Duration support (`30.seconds`)
* DSL builders for configuration
* Null safety (no `Optional<T>`)

**Requirements:**

* Minimum Kotlin version: 1.8.x
* Coroutines library: kotlinx-coroutines-core 1.7.x+

## Phases

* **Phase 1** - Coroutine-based workflows, untyped activity stubs, core Kotlin idioms
* **Phase 2** - Typed activity stubs, signals/queries/updates, child workflows
* **Phase 3** - Testing framework

> **Note:** Nexus support is a separate project and will be addressed independently.

## Design Principle

**Use idiomatic Kotlin language patterns wherever possible instead of custom APIs.**

The Kotlin SDK should feel natural to Kotlin developers by leveraging standard `kotlinx.coroutines` primitives. Custom APIs should only be introduced when Temporal-specific semantics cannot be achieved through standard patterns.

| Pattern | Standard Kotlin | Temporal Integration |
|---------|-----------------|----------------------|
| Parallel execution | `coroutineScope { async { ... } }` | Works via deterministic dispatcher |
| Await multiple | `awaitAll(d1, d2)` | Standard kotlinx.coroutines |
| Sleep/delay | `delay(duration)` | Intercepted via `Delay` interface |
| Deferred results | `Deferred<T>` | Standard + `Promise<T>.toDeferred()` |

This approach provides:
- **Familiar patterns**: Kotlin developers use patterns they already know
- **IDE support**: Full autocomplete and documentation for standard APIs
- **Ecosystem compatibility**: Works with existing coroutine libraries and utilities
- **Smaller API surface**: Less custom code to learn and maintain

## Kotlin Idioms

The SDK leverages Kotlin-specific language features for an idiomatic experience.

### Kotlin Duration

Use `kotlin.time.Duration` for readable time expressions:

```kotlin
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.hours

// Activity with timeouts using existing DSL builders
val result = KWorkflow.executeActivity<String>(
    "ProcessOrder",
    ActivityOptions {
        startToCloseTimeout = 30.seconds
        scheduleToCloseTimeout = 5.minutes
        heartbeatTimeout = 10.seconds
    },
    orderData
)

// Timers - standard kotlinx.coroutines delay (intercepted for determinism)
delay(1.hours)
```

> **Note:** The `ActivityOptions { }` DSL already exists in the `temporal-kotlin` module. The `Delay` interface intercepts standard `delay()` calls and routes them through Temporal's deterministic timer.

### Null Safety

Nullable types replace `Optional<T>` throughout the API. The following Java SDK types have Kotlin equivalents with null-safe APIs:

| Java SDK | Kotlin SDK |
|----------|------------|
| `io.temporal.workflow.Workflow` | `KWorkflow` object |
| `io.temporal.workflow.WorkflowInfo` | `KWorkflowInfo` |
| `io.temporal.workflow.Promise<T>` | Standard `Deferred<T>` via `Promise<T>.toDeferred()` |
| `io.temporal.activity.Activity` | `KActivity` object |
| `io.temporal.activity.ActivityExecutionContext` | `KActivityContext` |
| `io.temporal.activity.ActivityInfo` | `KActivityInfo` |
| `io.temporal.client.WorkflowStub` | `KWorkflowHandle<T>` / `KTypedWorkflowHandle<T, R>` |

```kotlin
// KWorkflowInfo - nullable instead of Optional
interface KWorkflowInfo {
    val workflowId: String
    val runId: String
    val parentWorkflowId: String?          // Optional in Java
    val parentRunId: String?               // Optional in Java
    fun getMemo(key: String): String?      // Optional in Java
    fun getSearchAttribute(key: String): Any?
    // ... other properties
}

// KActivityContext - activity execution context
interface KActivityContext {
    val info: KActivityInfo
    suspend fun heartbeat(details: Any? = null)
    fun doNotCompleteOnReturn()
    // ... other methods
}

// KActivityInfo - nullable instead of Optional
interface KActivityInfo {
    val activityId: String
    val activityType: String
    val workflowId: String
    val attempt: Int
    fun getHeartbeatDetails(): Payloads?   // Optional in Java
    // ... other properties
}

// Access via KWorkflow / KActivity
val info: KWorkflowInfo = KWorkflow.getInfo()
val parentId: String? = info.parentWorkflowId

val context: KActivityContext = KActivity.getContext()
val activityInfo: KActivityInfo = context.info
context.heartbeat("progress")
```

This eliminates `.orElse(null)`, `.isPresent`, and other Optional ceremony.

### Property Syntax for Queries

Queries can be defined as Kotlin properties in the workflow interface:

```kotlin
@WorkflowInterface
interface OrderWorkflow {
    @QueryMethod
    val status: OrderStatus  // Property syntax

    @QueryMethod
    fun getItemCount(): Int  // Method syntax
}

// Client usage via typed handle
val handle = client.getKWorkflowHandle<OrderWorkflow>("order-123")
val status = handle.query(OrderWorkflow::status)
val count = handle.query(OrderWorkflow::getItemCount)
```

## Workflow Definition

There are two approaches for workflow definition, depending on whether you need Java interoperability.

### Option A: Pure Kotlin (Recommended for Kotlin-only codebases)

For pure Kotlin codebases, define interfaces with `suspend` methods:

```kotlin
@WorkflowInterface
interface GreetingWorkflow {
    @WorkflowMethod
    suspend fun getGreeting(name: String): String
}

class GreetingWorkflowImpl : GreetingWorkflow {
    override suspend fun getGreeting(name: String): String {
        return KWorkflow.executeActivity<String>(
            "composeGreeting",
            ActivityOptions { startToCloseTimeout = 10.seconds },
            "Hello", name
        )
    }
}

// Client call - same pattern as activities, no stub needed
val result = client.executeWorkflow(
    GreetingWorkflow::getGreeting,
    WorkflowOptions {
        workflowId = "greeting-123"
        taskQueue = "greetings"
    },
    "Temporal"
)
```

### Option B: Java Interoperability (Parallel Interface Pattern)

When you need to share workflow interfaces with Java code, use the parallel interface pattern:

```kotlin
// Interface for client calls - non-suspend for Java compatibility
@WorkflowInterface
interface OrderWorkflow {
    @WorkflowMethod
    fun processOrder(order: Order): OrderResult

    @SignalMethod
    fun cancelOrder(reason: String)

    @QueryMethod
    val status: OrderStatus
}

// Parallel suspend interface for Kotlin implementation
@KWorkflowImpl(workflowInterface = OrderWorkflow::class)
interface OrderWorkflowSuspend {
    suspend fun processOrder(order: Order): OrderResult
    suspend fun cancelOrder(reason: String)
    val status: OrderStatus  // Queries are never suspend
}

// Kotlin implementation uses the suspend interface
class OrderWorkflowImpl : OrderWorkflowSuspend {
    override suspend fun processOrder(order: Order): OrderResult {
        // Full coroutine support - delay(), async, etc.
        delay(1.hours)
        return OrderResult(success = true)
    }

    override suspend fun cancelOrder(reason: String) { /* ... */ }
    override val status: OrderStatus get() = OrderStatus.PENDING
}

// Client call - same pattern, blocking for Option B
val result = client.executeWorkflow(
    OrderWorkflow::processOrder,
    WorkflowOptions {
        workflowId = "order-123"
        taskQueue = "orders"
    },
    order
)
```

**When to use which:**

| Scenario | Approach |
|----------|----------|
| Pure Kotlin codebase | Option A - suspend interfaces |
| Calling Java-defined workflows | Option A works (from coroutine context) |
| Kotlin workflows with Java-defined interface | Option B - parallel interface |
| Shared interface library with Java | Option B - parallel interface |

### Key Characteristics

* Use `coroutineScope`, `async`, `launch` for concurrent execution
* Use `delay()` for timers (maps to Temporal timers, not `Thread.sleep`)
* Reuses `@WorkflowInterface` and `@WorkflowMethod` annotations from Java SDK
* Data classes work naturally for parameters and results

### Signals, Queries, and Updates

Signals and updates follow the same suspend/non-suspend pattern as workflow methods. Queries are always synchronous (never suspend) and can be defined as properties:

```kotlin
@WorkflowInterface
interface OrderWorkflow {
    @WorkflowMethod
    suspend fun processOrder(order: Order): OrderResult

    @SignalMethod
    suspend fun cancelOrder(reason: String)

    @UpdateMethod
    suspend fun addItem(item: OrderItem): Boolean

    @UpdateValidatorMethod(updateMethod = "addItem")
    fun validateAddItem(item: OrderItem)

    // Queries - always synchronous, can use property syntax
    @QueryMethod
    val status: OrderStatus

    @QueryMethod
    fun getItemCount(): Int
}
```

### Child Workflows

Child workflows use the same stub-less pattern as activities:

```kotlin
// Simple case - execute child workflow and wait for result
override suspend fun parentWorkflow(): String {
    return KWorkflow.executeChildWorkflow(
        ChildWorkflow::doWork,
        ChildWorkflowOptions {
            workflowId = "child-workflow-id"
        },
        "input"
    )
}

// Parallel case - use standard coroutineScope { async {} }
override suspend fun parentWorkflowParallel(): String = coroutineScope {
    // Start child and activity in parallel using standard Kotlin async
    val childDeferred = async {
        KWorkflow.executeChildWorkflow(
            ChildWorkflow::doWork,
            ChildWorkflowOptions { workflowId = "child-workflow-id" },
            "input"
        )
    }
    val activityDeferred = async {
        KWorkflow.executeActivity(
            SomeActivities::doSomething,
            ActivityOptions { startToCloseTimeout = 30.seconds }
        )
    }

    // Wait for both using standard awaitAll
    val (childResult, activityResult) = awaitAll(childDeferred, activityDeferred)
    "$childResult - $activityResult"
}
```

> **Note:** We use standard `coroutineScope { async { } }` instead of custom `startChildWorkflow` or `startActivity` methods. The deterministic dispatcher ensures these execute correctly during replay.

**ChildWorkflowOptions:**

```kotlin
ChildWorkflowOptions {
    workflowId = "child-workflow-id"
    taskQueue = "child-queue"                      // Optional: defaults to parent's task queue
    workflowExecutionTimeout = 1.hours
    workflowRunTimeout = 30.minutes
    retryOptions = RetryOptions {
        initialInterval = 1.seconds
        maximumAttempts = 3
    }
    parentClosePolicy = ParentClosePolicy.TERMINATE
    cancellationType = ChildWorkflowCancellationType.WAIT_CANCELLATION_COMPLETED
}
```

### Timers and Delays

```kotlin
override suspend fun workflowWithTimer(): String {
    // Simple delay using Kotlin Duration
    delay(5.minutes)

    return "completed"
}
```

### Parallel Execution

Use standard `coroutineScope { async { } }` for parallel execution:

```kotlin
val options = ActivityOptions { startToCloseTimeout = 30.seconds }

override suspend fun parallelWorkflow(items: List<Item>): List<Result> = coroutineScope {
    // Process all items in parallel using standard Kotlin patterns
    items.map { item ->
        async {
            KWorkflow.executeActivity<Result>("process", options, item)
        }
    }.awaitAll()  // Standard kotlinx.coroutines.awaitAll
}

// Another example: parallel activities with different results
override suspend fun getGreetings(name: String): String = coroutineScope {
    val hello = async { KWorkflow.executeActivity<String>("greet", options, "Hello", name) }
    val goodbye = async { KWorkflow.executeActivity<String>("greet", options, "Goodbye", name) }

    // Standard awaitAll works with any Deferred
    val (helloResult, goodbyeResult) = awaitAll(hello, goodbye)
    "$helloResult\n$goodbyeResult"
}
```

**Why this works deterministically:**
- All coroutines inherit the workflow's deterministic dispatcher
- The dispatcher executes tasks in a FIFO queue ensuring consistent ordering
- Same execution order during replay

> **Note:** `coroutineScope` provides structured concurrency—if one `async` fails, all others are automatically cancelled. This maps naturally to Temporal's cancellation semantics.

### Await Condition

Wait for a condition to become true (equivalent to Java's `Workflow.await()`):

```kotlin
override suspend fun workflowWithCondition(): String {
    var approved = false

    // Signal handler sets approved = true
    // ...

    // Wait until approved (blocks workflow until condition is true)
    KWorkflow.awaitCondition { approved }

    return "Approved"
}

// With timeout - returns false if timed out
override suspend fun workflowWithTimeout(): String {
    var approved = false

    val wasApproved = KWorkflow.awaitCondition(timeout = 24.hours) { approved }

    return if (wasApproved) "Approved" else "Timed out"
}
```

> **Note:** Versioning (`KWorkflow.getVersion`), continue-as-new (`KWorkflow.continueAsNew`), side effects (`KWorkflow.sideEffect`), and search attributes (`KWorkflow.upsertSearchAttributes`) use the same patterns as the Java SDK.

## Cancellation

Kotlin's built-in coroutine cancellation replaces Java SDK's `CancellationScope`. This provides a more idiomatic experience while maintaining full Temporal semantics.

### How Cancellation Works

When a workflow is cancelled (from the server or programmatically), the Kotlin SDK translates this into coroutine cancellation. Cancellation is **cooperative**—it's checked at suspension points (`delay`, activity execution, child workflow execution, etc.):

```kotlin
override suspend fun processOrder(order: Order): OrderResult = coroutineScope {
    // Cancellation is checked at each suspension point
    val validated = KWorkflow.executeActivity(...)  // ← cancellation checked here
    delay(5.minutes)                                 // ← cancellation checked here
    val result = KWorkflow.executeActivity(...)      // ← cancellation checked here
    result
}
```

### Explicit Cancellation Checks

In rare cases where workflow code doesn't have suspension points (e.g., tight loops), you can check cancellation explicitly using `isActive` or `ensureActive()`. However, CPU-bound work should typically be delegated to activities.

### Parallel Execution and Cancellation

`coroutineScope` provides structured concurrency—if one child fails or the scope is cancelled, all children are automatically cancelled:

```kotlin
override suspend fun parallelWorkflow(): String = coroutineScope {
    val a = async { KWorkflow.executeActivity(...) }
    val b = async { KWorkflow.executeActivity(...) }

    // If either activity fails, the other is cancelled
    // If workflow is cancelled, both activities are cancelled
    "${a.await()} - ${b.await()}"
}
```

### Detached Scopes (Cleanup Logic)

Use `withContext(NonCancellable)` for cleanup code that must run even when the workflow is cancelled:

```kotlin
override suspend fun processOrder(order: Order): OrderResult {
    try {
        return doProcessOrder(order)
    } catch (e: CancellationException) {
        // Cleanup runs even though workflow is cancelled
        withContext(NonCancellable) {
            KWorkflow.executeActivity(
                OrderActivities::releaseReservation,
                ActivityOptions { startToCloseTimeout = 30.seconds },
                order
            )
        }
        throw e  // Re-throw to propagate cancellation
    }
}
```

This is equivalent to Java's `Workflow.newDetachedCancellationScope()`.

### Cancellation with Timeout

Use `withTimeout` to cancel a block after a duration:

```kotlin
override suspend fun processWithDeadline(order: Order): OrderResult {
    return withTimeout(1.hours) {
        // Everything in this block is cancelled if it takes > 1 hour
        val validated = KWorkflow.executeActivity(...)
        val charged = KWorkflow.executeActivity(...)
        OrderResult(success = true)
    }
}

// Or use withTimeoutOrNull to get null instead of exception
override suspend fun tryProcess(order: Order): OrderResult? {
    return withTimeoutOrNull(30.minutes) {
        KWorkflow.executeActivity(...)
    }
}
```

### Comparison with Java SDK

| Java SDK | Kotlin SDK |
|----------|------------|
| `Workflow.newCancellationScope(() -> { ... })` | `coroutineScope { ... }` |
| `Workflow.newDetachedCancellationScope(() -> { ... })` | `withContext(NonCancellable) { ... }` |
| `CancellationScope.cancel()` | `job.cancel()` |
| `CancellationScope.isCancelRequested()` | `!isActive` |
| `CancellationScope.throwCanceled()` | `ensureActive()` |
| `scope.run()` with timeout | `withTimeout(duration) { ... }` |

## Activity Definition

### String-based Activity Execution (Phase 1)

For calling activities by name (useful for cross-language interop or dynamic activity names):

```kotlin
// Execute activity by string name - suspend function, awaits result
val result = KWorkflow.executeActivity<String>(
    "activityName",
    ActivityOptions {
        startToCloseTimeout = 30.seconds
        retryOptions {
            initialInterval = 1.seconds
            maximumAttempts = 3
        }
    },
    arg1, arg2
)

// Parallel execution - use standard coroutineScope { async {} }
val results = coroutineScope {
    val d1 = async { KWorkflow.executeActivity<String>("activity1", options, arg1) }
    val d2 = async { KWorkflow.executeActivity<String>("activity2", options, arg2) }
    awaitAll(d1, d2)  // Returns List<String>
}
```

> **Note:** The `ActivityOptions { }` DSL already exists in `temporal-kotlin`. The nested `retryOptions { }` block is also supported.

### Typed Activities (Phase 2)

The typed activity API uses direct method references - no stub creation needed. This approach:
- Provides full compile-time type safety for arguments and return types
- Allows different options (timeouts, retry policies) per activity call
- Works with both Kotlin `suspend` and Java non-suspend activity interfaces
- Similar to TypeScript and Python SDK patterns

```kotlin
// Define activity interface
@ActivityInterface
interface GreetingActivities {
    @ActivityMethod
    suspend fun composeGreeting(greeting: String, name: String): String

    @ActivityMethod
    suspend fun sendEmail(email: Email): SendResult

    @ActivityMethod
    suspend fun log(message: String)
}

// In workflow - direct method reference, no stub needed
val greeting = KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,  // Direct reference to interface method
    ActivityOptions {
        startToCloseTimeout = 30.seconds
    },
    "Hello", "World"
)

// Different activity, different options
val result = KWorkflow.executeActivity(
    GreetingActivities::sendEmail,
    ActivityOptions {
        startToCloseTimeout = 2.minutes
        retryOptions = RetryOptions {
            maximumAttempts = 5
        }
    },
    email
)

// Void activities work too
KWorkflow.executeActivity(
    GreetingActivities::log,
    ActivityOptions { startToCloseTimeout = 5.seconds },
    "Processing started"
)
```

**Type Safety:** The API uses `KFunction` reflection to extract method metadata and provides compile-time type checking:

```kotlin
// Compile error! Wrong argument types
KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,
    options,
    123, true  // ✗ Type mismatch: expected String, String
)
```

**Parallel Execution:** Use standard `coroutineScope { async { } }` for concurrent execution:

```kotlin
override suspend fun parallelGreetings(names: List<String>): List<String> = coroutineScope {
    names.map { name ->
        async {
            KWorkflow.executeActivity(
                GreetingActivities::composeGreeting,
                ActivityOptions { startToCloseTimeout = 10.seconds },
                "Hello", name
            )
        }
    }.awaitAll()  // Standard kotlinx.coroutines.awaitAll
}

// Multiple different activities in parallel
val (result1, result2) = coroutineScope {
    val d1 = async { KWorkflow.executeActivity(Activities::operation1, options, arg1) }
    val d2 = async { KWorkflow.executeActivity(Activities::operation2, options, arg2) }
    awaitAll(d1, d2)
}
```

> **Note:** We use standard Kotlin `async` instead of a custom `startActivity` method. The workflow's deterministic dispatcher ensures correct replay behavior.

**Java Activity Interoperability:** Method references work regardless of whether the activity is defined in Kotlin or Java:

```kotlin
// Java activity interface works seamlessly
// public interface JavaPaymentActivities {
//     PaymentResult processPayment(String orderId, BigDecimal amount);
// }

val result: PaymentResult = KWorkflow.executeActivity(
    JavaPaymentActivities::processPayment,
    ActivityOptions { startToCloseTimeout = 2.minutes },
    orderId, amount
)
```

### Activity Execution API

The `KWorkflow` object provides type-safe overloads using `KFunction` types. The interface method reference (`Interface::method`) is used to extract metadata (interface class, method name) via reflection - the function is never invoked directly.

```kotlin
import kotlin.reflect.KFunction

object KWorkflow {
    // Execute activity - uses KFunction for metadata extraction
    // T = activity interface, A1..An = arguments, R = return type

    // 1 argument
    suspend fun <T, A1, R> executeActivity(
        activity: KFunction2<T, A1, R>,  // T::method with 1 arg
        options: ActivityOptions,
        arg1: A1
    ): R

    // 2 arguments
    suspend fun <T, A1, A2, R> executeActivity(
        activity: KFunction3<T, A1, A2, R>,  // T::method with 2 args
        options: ActivityOptions,
        arg1: A1, arg2: A2
    ): R

    // ... up to 6 arguments

    // Local activity - same pattern
    suspend fun <T, A1, R> executeLocalActivity(
        activity: KFunction2<T, A1, R>,
        options: LocalActivityOptions,
        arg1: A1
    ): R

    // --- String-based overloads (untyped) ---

    // Execute activity by name
    suspend inline fun <reified R> executeActivity(
        activityName: String,
        options: ActivityOptions,
        vararg args: Any?
    ): R

    // Execute local activity by name
    suspend inline fun <reified R> executeLocalActivity(
        activityName: String,
        options: LocalActivityOptions,
        vararg args: Any?
    ): R
}
```

**Parallel Execution:** Use standard `coroutineScope { async { } }` instead of custom handle types:

```kotlin
// Standard Kotlin pattern for parallel execution
val results = coroutineScope {
    val d1 = async { KWorkflow.executeActivity<Int>("add", options, 1, 2) }
    val d2 = async { KWorkflow.executeActivity<Int>("add", options, 3, 4) }
    awaitAll(d1, d2)  // Returns standard Deferred<Int> instances
}
```

> **Implementation Note:** `KFunction` provides `.name` for the method name and `.parameters[0].type` for the declaring interface. This metadata is used to make Temporal activity calls by name.

### Activity Implementation

There are two approaches for activity implementation, depending on whether you need Java interoperability.

#### Option A: Pure Kotlin (Recommended for Kotlin-only codebases)

For pure Kotlin codebases, define interfaces with `suspend` methods directly:

```kotlin
@ActivityInterface
interface GreetingActivities {
    @ActivityMethod
    suspend fun composeGreeting(greeting: String, name: String): String

    @ActivityMethod
    suspend fun sendEmail(email: Email): SendResult
}

class GreetingActivitiesImpl(
    private val emailService: EmailService
) : GreetingActivities {

    override suspend fun composeGreeting(greeting: String, name: String): String {
        // Full coroutine support - use withContext, async I/O, etc.
        return withContext(Dispatchers.IO) {
            "$greeting, $name!"
        }
    }

    override suspend fun sendEmail(email: Email): SendResult {
        // Suspend functions for async I/O
        return emailService.send(email)
    }
}

// In workflow - direct method reference, no stub needed
val greeting = KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,
    ActivityOptions { startToCloseTimeout = 30.seconds },
    "Hello", "World"
)
```

#### Option B: Java Interoperability (Parallel Interface Pattern)

When you need to share activity interfaces with Java code (e.g., activities implemented in Java, or interfaces defined in a shared Java module), use the parallel interface pattern:

```kotlin
// Interface for workflow calls - non-suspend for Java compatibility
// This interface can be defined in Java or Kotlin
@ActivityInterface
interface OrderActivities {
    @ActivityMethod
    fun validateOrder(order: Order): Boolean

    @ActivityMethod
    fun chargePayment(order: Order): PaymentResult
}

// Parallel suspend interface for Kotlin implementation
// Linked to the original interface via annotation
@KActivityImpl(activities = OrderActivities::class)
interface OrderActivitiesSuspend {
    suspend fun validateOrder(order: Order): Boolean
    suspend fun chargePayment(order: Order): PaymentResult
}

// Kotlin implementation uses the suspend interface
class OrderActivitiesImpl(
    private val paymentService: PaymentService
) : OrderActivitiesSuspend {

    override suspend fun validateOrder(order: Order): Boolean {
        return order.items.isNotEmpty() && order.total > 0
    }

    override suspend fun chargePayment(order: Order): PaymentResult {
        // Full suspend support for async operations
        return paymentService.charge(order)
    }
}

// In workflow - use the non-suspend interface for method references
val isValid = KWorkflow.executeActivity(
    OrderActivities::validateOrder,
    ActivityOptions { startToCloseTimeout = 10.seconds },
    order
)
```

**When to use which:**

| Scenario | Approach |
|----------|----------|
| Pure Kotlin codebase | Option A - suspend interfaces |
| Calling Java-defined activities | Option A works (executeActivity handles it) |
| Kotlin activities with Java-defined interface | Option B - parallel interface |
| Shared interface library with Java | Option B - parallel interface |

#### Registering Activities

```kotlin
// Option A: Register suspend implementation directly
worker.registerActivitiesImplementations(GreetingActivitiesImpl(emailService))

// Option B: Register implementation - binding inferred from @KActivityImpl annotation
worker.registerActivitiesImplementations(OrderActivitiesImpl(paymentService))
```

### Local Activities

Local activities use the same stub-less pattern:

```kotlin
@ActivityInterface
interface ValidationActivities {
    fun validate(input: String): Boolean
    fun sanitize(input: String): String
}

val isValid = KWorkflow.executeLocalActivity(
    ValidationActivities::validate,
    LocalActivityOptions {
        startToCloseTimeout = 5.seconds
    },
    input
)

val sanitized = KWorkflow.executeLocalActivity(
    ValidationActivities::sanitize,
    LocalActivityOptions {
        startToCloseTimeout = 1.seconds
    },
    input
)
```

> **Note:** Activity context, heartbeating, and async activity completion use the same APIs as the Java SDK (`Activity.getExecutionContext()`, `ActivityCompletionClient`, etc.).

## Client API

> **Note:** Many client extensions already exist in the `temporal-kotlin` module, including:
> - `WorkflowClient { }` DSL constructor
> - `WorkflowClient.newWorkflowStub<T> { }` with reified generics
> - `WorkflowStub.getResult<T>()` with reified generics
> - `WorkflowOptions { }`, `WorkflowClientOptions { }` DSL builders

### Creating a Client

```kotlin
val service = WorkflowServiceStubs.newLocalServiceStubs()

// Uses existing WorkflowClient DSL extension
val client = WorkflowClient(service) {
    setNamespace("default")
    setDataConverter(myConverter)
}
```

### Starting Workflows

```kotlin
// Execute workflow and wait for result - no stub needed
val result = client.executeWorkflow(
    GreetingWorkflow::getGreeting,
    WorkflowOptions {
        workflowId = "greeting-123"
        taskQueue = "greeting-queue"
        workflowExecutionTimeout = 1.hours
    },
    "Temporal"
)

// Or start async and get handle
val handle = client.startWorkflow(
    GreetingWorkflow::getGreeting,
    WorkflowOptions {
        workflowId = "greeting-123"
        taskQueue = "greeting-queue"
    },
    "Temporal"
)
val result = handle.result()  // Type inferred as String from method reference
```

### SignalWithStart

Atomically start a workflow and send a signal. If the workflow already exists, only the signal is sent:

```kotlin
// Returns KTypedWorkflowHandle<OrderWorkflow, OrderResult> - result type captured from method reference
val handle = client.signalWithStart(
    // Workflow to start
    workflow = OrderWorkflow::processOrder,
    options = WorkflowOptions {
        workflowId = "order-123"
        taskQueue = "orders"
    },
    workflowArg = order,
    // Signal to send
    signal = OrderWorkflow::cancelOrder,
    signalArg = "Price changed"
)

// Can use typed handle for queries/signals
val status = handle.query(OrderWorkflow::status)
val result = handle.result()  // Type inferred as OrderResult
```

### UpdateWithStart

Atomically start a workflow and send an update. If the workflow already exists, only the update is sent:

```kotlin
// Returns Pair<KTypedWorkflowHandle<OrderWorkflow, OrderResult>, Boolean>
// - handle with result type captured from workflow method reference
// - updateResult typed by update method return type
val (handle, updateResult: Boolean) = client.updateWithStart(
    // Workflow to start
    workflow = OrderWorkflow::processOrder,
    workflowArg = order,
    // Update to send
    update = OrderWorkflow::addItem,
    updateArg = newItem,
    // Options
    options = WorkflowOptions {
        workflowId = "order-123"
        taskQueue = "orders"
    }
)
println("Item added: $updateResult")

// Can use typed handle for further operations
val result = handle.result()  // Type inferred as OrderResult
```

### Workflow Handle

For interacting with existing workflows (signals, queries, results, cancellation), use a typed or untyped handle:

```kotlin
// Get typed handle for existing workflow by ID (like Python's get_workflow_handle_for)
val handle = client.getKWorkflowHandle<OrderWorkflow>("order-123")

// Send signal - method reference provides type safety
handle.signal(OrderWorkflow::cancelOrder, "Customer request")

// Query - method reference with compile-time type checking
val status = handle.query(OrderWorkflow::status)
val count = handle.query(OrderWorkflow::getItemCount)

// Get result (suspends until workflow completes)
val result = handle.result<OrderResult>()

// Updates - execute and wait for result
val updateResult = handle.executeUpdate(OrderWorkflow::addItem, newItem)

// Or start update async and get handle
val updateHandle = handle.startUpdate(OrderWorkflow::addItem, newItem)
val asyncResult = updateHandle.result()

// Cancel or terminate
handle.cancel()
handle.terminate("No longer needed")

// Workflow metadata
val info = handle.describe()
println("Workflow ID: ${handle.workflowId}, Run ID: ${handle.runId}")
```

**KWorkflowHandle API:**

```kotlin
// Base handle - returned by getKWorkflowHandle<T>(id)
// Result type is unknown, must specify when calling result<R>()
interface KWorkflowHandle<T> {
    val workflowId: String
    val runId: String?

    // Result - requires explicit type since we don't know it
    suspend fun <R> result(): R

    // Signals - type-safe method references
    suspend fun signal(method: KFunction1<T, *>)
    suspend fun <A1> signal(method: KFunction2<T, A1, *>, arg: A1)
    suspend fun <A1, A2> signal(method: KFunction3<T, A1, A2, *>, arg1: A1, arg2: A2)

    // Queries - type-safe method references
    fun <R> query(method: KFunction1<T, R>): R
    fun <R, A1> query(method: KFunction2<T, A1, R>, arg: A1): R

    // Updates - execute and wait for result
    suspend fun <R> executeUpdate(method: KFunction1<T, R>): R
    suspend fun <R, A1> executeUpdate(method: KFunction2<T, A1, R>, arg: A1): R

    // Updates - start and get handle for async result
    suspend fun <R> startUpdate(method: KFunction1<T, R>): KUpdateHandle<R>
    suspend fun <R, A1> startUpdate(method: KFunction2<T, A1, R>, arg: A1): KUpdateHandle<R>

    // Get handle for existing update by ID
    fun <R> getKUpdateHandle(updateId: String): KUpdateHandle<R>

    // Lifecycle
    suspend fun cancel()
    suspend fun terminate(reason: String? = null)
    fun describe(): WorkflowExecutionInfo
}

// Extended handle - returned by startWorkflow()
// Result type R is captured from the workflow method reference
interface KTypedWorkflowHandle<T, R> : KWorkflowHandle<T> {
    // Result type is known from method reference - no type parameter needed
    suspend fun result(): R
}

interface KUpdateHandle<R> {
    val updateId: String
    suspend fun result(): R
}
```

**How result type is captured:**

```kotlin
// startWorkflow captures result type from method reference
suspend fun <T, A1, R> startWorkflow(
    workflow: KFunction2<T, A1, R>,  // R is captured here
    options: WorkflowOptions,
    arg: A1
): KTypedWorkflowHandle<T, R>  // R is preserved in return type

// Usage - result type is inferred
val handle = client.startWorkflow(
    OrderWorkflow::processOrder,  // KFunction2<OrderWorkflow, Order, OrderResult>
    options,
    order
)
val result: OrderResult = handle.result()  // No type parameter needed!

// getKWorkflowHandle doesn't know result type
val existingHandle = client.getKWorkflowHandle<OrderWorkflow>(workflowId)
val result = existingHandle.result<OrderResult>()  // Must specify type
```

This pattern matches Python SDK's `WorkflowHandle` with the same method names (`signal`, `query`, `result`, `cancel`, `terminate`, `execute_update`, `start_update`).

**Untyped Handle (like Python's `get_workflow_handle`):**

For cases where you don't know the workflow type at compile time:

```kotlin
// Untyped handle - signal/query by string name
val untypedHandle = client.getWorkflowHandle("order-123")

// Operations use string names instead of method references
untypedHandle.signal("cancelOrder", "Customer request")
val status = untypedHandle.query<OrderStatus>("status")
val result = untypedHandle.result<OrderResult>()

// Cancel/terminate work the same
untypedHandle.cancel()
```

```kotlin
interface WorkflowHandle {
    val workflowId: String
    val runId: String?

    suspend fun <R> result(): R
    suspend fun signal(signalName: String, vararg args: Any?)
    fun <R> query(queryName: String, vararg args: Any?): R
    suspend fun executeUpdate(updateName: String, vararg args: Any?): Any?
    suspend fun cancel()
    suspend fun terminate(reason: String? = null)
    fun describe(): WorkflowExecutionInfo
}
```

## Worker API

### Enabling Kotlin Coroutine Support

Kotlin coroutine support is enabled via a plugin passed to the client (similar to Python SDK's plugin system). The plugin provides custom workflow and activity executors that handle `suspend` functions.

```kotlin
val service = WorkflowServiceStubs.newLocalServiceStubs()

// Plugin is passed to the client and propagates to workers
val client = WorkflowClient(service) {
    plugins = listOf(KotlinPlugin())
}

val factory = WorkerFactory(client) {
    maxWorkflowThreadCount = 800
}

val worker = factory.newWorker("task-queue") {
    maxConcurrentActivityExecutionSize = 100
}

// Register Kotlin coroutine workflows
worker.registerWorkflowImplementationTypes(
    GreetingWorkflowImpl::class,
    OrderWorkflowImpl::class
)

// Register activities - plugin detects suspend functions automatically
worker.registerActivitiesImplementations(
    GreetingActivitiesImpl(),  // Kotlin suspend activities
    JavaActivitiesImpl()        // Java activities work too
)

// Start the worker
factory.start()
```

> **Note:** The plugin API will be defined separately. It follows the same pattern as Python SDK's plugin system, allowing custom workflow runners and activity executors.

### Mixed Java and Kotlin

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

## Data Conversion

The Kotlin SDK uses `kotlinx.serialization` by default for JSON serialization. It provides compile-time safety, no reflection overhead, and native Kotlin support.

### kotlinx.serialization (Default)

Annotate data classes with `@Serializable`:

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

@Serializable
enum class OrderStatus { PENDING, PROCESSING, COMPLETED }
```

No additional configuration needed—the SDK automatically uses `kotlinx.serialization` for classes annotated with `@Serializable`.

**Custom JSON configuration:**

```kotlin
val client = WorkflowClient(service) {
    dataConverter = KotlinxSerializationDataConverter {
        ignoreUnknownKeys = true
        prettyPrint = false  // default
        encodeDefaults = true
    }
}
```

### Jackson (Optional, for Java Interop)

For mixed Java/Kotlin codebases or when integrating with existing Jackson-based infrastructure:

```kotlin
val converter = DefaultDataConverter.newDefaultInstance().withPayloadConverterOverrides(
    JacksonJsonPayloadConverter(
        KotlinObjectMapperFactory.new()
    )
)

val client = WorkflowClient(service) {
    dataConverter = converter
}
```

> **Note:** Jackson requires the `jackson-module-kotlin` dependency and uses runtime reflection. Prefer `kotlinx.serialization` for pure Kotlin projects.

## Interceptors

### Kotlin Interceptor Interface

```kotlin
interface KWorkerInterceptor {
    fun interceptWorkflow(next: KWorkflowInboundCallsInterceptor): KWorkflowInboundCallsInterceptor {
        return next
    }

    fun interceptActivity(next: KActivityInboundCallsInterceptor): KActivityInboundCallsInterceptor {
        return next
    }
}

interface KWorkflowInboundCallsInterceptor {
    suspend fun init(outboundCalls: KWorkflowOutboundCallsInterceptor)
    suspend fun execute(input: WorkflowInput): WorkflowOutput
    suspend fun handleSignal(input: SignalInput)
    suspend fun handleUpdate(input: UpdateInput): UpdateOutput
    fun handleQuery(input: QueryInput): QueryOutput
}

interface KWorkflowOutboundCallsInterceptor {
    suspend fun <R> executeActivity(input: ActivityInput<R>): ActivityOutput<R>
    fun <R> startActivity(input: ActivityInput<R>): KActivityHandle<R>
    suspend fun <R> executeChildWorkflow(input: ChildWorkflowInput<R>): ChildWorkflowOutput<R>
    fun <R> startChildWorkflow(input: ChildWorkflowInput<R>): ChildWorkflowHandle<R>
}

interface KActivityInboundCallsInterceptor {
    suspend fun execute(input: ActivityInput): ActivityOutput
}
```

### Example: Logging Interceptor

```kotlin
class LoggingInterceptor : KWorkerInterceptor {
    override fun interceptWorkflow(
        next: KWorkflowInboundCallsInterceptor
    ): KWorkflowInboundCallsInterceptor {
        return object : KWorkflowInboundCallsInterceptorBase(next) {
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

### Registering Interceptors

Kotlin interceptors are registered via the `KotlinPlugin`, which propagates them to all workers:

```kotlin
val client = WorkflowClient(service) {
    plugins = listOf(
        KotlinPlugin {
            workerInterceptors = listOf(
                LoggingInterceptor(),
                MetricsInterceptor()
            )
        }
    )
}
```

## Migration from Java SDK

### API Mapping

| Java SDK | Kotlin SDK |
|----------|------------|
| **Activities** | |
| `Workflow.newUntypedActivityStub(opts)` | *(not needed - options passed per call)* |
| `activities.execute("name", Cls, arg)` | `KWorkflow.executeActivity<R>("name", options, arg)` |
| `stub.method(arg)` (typed activity) | `KWorkflow.executeActivity(Interface::method, options, arg)` |
| `Async.function(stub::method, arg)` | `coroutineScope { async { KWorkflow.executeActivity(...) } }` |
| **Workflows** | |
| `Workflow.newChildWorkflowStub(...)` | `KWorkflow.executeChildWorkflow(Interface::method, options, ...)` |
| `client.newWorkflowStub(...)` | `client.startWorkflow(Interface::method, ...)` → `KTypedWorkflowHandle<T, R>` |
| `client.newWorkflowStub(Cls, id)` | `client.getKWorkflowHandle<T>(id)` → `KWorkflowHandle<T>` |
| `stub.signal(arg)` | `handle.signal(T::method, arg)` |
| `stub.query()` | `handle.query(T::method)` |
| `handle.getResult()` | `handle.result()` (type inferred) or `handle.result<R>()` |
| **Primitives** | |
| `Workflow.sleep(duration)` | `delay(duration)` - standard kotlinx.coroutines |
| `Workflow.await(() -> cond)` | `KWorkflow.awaitCondition { cond }` |
| `Promise<T>` | Standard `Deferred<T>` via `Promise<T>.toDeferred()` |
| `Optional<T>` | `T?` |
| `Duration.ofSeconds(30)` | `30.seconds` |
| **Parallel Execution** | |
| `Async.function(...)` + `Promise.get()` | `coroutineScope { async { ... } }` + `awaitAll()` |

### Before (Java)

```java
@WorkflowInterface
public interface GreetingWorkflow {
    @WorkflowMethod
    String getGreeting(String name);
}

public class GreetingWorkflowImpl implements GreetingWorkflow {
    @Override
    public String getGreeting(String name) {
        ActivityStub activities = Workflow.newUntypedActivityStub(
            ActivityOptions.newBuilder()
                .setStartToCloseTimeout(Duration.ofSeconds(30))
                .build()
        );
        return activities.execute("greet", String.class, name);
    }
}
```

### After (Kotlin)

```kotlin
@WorkflowInterface
interface GreetingWorkflow {
    @WorkflowMethod
    suspend fun getGreeting(name: String): String
}

class GreetingWorkflowImpl : GreetingWorkflow {
    override suspend fun getGreeting(name: String): String {
        return KWorkflow.executeActivity<String>(
            "greet",
            ActivityOptions { startToCloseTimeout = 30.seconds },
            name
        )
    }
}
```

### Interoperability

Kotlin workflows can call Java activities using direct method references:

```kotlin
override suspend fun processOrder(order: Order): String {
    // JavaActivities is a Java @ActivityInterface - no stub needed
    return KWorkflow.executeActivity(
        JavaActivities::process,
        ActivityOptions { startToCloseTimeout = 30.seconds },
        order
    )
}
```

Java workflows can be invoked from Kotlin clients:

```kotlin
val result = client.executeWorkflow(
    JavaWorkflowInterface::execute,
    WorkflowOptions { taskQueue = "java-queue" },
    input
)
```

## Complete Example

This example uses Option A (pure Kotlin with suspend interfaces).

```kotlin
// === Domain Types ===

@Serializable
data class Order(
    val id: String,
    val customerId: String,
    val items: List<OrderItem>,
    val priority: Priority = Priority.NORMAL
) {
    val total: BigDecimal get() = items.sumOf { it.price * it.quantity.toBigDecimal() }
}

@Serializable
data class OrderItem(
    val productId: String,
    val quantity: Int,
    val price: BigDecimal
)

@Serializable
data class OrderResult(val success: Boolean, val trackingNumber: String?)

enum class OrderStatus { PENDING, PROCESSING, SHIPPED, CANCELED }
enum class Priority { LOW, NORMAL, HIGH }

// === Workflow Interface ===

@WorkflowInterface
interface OrderWorkflow {
    @WorkflowMethod
    suspend fun processOrder(order: Order): OrderResult

    @UpdateMethod
    suspend fun addItem(item: OrderItem): Boolean

    @UpdateValidatorMethod(updateMethod = "addItem")
    fun validateAddItem(item: OrderItem)

    @QueryMethod
    val status: OrderStatus

    @QueryMethod
    val progress: Int
}

// === Activity Interface ===

@ActivityInterface
interface OrderActivities {
    @ActivityMethod
    suspend fun validateOrder(order: Order): Boolean

    @ActivityMethod
    suspend fun reserveInventory(item: OrderItem): Boolean

    @ActivityMethod
    suspend fun releaseInventory(item: OrderItem): Boolean

    @ActivityMethod
    suspend fun chargePayment(order: Order): Boolean

    @ActivityMethod
    suspend fun refundPayment(order: Order): Boolean

    @ActivityMethod
    suspend fun shipOrder(order: Order): String

    @ActivityMethod
    suspend fun notifyCustomer(customerId: String, message: String)
}

// === Activity Implementation ===

class OrderActivitiesImpl(
    private val inventoryService: InventoryService,
    private val paymentService: PaymentService,
    private val shippingService: ShippingService,
    private val notificationService: NotificationService
) : OrderActivities {

    override suspend fun validateOrder(order: Order): Boolean {
        return order.items.isNotEmpty() && order.items.all { it.quantity > 0 }
    }

    override suspend fun reserveInventory(item: OrderItem): Boolean {
        return inventoryService.reserve(item.productId, item.quantity)
    }

    override suspend fun releaseInventory(item: OrderItem): Boolean {
        return inventoryService.release(item.productId, item.quantity)
    }

    override suspend fun chargePayment(order: Order): Boolean {
        return paymentService.charge(order.customerId, order.total)
    }

    override suspend fun refundPayment(order: Order): Boolean {
        return paymentService.refund(order.customerId, order.total)
    }

    override suspend fun shipOrder(order: Order): String {
        return shippingService.createShipment(order)
    }

    override suspend fun notifyCustomer(customerId: String, message: String) {
        notificationService.send(customerId, message)
    }
}

// === Workflow Implementation ===

class OrderWorkflowImpl : OrderWorkflow {
    private var _status = OrderStatus.PENDING
    private var _progress = 0
    private var _order: Order? = null
    private var paymentCharged = false
    private var reservedItems = mutableListOf<OrderItem>()

    override val status get() = _status
    override val progress get() = _progress

    // Reusable options for common cases
    private val defaultOptions = ActivityOptions {
        startToCloseTimeout = 30.seconds
        retryOptions = RetryOptions {
            initialInterval = 1.seconds
            maximumAttempts = 3
        }
    }

    override suspend fun processOrder(order: Order): OrderResult {
        _order = order
        _status = OrderStatus.PROCESSING

        return try {
            doProcessOrder(order)
        } catch (e: CancellationException) {
            // Workflow was cancelled - run cleanup in detached scope
            // This code runs even though the workflow is cancelled
            withContext(NonCancellable) {
                cleanup(order)
            }
            _status = OrderStatus.CANCELED
            throw e  // Re-throw to complete workflow as cancelled
        }
    }

    private suspend fun doProcessOrder(order: Order): OrderResult = coroutineScope {
        // Validate order - direct method reference, no stub needed
        _progress = 10
        val isValid = KWorkflow.executeActivity(
            OrderActivities::validateOrder,
            ActivityOptions { startToCloseTimeout = 10.seconds },
            order
        )
        if (!isValid) {
            return@coroutineScope OrderResult(success = false, trackingNumber = null)
        }

        // Reserve inventory for all items in parallel using standard async
        // If workflow is cancelled here, all parallel activities are cancelled
        _progress = 30
        order.items.map { item ->
            async {
                val reserved = KWorkflow.executeActivity(
                    OrderActivities::reserveInventory,
                    defaultOptions,
                    item
                )
                if (reserved) {
                    reservedItems.add(item)  // Track for cleanup
                }
                reserved
            }
        }.awaitAll()  // Standard kotlinx.coroutines.awaitAll

        _progress = 60

        // Charge payment with timeout - auto-cancels if takes too long
        val charged = withTimeout(2.minutes) {
            KWorkflow.executeActivity(
                OrderActivities::chargePayment,
                ActivityOptions {
                    startToCloseTimeout = 2.minutes
                    retryOptions {
                        initialInterval = 5.seconds
                        maximumAttempts = 5
                    }
                },
                order
            )
        }
        if (!charged) {
            return@coroutineScope OrderResult(success = false, trackingNumber = null)
        }
        paymentCharged = true

        _progress = 80

        // Ship order
        val trackingNumber = KWorkflow.executeActivity(
            OrderActivities::shipOrder,
            defaultOptions,
            order
        )

        _status = OrderStatus.SHIPPED
        _progress = 100

        OrderResult(success = true, trackingNumber = trackingNumber)
    }

    /**
     * Cleanup logic that runs even when workflow is cancelled.
     * Called from within withContext(NonCancellable) block.
     */
    private suspend fun cleanup(order: Order) {
        // Release any reserved inventory
        for (item in reservedItems) {
            try {
                KWorkflow.executeActivity(
                    OrderActivities::releaseInventory,
                    defaultOptions,
                    item
                )
            } catch (e: Exception) {
                // Log but continue cleanup
            }
        }

        // Refund payment if it was charged
        if (paymentCharged) {
            try {
                KWorkflow.executeActivity(
                    OrderActivities::refundPayment,
                    defaultOptions,
                    order
                )
            } catch (e: Exception) {
                // Log but continue cleanup
            }
        }

        // Notify customer of cancellation
        try {
            KWorkflow.executeActivity(
                OrderActivities::notifyCustomer,
                defaultOptions,
                order.customerId, "Your order has been cancelled"
            )
        } catch (e: Exception) {
            // Best effort notification
        }
    }

    override fun validateAddItem(item: OrderItem) {
        require(item.quantity > 0) { "Quantity must be positive" }
        require(item.price >= BigDecimal.ZERO) { "Price cannot be negative" }
        require(_status == OrderStatus.PENDING) { "Cannot add items after processing started" }
    }

    override suspend fun addItem(item: OrderItem): Boolean {
        // Validator already checked status, so this is safe
        // Update would modify order items here
        return true
    }
}

// === Worker Setup ===

fun main() = runBlocking {
    // Initialize services (could use DI framework)
    val inventoryService = InventoryServiceImpl()
    val paymentService = PaymentServiceImpl()
    val shippingService = ShippingServiceImpl()
    val notificationService = NotificationServiceImpl()

    val service = WorkflowServiceStubs.newLocalServiceStubs()

    // Enable Kotlin coroutine support via plugin
    val client = WorkflowClient(service) {
        plugins = listOf(KotlinPlugin())
    }

    val factory = WorkerFactory(client)
    val worker = factory.newWorker("orders")

    // Plugin handles suspend functions automatically
    worker.registerWorkflowImplementationTypes(OrderWorkflowImpl::class)
    worker.registerActivitiesImplementations(
        OrderActivitiesImpl(inventoryService, paymentService, shippingService, notificationService)
    )

    factory.start()

    // === Client Usage ===

    val order = Order(
        id = "12345",
        customerId = "cust-789",
        items = listOf(
            OrderItem("prod-1", 2, 29.99.toBigDecimal()),
            OrderItem("prod-2", 1, 49.99.toBigDecimal())
        )
    )

    val workflowId = "order-${UUID.randomUUID()}"

    // Start workflow and get handle
    val handle = client.startWorkflow(
        OrderWorkflow::processOrder,
        WorkflowOptions {
            workflowId = workflowId
            taskQueue = "orders"
        },
        order
    )
    println("Started workflow: ${handle.workflowId}")

    // Query workflow state using typed handle
    val status = handle.query(OrderWorkflow::status)
    val progress = handle.query(OrderWorkflow::progress)
    println("Status: $status, Progress: $progress%")

    // Or get handle for existing workflow by ID
    val existingHandle = client.getKWorkflowHandle<OrderWorkflow>(workflowId)

    // Send update and wait for result
    val newItem = OrderItem("prod-3", 1, 19.99.toBigDecimal())
    val added = existingHandle.executeUpdate(OrderWorkflow::addItem, newItem)
    println("Item added: $added")

    // === Cancellation ===

    // Cancel workflow - triggers CancellationException, cleanup block runs
    // existingHandle.cancel()

    // Or terminate immediately - no cleanup runs
    // existingHandle.terminate("Emergency shutdown")

    // Wait for result - type inferred from startWorkflow method reference
    // If workflow was cancelled, this throws WorkflowFailedException
    try {
        val result = handle.result()
        println("Order result: $result")
    } catch (e: WorkflowFailedException) {
        if (e.cause is CanceledFailure) {
            println("Order was cancelled - cleanup activities were executed")
        } else {
            throw e
        }
    }
}
```
