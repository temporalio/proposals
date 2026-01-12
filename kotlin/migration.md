# Migration from Java SDK

## API Mapping

| Java SDK | Kotlin SDK |
|----------|------------|
| **Activities** | |
| `Workflow.newUntypedActivityStub(opts)` | *(not needed - options passed per call)* |
| `activities.execute("name", Cls, arg)` | `KWorkflow.executeActivity<R>("name", options, arg)` |
| `stub.method(arg)` (typed activity) | `KWorkflow.executeActivity(Interface::method, options, arg)` |
| `Async.function(stub::method, arg)` | `coroutineScope { async { KWorkflow.executeActivity(...) } }` |
| **Workflows** | |
| `Workflow.newChildWorkflowStub(...)` | `KWorkflow.executeChildWorkflow(Interface::method, options, ...)` |
| `Async.function(childStub::method, arg)` | `KWorkflow.startChildWorkflow(Interface::method, options, ...)` → `KChildWorkflowHandle<T, R>` |
| `Workflow.getWorkflowExecution(childStub)` | `childHandle.workflowId` / `childHandle.firstExecutionRunId` |
| `client.newWorkflowStub(...)` | `client.startWorkflow(Interface::method, ...)` → `KTypedWorkflowHandle<T, R>` |
| `client.newWorkflowStub(Cls, id)` | `client.getWorkflowHandle<T>(id)` → `KWorkflowHandle<T>` |
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
| **Options** | |
| `ActivityOptions.newBuilder()...build()` | `KActivityOptions(...)` |
| `LocalActivityOptions.newBuilder()...build()` | `KLocalActivityOptions(...)` |
| `ChildWorkflowOptions.newBuilder()...build()` | `KChildWorkflowOptions(...)` |
| `WorkflowOptions.newBuilder()...build()` | `KWorkflowOptions(...)` |
| `RetryOptions.newBuilder()...build()` | `KRetryOptions(...)` |

## Before (Java)

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

## After (Kotlin)

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
            KActivityOptions(startToCloseTimeout = 30.seconds),
            name
        )
    }
}
```

## Interoperability

### Kotlin Workflows Calling Java Activities

```kotlin
override suspend fun processOrder(order: Order): String {
    // JavaActivities is a Java @ActivityInterface - no stub needed
    return KWorkflow.executeActivity(
        JavaActivities::process,
        KActivityOptions(startToCloseTimeout = 30.seconds),
        order
    )
}
```

### Java Clients Calling Kotlin Workflows

```kotlin
val result = client.executeWorkflow(
    JavaWorkflowInterface::execute,
    KWorkflowOptions(workflowId = "java-workflow", taskQueue = "java-queue"),
    input
)
```

### Mixed Workers

A single worker can host both Java and Kotlin workflows:

```kotlin
// Java workflows (thread-based)
worker.registerWorkflowImplementationTypes(
    OrderWorkflowJavaImpl::class.java
)

// Kotlin workflows (coroutine-based)
worker.registerWorkflowImplementationTypes(
    GreetingWorkflowImpl::class
)

// Both run on the same worker - execution model is per-workflow-instance
factory.start()
```

## Related

- [Kotlin Idioms](./kotlin-idioms.md) - Kotlin-specific patterns
- [Worker Setup](./worker/setup.md) - Mixed Java/Kotlin workers

---

**Next:** [API Parity](./api-parity.md)
