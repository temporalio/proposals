# Migration from Java SDK

## API Mapping

| Java SDK | Kotlin SDK |
|----------|------------|
| **Client** | |
| `WorkflowClient.newInstance(service)` | `KWorkflowClient(service)` |
| `client.newWorkflowStub(Cls, opts)` | `client.startWorkflow(Interface::method, options, ...)` |
| `client.newWorkflowStub(Cls, id)` | `client.getWorkflowHandle<T>(id)` |
| `stub.method(arg)` | `client.executeWorkflow(Interface::method, options, arg)` |
| `stub.signal(arg)` | `handle.signal(T::method, arg)` |
| `stub.query()` | `handle.query(T::method)` |
| `handle.getResult()` | `handle.result()` or `handle.result<R>()` |
| **Worker** | |
| `WorkerFactory.newInstance(client)` | `KWorkerFactory(client)` |
| `factory.newWorker(taskQueue)` | `factory.newWorker(taskQueue)` → `KWorker` |
| `worker.registerWorkflowImplementationTypes(Cls)` | `worker.registerWorkflowImplementationTypes(Cls::class)` |
| `worker.registerActivitiesImplementations(impl)` | `worker.registerActivitiesImplementations(impl)` |
| **KWorkflow Object** | |
| `Workflow.getInfo()` | `KWorkflow.info` |
| `Workflow.getLogger()` | `KWorkflow.logger()` |
| `Workflow.sleep(duration)` | `delay(duration)` - standard kotlinx.coroutines |
| `Workflow.await(() -> cond)` | `KWorkflow.awaitCondition { cond }` |
| `Workflow.sideEffect(cls, func)` | `KWorkflow.sideEffect { func }` |
| `Workflow.getVersion(id, min, max)` | `KWorkflow.version(id, min, max)` |
| `Workflow.continueAsNew(args)` | `KWorkflow.continueAsNew(args)` |
| `Workflow.randomUUID()` | `KWorkflow.randomUUID()` |
| `Workflow.newRandom()` | `KWorkflow.newRandom()` |
| `Workflow.currentTimeMillis()` | `KWorkflow.currentTimeMillis()` |
| `Workflow.getTypedSearchAttributes()` | `KWorkflow.typedSearchAttributes` |
| `Workflow.upsertTypedSearchAttributes(...)` | `KWorkflow.upsertTypedSearchAttributes(...)` |
| `Workflow.getMemo(key, cls)` | `KWorkflow.memo<T>(key)` |
| `Workflow.upsertMemo(map)` | `KWorkflow.upsertMemo(map)` |
| `Workflow.getMetricsScope()` | `KWorkflow.metricsScope` |
| `Workflow.isReplaying()` | `KWorkflow.isReplaying` |
| `Workflow.getCurrentUpdateInfo()` | `KWorkflow.currentUpdateInfo` |
| **Activities (from workflow)** | |
| `Workflow.newActivityStub(Cls, opts)` | *(not needed - options passed per call)* |
| `stub.method(arg)` | `KWorkflow.executeActivity(Interface::method, options, arg)` |
| `Workflow.newLocalActivityStub(Cls, opts)` | *(not needed - options passed per call)* |
| `localStub.method(arg)` | `KWorkflow.executeLocalActivity(Interface::method, options, arg)` |
| `Async.function(stub::method, arg)` | `coroutineScope { async { KWorkflow.executeActivity(...) } }` |
| **Child Workflows** | |
| `Workflow.newChildWorkflowStub(Cls, opts)` | *(not needed - options passed per call)* |
| `childStub.method(arg)` | `KWorkflow.executeChildWorkflow(Interface::method, options, arg)` |
| `Async.function(childStub::method, arg)` | `KWorkflow.startChildWorkflow(...)` → `KChildWorkflowHandle` |
| `Workflow.getWorkflowExecution(childStub)` | `childHandle.workflowId` / `childHandle.runId()` |
| **External Workflows** | |
| `Workflow.newExternalWorkflowStub(Cls, id)` | `KWorkflow.getExternalWorkflowHandle<T>(id)` |
| `externalStub.signal(arg)` | `externalHandle.signal(T::method, arg)` |
| `Workflow.newUntypedExternalWorkflowStub(id)` | `KWorkflow.getExternalWorkflowHandle(id)` |
| **Cancellation** | |
| `Workflow.newCancellationScope(...)` | `coroutineScope { ... }` |
| `Workflow.newDetachedCancellationScope(...)` | `withContext(NonCancellable) { ... }` |
| `scope.cancel()` | `job.cancel()` |
| `CancellationScope.isCancelRequested()` | `!isActive` |
| **KActivity Object** | |
| `Activity.getExecutionContext()` | `KActivity.context` |
| `context.getInfo()` | `KActivity.context.info` or `KActivity.info` |
| `context.heartbeat(details)` | `KActivity.context.heartbeat(details)` |
| `context.getHeartbeatDetails(cls)` | `KActivity.context.heartbeatDetails<T>()` |
| `Activity.getLogger()` | `KActivity.logger()` |
| `context.doNotCompleteOnReturn()` | `KActivity.context.doNotCompleteOnReturn()` |
| **Testing** | |
| `TestWorkflowEnvironment.newInstance()` | `KTestWorkflowEnvironment.newInstance()` |
| `testEnv.newWorker(taskQueue)` | `testEnv.newWorker(taskQueue)` → `KWorker` |
| `testEnv.getWorkflowClient()` | `testEnv.workflowClient` → `KWorkflowClient` |
| `testEnv.sleep(duration)` | `testEnv.sleep(duration)` |
| **Primitives** | |
| `Promise<T>` | `Deferred<T>` via `async { }` |
| `Async.function(...)` + `Promise.get()` | `coroutineScope { async { ... } }` + `awaitAll()` |
| `Optional<T>` | `T?` |
| `Duration.ofSeconds(30)` | `30.seconds` |
| **Options** | |
| `ActivityOptions.newBuilder()...build()` | `KActivityOptions(...)` |
| `LocalActivityOptions.newBuilder()...build()` | `KLocalActivityOptions(...)` |
| `ChildWorkflowOptions.newBuilder()...build()` | `KChildWorkflowOptions(...)` |
| `WorkflowOptions.newBuilder()...build()` | `KWorkflowOptions(...)` |
| `RetryOptions.newBuilder()...build()` | `KRetryOptions(...)` |
| `ContinueAsNewOptions.newBuilder()...build()` | `KContinueAsNewOptions(...)` |

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
