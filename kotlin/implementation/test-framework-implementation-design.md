# Kotlin SDK Test Framework Implementation Design

## Overview

This document describes the implementation design for the Kotlin SDK test framework based on the [Test Framework Design API](./test-framework-design.md). The implementation wraps the Java SDK's test framework while providing Kotlin-idiomatic APIs.

## Package Structure

```
io.temporal.kotlin.testing/
├── KTestWorkflowEnvironment.kt      # Main test environment
├── KTestWorkflowExtension.kt        # JUnit 5 workflow extension
├── KTestActivityEnvironment.kt      # Activity test environment
├── KTestActivityExtension.kt        # JUnit 5 activity extension
├── KTestEnvironmentOptions.kt       # Configuration options
├── KWorker.kt                       # Kotlin worker wrapper
├── WorkflowInitialTime.kt           # Annotation for test initial time
└── internal/
    └── KTestActivityEnvironmentInternal.kt  # Internal implementation
```

---

## 1. KTestEnvironmentOptions

**Purpose:** Configuration options for test environments with DSL support.

### Implementation

```kotlin
package io.temporal.kotlin.testing

import com.uber.m3.tally.Scope
import io.temporal.api.enums.v1.IndexedValueType
import io.temporal.client.WorkflowClientOptions
import io.temporal.kotlin.TemporalDsl
import io.temporal.serviceclient.WorkflowServiceStubsOptions
import io.temporal.testing.TestEnvironmentOptions
import io.temporal.worker.WorkerFactoryOptions
import java.time.Instant

/**
 * Kotlin DSL builder for test environment options.
 */
@TemporalDsl
public class KTestEnvironmentOptionsBuilder internal constructor() {

  /** Namespace to use for testing. Default: "UnitTest" */
  public var namespace: String = "UnitTest"

  /** Initial time for the workflow virtual clock. Default: current time */
  public var initialTime: Instant? = null

  /** Whether to enable time skipping. Default: true */
  public var useTimeskipping: Boolean = true

  /** Whether to use external Temporal service. Default: false (in-memory) */
  public var useExternalService: Boolean = false

  /** Target endpoint for external service. */
  public var target: String? = null

  /** Metrics scope for reporting. */
  public var metricsScope: Scope? = null

  private var workerFactoryOptionsBuilder: (WorkerFactoryOptions.Builder.() -> Unit)? = null
  private var workflowClientOptionsBuilder: (WorkflowClientOptions.Builder.() -> Unit)? = null
  private var workflowServiceStubsOptionsBuilder: (WorkflowServiceStubsOptions.Builder.() -> Unit)? = null
  private val searchAttributes: MutableMap<String, IndexedValueType> = mutableMapOf()

  /**
   * Configure WorkerFactoryOptions.
   */
  public fun workerFactoryOptions(block: WorkerFactoryOptions.Builder.() -> Unit) {
    workerFactoryOptionsBuilder = block
  }

  /**
   * Configure WorkflowClientOptions.
   */
  public fun workflowClientOptions(block: WorkflowClientOptions.Builder.() -> Unit) {
    workflowClientOptionsBuilder = block
  }

  /**
   * Configure WorkflowServiceStubsOptions.
   */
  public fun workflowServiceStubsOptions(block: WorkflowServiceStubsOptions.Builder.() -> Unit) {
    workflowServiceStubsOptionsBuilder = block
  }

  /**
   * Register search attributes.
   */
  public fun searchAttributes(block: SearchAttributesBuilder.() -> Unit) {
    SearchAttributesBuilder(searchAttributes).apply(block)
  }

  @TemporalDsl
  public class SearchAttributesBuilder internal constructor(
    private val attributes: MutableMap<String, IndexedValueType>
  ) {
    public fun register(name: String, type: IndexedValueType) {
      attributes[name] = type
    }
  }

  internal fun build(): TestEnvironmentOptions {
    val builder = TestEnvironmentOptions.newBuilder()

    // Apply namespace via WorkflowClientOptions
    val clientOptions = WorkflowClientOptions.newBuilder().apply {
      setNamespace(namespace)
      workflowClientOptionsBuilder?.invoke(this)
    }.build()
    builder.setWorkflowClientOptions(clientOptions)

    // Apply other options
    workerFactoryOptionsBuilder?.let { block ->
      builder.setWorkerFactoryOptions(
        WorkerFactoryOptions.newBuilder().apply(block).build()
      )
    }

    workflowServiceStubsOptionsBuilder?.let { block ->
      builder.setWorkflowServiceStubsOptions(
        WorkflowServiceStubsOptions.newBuilder().apply(block).build()
      )
    }

    initialTime?.let { builder.setInitialTime(it) }
    builder.setUseTimeskipping(useTimeskipping)
    builder.setUseExternalService(useExternalService)
    target?.let { builder.setTarget(it) }
    metricsScope?.let { builder.setMetricsScope(it) }

    searchAttributes.forEach { (name, type) ->
      builder.registerSearchAttribute(name, type)
    }

    return builder.build()
  }
}

/**
 * Immutable configuration for test environments.
 */
public class KTestEnvironmentOptions private constructor(
  internal val javaOptions: TestEnvironmentOptions
) {

  public companion object {
    /**
     * Create options using DSL builder.
     */
    public fun newBuilder(block: KTestEnvironmentOptionsBuilder.() -> Unit = {}): KTestEnvironmentOptions {
      return KTestEnvironmentOptions(
        KTestEnvironmentOptionsBuilder().apply(block).build()
      )
    }

    /**
     * Get default options.
     */
    public fun getDefaultInstance(): KTestEnvironmentOptions {
      return KTestEnvironmentOptions(TestEnvironmentOptions.getDefaultInstance())
    }
  }
}
```

### Key Design Decisions

1. **DSL Builder Pattern**: Uses `@TemporalDsl` annotation for type-safe DSL
2. **Wraps Java Options**: Internally converts to `TestEnvironmentOptions`
3. **Nested DSL Builders**: Supports nested configuration for search attributes

---

## 2. KWorker

**Purpose:** Kotlin wrapper for Worker with idiomatic registration APIs.

### Implementation

```kotlin
package io.temporal.kotlin.testing

import io.temporal.kotlin.TemporalDsl
import io.temporal.kotlin.activity.SuspendActivityWrapper
import io.temporal.worker.Worker
import io.temporal.worker.WorkerOptions
import io.temporal.worker.WorkflowImplementationOptions
import kotlin.reflect.KClass

/**
 * Kotlin worker that provides idiomatic APIs for registering
 * Kotlin workflows and suspend activities.
 *
 * Use [worker] property for direct access to the underlying Java Worker
 * when interoperating with Java workflows/activities.
 */
public class KWorker internal constructor(
  /** The underlying Java Worker for interop scenarios */
  public val worker: Worker
) {

  /**
   * Register Kotlin workflow implementation types using reified generics.
   */
  public inline fun <reified T : Any> registerWorkflowImplementationTypes() {
    worker.registerWorkflowImplementationTypes(T::class.java)
  }

  /**
   * Register Kotlin workflow implementation types using KClass.
   */
  public fun registerWorkflowImplementationTypes(vararg workflowClasses: KClass<*>) {
    worker.registerWorkflowImplementationTypes(
      *workflowClasses.map { it.java }.toTypedArray()
    )
  }

  /**
   * Register Kotlin workflow implementation types with options using KClass.
   */
  public fun registerWorkflowImplementationTypes(
    options: WorkflowImplementationOptions,
    vararg workflowClasses: KClass<*>
  ) {
    worker.registerWorkflowImplementationTypes(
      options,
      *workflowClasses.map { it.java }.toTypedArray()
    )
  }

  /**
   * Register Kotlin workflow implementation types with options DSL.
   */
  public inline fun <reified T : Any> registerWorkflowImplementationTypes(
    options: WorkflowImplementationOptions.Builder.() -> Unit
  ) {
    val opts = WorkflowImplementationOptions.newBuilder().apply(options).build()
    worker.registerWorkflowImplementationTypes(opts, T::class.java)
  }

  /**
   * Register activity implementations.
   * Works with both regular and suspend activity implementations.
   */
  public fun registerActivitiesImplementations(vararg activities: Any) {
    worker.registerActivitiesImplementations(*activities)
  }

  /**
   * Register suspend activity implementations.
   * Wraps suspend functions for execution in the Temporal activity context.
   *
   * @param activities Activity implementation objects containing suspend functions
   */
  public fun registerSuspendActivities(vararg activities: Any) {
    activities.forEach { activity ->
      val wrapper = SuspendActivityWrapper.wrap(activity)
      worker.registerActivitiesImplementations(wrapper)
    }
  }

  /**
   * Register Nexus service implementations.
   */
  public fun registerNexusServiceImplementations(vararg services: Any) {
    worker.registerNexusServiceImplementation(*services)
  }
}
```

### Key Design Decisions

1. **Exposes Underlying Worker**: Via `worker` property for interop
2. **Reified Generics**: For type-safe registration without reflection
3. **KClass Support**: For vararg registration patterns
4. **Suspend Activity Support**: Via `SuspendActivityWrapper` integration

---

## 3. KTestWorkflowEnvironment

**Purpose:** Main test environment providing in-memory Temporal service with time skipping.

### Implementation

```kotlin
package io.temporal.kotlin.testing

import io.temporal.api.enums.v1.IndexedValueType
import io.temporal.api.nexus.v1.Endpoint
import io.temporal.kotlin.client.KWorkflowClient
import io.temporal.kotlin.toJavaDuration
import io.temporal.kotlin.worker.KotlinPlugin
import io.temporal.serviceclient.OperatorServiceStubs
import io.temporal.serviceclient.WorkflowServiceStubs
import io.temporal.testing.TestWorkflowEnvironment
import io.temporal.worker.Worker
import io.temporal.worker.WorkerOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.Closeable
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlin.time.Duration as KDuration
import kotlin.time.toJavaDuration as kotlinToJava

/**
 * Kotlin test environment for workflow unit testing.
 *
 * Provides an in-memory Temporal service with automatic time skipping,
 * allowing workflows that run for hours/days to be tested in milliseconds.
 *
 * Example:
 * ```kotlin
 * val testEnv = KTestWorkflowEnvironment.newInstance {
 *     namespace = "test-namespace"
 *     initialTime = Instant.parse("2024-01-01T00:00:00Z")
 * }
 *
 * val worker = testEnv.newWorker("task-queue")
 * worker.registerWorkflowImplementationTypes<MyWorkflowImpl>()
 * worker.registerActivitiesImplementations(MyActivitiesImpl())
 *
 * testEnv.start()
 *
 * val result = testEnv.workflowClient.executeWorkflow(
 *     MyWorkflow::execute,
 *     KWorkflowOptions(taskQueue = "task-queue"),
 *     "input"
 * )
 *
 * testEnv.close()
 * ```
 */
public class KTestWorkflowEnvironment private constructor(
  private val testEnvironment: TestWorkflowEnvironment
) : Closeable {

  /**
   * The Kotlin workflow client for interacting with workflows.
   */
  public val workflowClient: KWorkflowClient by lazy {
    KWorkflowClient(testEnvironment.workflowClient)
  }

  /**
   * Current test time in milliseconds since epoch.
   * May differ from system time due to time skipping.
   */
  public val currentTimeMillis: Long
    get() = testEnvironment.currentTimeMillis()

  /**
   * Current test time as an Instant.
   */
  public val currentTime: Instant
    get() = Instant.ofEpochMilli(currentTimeMillis)

  /**
   * The namespace used by this test environment.
   */
  public val namespace: String
    get() = testEnvironment.namespace

  /**
   * Whether the workers have been started.
   */
  public val isStarted: Boolean
    get() = testEnvironment.isStarted

  /**
   * Whether shutdown has been initiated.
   */
  public val isShutdown: Boolean
    get() = testEnvironment.isShutdown

  /**
   * Whether all workers have terminated.
   */
  public val isTerminated: Boolean
    get() = testEnvironment.isTerminated

  /**
   * Access to WorkflowServiceStubs for advanced scenarios.
   */
  public val workflowServiceStubs: WorkflowServiceStubs
    get() = testEnvironment.workflowServiceStubs

  /**
   * Access to OperatorServiceStubs for advanced scenarios.
   */
  public val operatorServiceStubs: OperatorServiceStubs
    get() = testEnvironment.operatorServiceStubs

  /**
   * Create a new Kotlin worker for the specified task queue.
   *
   * @param taskQueue The task queue name
   * @return A KWorker instance
   */
  public fun newWorker(taskQueue: String): KWorker {
    return KWorker(testEnvironment.newWorker(taskQueue))
  }

  /**
   * Create a new Kotlin worker with options.
   *
   * @param taskQueue The task queue name
   * @param options DSL builder for WorkerOptions
   * @return A KWorker instance
   */
  public fun newWorker(
    taskQueue: String,
    options: WorkerOptions.Builder.() -> Unit
  ): KWorker {
    val workerOptions = WorkerOptions.newBuilder().apply(options).build()
    return KWorker(testEnvironment.newWorker(taskQueue, workerOptions))
  }

  /**
   * Create a new Kotlin worker with WorkerOptions.
   *
   * @param taskQueue The task queue name
   * @param options WorkerOptions instance
   * @return A KWorker instance
   */
  public fun newWorker(taskQueue: String, options: WorkerOptions): KWorker {
    return KWorker(testEnvironment.newWorker(taskQueue, options))
  }

  /**
   * Start all registered workers.
   */
  public fun start() {
    testEnvironment.start()
  }

  /**
   * Sleep for the specified duration with time skipping.
   * This is a suspend function that advances test time without blocking.
   *
   * @param duration Kotlin Duration to sleep
   */
  public suspend fun sleep(duration: KDuration) {
    withContext(Dispatchers.IO) {
      testEnvironment.sleep(duration.kotlinToJava())
    }
  }

  /**
   * Sleep for the specified duration with time skipping.
   *
   * @param duration Java Duration to sleep
   */
  public suspend fun sleep(duration: Duration) {
    withContext(Dispatchers.IO) {
      testEnvironment.sleep(duration)
    }
  }

  /**
   * Register a callback to execute after the specified delay in test time.
   *
   * @param delay Kotlin Duration delay
   * @param callback The callback to execute
   */
  public fun registerDelayedCallback(delay: KDuration, callback: () -> Unit) {
    testEnvironment.registerDelayedCallback(delay.kotlinToJava()) { callback() }
  }

  /**
   * Register a callback to execute after the specified delay in test time.
   *
   * @param delay Java Duration delay
   * @param callback The callback to execute
   */
  public fun registerDelayedCallback(delay: Duration, callback: () -> Unit) {
    testEnvironment.registerDelayedCallback(delay) { callback() }
  }

  /**
   * Register a search attribute with the test server.
   *
   * @param name Search attribute name
   * @param type Search attribute type
   * @return true if registered, false if already exists
   */
  public fun registerSearchAttribute(name: String, type: IndexedValueType): Boolean {
    return testEnvironment.registerSearchAttribute(name, type)
  }

  /**
   * Create a Nexus endpoint for testing.
   *
   * @param name Endpoint name
   * @param taskQueue Task queue for the endpoint
   * @return The created Endpoint
   */
  public fun createNexusEndpoint(name: String, taskQueue: String): Endpoint {
    return testEnvironment.createNexusEndpoint(name, taskQueue)
  }

  /**
   * Delete a Nexus endpoint.
   *
   * @param endpoint The endpoint to delete
   */
  public fun deleteNexusEndpoint(endpoint: Endpoint) {
    testEnvironment.deleteNexusEndpoint(endpoint)
  }

  /**
   * Get diagnostic information including workflow histories.
   * Useful for debugging test failures.
   */
  public fun getDiagnostics(): String {
    return testEnvironment.diagnostics
  }

  /**
   * Initiate graceful shutdown.
   * Workers stop accepting new tasks but complete in-progress work.
   */
  public fun shutdown() {
    testEnvironment.shutdown()
  }

  /**
   * Initiate immediate shutdown.
   * Attempts to stop all processing immediately.
   */
  public fun shutdownNow() {
    testEnvironment.shutdownNow()
  }

  /**
   * Wait for all workers to terminate.
   *
   * @param timeout Maximum time to wait
   */
  public suspend fun awaitTermination(timeout: KDuration) {
    withContext(Dispatchers.IO) {
      testEnvironment.awaitTermination(
        timeout.inWholeMilliseconds,
        TimeUnit.MILLISECONDS
      )
    }
  }

  /**
   * Wait for all workers to terminate.
   *
   * @param timeout Maximum time to wait (Java Duration)
   */
  public suspend fun awaitTermination(timeout: Duration) {
    withContext(Dispatchers.IO) {
      testEnvironment.awaitTermination(
        timeout.toMillis(),
        TimeUnit.MILLISECONDS
      )
    }
  }

  /**
   * Close the test environment.
   * Calls shutdownNow() and awaitTermination().
   */
  override fun close() {
    testEnvironment.close()
  }

  public companion object {
    /**
     * Create a new test environment with default options.
     */
    public fun newInstance(): KTestWorkflowEnvironment {
      return KTestWorkflowEnvironment(TestWorkflowEnvironment.newInstance())
    }

    /**
     * Create a new test environment with DSL configuration.
     *
     * Example:
     * ```kotlin
     * val testEnv = KTestWorkflowEnvironment.newInstance {
     *     namespace = "test-namespace"
     *     initialTime = Instant.parse("2024-01-01T00:00:00Z")
     *     useTimeskipping = true
     *
     *     workerFactoryOptions {
     *         maxWorkflowThreadCount = 800
     *     }
     *
     *     searchAttributes {
     *         register("CustomKeyword", IndexedValueType.INDEXED_VALUE_TYPE_KEYWORD)
     *     }
     * }
     * ```
     */
    public fun newInstance(
      options: KTestEnvironmentOptionsBuilder.() -> Unit
    ): KTestWorkflowEnvironment {
      val javaOptions = KTestEnvironmentOptionsBuilder().apply(options).build()
      return KTestWorkflowEnvironment(TestWorkflowEnvironment.newInstance(javaOptions))
    }

    /**
     * Create a new test environment with pre-built options.
     */
    public fun newInstance(options: KTestEnvironmentOptions): KTestWorkflowEnvironment {
      return KTestWorkflowEnvironment(
        TestWorkflowEnvironment.newInstance(options.javaOptions)
      )
    }
  }
}

/**
 * Use the test environment with automatic cleanup.
 *
 * Example:
 * ```kotlin
 * KTestWorkflowEnvironment.newInstance().use { testEnv ->
 *     // Test code here
 * } // Automatically closed
 * ```
 */
public inline fun <T> KTestWorkflowEnvironment.use(block: (KTestWorkflowEnvironment) -> T): T {
  return try {
    block(this)
  } finally {
    close()
  }
}
```

### Key Design Decisions

1. **Wraps TestWorkflowEnvironment**: Provides Kotlin-idiomatic API over Java implementation
2. **Suspend Functions**: `sleep()` and `awaitTermination()` are suspend functions
3. **Dual Duration Support**: Accepts both `kotlin.time.Duration` and `java.time.Duration`
4. **Property Access**: Uses Kotlin properties instead of getter methods
5. **DSL Builder**: Static `newInstance { }` DSL for configuration
6. **KWorkflowClient Integration**: Returns `KWorkflowClient` for workflow operations
7. **KWorker Return**: `newWorker()` returns `KWorker` instead of Java `Worker`

---

## 4. WorkflowInitialTime Annotation

**Purpose:** Override initial time for specific test methods.

### Implementation

```kotlin
package io.temporal.kotlin.testing

/**
 * Annotation to specify the initial time for a workflow test.
 * Overrides the initial time configured in the extension.
 *
 * Example:
 * ```kotlin
 * @Test
 * @WorkflowInitialTime("2024-06-15T12:00:00Z")
 * fun `test with specific initial time`(workflow: MyWorkflow) {
 *     // Test runs with June 15, 2024 as initial time
 * }
 * ```
 */
@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.RUNTIME)
public annotation class WorkflowInitialTime(
  /**
   * ISO-8601 formatted timestamp for the initial time.
   * Example: "2024-01-01T00:00:00Z"
   */
  val value: String
)
```

---

## 5. KTestWorkflowExtension

**Purpose:** JUnit 5 extension for simplified workflow testing.

### Implementation

```kotlin
package io.temporal.kotlin.testing

import io.temporal.api.enums.v1.IndexedValueType
import io.temporal.client.WorkflowClientOptions
import io.temporal.client.WorkflowOptions
import io.temporal.common.metadata.POJOWorkflowImplMetadata
import io.temporal.common.metadata.POJOWorkflowInterfaceMetadata
import io.temporal.kotlin.TemporalDsl
import io.temporal.kotlin.client.KWorkflowClient
import io.temporal.kotlin.client.KWorkflowOptions
import io.temporal.testing.TestWorkflowEnvironment
import io.temporal.worker.Worker
import io.temporal.worker.WorkerFactoryOptions
import io.temporal.worker.WorkerOptions
import io.temporal.worker.WorkflowImplementationOptions
import io.temporal.workflow.DynamicWorkflow
import org.junit.jupiter.api.extension.*
import org.junit.platform.commons.support.AnnotationSupport
import java.lang.reflect.Constructor
import java.lang.reflect.Parameter
import java.time.Instant
import java.util.*
import kotlin.reflect.KClass

/**
 * JUnit 5 extension for testing Temporal workflows with Kotlin-idiomatic APIs.
 *
 * Example:
 * ```kotlin
 * class MyWorkflowTest {
 *     companion object {
 *         @JvmField
 *         @RegisterExtension
 *         val testWorkflow = kTestWorkflowExtension {
 *             registerWorkflowImplementationTypes<MyWorkflowImpl>()
 *             setActivityImplementations(MyActivitiesImpl())
 *         }
 *     }
 *
 *     @Test
 *     fun `test workflow execution`(workflow: MyWorkflow) {
 *         val result = workflow.execute("input")
 *         assertEquals("expected", result)
 *     }
 * }
 * ```
 */
public class KTestWorkflowExtension private constructor(
  private val config: ExtensionConfig
) : ParameterResolver, TestWatcher, BeforeEachCallback, AfterEachCallback {

  private data class ExtensionConfig(
    val namespace: String,
    val workflowTypes: Map<Class<*>, WorkflowImplementationOptions>,
    val activityImplementations: Array<Any>,
    val suspendActivityImplementations: Array<Any>,
    val nexusServiceImplementations: Array<Any>,
    val workerOptions: WorkerOptions,
    val workerFactoryOptions: WorkerFactoryOptions?,
    val workflowClientOptions: WorkflowClientOptions?,
    val useExternalService: Boolean,
    val target: String?,
    val doNotStart: Boolean,
    val initialTimeMillis: Long,
    val useTimeskipping: Boolean,
    val searchAttributes: Map<String, IndexedValueType>
  )

  private val supportedParameterTypes = mutableSetOf<Class<*>>().apply {
    add(KTestWorkflowEnvironment::class.java)
    add(KWorkflowClient::class.java)
    add(KWorkflowOptions::class.java)
    add(KWorker::class.java)
    add(Worker::class.java)
    // Add workflow interface types
    config.workflowTypes.keys.forEach { workflowType ->
      if (!DynamicWorkflow::class.java.isAssignableFrom(workflowType)) {
        val metadata = POJOWorkflowImplMetadata.newInstance(workflowType)
        metadata.workflowInterfaces.forEach { add(it.interfaceClass) }
      }
    }
  }

  private val includesDynamicWorkflow = config.workflowTypes.keys.any {
    DynamicWorkflow::class.java.isAssignableFrom(it)
  }

  override fun supportsParameter(
    parameterContext: ParameterContext,
    extensionContext: ExtensionContext
  ): Boolean {
    val parameter = parameterContext.parameter
    if (parameter.declaringExecutable is Constructor<*>) return false

    val parameterType = parameter.type
    if (supportedParameterTypes.contains(parameterType)) return true

    if (!includesDynamicWorkflow) return false

    return try {
      POJOWorkflowInterfaceMetadata.newInstance(parameterType)
      true
    } catch (e: Exception) {
      false
    }
  }

  override fun resolveParameter(
    parameterContext: ParameterContext,
    extensionContext: ExtensionContext
  ): Any {
    val parameterType = parameterContext.parameter.type
    val store = getStore(extensionContext)

    return when (parameterType) {
      KTestWorkflowEnvironment::class.java -> getTestEnvironment(store)
      KWorkflowClient::class.java -> getTestEnvironment(store).workflowClient
      KWorkflowOptions::class.java -> getWorkflowOptions(store)
      KWorker::class.java -> getKWorker(store)
      Worker::class.java -> getKWorker(store).worker
      else -> {
        // Create workflow stub
        val testEnv = getTestEnvironment(store)
        val options = getWorkflowOptions(store)
        testEnv.workflowClient.workflowClient.newWorkflowStub(
          parameterType,
          options.toJavaOptions()
        )
      }
    }
  }

  override fun beforeEach(context: ExtensionContext) {
    val currentInitialTimeMillis = AnnotationSupport.findAnnotation(
      context.element,
      WorkflowInitialTime::class.java
    ).map { Instant.parse(it.value).toEpochMilli() }
      .orElse(config.initialTimeMillis)

    val testEnvOptions = io.temporal.testing.TestEnvironmentOptions.newBuilder().apply {
      setUseExternalService(config.useExternalService)
      setUseTimeskipping(config.useTimeskipping)
      config.target?.let { setTarget(it) }
      if (currentInitialTimeMillis > 0) setInitialTimeMillis(currentInitialTimeMillis)

      val clientOptions = (config.workflowClientOptions?.let {
        WorkflowClientOptions.newBuilder(it)
      } ?: WorkflowClientOptions.newBuilder())
        .setNamespace(config.namespace)
        .build()
      setWorkflowClientOptions(clientOptions)

      config.workerFactoryOptions?.let { setWorkerFactoryOptions(it) }
      config.searchAttributes.forEach { (name, type) ->
        registerSearchAttribute(name, type)
      }
    }.build()

    val javaTestEnv = TestWorkflowEnvironment.newInstance(testEnvOptions)
    val testEnvironment = KTestWorkflowEnvironment.newInstance {
      // Options already applied to javaTestEnv
    }

    // Create task queue
    val taskQueue = "WorkflowTest-${context.displayName}-${context.uniqueId}"
    val worker = javaTestEnv.newWorker(taskQueue, config.workerOptions)
    val kWorker = KWorker(worker)

    // Register workflows
    config.workflowTypes.forEach { (wfType, options) ->
      worker.registerWorkflowImplementationTypes(options, wfType)
    }

    // Register activities
    worker.registerActivitiesImplementations(*config.activityImplementations)

    // Register suspend activities
    config.suspendActivityImplementations.forEach { activity ->
      kWorker.registerSuspendActivities(activity)
    }

    // Register Nexus services
    if (config.nexusServiceImplementations.isNotEmpty()) {
      worker.registerNexusServiceImplementation(*config.nexusServiceImplementations)
    }

    if (!config.doNotStart) {
      javaTestEnv.start()
    }

    // Store in extension context
    val store = getStore(context)
    store.put(TEST_ENVIRONMENT_KEY, KTestWorkflowEnvironment.Companion::class.java.getDeclaredMethod(
      "newInstance"
    ).let {
      // Wrap the Java test environment
      val field = KTestWorkflowEnvironment::class.java.getDeclaredField("testEnvironment")
      field.isAccessible = true
      KTestWorkflowEnvironment::class.java.getDeclaredConstructor(
        TestWorkflowEnvironment::class.java
      ).apply { isAccessible = true }.newInstance(javaTestEnv)
    })
    store.put(KWORKER_KEY, kWorker)
    store.put(WORKFLOW_OPTIONS_KEY, KWorkflowOptions(taskQueue = taskQueue))
  }

  override fun afterEach(context: ExtensionContext) {
    val testEnv = getStore(context).get(TEST_ENVIRONMENT_KEY, KTestWorkflowEnvironment::class.java)
    testEnv?.close()
  }

  override fun testFailed(context: ExtensionContext, cause: Throwable) {
    val testEnv = getStore(context).get(TEST_ENVIRONMENT_KEY, KTestWorkflowEnvironment::class.java)
    testEnv?.let {
      System.err.println("Workflow execution histories:\n${it.getDiagnostics()}")
    }
  }

  private fun getStore(context: ExtensionContext): ExtensionContext.Store {
    val namespace = ExtensionContext.Namespace.create(
      KTestWorkflowExtension::class.java,
      context.requiredTestMethod
    )
    return context.getStore(namespace)
  }

  private fun getTestEnvironment(store: ExtensionContext.Store): KTestWorkflowEnvironment {
    return store.get(TEST_ENVIRONMENT_KEY, KTestWorkflowEnvironment::class.java)
      ?: throw IllegalStateException("Test environment not initialized")
  }

  private fun getKWorker(store: ExtensionContext.Store): KWorker {
    return store.get(KWORKER_KEY, KWorker::class.java)
      ?: throw IllegalStateException("Worker not initialized")
  }

  private fun getWorkflowOptions(store: ExtensionContext.Store): KWorkflowOptions {
    return store.get(WORKFLOW_OPTIONS_KEY, KWorkflowOptions::class.java)
      ?: throw IllegalStateException("Workflow options not initialized")
  }

  public companion object {
    private const val TEST_ENVIRONMENT_KEY = "testEnvironment"
    private const val KWORKER_KEY = "kWorker"
    private const val WORKFLOW_OPTIONS_KEY = "workflowOptions"

    /**
     * Create a new extension builder.
     */
    public fun newBuilder(): Builder = Builder()
  }

  /**
   * Builder for KTestWorkflowExtension.
   */
  @TemporalDsl
  public class Builder internal constructor() {
    private var namespace: String = "UnitTest"
    private val workflowTypes = mutableMapOf<Class<*>, WorkflowImplementationOptions>()
    private var activityImplementations: Array<Any> = emptyArray()
    private var suspendActivityImplementations: Array<Any> = emptyArray()
    private var nexusServiceImplementations: Array<Any> = emptyArray()
    private var workerOptions: WorkerOptions = WorkerOptions.getDefaultInstance()
    private var workerFactoryOptions: WorkerFactoryOptions? = null
    private var workflowClientOptions: WorkflowClientOptions? = null
    private var useExternalService: Boolean = false
    private var target: String? = null
    private var doNotStart: Boolean = false
    private var initialTimeMillis: Long = 0
    private var useTimeskipping: Boolean = true
    private val searchAttributes = mutableMapOf<String, IndexedValueType>()

    /** Set the namespace. Default: "UnitTest" */
    public var namespace_: String
      get() = namespace
      set(value) { namespace = value }

    /** Initial time for the test. */
    public var initialTime: Instant? = null
      set(value) {
        field = value
        initialTimeMillis = value?.toEpochMilli() ?: 0
      }

    /** Whether to enable time skipping. Default: true */
    public var useTimeskipping_: Boolean
      get() = useTimeskipping
      set(value) { useTimeskipping = value }

    /** Whether to defer worker startup. Default: false */
    public var doNotStart_: Boolean
      get() = doNotStart
      set(value) { doNotStart = value }

    /**
     * Register workflow implementation types using reified generics.
     */
    public inline fun <reified T : Any> registerWorkflowImplementationTypes() {
      workflowTypes[T::class.java] = WorkflowImplementationOptions.newBuilder().build()
    }

    /**
     * Register workflow implementation types with options DSL.
     */
    public inline fun <reified T : Any> registerWorkflowImplementationTypes(
      options: WorkflowImplementationOptions.Builder.() -> Unit
    ) {
      workflowTypes[T::class.java] = WorkflowImplementationOptions.newBuilder().apply(options).build()
    }

    /**
     * Register workflow implementation types.
     */
    public fun registerWorkflowImplementationTypes(vararg classes: Class<*>) {
      val defaultOptions = WorkflowImplementationOptions.newBuilder().build()
      classes.forEach { workflowTypes[it] = defaultOptions }
    }

    /**
     * Register workflow implementation types with options.
     */
    public fun registerWorkflowImplementationTypes(
      options: WorkflowImplementationOptions,
      vararg classes: Class<*>
    ) {
      classes.forEach { workflowTypes[it] = options }
    }

    /**
     * Set activity implementations.
     */
    public fun setActivityImplementations(vararg activities: Any) {
      activityImplementations = arrayOf(*activities)
    }

    /**
     * Set suspend activity implementations.
     */
    public fun setSuspendActivityImplementations(vararg activities: Any) {
      suspendActivityImplementations = arrayOf(*activities)
    }

    /**
     * Set Nexus service implementations.
     */
    public fun setNexusServiceImplementations(vararg services: Any) {
      nexusServiceImplementations = arrayOf(*services)
    }

    /**
     * Configure worker options.
     */
    public fun workerOptions(block: WorkerOptions.Builder.() -> Unit) {
      workerOptions = WorkerOptions.newBuilder().apply(block).build()
    }

    /**
     * Configure worker factory options.
     */
    public fun workerFactoryOptions(block: WorkerFactoryOptions.Builder.() -> Unit) {
      workerFactoryOptions = WorkerFactoryOptions.newBuilder().apply(block).build()
    }

    /**
     * Configure workflow client options.
     */
    public fun workflowClientOptions(block: WorkflowClientOptions.Builder.() -> Unit) {
      workflowClientOptions = WorkflowClientOptions.newBuilder().apply(block).build()
    }

    /**
     * Use internal in-memory service (default).
     */
    public fun useInternalService() {
      useExternalService = false
      target = null
    }

    /**
     * Use external Temporal service with ClientConfigProfile.
     */
    public fun useExternalService() {
      useExternalService = true
      target = null
    }

    /**
     * Use external Temporal service with explicit address.
     */
    public fun useExternalService(address: String) {
      useExternalService = true
      target = address
    }

    /**
     * Configure search attributes.
     */
    public fun searchAttributes(block: SearchAttributesBuilder.() -> Unit) {
      SearchAttributesBuilder(searchAttributes).apply(block)
    }

    @TemporalDsl
    public class SearchAttributesBuilder internal constructor(
      private val attributes: MutableMap<String, IndexedValueType>
    ) {
      public fun register(name: String, type: IndexedValueType) {
        attributes[name] = type
      }
    }

    public fun build(): KTestWorkflowExtension {
      return KTestWorkflowExtension(
        ExtensionConfig(
          namespace = namespace,
          workflowTypes = workflowTypes.toMap(),
          activityImplementations = activityImplementations,
          suspendActivityImplementations = suspendActivityImplementations,
          nexusServiceImplementations = nexusServiceImplementations,
          workerOptions = workerOptions,
          workerFactoryOptions = workerFactoryOptions,
          workflowClientOptions = workflowClientOptions,
          useExternalService = useExternalService,
          target = target,
          doNotStart = doNotStart,
          initialTimeMillis = initialTimeMillis,
          useTimeskipping = useTimeskipping,
          searchAttributes = searchAttributes.toMap()
        )
      )
    }
  }
}

/**
 * DSL function to create a KTestWorkflowExtension.
 *
 * Example:
 * ```kotlin
 * companion object {
 *     @JvmField
 *     @RegisterExtension
 *     val testWorkflow = kTestWorkflowExtension {
 *         registerWorkflowImplementationTypes<MyWorkflowImpl>()
 *         setActivityImplementations(MyActivitiesImpl())
 *     }
 * }
 * ```
 */
public fun kTestWorkflowExtension(
  block: KTestWorkflowExtension.Builder.() -> Unit
): KTestWorkflowExtension {
  return KTestWorkflowExtension.newBuilder().apply(block).build()
}
```

### Key Design Decisions

1. **DSL Function**: `kTestWorkflowExtension { }` top-level function
2. **Reified Generics**: `registerWorkflowImplementationTypes<T>()` for type-safe registration
3. **Parameter Injection**: Supports `KTestWorkflowEnvironment`, `KWorkflowClient`, `KWorkflowOptions`, `KWorker`, `Worker`, and workflow stubs
4. **Initial Time Annotation**: Supports `@WorkflowInitialTime` per-test override
5. **Test Failure Diagnostics**: Automatically prints workflow histories on failure
6. **External Service Support**: `useExternalService()` and `useExternalService(address)`

---

## 6. KTestActivityEnvironment

**Purpose:** Environment for unit testing activity implementations in isolation.

### Implementation

```kotlin
package io.temporal.kotlin.testing

import io.temporal.activity.ActivityOptions
import io.temporal.activity.LocalActivityOptions
import io.temporal.kotlin.TemporalDsl
import io.temporal.kotlin.activity.KActivityOptions
import io.temporal.kotlin.activity.KLocalActivityOptions
import io.temporal.kotlin.activity.SuspendActivityWrapper
import io.temporal.testing.TestActivityEnvironment
import io.temporal.workflow.Functions
import java.io.Closeable
import java.lang.reflect.Type
import kotlin.reflect.KFunction1
import kotlin.reflect.KFunction2
import kotlin.reflect.KFunction3
import kotlin.reflect.KFunction4
import kotlin.reflect.KSuspendFunction1
import kotlin.reflect.KSuspendFunction2
import kotlin.reflect.KSuspendFunction3
import kotlin.reflect.KSuspendFunction4
import kotlin.reflect.jvm.javaMethod

/**
 * Kotlin test environment for activity unit testing.
 *
 * Supports testing both regular and suspend activity implementations
 * in isolation without needing workflows.
 *
 * Example:
 * ```kotlin
 * val activityEnv = KTestActivityEnvironment.newInstance()
 * activityEnv.registerActivitiesImplementations(MyActivitiesImpl())
 *
 * val result = activityEnv.executeActivity(
 *     MyActivities::doSomething,
 *     KActivityOptions(startToCloseTimeout = 30.seconds),
 *     "input"
 * )
 *
 * assertEquals("expected", result)
 * activityEnv.close()
 * ```
 */
public class KTestActivityEnvironment private constructor(
  private val testEnvironment: TestActivityEnvironment
) : Closeable {

  /**
   * Register activity implementations.
   */
  public fun registerActivitiesImplementations(vararg activities: Any) {
    testEnvironment.registerActivitiesImplementations(*activities)
  }

  /**
   * Register suspend activity implementations.
   */
  public fun registerSuspendActivities(vararg activities: Any) {
    activities.forEach { activity ->
      val wrapper = SuspendActivityWrapper.wrap(activity)
      testEnvironment.registerActivitiesImplementations(wrapper)
    }
  }

  // ========== Execute Activity (1-4 args) ==========

  /**
   * Execute an activity with no arguments.
   */
  public fun <T, R> executeActivity(
    activity: KFunction1<T, R>,
    options: KActivityOptions
  ): R {
    val stub = createActivityStub<T>(activity, options.toJavaOptions())
    @Suppress("UNCHECKED_CAST")
    return activity.call(stub) as R
  }

  /**
   * Execute an activity with one argument.
   */
  public fun <T, A1, R> executeActivity(
    activity: KFunction2<T, A1, R>,
    options: KActivityOptions,
    arg1: A1
  ): R {
    val stub = createActivityStub<T>(activity, options.toJavaOptions())
    @Suppress("UNCHECKED_CAST")
    return activity.call(stub, arg1) as R
  }

  /**
   * Execute an activity with two arguments.
   */
  public fun <T, A1, A2, R> executeActivity(
    activity: KFunction3<T, A1, A2, R>,
    options: KActivityOptions,
    arg1: A1,
    arg2: A2
  ): R {
    val stub = createActivityStub<T>(activity, options.toJavaOptions())
    @Suppress("UNCHECKED_CAST")
    return activity.call(stub, arg1, arg2) as R
  }

  /**
   * Execute an activity with three arguments.
   */
  public fun <T, A1, A2, A3, R> executeActivity(
    activity: KFunction4<T, A1, A2, A3, R>,
    options: KActivityOptions,
    arg1: A1,
    arg2: A2,
    arg3: A3
  ): R {
    val stub = createActivityStub<T>(activity, options.toJavaOptions())
    @Suppress("UNCHECKED_CAST")
    return activity.call(stub, arg1, arg2, arg3) as R
  }

  // ========== Execute Suspend Activity (1-4 args) ==========

  /**
   * Execute a suspend activity with no arguments.
   */
  @JvmName("executeSuspendActivity0")
  public suspend fun <T, R> executeActivity(
    activity: KSuspendFunction1<T, R>,
    options: KActivityOptions
  ): R {
    val stub = createActivityStub<T>(activity, options.toJavaOptions())
    @Suppress("UNCHECKED_CAST")
    return activity.call(stub) as R
  }

  /**
   * Execute a suspend activity with one argument.
   */
  @JvmName("executeSuspendActivity1")
  public suspend fun <T, A1, R> executeActivity(
    activity: KSuspendFunction2<T, A1, R>,
    options: KActivityOptions,
    arg1: A1
  ): R {
    val stub = createActivityStub<T>(activity, options.toJavaOptions())
    @Suppress("UNCHECKED_CAST")
    return activity.call(stub, arg1) as R
  }

  /**
   * Execute a suspend activity with two arguments.
   */
  @JvmName("executeSuspendActivity2")
  public suspend fun <T, A1, A2, R> executeActivity(
    activity: KSuspendFunction3<T, A1, A2, R>,
    options: KActivityOptions,
    arg1: A1,
    arg2: A2
  ): R {
    val stub = createActivityStub<T>(activity, options.toJavaOptions())
    @Suppress("UNCHECKED_CAST")
    return activity.call(stub, arg1, arg2) as R
  }

  /**
   * Execute a suspend activity with three arguments.
   */
  @JvmName("executeSuspendActivity3")
  public suspend fun <T, A1, A2, A3, R> executeActivity(
    activity: KSuspendFunction4<T, A1, A2, A3, R>,
    options: KActivityOptions,
    arg1: A1,
    arg2: A2,
    arg3: A3
  ): R {
    val stub = createActivityStub<T>(activity, options.toJavaOptions())
    @Suppress("UNCHECKED_CAST")
    return activity.call(stub, arg1, arg2, arg3) as R
  }

  // ========== Execute Local Activity (1-4 args) ==========

  /**
   * Execute a local activity with no arguments.
   */
  public fun <T, R> executeLocalActivity(
    activity: KFunction1<T, R>,
    options: KLocalActivityOptions
  ): R {
    val stub = createLocalActivityStub<T>(activity, options.toJavaOptions())
    @Suppress("UNCHECKED_CAST")
    return activity.call(stub) as R
  }

  /**
   * Execute a local activity with one argument.
   */
  public fun <T, A1, R> executeLocalActivity(
    activity: KFunction2<T, A1, R>,
    options: KLocalActivityOptions,
    arg1: A1
  ): R {
    val stub = createLocalActivityStub<T>(activity, options.toJavaOptions())
    @Suppress("UNCHECKED_CAST")
    return activity.call(stub, arg1) as R
  }

  /**
   * Execute a local activity with two arguments.
   */
  public fun <T, A1, A2, R> executeLocalActivity(
    activity: KFunction3<T, A1, A2, R>,
    options: KLocalActivityOptions,
    arg1: A1,
    arg2: A2
  ): R {
    val stub = createLocalActivityStub<T>(activity, options.toJavaOptions())
    @Suppress("UNCHECKED_CAST")
    return activity.call(stub, arg1, arg2) as R
  }

  /**
   * Execute a local activity with three arguments.
   */
  public fun <T, A1, A2, A3, R> executeLocalActivity(
    activity: KFunction4<T, A1, A2, A3, R>,
    options: KLocalActivityOptions,
    arg1: A1,
    arg2: A2,
    arg3: A3
  ): R {
    val stub = createLocalActivityStub<T>(activity, options.toJavaOptions())
    @Suppress("UNCHECKED_CAST")
    return activity.call(stub, arg1, arg2, arg3) as R
  }

  // ========== Heartbeat Testing ==========

  /**
   * Set heartbeat details for the next activity execution.
   * Simulates activity retry with heartbeat checkpoint.
   */
  public fun <T> setHeartbeatDetails(details: T) {
    testEnvironment.setHeartbeatDetails(details)
  }

  /**
   * Set a listener for activity heartbeats.
   */
  public inline fun <reified T> setActivityHeartbeatListener(
    noinline listener: (T) -> Unit
  ) {
    testEnvironment.setActivityHeartbeatListener(
      T::class.java,
      Functions.Proc1 { listener(it) }
    )
  }

  /**
   * Set a listener for activity heartbeats with type information.
   */
  public fun <T> setActivityHeartbeatListener(
    detailsClass: Class<T>,
    detailsType: Type,
    listener: (T) -> Unit
  ) {
    testEnvironment.setActivityHeartbeatListener(
      detailsClass,
      detailsType,
      Functions.Proc1 { listener(it) }
    )
  }

  // ========== Cancellation Testing ==========

  /**
   * Request cancellation of the currently executing activity.
   * Cancellation is delivered on the next heartbeat.
   */
  public fun requestCancelActivity() {
    testEnvironment.requestCancelActivity()
  }

  // ========== Lifecycle ==========

  override fun close() {
    testEnvironment.close()
  }

  // ========== Internal Helpers ==========

  @Suppress("UNCHECKED_CAST")
  private fun <T> createActivityStub(
    activity: kotlin.reflect.KFunction<*>,
    options: ActivityOptions
  ): T {
    val activityClass = activity.javaMethod?.declaringClass
      ?: throw IllegalArgumentException("Cannot determine activity interface")
    return testEnvironment.newActivityStub(activityClass, options) as T
  }

  @Suppress("UNCHECKED_CAST")
  private fun <T> createLocalActivityStub(
    activity: kotlin.reflect.KFunction<*>,
    options: LocalActivityOptions
  ): T {
    val activityClass = activity.javaMethod?.declaringClass
      ?: throw IllegalArgumentException("Cannot determine activity interface")
    return testEnvironment.newLocalActivityStub(activityClass, options, emptyMap()) as T
  }

  public companion object {
    /**
     * Create a new activity test environment with default options.
     */
    public fun newInstance(): KTestActivityEnvironment {
      return KTestActivityEnvironment(TestActivityEnvironment.newInstance())
    }

    /**
     * Create a new activity test environment with DSL configuration.
     */
    public fun newInstance(
      options: KTestEnvironmentOptionsBuilder.() -> Unit
    ): KTestActivityEnvironment {
      val javaOptions = KTestEnvironmentOptionsBuilder().apply(options).build()
      return KTestActivityEnvironment(TestActivityEnvironment.newInstance(javaOptions))
    }

    /**
     * Create a new activity test environment with pre-built options.
     */
    public fun newInstance(options: KTestEnvironmentOptions): KTestActivityEnvironment {
      return KTestActivityEnvironment(
        TestActivityEnvironment.newInstance(options.javaOptions)
      )
    }
  }
}
```

### Key Design Decisions

1. **Method Reference API**: `executeActivity(MyActivity::method, options, args)`
2. **Suspend Function Support**: Separate overloads for suspend activities
3. **Local Activity Support**: `executeLocalActivity` methods
4. **Heartbeat Testing**: `setHeartbeatDetails` and `setActivityHeartbeatListener`
5. **Cancellation Testing**: `requestCancelActivity()`

---

## 7. KTestActivityExtension

**Purpose:** JUnit 5 extension for simplified activity testing.

### Implementation

```kotlin
package io.temporal.kotlin.testing

import io.temporal.kotlin.TemporalDsl
import io.temporal.kotlin.activity.SuspendActivityWrapper
import io.temporal.testing.TestActivityEnvironment
import io.temporal.testing.TestEnvironmentOptions
import org.junit.jupiter.api.extension.*
import java.lang.reflect.Constructor

/**
 * JUnit 5 extension for testing Temporal activities.
 *
 * Example:
 * ```kotlin
 * class MyActivityTest {
 *     companion object {
 *         @JvmField
 *         @RegisterExtension
 *         val testActivity = kTestActivityExtension {
 *             setActivityImplementations(MyActivitiesImpl())
 *         }
 *     }
 *
 *     @Test
 *     fun `test activity`(activityEnv: KTestActivityEnvironment) {
 *         val result = activityEnv.executeActivity(
 *             MyActivities::doSomething,
 *             KActivityOptions(startToCloseTimeout = 30.seconds),
 *             "input"
 *         )
 *         assertEquals("expected", result)
 *     }
 * }
 * ```
 */
public class KTestActivityExtension private constructor(
  private val config: ExtensionConfig
) : ParameterResolver, BeforeEachCallback, AfterEachCallback {

  private data class ExtensionConfig(
    val testEnvironmentOptions: TestEnvironmentOptions,
    val activityImplementations: Array<Any>,
    val suspendActivityImplementations: Array<Any>
  )

  override fun supportsParameter(
    parameterContext: ParameterContext,
    extensionContext: ExtensionContext
  ): Boolean {
    val parameter = parameterContext.parameter
    if (parameter.declaringExecutable is Constructor<*>) return false
    return parameter.type == KTestActivityEnvironment::class.java
  }

  override fun resolveParameter(
    parameterContext: ParameterContext,
    extensionContext: ExtensionContext
  ): Any {
    return getStore(extensionContext).get(
      TEST_ENVIRONMENT_KEY,
      KTestActivityEnvironment::class.java
    ) ?: throw IllegalStateException("Activity environment not initialized")
  }

  override fun beforeEach(context: ExtensionContext) {
    val javaEnv = TestActivityEnvironment.newInstance(config.testEnvironmentOptions)

    // Register regular activities
    javaEnv.registerActivitiesImplementations(*config.activityImplementations)

    // Register suspend activities
    config.suspendActivityImplementations.forEach { activity ->
      val wrapper = SuspendActivityWrapper.wrap(activity)
      javaEnv.registerActivitiesImplementations(wrapper)
    }

    val kEnv = KTestActivityEnvironment::class.java
      .getDeclaredConstructor(TestActivityEnvironment::class.java)
      .apply { isAccessible = true }
      .newInstance(javaEnv)

    getStore(context).put(TEST_ENVIRONMENT_KEY, kEnv)
  }

  override fun afterEach(context: ExtensionContext) {
    getStore(context).get(TEST_ENVIRONMENT_KEY, KTestActivityEnvironment::class.java)?.close()
  }

  private fun getStore(context: ExtensionContext): ExtensionContext.Store {
    val namespace = ExtensionContext.Namespace.create(
      KTestActivityExtension::class.java,
      context.requiredTestMethod
    )
    return context.getStore(namespace)
  }

  public companion object {
    private const val TEST_ENVIRONMENT_KEY = "testEnvironment"

    public fun newBuilder(): Builder = Builder()
  }

  @TemporalDsl
  public class Builder internal constructor() {
    private var testEnvironmentOptions: TestEnvironmentOptions =
      TestEnvironmentOptions.getDefaultInstance()
    private var activityImplementations: Array<Any> = emptyArray()
    private var suspendActivityImplementations: Array<Any> = emptyArray()

    /**
     * Configure test environment options.
     */
    public fun testEnvironmentOptions(block: KTestEnvironmentOptionsBuilder.() -> Unit) {
      testEnvironmentOptions = KTestEnvironmentOptionsBuilder().apply(block).build()
    }

    /**
     * Set activity implementations.
     */
    public fun setActivityImplementations(vararg activities: Any) {
      activityImplementations = arrayOf(*activities)
    }

    /**
     * Set suspend activity implementations.
     */
    public fun setSuspendActivityImplementations(vararg activities: Any) {
      suspendActivityImplementations = arrayOf(*activities)
    }

    public fun build(): KTestActivityExtension {
      return KTestActivityExtension(
        ExtensionConfig(
          testEnvironmentOptions = testEnvironmentOptions,
          activityImplementations = activityImplementations,
          suspendActivityImplementations = suspendActivityImplementations
        )
      )
    }
  }
}

/**
 * DSL function to create a KTestActivityExtension.
 */
public fun kTestActivityExtension(
  block: KTestActivityExtension.Builder.() -> Unit
): KTestActivityExtension {
  return KTestActivityExtension.newBuilder().apply(block).build()
}
```

---

## 8. Implementation Notes

### Dependencies

The test framework module will need the following dependencies:

```kotlin
// build.gradle.kts
dependencies {
  api(project(":temporal-kotlin"))
  api("io.temporal:temporal-testing:VERSION")

  implementation("org.junit.jupiter:junit-jupiter-api:5.10.0")
  implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")

  testImplementation("org.junit.jupiter:junit-jupiter:5.10.0")
  testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
}
```

### Module Structure

```
temporal-kotlin-testing/
├── src/main/kotlin/io/temporal/kotlin/testing/
│   ├── KTestWorkflowEnvironment.kt
│   ├── KTestWorkflowExtension.kt
│   ├── KTestActivityEnvironment.kt
│   ├── KTestActivityExtension.kt
│   ├── KTestEnvironmentOptions.kt
│   ├── KWorker.kt
│   └── WorkflowInitialTime.kt
└── src/test/kotlin/io/temporal/kotlin/testing/
    ├── KTestWorkflowEnvironmentTest.kt
    ├── KTestWorkflowExtensionTest.kt
    ├── KTestActivityEnvironmentTest.kt
    └── KTestActivityExtensionTest.kt
```

### Key Integration Points

1. **SuspendActivityWrapper**: Reuse existing implementation for suspend activity support
2. **KotlinPlugin**: Ensure Kotlin workflow support via existing plugin
3. **KWorkflowClient**: Return Kotlin client from test environment
4. **KWorkflowOptions**: Use existing options classes

### Thread Safety

- Test environments are designed for single-threaded test execution
- Each test method gets its own environment instance (via JUnit extension lifecycle)
- Suspend functions use `Dispatchers.IO` for blocking operations

---

## 9. Summary

This implementation design provides:

| Component | Purpose |
|-----------|---------|
| `KTestEnvironmentOptions` | Configuration with DSL builder |
| `KWorker` | Kotlin wrapper for Worker with suspend activity support |
| `KTestWorkflowEnvironment` | Main test environment with time skipping |
| `KTestWorkflowExtension` | JUnit 5 extension for workflow tests |
| `KTestActivityEnvironment` | Activity unit testing environment |
| `KTestActivityExtension` | JUnit 5 extension for activity tests |
| `WorkflowInitialTime` | Annotation for per-test initial time |

The design:
- Wraps Java SDK test framework for full compatibility
- Provides Kotlin-idiomatic DSL builders
- Supports suspend functions throughout
- Integrates with existing Kotlin SDK components
- Follows established Kotlin SDK patterns
