# Testing

The Kotlin SDK provides testing utilities that integrate with `kotlinx.coroutines.test` for testing workflows and activities.

## Test Environment

Use `KTestWorkflowEnvironment` to create an in-memory Temporal environment for fast, deterministic tests:

```kotlin
class OrderWorkflowTest {
    private lateinit var testEnv: KTestWorkflowEnvironment
    private lateinit var worker: KWorker
    private lateinit var client: KClient

    @BeforeEach
    fun setup() {
        testEnv = KTestWorkflowEnvironment.newInstance()
        worker = testEnv.newWorker("test-queue")
        client = testEnv.workflowClient
    }

    @AfterEach
    fun teardown() {
        testEnv.close()
    }

    @Test
    fun `test order workflow completes successfully`() = runTest {
        // Register workflow and mock activities
        worker.registerWorkflowImplementationTypes(OrderWorkflowImpl::class)
        worker.registerActivitiesImplementations(MockOrderActivities())
        testEnv.start()

        // Execute workflow
        val result = client.executeWorkflow(
            OrderWorkflow::processOrder,
            KWorkflowOptions(
                workflowId = "test-order-123",
                taskQueue = "test-queue"
            ),
            testOrder
        )

        assertEquals(OrderStatus.COMPLETED, result.status)
    }
}
```

## KTestWorkflowEnvironment API

```kotlin
/**
 * Kotlin test environment wrapping TestWorkflowEnvironment.
 * Provides coroutine-friendly APIs for testing workflows.
 */
class KTestWorkflowEnvironment private constructor(
    private val delegate: TestWorkflowEnvironment
) : AutoCloseable {
    companion object {
        fun newInstance(): KTestWorkflowEnvironment
        fun newInstance(options: TestEnvironmentOptions): KTestWorkflowEnvironment
        fun newInstance(options: TestEnvironmentOptions.Builder.() -> Unit): KTestWorkflowEnvironment
    }

    /** The workflow client for starting and interacting with workflows */
    val workflowClient: KClient

    /** Create a new worker for the given task queue */
    fun newWorker(taskQueue: String): KWorker
    fun newWorker(taskQueue: String, options: WorkerOptions.Builder.() -> Unit): KWorker

    /** Start the test environment (workers begin processing) */
    fun start()

    /** Shutdown the test environment */
    override fun close()

    // Time control
    /** Current test time */
    val currentTimeMillis: Long

    /** Skip time forward, triggering any timers that fire */
    suspend fun skipTime(duration: Duration)

    /** Sleep real time (for integration-style tests) */
    suspend fun sleep(duration: Duration)

    /** Register a callback for when workflow reaches a timer */
    fun registerDelayCallback(duration: Duration, callback: () -> Unit)

    // Advanced
    /** Access the underlying TestWorkflowEnvironment */
    val testEnvironment: TestWorkflowEnvironment
}
```

## Time Skipping

Test long-running workflows without waiting for real time to pass:

```kotlin
@Test
fun `test workflow with timers`() = runTest {
    worker.registerWorkflowImplementationTypes(ReminderWorkflowImpl::class)
    testEnv.start()

    // Start workflow that has a 24-hour delay
    val handle = client.startWorkflow(
        ReminderWorkflow::scheduleReminder,
        KWorkflowOptions(
            workflowId = "reminder-123",
            taskQueue = "test-queue"
        ),
        reminder
    )

    // Skip 24 hours instantly
    testEnv.skipTime(24.hours)

    // Workflow should now be complete
    val result = handle.result()
    assertTrue(result.reminderSent)
}
```

## Mocking Activities

### Simple Mock Implementation

```kotlin
class MockOrderActivities : OrderActivities {
    var chargePaymentCalled = false
    var lastOrder: Order? = null

    override suspend fun chargePayment(order: Order): PaymentResult {
        chargePaymentCalled = true
        lastOrder = order
        return PaymentResult(success = true, transactionId = "mock-tx-123")
    }

    override suspend fun shipOrder(order: Order): ShipmentResult {
        return ShipmentResult(trackingNumber = "MOCK-TRACK-123")
    }
}

@Test
fun `test payment is charged`() = runTest {
    val mockActivities = MockOrderActivities()
    worker.registerWorkflowImplementationTypes(OrderWorkflowImpl::class)
    worker.registerActivitiesImplementations(mockActivities)
    testEnv.start()

    client.executeWorkflow(
        OrderWorkflow::processOrder,
        options,
        testOrder
    )

    assertTrue(mockActivities.chargePaymentCalled)
    assertEquals(testOrder, mockActivities.lastOrder)
}
```

### Using Mocking Frameworks

```kotlin
@Test
fun `test with mockk`() = runTest {
    val mockActivities = mockk<OrderActivities>()
    coEvery { mockActivities.chargePayment(any()) } returns PaymentResult(success = true, transactionId = "tx-123")
    coEvery { mockActivities.shipOrder(any()) } returns ShipmentResult(trackingNumber = "TRACK-123")

    worker.registerWorkflowImplementationTypes(OrderWorkflowImpl::class)
    worker.registerActivitiesImplementations(mockActivities)
    testEnv.start()

    val result = client.executeWorkflow(OrderWorkflow::processOrder, options, testOrder)

    coVerify { mockActivities.chargePayment(testOrder) }
    assertTrue(result.success)
}
```

## Testing Signals and Queries

```kotlin
@Test
fun `test signal updates workflow state`() = runTest {
    worker.registerWorkflowImplementationTypes(OrderWorkflowImpl::class)
    worker.registerActivitiesImplementations(mockActivities)
    testEnv.start()

    val handle = client.startWorkflow(
        OrderWorkflow::processOrder,
        options,
        testOrder
    )

    // Query initial state
    val initialStatus = handle.query(OrderWorkflow::status)
    assertEquals(OrderStatus.PENDING, initialStatus)

    // Send signal
    handle.signal(OrderWorkflow::updatePriority, Priority.HIGH)

    // Query updated state
    val priority = handle.query(OrderWorkflow::priority)
    assertEquals(Priority.HIGH, priority)
}
```

## Testing Updates

```kotlin
@Test
fun `test update modifies order`() = runTest {
    worker.registerWorkflowImplementationTypes(OrderWorkflowImpl::class)
    worker.registerActivitiesImplementations(mockActivities)
    testEnv.start()

    val handle = client.startWorkflow(
        OrderWorkflow::processOrder,
        options,
        testOrder
    )

    // Execute update
    val added = handle.executeUpdate(OrderWorkflow::addItem, newItem)
    assertTrue(added)

    // Verify via query
    val itemCount = handle.query(OrderWorkflow::getItemCount)
    assertEquals(2, itemCount)  // Original item + new item
}
```

## Testing Cancellation

```kotlin
@Test
fun `test workflow handles cancellation gracefully`() = runTest {
    worker.registerWorkflowImplementationTypes(OrderWorkflowImpl::class)
    worker.registerActivitiesImplementations(mockActivities)
    testEnv.start()

    val handle = client.startWorkflow(
        OrderWorkflow::processOrder,
        options,
        testOrder
    )

    // Cancel the workflow
    handle.cancel()

    // Verify cleanup activities were called
    val description = handle.describe()
    assertEquals(WorkflowExecutionStatus.WORKFLOW_EXECUTION_STATUS_CANCELED, description.status)
}
```

## Testing Child Workflows

```kotlin
@Test
fun `test parent orchestrates child workflows`() = runTest {
    worker.registerWorkflowImplementationTypes(
        ParentWorkflowImpl::class,
        ChildWorkflowImpl::class
    )
    worker.registerActivitiesImplementations(mockActivities)
    testEnv.start()

    val result = client.executeWorkflow(
        ParentWorkflow::orchestrate,
        options,
        parentInput
    )

    assertEquals(3, result.childResults.size)
}
```

## Integration Testing

For tests that need a real Temporal server:

```kotlin
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class OrderWorkflowIntegrationTest {
    private lateinit var service: WorkflowServiceStubs
    private lateinit var client: KClient
    private lateinit var factory: KWorkerFactory

    @BeforeAll
    fun setup() {
        // Connect to local Temporal server
        service = WorkflowServiceStubs.newLocalServiceStubs()
        client = KClient(service)
        factory = KWorkerFactory(client)

        val worker = factory.newWorker("integration-test-queue")
        worker.registerWorkflowImplementationTypes(OrderWorkflowImpl::class)
        worker.registerActivitiesImplementations(RealOrderActivities())
        factory.start()
    }

    @AfterAll
    fun teardown() {
        factory.shutdown()
        service.shutdown()
    }

    @Test
    fun `integration test with real server`() = runBlocking {
        val result = client.executeWorkflow(
            OrderWorkflow::processOrder,
            KWorkflowOptions(
                workflowId = "integration-test-${UUID.randomUUID()}",
                taskQueue = "integration-test-queue"
            ),
            testOrder
        )

        assertTrue(result.success)
    }
}
```

## Best Practices

1. **Use `runTest`** from `kotlinx.coroutines.test` for suspend function tests
2. **Prefer unit tests** with `KTestWorkflowEnvironment` for fast feedback
3. **Use time skipping** for workflows with delays - don't wait for real time
4. **Mock activities** to isolate workflow logic and control external dependencies
5. **Test edge cases**: cancellation, timeouts, failures, retries
6. **Use unique workflow IDs** in integration tests to avoid conflicts

## Dependencies

Add the testing dependency to your project:

```kotlin
// build.gradle.kts
testImplementation("io.temporal:temporal-testing:$temporalVersion")
testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:$coroutinesVersion")
```

## Related

- [Workflow Definition](./workflows/definition.md) - Defining testable workflows
- [Activities](./activities/README.md) - Defining testable activities
- [Worker Setup](./worker/setup.md) - Production worker configuration

---

**Next:** [Migration Guide](./migration.md)
