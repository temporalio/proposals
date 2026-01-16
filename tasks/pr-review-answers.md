# PR Review Answers

Decisions on unanswered comments from @cretz on PR #104.

---

## 1. Workflow timer/sleep (api-parity.md:11)

**Decision:** Add `KWorkflow.delay()` with an overload for options

```kotlin
// Simple case
KWorkflow.delay(10.seconds)

// With options
KWorkflow.delay(10.seconds, KTimerOptions(summary = "Waiting for retry"))
```

**Open question:** Should stdlib `delay()` also work (mapping internally), or require explicit `KWorkflow.delay()`?

---

## 2. Async await helpers (api-parity.md:20)

**Decision:** Use standard Kotlin coroutines (Option A) - no need for `KWorkflow.awaitAll()` etc.

```kotlin
// Use standard coroutines
coroutineScope {
    val results = listOf(
        async { activity1() },
        async { activity2() }
    ).awaitAll()
}
```

---

## 3. Default activity options (api-parity.md:21)

**Decision:** Per-call only (Option A) - like newer SDKs, no shared/default activity options mechanism

---

## 4. Rename typedSearchAttributes (api-parity.md:70)

**Decision:** Rename to `searchAttributes` (Option A) - no legacy to disambiguate from in Kotlin SDK

---

## 5. getVersion side-effecting (api-parity.md:94)

**Decision:** PENDING - Ask cretz if full patching API (Option D) is preferred

---

## 6. WithStartWorkflowOperation design (advanced.md:21)

**Decision:** PENDING - Present Option B and ask cretz if this is what he meant:

```kotlin
val result = client.updateWithStart(
    KWithStartWorkflowOperation(MyWorkflow::run, arg, options),  // arg before options
    MyWorkflow::myUpdate,
    updateArg
)
```

---

## 7. Handle naming (workflow-client.md:77)

**Decision:** Rename to `workflowHandle()` (Option C) - more Kotlin idiomatic, no get/new prefix

---

## 8. Reified R for optional approach (workflow-client.md:77)

**Decision:** Add overload to specify `R` when getting handle (Option B):

```kotlin
val handle = client.workflowHandle<String>(workflowId)
val result = handle.result()  // R already known
```

---

## 9. Options after args (workflow-client.md:31)

**Decision:** Already updated - args before options (Option B) in open-questions.md

---

## 10. Client connect static call (workflow-client.md:12)

**Decision:** Single `KWorkflowClient.connect(options)` like newer SDKs (Option A)

```kotlin
val client = KWorkflowClient.connect(
    KWorkflowClientOptions(
        target = "localhost:7233",
        namespace = "default"
    )
)

// Access raw gRPC services when needed
val workflowService = client.workflowService
```

---

## 11. Handle type hierarchy (workflow-handle.md:45)

**Decision:** Use cretz's recommended naming (Option B)

```kotlin
KWorkflowHandleUntyped                           // Untyped base
KWorkflowHandle<T> : KWorkflowHandleUntyped      // Typed workflow, untyped result
KWorkflowHandleWithResult<T, R> : KWorkflowHandle<T>  // Fully typed
```

---

## 12. Options class for handle methods (workflow-handle.md:87)

**Decision:** Use options class with convenience overloads (Option B). Options always last.

```kotlin
// Primary API with options
suspend fun <R> startUpdate(
    method: KSuspendFunction1<T, R>,
    options: KStartUpdateOptions
): KUpdateHandle<R>

// Convenience overload with arg before options
suspend fun <R, A1> startUpdate(
    method: KSuspendFunction2<T, A1, R>,
    arg: A1,
    options: KStartUpdateOptions
): KUpdateHandle<R>
```

---

## 13. List super class (workflow-handle.md:178)

**Decision:** Add hierarchy (Option A)

```kotlin
// Base class returned by listWorkflows()
open class KWorkflowExecutionInfo(
    val execution: WorkflowExecution,
    val workflowType: String,
    val taskQueue: String,
    val startTime: Instant,
    val status: WorkflowExecutionStatus
    // ... lighter set of fields
)

// Extended class returned by describe()
class KWorkflowExecutionDescription(
    // ... all fields from info plus additional details
) : KWorkflowExecutionInfo(...)
```

---

## 14. Wait for stage required (workflow-handle.md:86)

**Decision:** Make waitForStage required, no default (Option B)

```kotlin
// waitForStage is required - no default value
suspend fun <R> startUpdate(
    method: KSuspendFunction1<T, R>,
    options: KStartUpdateOptions  // waitForStage required in options
): KUpdateHandle<R>
```

Note: This aligns with the decision in Q12 to use options classes. `KStartUpdateOptions.waitForStage` will be required.

---

## 15. Data converter design (README.md:52)

**Decision:** TBD - Mark for later detailed design

Options to consider:
- A) Newer SDK pattern with composable components (payloadConverter, failureConverter, payloadCodec)
- B) Keep current Java-style DataConverter interface

---

## 16. Client interceptors (interceptors.md:1)

**Decision:** Add client interceptors (Option A)

Add `KWorkflowClientInterceptor` for intercepting client-side operations:
- startWorkflow
- signalWorkflow
- queryWorkflow
- executeUpdate
- etc.

---

## 17. Remove required interfaces (kotlin-idioms.md:21)

**Decision:** Already addressed - interfaces are optional (Option B already in API spec)

Plain classes with annotated methods are supported; @WorkflowInterface/@ActivityInterface are optional.

---

## 18. Cancellation statement unclear (cancellation.md:32)

**Decision:** Clarify wording (Option A)

Update docs to clarify this is standard Kotlin `coroutineScope` exception propagation behavior:
- When one child fails with exception, coroutineScope cancels all other children
- This is automatic Kotlin structured concurrency, not Temporal-specific behavior

---

## 19. Discourage start pattern (README.md:32)

**Decision:** Recommend run() pattern (Option A)

Update examples to use `factory.run()` which blocks and propagates fatal errors.
Mention `start()`/`shutdown()` as alternative for advanced use cases.

```kotlin
// Recommended pattern
factory.run()  // Blocks until shutdown, propagates fatal errors

// Alternative for advanced use cases
factory.start()  // Returns immediately
// ...
factory.shutdown()
```

---

## 24. Event loop control (kotlin-idioms.md:58)

**Decision:** Kotlin wraps Java SDK, `awaitCondition` built on `Async.await()`

Kotlin SDK does not have its own event loop - it's implemented on top of Java SDK. The `awaitCondition` functionality will be built on top of the new `Async.await()` method being added to Java SDK (PR #2751), which returns a `Promise` for non-blocking condition waiting.

```kotlin
// Kotlin awaitCondition suspends the coroutine
KWorkflow.awaitCondition { condition }

// Implemented using Java's Async.await() under the hood
// Async.await(supplier) -> Promise<T>
```

---

## 23. Priority for local activities (local-activities.md)

**Decision:** Already addressed - priority removed from KLocalActivityOptions

The `KLocalActivityOptions` class doesn't include `priority` or other non-applicable fields (like task queue). Local activities run in-process, so task queue routing options don't apply.

---

## 22. Heartbeat details collection (implementation.md)

**Decision:** Support single argument only, like Java SDK

Keep it simple - heartbeat accepts a single detail value. If users need multiple values, they wrap them in a data class.

```kotlin
// Heartbeat with single value
ctx.heartbeat(progressPercent)

// Or wrap multiple values in a data class
data class MyProgress(val percent: Int, val checkpoint: String)
ctx.heartbeat(MyProgress(50, "step-3"))

// Retrieve on retry
val progress: MyProgress? = ctx.lastHeartbeatDetails<MyProgress>()
```

Use `lastHeartbeatDetails` naming to clarify it's from the last heartbeat before retry.

---

## 21. Logger on context (implementation.md)

**Decision:** Remove logger from context, use MDC only (Option A)

Use MDC/coroutine context for activity and workflow metadata. Users use standard logging frameworks. Temporal SDK populates MDC automatically with workflowId, activityId, etc.

```kotlin
// SDK sets up MDC with activity/workflow info automatically
val logger = LoggerFactory.getLogger(MyActivity::class.java)
logger.info("Processing...")  // MDC includes activityId, workflowId, taskQueue, etc.
```

Remove `KActivity.logger()` and `KWorkflow.logger()` from the API. This matches Java SDK approach.

---

## 20. Context data type (implementation.md)

**Decision:** Use `KActivityContext.current()` pattern, remove KActivity class

Move context access to the context class itself, matching .NET pattern. Since Kotlin doesn't have checked exceptions, `Activity.wrap()` is not needed, so `KActivity` class can be removed entirely.

```kotlin
val ctx = KActivityContext.current()
ctx.info                      // ActivityInfo
ctx.heartbeat(details)
ctx.heartbeatDetails<T>()
ctx.doNotCompleteOnReturn()
ctx.cancellationFuture()      // for non-suspend activities
```

---
