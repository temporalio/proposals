# Kotlin Idioms

The SDK leverages Kotlin-specific language features for an idiomatic experience.

## Kotlin Duration

Use `kotlin.time.Duration` for readable time expressions:

```kotlin
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.hours

// Activity with timeouts using KOptions
val result = KWorkflow.executeActivity<String>(
    "ProcessOrder",
    KActivityOptions(
        startToCloseTimeout = 30.seconds,
        scheduleToCloseTimeout = 5.minutes,
        heartbeatTimeout = 10.seconds
    ),
    orderData
)

// Timers - standard kotlinx.coroutines delay (intercepted for determinism)
delay(1.hours)
```

> **Note:** The `Delay` interface intercepts standard `delay()` calls and routes them through Temporal's deterministic timer.

## Null Safety

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

// KActivityInfo - nullable instead of Optional
interface KActivityInfo {
    val activityId: String
    val activityType: String
    val workflowId: String
    val attempt: Int
    fun getHeartbeatDetails(): Payloads?   // Optional in Java
    // ... other properties
}

// Access via KWorkflow / KActivity objects
val info: KWorkflowInfo = KWorkflow.getInfo()
val parentId: String? = info.parentWorkflowId

// KActivity.getContext() returns KActivityContext (matches Java's Activity.getExecutionContext())
val context: KActivityContext = KActivity.getContext()
val activityInfo: KActivityInfo = context.info
context.heartbeat("progress")                  // Blocking version for regular activities
context.suspendHeartbeat("progress")           // Suspend version for suspend activities
val logger = context.logger()                  // Get activity logger
```

This eliminates `.orElse(null)`, `.isPresent`, and other Optional ceremony.

## Property Syntax for Queries

Queries can be defined as Kotlin properties in the workflow interface:

```kotlin
@WorkflowInterface
interface OrderWorkflow {
    @QueryMethod
    val status: OrderStatus  // Property syntax

    @QueryMethod
    fun getItemCount(): Int  // Method syntax
}

// Client usage via typed handle (using KWorkflowClient)
val handle = client.getWorkflowHandle<OrderWorkflow>("order-123")
val status = handle.query(OrderWorkflow::status)
val count = handle.query(OrderWorkflow::getItemCount)
```

## Next Steps

- [KOptions Classes](./configuration/koptions.md) - Kotlin-native configuration
- [Workflow Definition](./workflows/definition.md) - Using these idioms in workflows
- [Activity Definition](./activities/definition.md) - Using these idioms in activities
