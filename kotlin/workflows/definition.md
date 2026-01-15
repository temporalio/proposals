# Workflow Definition

Define workflow interfaces with `suspend` methods for full Kotlin coroutine support:

```kotlin
@WorkflowInterface
interface GreetingWorkflow {
    suspend fun getGreeting(name: String): String
}

// Use @WorkflowMethod only when customizing the workflow type name
@WorkflowInterface
interface CustomNameWorkflow {
    @WorkflowMethod(name = "CustomGreeting")
    suspend fun getGreeting(name: String): String
}

class GreetingWorkflowImpl : GreetingWorkflow {
    override suspend fun getGreeting(name: String): String {
        return KWorkflow.executeActivity(
            GreetingActivities::composeGreeting,
            KActivityOptions(startToCloseTimeout = 10.seconds),
            "Hello", name
        )
    }
}

// Client call using KClient - same pattern as activities, no stub needed
val result = client.executeWorkflow(
    GreetingWorkflow::getGreeting,
    KWorkflowOptions(
        workflowId = "greeting-123",
        taskQueue = "greetings"
    ),
    "Temporal"
)
```

## Java Interoperability

### Kotlin Calling Java Workflows

Kotlin clients can call Java workflows using typed method references:

```kotlin
// Java workflow interface (defined in Java)
// @WorkflowInterface
// public interface OrderWorkflow {
//     @WorkflowMethod
//     OrderResult processOrder(Order order);
// }

// Kotlin client calling Java workflow - works seamlessly
val result: OrderResult = client.executeWorkflow(
    OrderWorkflow::processOrder,
    KWorkflowOptions(
        workflowId = "order-123",
        taskQueue = "orders"
    ),
    order
)
```

### Java Calling Kotlin Workflows

Java clients can invoke Kotlin suspend workflows using **untyped workflow stubs**. The workflow type name defaults to the interface name.

```java
// Java client calling a Kotlin suspend workflow
WorkflowStub stub = client.newUntypedWorkflowStub(
    "GreetingWorkflow",  // Workflow type = interface name
    WorkflowOptions.newBuilder()
        .setTaskQueue("greetings")
        .setWorkflowId("greeting-123")
        .build()
);

stub.start("Temporal");
String result = stub.getResult(String.class);
```

Alternatively, Java clients can define their own Java interface with the **same name** as the Kotlin interface to use typed stubs:

```java
// Java interface matching the Kotlin workflow type
@WorkflowInterface
public interface GreetingWorkflow {
    String getGreeting(String name);  // @WorkflowMethod optional in Java too
}

// Java client using typed stub
GreetingWorkflow workflow = client.newWorkflowStub(
    GreetingWorkflow.class,
    WorkflowOptions.newBuilder()
        .setTaskQueue("greetings")
        .setWorkflowId("greeting-123")
        .build()
);
String result = workflow.getGreeting("Temporal");
```

> **Note:** Java cannot directly use Kotlin suspend interfaces because suspend functions compile to methods with an extra `Continuation` parameter. The untyped stub approach is recommended for Java clients.

## Parameter Restrictions

**Default parameter values are allowed for methods with 0 or 1 arguments.** For methods with 2+ arguments, defaults are not allowed. This is validated at worker registration time.

```kotlin
// ✓ ALLOWED - 1 argument with default
@WorkflowMethod
suspend fun processOrder(priority: Int = 0): OrderResult

// ✗ NOT ALLOWED - 2+ arguments with defaults
@WorkflowMethod
suspend fun processOrder(orderId: String, priority: Int = 0)  // Error!

// ✓ CORRECT for 2+ arguments - use a parameter object with optional fields
data class ProcessOrderParams(
    val orderId: String,
    val priority: Int? = null
)

@WorkflowMethod
suspend fun processOrder(params: ProcessOrderParams): OrderResult
```

**Rationale:** This aligns with Python, .NET, and Ruby SDKs which support defaults. For complex inputs with multiple parameters, the parameter object pattern avoids serialization ambiguity and cross-language issues. See [full discussion](../open-questions.md#default-parameter-values).

## Key Characteristics

* Use `coroutineScope`, `async`, `launch` for concurrent execution
* Use `delay()` for timers (maps to Temporal timers, not `Thread.sleep`)
* Reuses `@WorkflowInterface` annotation from Java SDK
* Method annotations (`@WorkflowMethod`, `@SignalMethod`, etc.) are optional - use only when customizing names
* Data classes work naturally for parameters and results

> **Note:** Versioning (`KWorkflow.version()`), side effects (`KWorkflow.sideEffect`), and search attributes (`KWorkflow.upsertSearchAttributes`) use the same patterns as the Java SDK. Logging uses standard logging frameworks with MDC - the SDK automatically populates MDC with workflow context (workflowId, runId, taskQueue, etc.).

## Related

- [Child Workflows](./child-workflows.md) - Orchestrating child workflows
- [Timers & Parallel Execution](./timers-parallel.md) - Delays and async patterns

---

## Open Questions (Decision Needed)

### Interfaceless Workflow Definition

**Status:** Decision needed | [Full discussion](../open-questions.md#interfaceless-workflows-and-activities)

Currently, workflows require interface definitions:

```kotlin
// Current approach - requires interface
@WorkflowInterface
interface GreetingWorkflow {
    @WorkflowMethod
    suspend fun getGreeting(name: String): String
}

class GreetingWorkflowImpl : GreetingWorkflow {
    override suspend fun getGreeting(name: String): String {
        // implementation
    }
}
```

**Proposal:** Allow defining workflows directly on implementation classes without interfaces, similar to Python SDK:

```kotlin
// Proposed approach - no interface required
class GreetingWorkflow {
    suspend fun getGreeting(name: String): String {
        return KWorkflow.executeActivity(
            GreetingActivities::composeGreeting,
            KActivityOptions(startToCloseTimeout = 10.seconds),
            "Hello", name
        )
    }
}

// Client call using method reference to impl class
val result = client.executeWorkflow(
    GreetingWorkflow::getGreeting,
    KWorkflowOptions(workflowId = "greeting-123", taskQueue = "greetings"),
    "World"
)
```

**Benefits:**
- Reduces boilerplate (no separate interface file)
- More similar to Python SDK experience
- Kotlin-only feature, no Java SDK changes required

**Trade-offs:**
- Different from Java SDK convention
- Workflow type name derived from class name (convention-based, respects `@WorkflowMethod(name = "...")`)

---

**Next:** [Signals, Queries & Updates](./signals-queries.md)
