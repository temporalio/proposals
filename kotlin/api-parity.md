# Java SDK API Parity

This document describes the intentional differences between Java and Kotlin SDK APIs, and identifies remaining gaps.

## APIs Not Needed in Kotlin

The following Java SDK APIs are **not needed** in the Kotlin SDK due to language differences:

| Java SDK API | Reason Not Needed |
|--------------|-------------------|
| `Workflow.sleep(Duration)` | Use `kotlinx.coroutines.delay()` - intercepted by dispatcher |
| `Workflow.newTimer(Duration)` | Use `async { delay(duration) }` for racing timers |
| `Workflow.wrap(Exception)` | Kotlin has no checked exceptions - not needed |
| `Activity.wrap(Throwable)` | Kotlin has no checked exceptions - not needed |
| `Workflow.newCancellationScope(...)` | Use Kotlin's `coroutineScope { }` with structured concurrency |
| `Workflow.newDetachedCancellationScope(...)` | Use `supervisorScope { }` or launch in parent scope |
| `Workflow.newWorkflowLock()` | Not needed - cooperative coroutines don't have true concurrency |
| `Workflow.newWorkflowSemaphore(...)` | Use structured concurrency patterns (e.g., `chunked().map { async }.awaitAll()`) |
| `Workflow.newQueue(...)` / `newWorkflowQueue(...)` | Use `mutableListOf` + `awaitCondition` - no concurrent access in suspend model |
| `Workflow.newPromise()` / `newFailedPromise(...)` | Use `CompletableDeferred<T>` from kotlinx.coroutines |
| `Workflow.setDefaultActivityOptions(...)` | Pass `KActivityOptions` per call, or define shared `val defaultOptions` |
| `Workflow.setActivityOptions(...)` | Pass options per call |
| `Workflow.applyActivityOptions(...)` | Pass options per call |
| `Workflow.setDefaultLocalActivityOptions(...)` | Pass `KLocalActivityOptions` per call |
| `Workflow.applyLocalActivityOptions(...)` | Pass options per call |

## Activity API Design Decisions

### Single heartbeat() API

The Kotlin SDK provides a single `heartbeat()` method on `KActivityContext` for both sync and suspend activities:

```kotlin
context.heartbeat(progressDetails)
```

**Rationale:** Heartbeat is a short, non-blocking operation that records progress locally. The actual network call happens asynchronously in the background. A separate `suspendHeartbeat()` API is unnecessary.

### Both Sync and Suspend Activities Supported

The Kotlin SDK supports both regular and suspend activity methods:

```kotlin
@ActivityInterface
interface OrderActivities {
    fun validate(order: Order): Boolean        // Sync - runs on thread pool
    suspend fun fetchExternal(id: String): Data // Suspend - runs on coroutine
}
```

**Rationale:** This matches other Kotlin frameworks (Spring, Micronaut, gRPC-Kotlin) that detect method signatures and handle them appropriately. It reduces migration friction from Java SDK and gives developers choice.

## Cancellation Support

Kotlin coroutine cancellation is fully integrated with Temporal workflow cancellation:

- Workflow cancellation triggers `coroutineScope.cancel(CancellationException(...))`
- Cancellation propagates to all child coroutines (activities, timers, child workflows)
- Activities use `suspendCancellableCoroutine` with `invokeOnCancellation` to cancel via Temporal
- Use standard Kotlin patterns: `try/finally`, `use { }`, `invokeOnCompletion`

## Implemented APIs (Java SDK Parity)

The following Java SDK workflow APIs have Kotlin equivalents in `KWorkflow`:

### Search Attributes & Memo

| Java SDK API | Kotlin SDK |
|--------------|------------|
| `Workflow.getTypedSearchAttributes()` | `KWorkflow.getTypedSearchAttributes()` |
| `Workflow.upsertTypedSearchAttributes(...)` | `KWorkflow.upsertTypedSearchAttributes()` |
| `Workflow.getMemo(key, class)` | `KWorkflow.getMemo()` |
| `Workflow.upsertMemo(...)` | `KWorkflow.upsertMemo()` |

### Workflow State & Context

| Java SDK API | Kotlin SDK |
|--------------|------------|
| `Workflow.getLastCompletionResult(class)` | `KWorkflow.getLastCompletionResult<T>()` |
| `Workflow.getPreviousRunFailure()` | `KWorkflow.previousRunFailure` |
| `Workflow.isReplaying()` | `KWorkflow.isReplaying` |
| `Workflow.getCurrentUpdateInfo()` | `KWorkflow.currentUpdateInfo` |
| `Workflow.isEveryHandlerFinished()` | `KWorkflow.isEveryHandlerFinished` |
| `Workflow.setCurrentDetails(...)` | `KWorkflow.currentDetails = ...` |
| `Workflow.getCurrentDetails()` | `KWorkflow.currentDetails` |
| `Workflow.getMetricsScope()` | `KWorkflow.metricsScope` |

### Side Effects & Utilities

| Java SDK API | Kotlin SDK |
|--------------|------------|
| `Workflow.sideEffect(...)` | `KWorkflow.sideEffect()` |
| `Workflow.mutableSideEffect(...)` | `KWorkflow.mutableSideEffect()` |
| `Workflow.getVersion(...)` | `KWorkflow.getVersion()` |
| `Workflow.retry(...)` | `KWorkflow.retry()` |
| `Workflow.randomUUID()` | `KWorkflow.randomUUID()` |
| `Workflow.newRandom()` | `KWorkflow.newRandom()` |

### Dynamic Handler Registration

| Java SDK API | Kotlin SDK |
|--------------|------------|
| `Workflow.registerListener(DynamicSignalHandler)` | `KWorkflow.registerDynamicSignalHandler()` |
| `Workflow.registerListener(DynamicQueryHandler)` | `KWorkflow.registerDynamicQueryHandler()` |
| `Workflow.registerListener(DynamicUpdateHandler)` | `KWorkflow.registerDynamicUpdateHandler()` |
| N/A (new in Kotlin SDK) | `KWorkflow.registerSignalHandler()` |
| N/A (new in Kotlin SDK) | `KWorkflow.registerQueryHandler()` |
| N/A (new in Kotlin SDK) | `KWorkflow.registerUpdateHandler()` |
| N/A (new in Kotlin SDK) | `KWorkflow.registerDynamicUpdateValidator()` |

## Remaining Gaps

| Java SDK API | Status |
|--------------|--------|
| `Workflow.newNexusServiceStub(...)` | Nexus support - deferred to separate project |
| `Workflow.startNexusOperation(...)` | Nexus support - deferred to separate project |
| `Workflow.getInstance()` | Advanced use case - low priority |

## KActivityInfo Gaps

| Java ActivityInfo Field | Status |
|------------------------|--------|
| `workflowType` | Missing - workflow type that called the activity |
| `currentAttemptScheduledTimestamp` | Missing - current attempt schedule time |
| `retryOptions` | Missing - activity retry options |

## Related

- [Migration Guide](./migration.md) - Practical migration steps
- [Kotlin Idioms](./kotlin-idioms.md) - Kotlin-specific patterns
- [README](./README.md) - Back to documentation home
