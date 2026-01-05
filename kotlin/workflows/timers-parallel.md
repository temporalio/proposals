# Timers and Parallel Execution

## Timers and Delays

```kotlin
override suspend fun workflowWithTimer(): String {
    // Simple delay using Kotlin Duration
    delay(5.minutes)

    return "completed"
}
```

The standard `kotlinx.coroutines.delay()` is intercepted by Temporal's deterministic dispatcher and creates durable timers.

## Parallel Execution

Use standard `coroutineScope { async { } }` for parallel execution:

```kotlin
val options = KActivityOptions(startToCloseTimeout = 30.seconds)

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

## Await Condition

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

## Timeout Patterns

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

## Racing Patterns

Race multiple operations and take the first result:

```kotlin
override suspend fun raceOperations(): String = coroutineScope {
    // Start multiple operations
    val fast = async { KWorkflow.executeActivity(Activities::fastOperation, options) }
    val slow = async { KWorkflow.executeActivity(Activities::slowOperation, options) }

    // Use select to get first result
    select {
        fast.onAwait { "Fast: $it" }
        slow.onAwait { "Slow: $it" }
    }
    // Note: The other coroutine is still running but will be cancelled when scope exits
}
```

## Next Steps

- [Cancellation](./cancellation.md) - How cancellation works with parallel execution
- [Child Workflows](./child-workflows.md) - Parallel child workflow patterns
