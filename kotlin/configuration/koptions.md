# KOptions Classes

For a fully idiomatic Kotlin experience, the SDK provides dedicated `KOptions` data classes that accept `kotlin.time.Duration` directly, use named parameters with default values, and follow immutable data class patterns.

## KActivityOptions

```kotlin
/**
 * Kotlin-native activity options with Duration support.
 * All timeout properties accept kotlin.time.Duration directly.
 */
data class KActivityOptions(
    val startToCloseTimeout: Duration? = null,
    val scheduleToCloseTimeout: Duration? = null,
    val scheduleToStartTimeout: Duration? = null,
    val heartbeatTimeout: Duration? = null,
    val taskQueue: String? = null,
    val retryOptions: KRetryOptions? = null,
    val cancellationType: ActivityCancellationType? = null,  // Java default: TRY_CANCEL
    val disableEagerExecution: Boolean = false
)
```

**Usage:**

```kotlin
val result = KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,
    KActivityOptions(
        startToCloseTimeout = 30.seconds,
        scheduleToCloseTimeout = 5.minutes,
        heartbeatTimeout = 10.seconds,
        retryOptions = KRetryOptions(
            initialInterval = 1.seconds,
            maximumAttempts = 3
        )
    ),
    "Hello", "World"
)
```

## KLocalActivityOptions

```kotlin
/**
 * Kotlin-native local activity options.
 */
data class KLocalActivityOptions(
    val startToCloseTimeout: Duration? = null,
    val scheduleToCloseTimeout: Duration? = null,
    val localRetryThreshold: Duration? = null,
    val retryOptions: KRetryOptions? = null
)
```

**Usage:**

```kotlin
val validated = KWorkflow.executeLocalActivity(
    ValidationActivities::validate,
    KLocalActivityOptions(
        startToCloseTimeout = 5.seconds,
        localRetryThreshold = 10.seconds
    ),
    input
)
```

## KRetryOptions

```kotlin
/**
 * Kotlin-native retry options.
 */
data class KRetryOptions(
    val initialInterval: Duration = 1.seconds,
    val backoffCoefficient: Double = 2.0,
    val maximumInterval: Duration? = null,
    val maximumAttempts: Int = 0,  // 0 = unlimited
    val doNotRetry: List<String> = emptyList()
)
```

## KChildWorkflowOptions

```kotlin
/**
 * Kotlin-native child workflow options.
 * All fields are optional - null values inherit from parent workflow or use Java SDK defaults.
 */
data class KChildWorkflowOptions(
    val namespace: String? = null,
    val workflowId: String? = null,
    val workflowIdReusePolicy: WorkflowIdReusePolicy? = null,
    val workflowRunTimeout: Duration? = null,
    val workflowExecutionTimeout: Duration? = null,
    val workflowTaskTimeout: Duration? = null,
    val taskQueue: String? = null,
    val retryOptions: KRetryOptions? = null,
    val cronSchedule: String? = null,
    val parentClosePolicy: ParentClosePolicy? = null,
    val memo: Map<String, Any>? = null,
    val typedSearchAttributes: SearchAttributes? = null,
    val cancellationType: ChildWorkflowCancellationType? = null,
    val staticSummary: String? = null,
    val staticDetails: String? = null,
    val priority: Priority? = null
)
```

**Usage:**

```kotlin
val childResult = KWorkflow.executeChildWorkflow(
    ChildWorkflow::process,
    KChildWorkflowOptions(
        workflowId = "child-123",
        workflowExecutionTimeout = 1.hours,
        retryOptions = KRetryOptions(maximumAttempts = 3)
    ),
    data
)
```

## KWorkflowOptions

```kotlin
/**
 * Kotlin-native workflow options for client execution.
 * workflowId and taskQueue are optional - if not provided, will use defaults or generate UUID.
 */
data class KWorkflowOptions(
    val workflowId: String? = null,
    val workflowIdReusePolicy: WorkflowIdReusePolicy? = null,
    val workflowIdConflictPolicy: WorkflowIdConflictPolicy? = null,
    val workflowRunTimeout: Duration? = null,
    val workflowExecutionTimeout: Duration? = null,
    val workflowTaskTimeout: Duration? = null,
    val taskQueue: String? = null,
    val retryOptions: KRetryOptions? = null,
    val cronSchedule: String? = null,
    val memo: Map<String, Any>? = null,
    val typedSearchAttributes: SearchAttributes? = null,
    val disableEagerExecution: Boolean = true,
    val startDelay: Duration? = null,
    val staticSummary: String? = null,
    val staticDetails: String? = null,
    val priority: Priority? = null
)
```

**Usage:**

```kotlin
val result = client.executeWorkflow(
    OrderWorkflow::processOrder,
    KWorkflowOptions(
        workflowId = "order-123",
        taskQueue = "orders",
        workflowExecutionTimeout = 24.hours,
        workflowRunTimeout = 1.hours
    ),
    order
)
```

## KContinueAsNewOptions

```kotlin
/**
 * Options for continuing a workflow as a new execution.
 * All fields are optional - null values inherit from the current workflow.
 */
data class KContinueAsNewOptions(
    val workflowRunTimeout: Duration? = null,
    val taskQueue: String? = null,
    val retryOptions: KRetryOptions? = null,
    val workflowTaskTimeout: Duration? = null,
    val memo: Map<String, Any>? = null,
    val typedSearchAttributes: SearchAttributes? = null,
    val contextPropagators: List<ContextPropagator>? = null
)
```

## Copying with Modifications

Data classes support the `copy()` function for creating variants:

```kotlin
val baseOptions = KActivityOptions(
    startToCloseTimeout = 30.seconds,
    retryOptions = KRetryOptions(maximumAttempts = 3)
)

// Create variant with different timeout
val longRunningOptions = baseOptions.copy(
    startToCloseTimeout = 5.minutes,
    heartbeatTimeout = 30.seconds
)
```

## KOptions vs DSL Builders

The Kotlin SDK provides two approaches for configuring options:

1. **KOptions (Recommended)** - Native Kotlin data classes designed for the Kotlin SDK
2. **DSL Builders** - Extension functions on Java SDK builders, provided as a stopgap for using Kotlin with the Java SDK

> **Important:** When using the Kotlin SDK (`KWorkflow`, `KWorkflowClient`, etc.), always use KOptions classes. The DSL builders (`ActivityOptions { }`, `WorkflowOptions { }`, etc.) exist only for compatibility when using Kotlin with the Java SDK directly and should not be used with the Kotlin SDK APIs.

| Aspect | DSL Builder (Java SDK interop) | KOptions (Kotlin SDK) |
|--------|--------------------------------|------------------------|
| Duration | Requires `.toJava()` conversion | Native `kotlin.time.Duration` |
| Syntax | `setStartToCloseTimeout(...)` | `startToCloseTimeout = ...` |
| Defaults | Must check Java defaults | Visible in constructor |
| Immutability | Mutable builder | Immutable data class |
| Copy | Manual rebuild | `copy()` function |
| IDE | Limited autocomplete | Full parameter hints |
| Usage | Java SDK only | Kotlin SDK |

> **Implementation Note:** KOptions classes internally convert to Java SDK options. The conversion happens once when the activity/workflow is scheduled, so there's no runtime overhead during workflow execution.

## Related

- [Data Conversion](./data-conversion.md) - Serialization configuration
- [Interceptors](./interceptors.md) - Cross-cutting concerns

---

**Next:** [Data Conversion](./data-conversion.md)
