# Workflow Definition

Define workflow interfaces with `suspend` methods for full Kotlin coroutine support:

```kotlin
@WorkflowInterface
interface GreetingWorkflow {
    @WorkflowMethod
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
    @WorkflowMethod
    String getGreeting(String name);
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

## Related

- [Child Workflows](./child-workflows.md) - Orchestrating child workflows
- [Timers & Parallel Execution](./timers-parallel.md) - Delays and async patterns

---

## Open Questions (Decision Needed)

### Interfaceless Workflow Definition

**Status:** Decision needed

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
    @WorkflowMethod
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
