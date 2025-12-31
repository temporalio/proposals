# Phase 1.5: Plugin Architecture - Detailed Plan

## Overview

Implement a plugin architecture for the Java SDK that enables language-specific extensions like Kotlin coroutine support. This design intercepts workflow type registration and allows plugins to provide custom workflow implementation factories.

## Motivation

The current Phase 1.4 implementation provides worker-side Kotlin integration through extension functions:

```kotlin
val plugin = KotlinPlugin { deadlockDetectionTimeout = 1500L }
worker.registerKotlinWorkflowImplementationTypes(plugin, MyWorkflowImpl::class)
```

This works but has limitations:
1. **Separate registration API** - Users must use Kotlin-specific extension functions
2. **No DataConverter propagation** - Plugin creates its own default DataConverter
3. **Not extensible** - Pattern doesn't generalize to other language integrations
4. **Mixed workflows require manual partitioning** - Users must know which workflows are suspend

## Goals

1. Create a plugin interface that generalizes to any language/framework integration
2. Enable automatic workflow type detection during standard `registerWorkflowImplementationTypes` calls
3. Propagate configuration (DataConverter) from client through to plugins
4. Maintain backward compatibility with existing extension function API

## Non-Goals (Phase 1.5)

1. Client-side plugins - Kotlin suspend workflows work with existing untyped client stubs
2. Activity plugins - Activity registration doesn't need special Kotlin handling
3. Complex plugin chaining/ordering - Keep initial implementation simple

## Proposed Design

### Core Concept: Registration Interception

The key insight is that plugins should intercept workflow type registration rather than requiring a separate registration API:

```kotlin
// User registers workflows with standard API
worker.registerWorkflowImplementationTypes(
    MySuspendWorkflowImpl::class.java,  // Plugin handles this
    MyJavaWorkflowImpl::class.java      // Default POJO factory handles this
)
```

When `registerWorkflowImplementationTypes` is called:
1. For each workflow class, ask plugins if they handle this type
2. First plugin to return a factory wins
3. If no plugin handles it, use the default POJO factory

### Component 1: WorkerPlugin Interface (Java SDK)

**Location:** `temporal-sdk/src/main/java/io/temporal/plugin/WorkerPlugin.java`

```java
package io.temporal.plugin;

import io.temporal.common.converter.DataConverter;
import io.temporal.internal.worker.WorkflowImplementationFactory;
import io.temporal.worker.Worker;
import io.temporal.worker.WorkerOptions;
import javax.annotation.Nullable;

/**
 * Plugin interface for extending Worker functionality.
 *
 * Plugins enable language-specific or framework-specific extensions to Temporal workers.
 * They can:
 * - Modify WorkerOptions before worker creation
 * - Intercept workflow type registration and provide custom factories
 * - Register activity implementations after worker creation
 *
 * Plugins are registered at the WorkerFactory level and are applied to all workers
 * created by that factory.
 *
 * Example implementation:
 * <pre>{@code
 * public class MyLanguagePlugin implements WorkerPlugin {
 *     private MyWorkflowFactory factory;
 *
 *     @Override
 *     public WorkerOptions.Builder configureWorker(WorkerOptions.Builder builder) {
 *         return builder.setDefaultDeadlockDetectionTimeout(1500);
 *     }
 *
 *     @Override
 *     public WorkflowImplementationFactory getFactoryForType(
 *             Class<?> clazz, DataConverter dataConverter) {
 *         if (!isMyLanguageWorkflow(clazz)) {
 *             return null; // Let default factory handle it
 *         }
 *         if (factory == null) {
 *             factory = new MyWorkflowFactory(dataConverter);
 *         }
 *         factory.registerWorkflowImplementationType(clazz);
 *         return factory;
 *     }
 * }
 * }</pre>
 *
 * Usage with WorkerFactory:
 * <pre>{@code
 * WorkerFactory factory = WorkerFactory.newInstance(
 *     client,
 *     WorkerFactoryOptions.newBuilder()
 *         .addPlugin(new MyLanguagePlugin())
 *         .build()
 * );
 * Worker worker = factory.newWorker("task-queue");
 * // Plugin automatically handles workflow types during registration
 * worker.registerWorkflowImplementationTypes(
 *     MyLanguageWorkflow.class,  // Handled by plugin
 *     StandardJavaWorkflow.class  // Handled by default factory
 * );
 * }</pre>
 */
public interface WorkerPlugin {

    /**
     * Called before Worker is created to allow modification of worker options.
     *
     * @param builder the WorkerOptions builder to modify
     * @return the modified builder (may be same instance or new)
     */
    default WorkerOptions.Builder configureWorker(WorkerOptions.Builder builder) {
        return builder;
    }

    /**
     * Called for each workflow implementation type being registered.
     *
     * If this plugin handles the workflow type, it should:
     * 1. Register the type with its internal factory
     * 2. Return the factory instance
     *
     * If this plugin does not handle the type, return null to let the next
     * plugin or the default POJO factory handle it.
     *
     * @param workflowImplementationType the workflow implementation class being registered
     * @param dataConverter the DataConverter from WorkflowClient options
     * @return a factory that handles this workflow type, or null to delegate
     */
    @Nullable
    default WorkflowImplementationFactory getFactoryForType(
            Class<?> workflowImplementationType, DataConverter dataConverter) {
        return null;
    }

    /**
     * Called after Worker is created to allow registration of activity implementations
     * or other setup.
     *
     * Note: For workflow registration, prefer using getFactoryForType which integrates
     * with the standard registerWorkflowImplementationTypes API.
     *
     * @param worker the created worker
     * @param dataConverter the DataConverter from WorkflowClient options
     */
    default void onWorkerCreated(Worker worker, DataConverter dataConverter) {
        // Default no-op
    }
}
```

**Key Design Points:**
- `getFactoryForType` is called for each workflow class during registration
- Plugins can lazily create and reuse a single factory instance
- The same factory can handle multiple workflow types
- Returning `null` means "I don't handle this type, try the next plugin"

### Component 2: WorkerFactoryOptions Plugin Support

**Location:** `temporal-sdk/src/main/java/io/temporal/worker/WorkerFactoryOptions.java`

```java
// Add to existing WorkerFactoryOptions class:

public final class WorkerFactoryOptions {
    // ... existing fields ...
    private final List<WorkerPlugin> plugins;

    // In Builder:
    public static final class Builder {
        private List<WorkerPlugin> plugins = new ArrayList<>();

        /**
         * Adds a plugin that will be applied to all workers created by this factory.
         */
        public Builder addPlugin(WorkerPlugin plugin) {
            this.plugins.add(Objects.requireNonNull(plugin));
            return this;
        }

        /**
         * Sets all plugins, replacing any previously added.
         */
        public Builder setPlugins(List<WorkerPlugin> plugins) {
            this.plugins = new ArrayList<>(plugins);
            return this;
        }
    }

    public List<WorkerPlugin> getPlugins() {
        return Collections.unmodifiableList(plugins);
    }
}
```

### Component 3: Worker Registration Interception

**Location:** `temporal-sdk/src/main/java/io/temporal/worker/Worker.java`

The Worker class is modified to:
1. Store plugins and dataConverter passed from WorkerFactory
2. Intercept `registerWorkflowImplementationTypes` to call plugins

```java
public final class Worker implements Suspendable {
    // ... existing fields ...
    private final List<WorkerPlugin> plugins;
    private final DataConverter dataConverter;
    private final List<WorkflowImplementationFactory> workflowImplementationFactories = new ArrayList<>();

    // Updated constructor receives plugins and dataConverter
    Worker(
        WorkflowClient client,
        String taskQueue,
        WorkerFactoryOptions factoryOptions,
        WorkerOptions options,
        // ... other params ...
        List<WorkerPlugin> plugins,
        DataConverter dataConverter
    ) {
        // ... existing initialization ...
        this.plugins = plugins;
        this.dataConverter = dataConverter;
    }

    /**
     * Registers workflow implementation types.
     * Plugins are consulted first for each type.
     */
    public void registerWorkflowImplementationTypes(
            WorkflowImplementationOptions options,
            Class<?>... workflowImplementationClasses) {
        checkNotStarted();

        for (Class<?> clazz : workflowImplementationClasses) {
            WorkflowImplementationFactory factory = null;

            // Ask plugins if they handle this type
            for (WorkerPlugin plugin : plugins) {
                factory = plugin.getFactoryForType(clazz, dataConverter);
                if (factory != null) {
                    break; // First plugin to return a factory wins
                }
            }

            if (factory != null) {
                // Plugin handles this type - track the factory
                if (!workflowImplementationFactories.contains(factory)) {
                    workflowImplementationFactories.add(factory);
                }
            } else {
                // No plugin handles it - use default POJO factory
                workflowWorker.registerWorkflowImplementationTypes(options, clazz);
            }
        }
    }

    // During worker start, register all plugin factories with the workflow worker
    public void start() {
        // ... existing code ...
        for (WorkflowImplementationFactory factory : workflowImplementationFactories) {
            workflowWorker.registerWorkflowImplementationFactory(factory);
        }
        // ... existing code ...
    }
}
```

### Component 4: WorkerFactory Plugin Integration

**Location:** `temporal-sdk/src/main/java/io/temporal/worker/WorkerFactory.java`

```java
public synchronized Worker newWorker(String taskQueue, WorkerOptions options) {
    // ... existing validation ...

    // Let plugins configure worker options
    WorkerOptions.Builder optionsBuilder = WorkerOptions.newBuilder(options);
    for (WorkerPlugin plugin : factoryOptions.getPlugins()) {
        optionsBuilder = plugin.configureWorker(optionsBuilder);
    }
    WorkerOptions configuredOptions = optionsBuilder.build();

    DataConverter dataConverter = workflowClient.getOptions().getDataConverter();

    Worker worker = new Worker(
        workflowClient,
        taskQueue,
        factoryOptions,
        configuredOptions,
        // ... other params ...
        factoryOptions.getPlugins(),  // Pass plugins to worker
        dataConverter                   // Pass dataConverter to worker
    );

    workers.put(taskQueue, worker);

    // Notify plugins of worker creation (for activity registration etc.)
    for (WorkerPlugin plugin : factoryOptions.getPlugins()) {
        plugin.onWorkerCreated(worker, dataConverter);
    }

    return worker;
}
```

### Component 5: KotlinPlugin Implementation

**Location:** `temporal-kotlin/src/main/kotlin/io/temporal/kotlin/worker/KotlinPlugin.kt`

```kotlin
package io.temporal.kotlin.worker

import io.temporal.common.converter.DataConverter
import io.temporal.internal.worker.WorkflowImplementationFactory
import io.temporal.kotlin.TemporalDsl
import io.temporal.kotlin.internal.KotlinWorkflowDefinition
import io.temporal.kotlin.internal.KotlinWorkflowImplementationFactory
import io.temporal.plugin.WorkerPlugin
import io.temporal.worker.WorkerOptions

/**
 * Plugin for enabling Kotlin coroutine support in Temporal workflows.
 *
 * When registered with a WorkerFactory, this plugin automatically detects Kotlin
 * suspend workflows during registration and routes them to the Kotlin coroutine
 * execution runtime. Non-suspend workflows are handled by the default Java factory.
 *
 * Usage:
 * ```kotlin
 * val factory = WorkerFactory.newInstance(
 *     client,
 *     WorkerFactoryOptions.newBuilder()
 *         .addPlugin(KotlinPlugin { deadlockDetectionTimeout = 1500L })
 *         .build()
 * )
 * val worker = factory.newWorker("task-queue")
 *
 * // Suspend workflows auto-detected and routed to Kotlin factory
 * // Non-suspend workflows use default Java factory
 * worker.registerWorkflowImplementationTypes(
 *     MySuspendWorkflowImpl::class.java,
 *     MyJavaWorkflowImpl::class.java
 * )
 * ```
 */
public class KotlinPlugin private constructor(
    private val options: KotlinPluginOptions
) : WorkerPlugin {

    /** Lazily created factory - shared across all workflow types handled by this plugin. */
    private var factory: KotlinWorkflowImplementationFactory? = null

    /**
     * Configures worker options before worker creation.
     * Sets deadlock detection timeout if configured.
     */
    override fun configureWorker(builder: WorkerOptions.Builder): WorkerOptions.Builder {
        if (options.configureDeadlockDetection) {
            builder.setDefaultDeadlockDetectionTimeout(options.deadlockDetectionTimeout)
        }
        return builder
    }

    /**
     * Called for each workflow type during registration.
     *
     * If the workflow uses Kotlin suspend functions, this plugin handles it by:
     * 1. Creating/reusing a KotlinWorkflowImplementationFactory
     * 2. Registering the type with that factory
     * 3. Returning the factory
     *
     * For non-suspend workflows, returns null to let the default POJO factory handle them.
     */
    override fun getFactoryForType(
        workflowImplementationType: Class<*>,
        dataConverter: DataConverter
    ): WorkflowImplementationFactory? {
        // Check if this is a Kotlin suspend workflow
        if (!KotlinWorkflowDefinition.isSuspendWorkflow(workflowImplementationType)) {
            return null // Not a suspend workflow, let default factory handle it
        }

        // Lazily create the factory
        if (factory == null) {
            factory = KotlinWorkflowImplementationFactory(
                dataConverter = dataConverter,
                deadlockDetectionTimeoutMs = options.deadlockDetectionTimeout
            )
        }

        // Register the workflow type with our factory
        factory!!.registerWorkflowImplementationType(workflowImplementationType)
        return factory
    }

    public val deadlockDetectionTimeout: Long
        get() = options.deadlockDetectionTimeout

    public companion object {
        @JvmStatic
        public fun create(): KotlinPlugin = KotlinPlugin(KotlinPluginOptions())

        @JvmStatic
        public fun create(options: KotlinPluginOptions): KotlinPlugin = KotlinPlugin(options)

        @JvmStatic
        public fun create(block: KotlinPluginOptions.Builder.() -> Unit): KotlinPlugin {
            return KotlinPlugin(KotlinPluginOptions.Builder().apply(block).build())
        }
    }
}

/**
 * Configuration options for the Kotlin plugin.
 */
public class KotlinPluginOptions(
    public val deadlockDetectionTimeout: Long = DEFAULT_DEADLOCK_DETECTION_TIMEOUT,
    public val configureDeadlockDetection: Boolean = true
) {
    public companion object {
        public const val DEFAULT_DEADLOCK_DETECTION_TIMEOUT: Long = 1000L
    }

    @TemporalDsl
    public class Builder {
        public var deadlockDetectionTimeout: Long = DEFAULT_DEADLOCK_DETECTION_TIMEOUT
        public var configureDeadlockDetection: Boolean = true

        public fun build(): KotlinPluginOptions = KotlinPluginOptions(
            deadlockDetectionTimeout = deadlockDetectionTimeout,
            configureDeadlockDetection = configureDeadlockDetection
        )
    }
}

// DSL functions for Kotlin-friendly construction
public fun KotlinPlugin(
    options: @TemporalDsl KotlinPluginOptions.Builder.() -> Unit
): KotlinPlugin = KotlinPlugin.create(options)

public fun KotlinPlugin(): KotlinPlugin = KotlinPlugin.create()
```

## Changes Summary

### Change 1: Create WorkerPlugin Interface

**Summary:** Define plugin interface with `getFactoryForType` method

**Scope:**
- Create `io.temporal.plugin` package
- Add `WorkerPlugin` interface with `configureWorker`, `getFactoryForType`, and `onWorkerCreated` methods
- `getFactoryForType` returns a factory for workflow types the plugin handles

**Tests:**
- Unit test for default method behavior
- Test plugin returning factory for specific types
- Test plugin returning null for unhandled types

---

### Change 2: Add Plugin Support to WorkerFactoryOptions

**Summary:** Enable plugin registration at factory level

**Scope:**
- Add `plugins` field to `WorkerFactoryOptions`
- Add `addPlugin()` and `setPlugins()` builder methods
- Add `getPlugins()` accessor

**Tests:**
- Test adding single plugin
- Test adding multiple plugins
- Test plugin list immutability

---

### Change 3: Integrate Plugins in Worker Registration

**Summary:** Intercept workflow registration to call plugins

**Scope:**
- Add `plugins` and `dataConverter` fields to Worker
- Modify `registerWorkflowImplementationTypes` to call `plugin.getFactoryForType` for each class
- Track plugin-provided factories and register them at worker start
- Classes not handled by plugins use default POJO factory

**Tests:**
- Test plugin factory is used for handled types
- Test default factory is used for unhandled types
- Test mixed workflow registration (some handled, some not)
- Test DataConverter is passed correctly

---

### Change 4: Update WorkerFactory to Pass Plugins

**Summary:** Wire plugins and DataConverter through to Worker

**Scope:**
- Pass `factoryOptions.getPlugins()` to Worker constructor
- Pass `dataConverter` from client to Worker constructor
- Call `plugin.configureWorker()` before worker creation
- Call `plugin.onWorkerCreated()` after worker creation

---

### Change 5: Simplify KotlinPlugin

**Summary:** Implement `getFactoryForType` for automatic suspend workflow detection

**Scope:**
- Implement `WorkerPlugin.getFactoryForType`
- Detect suspend workflows via `KotlinWorkflowDefinition.isSuspendWorkflow()`
- Create factory lazily, reuse for all suspend workflow types
- Return `null` for non-suspend workflows

**Tests:**
- Test suspend workflow detection and routing
- Test non-suspend workflow delegation to default factory
- Test factory reuse across multiple workflow types
- Test DataConverter propagation to factory

## Usage Examples

### Standard Registration with Plugin (Recommended)

```kotlin
// 1. Create factory with Kotlin plugin
val factory = WorkerFactory.newInstance(
    client,
    WorkerFactoryOptions.newBuilder()
        .addPlugin(KotlinPlugin { deadlockDetectionTimeout = 1500L })
        .build()
)

// 2. Create worker
val worker = factory.newWorker("my-task-queue")

// 3. Register workflows - suspend workflows auto-detected
worker.registerWorkflowImplementationTypes(
    MySuspendWorkflowImpl::class.java,  // Plugin handles this
    MyJavaWorkflowImpl::class.java      // Default factory handles this
)

// 4. Register activities
worker.registerActivitiesImplementations(MyActivityImpl())

// 5. Start factory
factory.start()
```

### With Custom DataConverter

```kotlin
// DataConverter flows from client through to plugin automatically
val clientOptions = WorkflowClientOptions.newBuilder()
    .setDataConverter(JacksonJsonDataConverter.newDefaultInstance())
    .build()
val client = WorkflowClient.newInstance(service, clientOptions)

// Plugin receives the client's DataConverter in getFactoryForType
val factory = WorkerFactory.newInstance(
    client,
    WorkerFactoryOptions.newBuilder()
        .addPlugin(KotlinPlugin())
        .build()
)
```

### Legacy Extension Functions (Still Supported)

```kotlin
// These extension functions are deprecated but still work
val plugin = KotlinPlugin()
worker.registerKotlinWorkflowImplementationTypes(
    plugin,
    MyWorkflowImpl::class
)
```

## Backward Compatibility

- Existing `Worker.registerKotlinWorkflowImplementationTypes()` extension functions are deprecated but continue to work
- Existing code without plugins works unchanged - default POJO factory handles all workflows
- Plugin-based approach is opt-in via `WorkerFactoryOptions.addPlugin()`

## Advantages of This Design

1. **Single registration API** - Users use standard `registerWorkflowImplementationTypes` for all workflows
2. **Automatic detection** - Suspend workflows are automatically routed to the Kotlin factory
3. **DataConverter propagation** - Plugins receive the client's DataConverter automatically
4. **Extensible** - Pattern generalizes to other language/framework integrations
5. **Composable** - Multiple plugins can coexist, each handling different workflow types

## Future Considerations

1. **Activity plugins** - Could extend `getFactoryForType` pattern to activities
2. **Plugin ordering/priority** - Could add explicit ordering for plugin consultation
3. **Plugin lifecycle** - Could add `onWorkerShutdown` hook
4. **Client-side plugins** - Could add interceptors for workflow stubs
