# Workflow Definition

There are two approaches for workflow definition, depending on whether you need Java interoperability.

## Option A: Pure Kotlin (Recommended)

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
            KActivityOptions(startToCloseTimeout = 10.seconds),
            "Hello", name
        )
    }
}

// Client call using KWorkflowClient - same pattern as activities, no stub needed
val result = client.executeWorkflow(
    GreetingWorkflow::getGreeting,
    KWorkflowOptions(
        workflowId = "greeting-123",
        taskQueue = "greetings"
    ),
    "Temporal"
)
```

## Option B: Java Interoperability (Parallel Interface Pattern)

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

// Client call using KWorkflowClient - same pattern, suspends for result
val result = client.executeWorkflow(
    OrderWorkflow::processOrder,
    KWorkflowOptions(
        workflowId = "order-123",
        taskQueue = "orders"
    ),
    order
)
```

## When to Use Which

| Scenario | Approach |
|----------|----------|
| Pure Kotlin codebase | Option A - suspend interfaces |
| Calling Java-defined workflows | Option A works (from coroutine context) |
| Kotlin workflows with Java-defined interface | Option B - parallel interface |
| Shared interface library with Java | Option B - parallel interface |

## Key Characteristics

* Use `coroutineScope`, `async`, `launch` for concurrent execution
* Use `delay()` for timers (maps to Temporal timers, not `Thread.sleep`)
* Reuses `@WorkflowInterface` and `@WorkflowMethod` annotations from Java SDK
* Data classes work naturally for parameters and results

## Logging

Use `KWorkflow.logger()` for workflow-safe logging:

```kotlin
// Get logger using workflow type as name
val log = KWorkflow.logger()
log.info("Processing order")

// Or with custom logger name
val customLog = KWorkflow.logger("my.custom.logger")

// Or with class
val classLog = KWorkflow.logger(MyWorkflowImpl::class.java)
```

> **Note:** Versioning (`KWorkflow.getVersion`), side effects (`KWorkflow.sideEffect`), and search attributes (`KWorkflow.upsertSearchAttributes`) use the same patterns as the Java SDK.

## Next Steps

- [Signals, Queries & Updates](./signals-queries.md) - Communication patterns
- [Child Workflows](./child-workflows.md) - Orchestrating child workflows
- [Timers & Parallel Execution](./timers-parallel.md) - Delays and async patterns
