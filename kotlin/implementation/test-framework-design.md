# Kotlin SDK Test Framework Design

## Overview

This document describes the user experience for testing Temporal workflows and activities in the Kotlin SDK. The test framework provides Kotlin-idiomatic APIs while maintaining consistency with the Java SDK where appropriate.

## Design Principles

1. **Kotlin-Idiomatic**: DSL builders, suspend functions, extension functions, null safety
2. **Coroutine-Native**: Full support for suspend functions and coroutine-based testing
3. **Minimal Boilerplate**: Sensible defaults, concise APIs
4. **Java Interoperability**: Can test Kotlin workflows calling Java activities and vice versa
5. **Familiar to Java Users**: Similar structure and concepts as Java SDK test framework

---

## Package Structure

Following the Java SDK pattern:
```
io.temporal.kotlin.testing
├── KTestWorkflowEnvironment
├── KTestWorkflowExtension
├── KTestActivityEnvironment
├── KTestActivityExtension
└── KTestEnvironmentOptions
```

---

## 1. KTestWorkflowEnvironment

The core interface for workflow testing, providing an in-memory Temporal service with automatic time skipping.

### Creating a Test Environment

```kotlin
// Simple creation with defaults
val testEnv = KTestWorkflowEnvironment.newInstance()

// With configuration DSL
val testEnv = KTestWorkflowEnvironment.newInstance {
    namespace = "test-namespace"
    initialTime = Instant.parse("2024-01-01T00:00:00Z")
    useTimeskipping = true

    workerFactoryOptions {
        // WorkerFactoryOptions configuration
    }

    workflowClientOptions {
        // WorkflowClientOptions configuration
    }

    searchAttributes {
        register("CustomKeyword", IndexedValueType.INDEXED_VALUE_TYPE_KEYWORD)
        register("CustomInt", IndexedValueType.INDEXED_VALUE_TYPE_INT)
    }
}
```

### Worker Management

```kotlin
// Create a KWorker for a task queue (returns KWorker for pure Kotlin)
val worker: KWorker = testEnv.newWorker("my-task-queue")

// With worker options DSL
val worker: KWorker = testEnv.newWorker("my-task-queue") {
    maxConcurrentActivityExecutionSize = 100
    maxConcurrentWorkflowTaskExecutionSize = 50
}

// Register workflow and activity implementations
worker.registerWorkflowImplementationTypes<MyWorkflowImpl>()
worker.registerActivitiesImplementations(MyActivitiesImpl())

// Register Kotlin suspend activities
worker.registerSuspendActivities(MySuspendActivitiesImpl())
```

### KWorker API

`KWorker` is the Kotlin-idiomatic worker for pure Kotlin implementations:

```kotlin
/**
 * Kotlin worker that provides idiomatic APIs for registering
 * Kotlin workflows and suspend activities.
 */
class KWorker {
    /** The underlying Java Worker for interop scenarios */
    val worker: Worker

    /** Register Kotlin workflow implementation types */
    inline fun <reified T : Any> registerWorkflowImplementationTypes()
    fun registerWorkflowImplementationTypes(vararg workflowClasses: KClass<*>)
    fun registerWorkflowImplementationTypes(
        options: WorkflowImplementationOptions,
        vararg workflowClasses: KClass<*>
    )

    /** Register activity implementations (both regular and suspend) */
    fun registerActivitiesImplementations(vararg activities: Any)

    /** Register suspend activity implementations */
    fun registerSuspendActivities(vararg activities: Any)

    /** Register Nexus service implementations */
    fun registerNexusServiceImplementations(vararg services: Any)
}
```

**When to use `KWorker` vs `Worker`:**
- Use `KWorker` for pure Kotlin implementations (workflows and activities)
- Use `Worker` (via `worker` property) when mixing Java and Kotlin workflows/activities

### Client Access

```kotlin
// Get the workflow client (KWorkflowClient)
val client: KWorkflowClient = testEnv.workflowClient

// Start and execute workflows
val result = client.executeWorkflow(
    MyWorkflow::execute,
    KWorkflowOptions(taskQueue = "my-task-queue"),
    "input"
)
```

### Time Manipulation

```kotlin
// Get current test time
val currentTime: Instant = testEnv.currentTime
val currentTimeMillis: Long = testEnv.currentTimeMillis

// Sleep with time skipping (suspend function)
testEnv.sleep(5.minutes)
testEnv.sleep(Duration.ofMinutes(5))  // Java Duration also supported

// Register delayed callbacks
testEnv.registerDelayedCallback(10.seconds) {
    // This executes when test time reaches 10 seconds
    println("10 seconds have passed in test time")
}
```

### Lifecycle Management

```kotlin
// Start all registered workers
testEnv.start()

// Shutdown
testEnv.shutdown()       // Graceful shutdown
testEnv.shutdownNow()    // Immediate shutdown

// Await termination (suspend function)
testEnv.awaitTermination(30.seconds)

// Check status
val isStarted: Boolean = testEnv.isStarted
val isShutdown: Boolean = testEnv.isShutdown
val isTerminated: Boolean = testEnv.isTerminated

// Auto-close with use {}
KTestWorkflowEnvironment.newInstance().use { testEnv ->
    // Test code here
    // Automatically closed when block exits
}
```

### Diagnostics

```kotlin
// Get diagnostic information (workflow histories)
val diagnostics: String = testEnv.getDiagnostics()
```

### Service Access (Advanced)

```kotlin
// Direct access to gRPC stubs
val workflowStubs: WorkflowServiceStubs = testEnv.workflowServiceStubs
val operatorStubs: OperatorServiceStubs = testEnv.operatorServiceStubs
val namespace: String = testEnv.namespace
```

---

## 2. KTestWorkflowExtension (JUnit 5)

A JUnit 5 extension that simplifies workflow testing with automatic lifecycle management and parameter injection.

### Basic Usage

```kotlin
class MyWorkflowTest {
    companion object {
        @JvmField
        @RegisterExtension
        val testWorkflow = kTestWorkflowExtension {
            registerWorkflowImplementationTypes<MyWorkflowImpl>()
            setActivityImplementations(MyActivitiesImpl())
        }
    }

    @Test
    fun `test workflow execution`(workflow: MyWorkflow) {
        val result = workflow.execute("input")
        assertEquals("expected", result)
    }

    @Test
    fun `test with environment access`(
        workflow: MyWorkflow,
        testEnv: KTestWorkflowEnvironment,
        client: KWorkflowClient
    ) {
        // Access to all test components via parameter injection
        testEnv.sleep(5.minutes)
        val result = workflow.execute("input")
        assertEquals("expected", result)
    }
}
```

### Configuration DSL

```kotlin
val testWorkflow = kTestWorkflowExtension {
    // Workflow Registration
    registerWorkflowImplementationTypes<MyWorkflowImpl>()
    registerWorkflowImplementationTypes<AnotherWorkflowImpl>()

    // With workflow implementation options
    registerWorkflowImplementationTypes<MyWorkflowImpl> {
        failWorkflowExceptionTypes = listOf(MyBusinessException::class.java)
    }

    // Activity Registration
    setActivityImplementations(MyActivitiesImpl())

    // Suspend Activity Registration
    setSuspendActivityImplementations(MySuspendActivitiesImpl())

    // Nexus Service Registration
    setNexusServiceImplementations(MyNexusServiceImpl())

    // Worker Configuration
    workerOptions {
        maxConcurrentActivityExecutionSize = 100
    }

    workerFactoryOptions {
        // WorkerFactoryOptions configuration
    }

    // Client Configuration
    workflowClientOptions {
        // WorkflowClientOptions configuration
    }

    namespace = "TestNamespace"  // Default: "UnitTest"

    // Service Selection
    useInternalService()  // Default - in-memory service
    // OR
    useExternalService()  // Uses ClientConfigProfile.load() - reads from env vars (TEMPORAL_ADDRESS, etc.)
    // OR
    useExternalService("custom-host:7233")  // Explicit address override

    // Time Configuration
    initialTime = Instant.parse("2024-01-01T00:00:00Z")
    useTimeskipping = true  // Default: true

    // Search Attributes
    searchAttributes {
        register("CustomAttr", IndexedValueType.INDEXED_VALUE_TYPE_KEYWORD)
    }

    // Defer worker startup (for mock registration)
    doNotStart = true
}
```

### Parameter Injection

The extension supports injecting the following types into test methods:

| Type | Description |
|------|-------------|
| `KTestWorkflowEnvironment` | The test environment |
| `KWorkflowClient` | The workflow client |
| `KWorkflowOptions` | Default workflow options |
| `KWorker` | The Kotlin worker instance |
| `Worker` | The Java worker instance (for mixed Java/Kotlin) |
| `<T>` (workflow interface) | A workflow stub ready to execute |

**Note:** Use `KWorker` for pure Kotlin implementations. Use `Worker` only when mixing Java and Kotlin workflows/activities in the same test.

```kotlin
@Test
fun `test with all injected parameters`(
    testEnv: KTestWorkflowEnvironment,
    client: KWorkflowClient,
    worker: KWorker,
    options: KWorkflowOptions,
    workflow: MyWorkflow  // Automatically creates stub
) {
    // All parameters automatically injected
}
```

### Initial Time Annotation

Override the initial time for specific tests:

```kotlin
@Test
@WorkflowInitialTime("2024-06-15T12:00:00Z")
fun `test with specific initial time`(workflow: MyWorkflow) {
    // Test runs with specified initial time
}
```

### Testing with Mocks

```kotlin
class MockedActivityTest {
    companion object {
        @JvmField
        @RegisterExtension
        val testWorkflow = kTestWorkflowExtension {
            registerWorkflowImplementationTypes<MyWorkflowImpl>()
            doNotStart = true  // Important: defer startup for mock registration
        }
    }

    @Test
    fun `test with mocked activities`(
        testEnv: KTestWorkflowEnvironment,
        worker: KWorker,
        workflow: MyWorkflow
    ) {
        // Create mock
        val mockActivity = mock<MyActivity> {
            on { doSomething(any()) } doReturn "mocked result"
        }

        // Register mock and start
        worker.registerActivitiesImplementations(mockActivity)
        testEnv.start()

        // Execute workflow
        val result = workflow.execute("input")
        assertEquals("mocked result", result)

        // Verify
        verify(mockActivity).doSomething(any())
    }
}
```

---

## 3. KTestActivityEnvironment

For unit testing activity implementations in isolation.

### Creating an Activity Test Environment

```kotlin
// Simple creation
val activityEnv = KTestActivityEnvironment.newInstance()

// With configuration
val activityEnv = KTestActivityEnvironment.newInstance {
    workflowClientOptions {
        // Configuration
    }
}
```

### Registering and Testing Activities

```kotlin
// Register activity implementations
activityEnv.registerActivitiesImplementations(MyActivitiesImpl())

// Register suspend activities
activityEnv.registerSuspendActivities(MySuspendActivitiesImpl())

// Execute activity using method reference (same pattern as KWorkflow.executeActivity)
val result = activityEnv.executeActivity(
    MyActivity::doSomething,
    KActivityOptions(startToCloseTimeout = 30.seconds),
    "input"
)
assertEquals("expected", result)

// With retry options
val result = activityEnv.executeActivity(
    MyActivity::processOrder,
    KActivityOptions(
        startToCloseTimeout = 30.seconds,
        retryOptions = KRetryOptions(maximumAttempts = 3)
    ),
    orderData
)
```

### Testing Local Activities

```kotlin
val result = activityEnv.executeLocalActivity(
    MyActivity::validate,
    KLocalActivityOptions(startToCloseTimeout = 10.seconds),
    input
)
assertEquals("valid", result)
```

### Heartbeat Testing

```kotlin
// Set heartbeat details for the next activity call (simulates retry with heartbeat)
activityEnv.setHeartbeatDetails("checkpoint-data")

// Listen for heartbeats during activity execution
activityEnv.setActivityHeartbeatListener<String> { details ->
    println("Activity heartbeat: $details")
}

// With complex types
activityEnv.setActivityHeartbeatListener<MyProgressData> { progress ->
    println("Progress: ${progress.percentage}%")
}
```

### Cancellation Testing

```kotlin
@Test
fun `test activity cancellation handling`() {
    val activityEnv = KTestActivityEnvironment.newInstance()
    activityEnv.registerActivitiesImplementations(MyActivitiesImpl())

    // Request cancellation during activity execution
    activityEnv.requestCancelActivity()

    assertThrows<ActivityCanceledException> {
        activityEnv.executeActivity(
            MyActivity::longRunningTask,
            KActivityOptions(startToCloseTimeout = 1.minutes)
        )
    }
}
```

### Lifecycle

```kotlin
// Auto-close with use {}
KTestActivityEnvironment.newInstance().use { activityEnv ->
    // Test code
}

// Manual close
activityEnv.close()
```

---

## 4. KTestActivityExtension (JUnit 5)

A JUnit 5 extension for simplified activity testing.

### Basic Usage

```kotlin
class MyActivityTest {
    companion object {
        @JvmField
        @RegisterExtension
        val testActivity = kTestActivityExtension {
            setActivityImplementations(MyActivitiesImpl())
        }
    }

    @Test
    fun `test activity`(activityEnv: KTestActivityEnvironment) {
        val result = activityEnv.executeActivity(
            MyActivity::doSomething,
            KActivityOptions(startToCloseTimeout = 30.seconds),
            "input"
        )
        assertEquals("expected", result)
    }

    @Test
    fun `test with heartbeat`(activityEnv: KTestActivityEnvironment) {
        activityEnv.setHeartbeatDetails("checkpoint")
        val result = activityEnv.executeActivity(
            MyActivity::resumableTask,
            KActivityOptions(
                startToCloseTimeout = 1.minutes,
                heartbeatTimeout = 10.seconds
            )
        )
        assertEquals("completed", result)
    }
}
```

### Configuration

```kotlin
val testActivity = kTestActivityExtension {
    setActivityImplementations(MyActivitiesImpl())
    setSuspendActivityImplementations(MySuspendActivitiesImpl())

    testEnvironmentOptions {
        workflowClientOptions {
            // Configuration
        }
    }
}
```

---

## 5. Testing Suspend Activities

The Kotlin SDK provides first-class support for testing suspend activities.

### Unit Testing Suspend Activities

```kotlin
class SuspendActivityTest {
    companion object {
        @JvmField
        @RegisterExtension
        val testActivity = kTestActivityExtension {
            setSuspendActivityImplementations(MySuspendActivitiesImpl())
        }
    }

    @Test
    fun `test suspend activity`(activityEnv: KTestActivityEnvironment) = runTest {
        val result = activityEnv.executeActivity(
            MySuspendActivities::fetchDataAsync,
            KActivityOptions(startToCloseTimeout = 30.seconds),
            "key"
        )
        assertEquals("value", result)
    }
}
```

### Integration Testing with Workflows

```kotlin
class WorkflowWithSuspendActivitiesTest {
    companion object {
        @JvmField
        @RegisterExtension
        val testWorkflow = kTestWorkflowExtension {
            registerWorkflowImplementationTypes<MyWorkflowImpl>()
            setSuspendActivityImplementations(MySuspendActivitiesImpl())
        }
    }

    @Test
    fun `workflow calls suspend activities`(workflow: MyWorkflow) {
        val result = workflow.processData("input")
        assertEquals("processed", result)
    }
}
```

---

## 6. Common Testing Patterns

### Pattern 1: Basic Workflow Test

```kotlin
class BasicWorkflowTest {
    companion object {
        @JvmField
        @RegisterExtension
        val testWorkflow = kTestWorkflowExtension {
            registerWorkflowImplementationTypes<GreetingWorkflowImpl>()
            setActivityImplementations(GreetingActivitiesImpl())
        }
    }

    @Test
    fun `greets user correctly`(workflow: GreetingWorkflow) {
        val result = workflow.greet("World")
        assertEquals("Hello, World!", result)
    }
}
```

### Pattern 2: Testing Signals and Queries

```kotlin
@Test
fun `handles signals correctly`(
    workflow: OrderWorkflow,
    testEnv: KTestWorkflowEnvironment,
    client: KWorkflowClient
) = runBlocking {
    // Start workflow asynchronously
    val handle = client.startWorkflow(
        OrderWorkflow::processOrder,
        KWorkflowOptions(
            taskQueue = "orders",
            workflowId = "order-workflow-1"
        ),
        "order-123"
    )

    // Let workflow start
    testEnv.sleep(1.seconds)

    // Query current state
    val status = handle.query(OrderWorkflow::getStatus)
    assertEquals("PENDING", status)

    // Send signal
    handle.signal(OrderWorkflow::approve, "manager-1")

    // Wait for completion
    val result = handle.result()
    assertEquals("COMPLETED", result)
}
```

### Pattern 3: Testing Updates

```kotlin
@Test
fun `handles updates correctly`(
    workflow: CounterWorkflow,
    testEnv: KTestWorkflowEnvironment,
    client: KWorkflowClient
) = runBlocking {
    val handle = client.startWorkflow(
        CounterWorkflow::run,
        KWorkflowOptions(
            taskQueue = "counters",
            workflowId = "counter-1"
        )
    )

    testEnv.sleep(1.seconds)

    // Execute update and get result
    val newValue = handle.executeUpdate(CounterWorkflow::increment, 5)
    assertEquals(5, newValue)

    val finalValue = handle.executeUpdate(CounterWorkflow::increment, 3)
    assertEquals(8, finalValue)
}
```

### Pattern 4: Testing Time-Dependent Workflows

```kotlin
@Test
@WorkflowInitialTime("2024-01-01T00:00:00Z")
fun `processes scheduled tasks`(
    workflow: ScheduledWorkflow,
    testEnv: KTestWorkflowEnvironment
) {
    // Start workflow that waits for specific time
    val future = async { workflow.waitUntilTime() }

    // Advance time by 1 hour (time skipping makes this instant)
    testEnv.sleep(1.hours)

    val result = future.await()
    assertEquals("executed at scheduled time", result)
}
```

### Pattern 5: Testing Retries and Failures

```kotlin
@Test
fun `retries failed activities`(
    testEnv: KTestWorkflowEnvironment,
    worker: KWorker,
    workflow: RetryWorkflow
) {
    var attempts = 0
    val mockActivity = mock<UnreliableActivity> {
        on { unreliableCall() } doAnswer {
            attempts++
            if (attempts < 3) {
                throw RuntimeException("Temporary failure")
            }
            "success"
        }
    }

    worker.registerActivitiesImplementations(mockActivity)
    testEnv.start()

    val result = workflow.executeWithRetry()

    assertEquals("success", result)
    assertEquals(3, attempts)
}
```

### Pattern 6: Testing Child Workflows

```kotlin
@Test
fun `executes child workflows`(workflow: ParentWorkflow) {
    val result = workflow.processWithChildren(listOf("a", "b", "c"))
    assertEquals(listOf("processed-a", "processed-b", "processed-c"), result)
}
```

### Pattern 7: Testing Continue-As-New

```kotlin
@Test
fun `continues as new after threshold`(
    workflow: BatchWorkflow,
    testEnv: KTestWorkflowEnvironment
) {
    // Workflow that continues-as-new every 100 items
    val result = workflow.processBatch((1..250).toList())

    assertEquals(250, result.processedCount)
    assertEquals(3, result.continuations)  // 100 + 100 + 50
}
```

### Pattern 8: Async Activity Completion

```kotlin
@Test
fun `handles async activity completion`(activityEnv: KTestActivityEnvironment) {
    activityEnv.registerActivitiesImplementations(AsyncActivityImpl())

    // Activity signals async completion
    assertThrows<ActivityRequestedAsyncCompletion> {
        activityEnv.executeActivity(
            AsyncActivity::startAsyncOperation,
            KActivityOptions(startToCloseTimeout = 1.minutes)
        )
    }
}
```

### Pattern 9: Testing with External Service

```kotlin
class ExternalServiceTest {
    companion object {
        @JvmField
        @RegisterExtension
        val testWorkflow = kTestWorkflowExtension {
            registerWorkflowImplementationTypes<MyWorkflowImpl>()
            setActivityImplementations(MyActivitiesImpl())
            // Uses ClientConfigProfile.load() which reads from:
            // - TEMPORAL_ADDRESS (service address)
            // - TEMPORAL_NAMESPACE (namespace)
            // - TEMPORAL_API_KEY (optional API key)
            // - TEMPORAL_TLS_* (TLS configuration)
            useExternalService()
        }
    }

    @Test
    fun `works with real temporal service`(workflow: MyWorkflow) {
        val result = workflow.execute("input")
        assertEquals("expected", result)
    }
}

// Alternative: explicit address override
class ExplicitAddressTest {
    companion object {
        @JvmField
        @RegisterExtension
        val testWorkflow = kTestWorkflowExtension {
            registerWorkflowImplementationTypes<MyWorkflowImpl>()
            setActivityImplementations(MyActivitiesImpl())
            useExternalService("localhost:7233")  // Explicit address
            namespace = "test-namespace"
        }
    }
}
```

### Pattern 10: Diagnostics on Failure

```kotlin
class DiagnosticTest {
    companion object {
        @JvmField
        @RegisterExtension
        val testWorkflow = kTestWorkflowExtension {
            registerWorkflowImplementationTypes<MyWorkflowImpl>()
            setActivityImplementations(MyActivitiesImpl())
        }
    }

    @Test
    fun `test with diagnostics on failure`(
        workflow: MyWorkflow,
        testEnv: KTestWorkflowEnvironment
    ) {
        try {
            workflow.execute("input")
        } catch (e: Exception) {
            // Print workflow histories for debugging
            println(testEnv.getDiagnostics())
            throw e
        }
    }
}
```

---

## 7. Builder Functions

For cases where the DSL is not preferred, traditional builders are available:

```kotlin
// Test environment
val testEnv = KTestWorkflowEnvironment.newInstance(
    KTestEnvironmentOptions.newBuilder()
        .setNamespace("test")
        .setInitialTime(Instant.now())
        .setUseTimeskipping(true)
        .build()
)

// Test extension
val testWorkflow = KTestWorkflowExtension.newBuilder()
    .registerWorkflowImplementationTypes(MyWorkflowImpl::class.java)
    .setActivityImplementations(MyActivitiesImpl())
    .build()
```

---

## 8. Integration with kotlinx-coroutines-test

The test framework integrates with `kotlinx-coroutines-test` for coroutine testing:

```kotlin
@Test
fun `test with coroutine test utilities`(
    workflow: MyWorkflow,
    testEnv: KTestWorkflowEnvironment
) = runTest {
    // Use kotlinx-coroutines-test utilities
    val result = workflow.execute("input")
    assertEquals("expected", result)
}
```

---

## 9. Summary: Java vs Kotlin Comparison

| Java SDK | Kotlin SDK | Notes |
|----------|------------|-------|
| `TestWorkflowEnvironment.newInstance()` | `KTestWorkflowEnvironment.newInstance()` | Same pattern |
| `TestWorkflowEnvironment.newInstance(options)` | `KTestWorkflowEnvironment.newInstance { }` | DSL builder |
| `TestWorkflowExtension.newBuilder()...build()` | `kTestWorkflowExtension { }` | DSL builder |
| `testEnv.newWorker()` returns `Worker` | `testEnv.newWorker()` returns `KWorker` | Kotlin wrapper |
| `Worker` | `KWorker` (with `worker` property for interop) | Kotlin-idiomatic registration |
| `testEnv.sleep(Duration)` | `testEnv.sleep(Duration)` | Suspend function, supports kotlin.time |
| `testEnv.currentTimeMillis()` | `testEnv.currentTimeMillis` / `testEnv.currentTime` | Property access + Instant |
| `TestActivityEnvironment` | `KTestActivityEnvironment` | Same pattern |
| `activityEnv.newActivityStub(T.class, options)` | `activityEnv.executeActivity(T::method, options, args)` | Handle approach (consistent with SDK) |
| `testEnv.getWorkflowClient()` | `testEnv.workflowClient` | Property access |
| N/A | `setSuspendActivityImplementations()` | Kotlin-specific |
| Builder pattern | DSL + Builder pattern | Both available |

---

## 10. External Service Configuration

When using `useExternalService()` without an explicit address, the test framework uses `ClientConfigProfile.load()` to load configuration from environment variables and config files.

### Environment Variables

| Variable | Description |
|----------|-------------|
| `TEMPORAL_ADDRESS` | Service address (e.g., `localhost:7233` or `myns.tmprl.cloud:7233`) |
| `TEMPORAL_NAMESPACE` | Namespace to use |
| `TEMPORAL_API_KEY` | API key for authentication (Temporal Cloud) |
| `TEMPORAL_TLS` | Enable TLS (`true`/`false`) |
| `TEMPORAL_TLS_CLIENT_CERT_PATH` | Path to client certificate file |
| `TEMPORAL_TLS_CLIENT_KEY_PATH` | Path to client key file |
| `TEMPORAL_TLS_SERVER_CA_CERT_PATH` | Path to CA certificate file |
| `TEMPORAL_TLS_SERVER_NAME` | Server name for TLS verification |
| `TEMPORAL_TLS_DISABLE_HOST_VERIFICATION` | Disable host verification (`true`/`false`) |
| `TEMPORAL_PROFILE` | Config file profile to use (default: `default`) |
| `TEMPORAL_GRPC_META_*` | Custom gRPC metadata (e.g., `TEMPORAL_GRPC_META_MY_HEADER=value`) |

### Example: Running Tests Against Temporal Cloud

```bash
export TEMPORAL_ADDRESS="myns.tmprl.cloud:7233"
export TEMPORAL_NAMESPACE="myns"
export TEMPORAL_API_KEY="my-api-key"

./gradlew test
```

### Example: Running Tests Against Local Server with mTLS

```bash
export TEMPORAL_ADDRESS="localhost:7233"
export TEMPORAL_NAMESPACE="default"
export TEMPORAL_TLS=true
export TEMPORAL_TLS_CLIENT_CERT_PATH="/path/to/client.pem"
export TEMPORAL_TLS_CLIENT_KEY_PATH="/path/to/client.key"
export TEMPORAL_TLS_SERVER_CA_CERT_PATH="/path/to/ca.pem"

./gradlew test
```

---

## 11. Dependencies

```kotlin
// build.gradle.kts
dependencies {
    testImplementation("io.temporal:temporal-kotlin-testing:VERSION")

    // JUnit 5
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.0")

    // Coroutine testing (optional)
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")

    // Mocking (optional)
    testImplementation("org.mockito.kotlin:mockito-kotlin:5.1.0")
}
```

---

## 12. Implementation Notes

1. **KTestWorkflowEnvironment** wraps `TestWorkflowEnvironment` and returns `KWorkflowClient`
2. **KWorker** wraps `Worker` with Kotlin-idiomatic registration APIs; exposes underlying `Worker` for interop
3. **Time functions** use `kotlin.time.Duration` with `java.time.Duration` overloads
4. **Suspend functions** for `sleep()` and `awaitTermination()`
5. **Extension functions** provide Kotlin-idiomatic APIs on Java types
6. **DSL builders** internally use Java builders for configuration
7. **Parameter injection** in extensions works via JUnit 5's `ParameterResolver`
