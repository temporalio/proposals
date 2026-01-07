# Continue-As-New

Continue-as-new completes the current workflow execution and immediately starts a new execution with fresh event history. This is essential for:

- **Preventing history growth**: Long-running workflows accumulate event history which can impact performance. Continue-as-new resets the history.
- **Batch processing**: Process a batch of items, then continue-as-new with the next batch offset.
- **Implementing loops**: Instead of infinite loops that accumulate history, use continue-as-new.

## Basic Usage

```kotlin
// Basic continue-as-new - same workflow type, inherit all options
KWorkflow.continueAsNew(nextBatchId, newOffset)

// With modified options
KWorkflow.continueAsNew(
    KContinueAsNewOptions(
        taskQueue = "high-priority-queue",
        workflowRunTimeout = 2.hours
    ),
    nextBatchId, newOffset
)

// Continue as different workflow type (for versioning/migration)
KWorkflow.continueAsNew(
    "OrderProcessorV2",
    KContinueAsNewOptions(taskQueue = "orders-v2"),
    migratedState
)

// Type-safe continue as different workflow using method reference
KWorkflow.continueAsNew(
    OrderProcessorV2::process,
    KContinueAsNewOptions(),
    migratedState
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
    val typedSearchAttributes: SearchAttributes? = null
)
```

## Batch Processing Pattern

```kotlin
class BatchProcessorImpl : BatchProcessor {
    override suspend fun processBatches(startOffset: Int) {
        val batchSize = 100
        val items = KWorkflow.executeActivity(
            DataActivities::fetchBatch,
            KActivityOptions(startToCloseTimeout = 1.minutes),
            startOffset, batchSize
        )

        if (items.isEmpty()) {
            return  // All done, workflow completes normally
        }

        // Process items...
        for (item in items) {
            KWorkflow.executeActivity(
                DataActivities::processItem,
                KActivityOptions(startToCloseTimeout = 30.seconds),
                item
            )
        }

        // Continue with the next batch
        KWorkflow.continueAsNew(startOffset + batchSize)
    }
}
```

## History Size Check Pattern

```kotlin
override suspend fun execute(state: WorkflowState) {
    while (true) {
        // Check if history is getting too large
        if (KWorkflow.info.isContinueAsNewSuggested) {
            KWorkflow.continueAsNew(state)
        }

        // Wait for signals and process...
        KWorkflow.awaitCondition { hasNewWork }
        processWork()
    }
}
```

## KWorkflow.continueAsNew API

```kotlin
object KWorkflow {
    /**
     * Continue workflow as new with the same workflow type.
     * This function never returns - it terminates the current execution.
     */
    fun continueAsNew(vararg args: Any?): Nothing

    /**
     * Continue workflow as new with modified options.
     * Null option values inherit from the current workflow.
     */
    fun continueAsNew(options: KContinueAsNewOptions, vararg args: Any?): Nothing

    /**
     * Continue as a different workflow type.
     * Useful for workflow versioning or migration.
     */
    fun continueAsNew(
        workflowType: String,
        options: KContinueAsNewOptions,
        vararg args: Any?
    ): Nothing

    /**
     * Type-safe continue as different workflow using method reference.
     */
    fun <T> continueAsNew(
        workflow: KFunction<*>,
        options: KContinueAsNewOptions,
        vararg args: Any?
    ): Nothing
}
```

> **Important:** `continueAsNew` never returns normally. It terminates the current workflow execution and signals Temporal to start a new execution. The return type `Nothing` indicates this in Kotlin's type system.

## Related

- [Workflow Definition](./definition.md) - Basic workflow patterns
- [Migration Guide](../migration.md) - Java SDK comparison

---

**Next:** [Activities](../activities/README.md)
