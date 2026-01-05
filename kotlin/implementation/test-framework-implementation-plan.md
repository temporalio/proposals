# Kotlin SDK Test Framework Implementation Plan

## Overview

This document outlines the implementation plan for the Kotlin SDK test framework, broken down into small, incremental commits. Each commit is designed to:

- Be as small as possible while adding testable functionality
- Make sense in isolation
- Build on previous commits without breaking them
- Have clear test scenarios

**Total commits: 26**

---

## Phase 1: Foundation (Commits 1-3)

### Commit 1: Add temporal-kotlin-testing module structure

**Description:** Set up the new Gradle module with dependencies.

**Files:**
```
temporal-kotlin-testing/
├── build.gradle.kts
└── src/
    ├── main/kotlin/io/temporal/kotlin/testing/
    │   └── .gitkeep
    └── test/kotlin/io/temporal/kotlin/testing/
        └── .gitkeep
```

**Changes:**
- Create `temporal-kotlin-testing` directory structure
- Add `build.gradle.kts` with dependencies:
  - `api(project(":temporal-kotlin"))`
  - `api("io.temporal:temporal-testing")`
  - `implementation("org.junit.jupiter:junit-jupiter-api")`
  - `implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core")`
- Add module to root `settings.gradle.kts`

**Test scenarios:**
- Module compiles successfully
- Dependencies resolve correctly

---

### Commit 2: Add WorkflowInitialTime annotation

**Description:** Add annotation for per-test initial time override.

**Files:**
```
temporal-kotlin-testing/src/main/kotlin/io/temporal/kotlin/testing/
└── WorkflowInitialTime.kt
```

**Content:**
```kotlin
@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.RUNTIME)
annotation class WorkflowInitialTime(val value: String)
```

**Test scenarios:**
- Annotation can be applied to functions
- Value is accessible via reflection
- Invalid ISO-8601 strings detected at parse time (not annotation time)

---

### Commit 3: Add KTestEnvironmentOptions with DSL builder

**Description:** Add configuration options with Kotlin DSL support.

**Files:**
```
temporal-kotlin-testing/src/main/kotlin/io/temporal/kotlin/testing/
└── KTestEnvironmentOptions.kt
```

**Content:**
- `KTestEnvironmentOptionsBuilder` class with:
  - `namespace: String` (default: "UnitTest")
  - `initialTime: Instant?`
  - `useTimeskipping: Boolean` (default: true)
  - `useExternalService: Boolean` (default: false)
  - `target: String?`
  - `metricsScope: Scope?`
  - `workerFactoryOptions {}` DSL
  - `workflowClientOptions {}` DSL
  - `workflowServiceStubsOptions {}` DSL
  - `searchAttributes {}` nested DSL with `register(name, type)`
  - `build()` method returning `TestEnvironmentOptions`
- `KTestEnvironmentOptions` class with:
  - `internal val javaOptions: TestEnvironmentOptions`
  - Companion: `newBuilder {}`, `getDefaultInstance()`

**Test scenarios:**
- Builder with defaults creates valid TestEnvironmentOptions
- Each property correctly maps to Java options
- Nested DSLs (workerFactoryOptions, searchAttributes) work correctly
- `@TemporalDsl` annotation prevents DSL leakage

---

## Phase 2: KWorker (Commits 4-6) ✅ COMPLETE

> **Note:** KWorker was initially implemented in `temporal-kotlin-testing` but has since been moved to `temporal-kotlin/src/main/kotlin/io/temporal/kotlin/worker/KWorker.kt` to make it available for production use. `KWorkerFactory.newWorker()` now returns `KWorker`.

### Commit 4: Add KWorker with workflow registration ✅

**Description:** Add Kotlin worker wrapper with workflow registration methods.

**Files:**
```
temporal-kotlin/src/main/kotlin/io/temporal/kotlin/worker/
└── KWorker.kt
```

**Content:**
```kotlin
class KWorker internal constructor(val worker: Worker) {
    inline fun <reified T : Any> registerWorkflowImplementationTypes()
    fun registerWorkflowImplementationTypes(vararg workflowClasses: KClass<*>)
    fun registerWorkflowImplementationTypes(
        options: WorkflowImplementationOptions,
        vararg workflowClasses: KClass<*>
    )
    inline fun <reified T : Any> registerWorkflowImplementationTypes(
        options: WorkflowImplementationOptions.Builder.() -> Unit
    )
}
```

**Test scenarios:**
- Reified generic registration works: `registerWorkflowImplementationTypes<MyWorkflowImpl>()`
- KClass vararg registration works
- Options DSL correctly applies WorkflowImplementationOptions
- Underlying Worker receives correct registrations

---

### Commit 5: Add KWorker activity registration methods ✅

**Description:** Add activity registration including suspend activity support.

**Files:**
- `KWorker.kt` (modify)

**Content:**
```kotlin
// Add to KWorker class:
fun registerActivitiesImplementations(vararg activities: Any)
fun registerSuspendActivities(vararg activities: Any)
```

**Test scenarios:**
- Regular activities registered and callable
- Suspend activities wrapped via `SuspendActivityWrapper`
- Mixed registration (regular + suspend) works

---

### Commit 6: Add KWorker Nexus service registration ✅

**Description:** Add Nexus service registration method.

**Files:**
- `KWorker.kt` (modify)

**Content:**
```kotlin
// Add to KWorker class:
fun registerNexusServiceImplementations(vararg services: Any)
```

**Test scenarios:**
- Nexus services registered on underlying Worker
- Services callable via Nexus operations

---

## Phase 3: KTestWorkflowEnvironment (Commits 7-12)

### Commit 7: Add KTestWorkflowEnvironment basic structure

**Description:** Add core test environment with worker creation.

**Files:**
```
temporal-kotlin-testing/src/main/kotlin/io/temporal/kotlin/testing/
└── KTestWorkflowEnvironment.kt
```

**Content:**
```kotlin
class KTestWorkflowEnvironment private constructor(
    private val testEnvironment: TestWorkflowEnvironment
) : Closeable {
    val namespace: String

    fun newWorker(taskQueue: String): KWorker
    fun newWorker(taskQueue: String, options: WorkerOptions.Builder.() -> Unit): KWorker
    fun newWorker(taskQueue: String, options: WorkerOptions): KWorker

    companion object {
        fun newInstance(): KTestWorkflowEnvironment
        fun newInstance(options: KTestEnvironmentOptionsBuilder.() -> Unit): KTestWorkflowEnvironment
        fun newInstance(options: KTestEnvironmentOptions): KTestWorkflowEnvironment
    }
}
```

**Test scenarios:**
- Environment created with defaults
- Environment created with DSL options
- Workers created with correct task queue
- Workers return KWorker instances

---

### Commit 8: Add KTestWorkflowEnvironment client access

**Description:** Add workflow client and service stub access.

**Files:**
- `KTestWorkflowEnvironment.kt` (modify)

**Content:**
```kotlin
// Add to KTestWorkflowEnvironment:
val workflowClient: KWorkflowClient  // lazy
val workflowServiceStubs: WorkflowServiceStubs
val operatorServiceStubs: OperatorServiceStubs
```

**Test scenarios:**
- `workflowClient` returns valid KWorkflowClient
- Client can create workflow stubs
- Service stubs accessible for advanced operations

---

### Commit 9: Add KTestWorkflowEnvironment time manipulation

**Description:** Add time-related properties and sleep function.

**Files:**
- `KTestWorkflowEnvironment.kt` (modify)

**Content:**
```kotlin
// Add to KTestWorkflowEnvironment:
val currentTimeMillis: Long
val currentTime: Instant

suspend fun sleep(duration: kotlin.time.Duration)
suspend fun sleep(duration: java.time.Duration)
```

**Test scenarios:**
- `currentTime` returns test environment time (not system time)
- `sleep()` advances test time without real delay
- Both Kotlin and Java Duration overloads work
- Workflow timers fire after sleep advances time

---

### Commit 10: Add KTestWorkflowEnvironment delayed callbacks

**Description:** Add delayed callback registration.

**Files:**
- `KTestWorkflowEnvironment.kt` (modify)

**Content:**
```kotlin
// Add to KTestWorkflowEnvironment:
fun registerDelayedCallback(delay: kotlin.time.Duration, callback: () -> Unit)
fun registerDelayedCallback(delay: java.time.Duration, callback: () -> Unit)
```

**Test scenarios:**
- Callback executes when test time reaches delay
- Multiple callbacks execute in correct order
- Both Duration types work

---

### Commit 11: Add KTestWorkflowEnvironment lifecycle management

**Description:** Add start, shutdown, and termination methods.

**Files:**
- `KTestWorkflowEnvironment.kt` (modify)

**Content:**
```kotlin
// Add to KTestWorkflowEnvironment:
val isStarted: Boolean
val isShutdown: Boolean
val isTerminated: Boolean

fun start()
fun shutdown()
fun shutdownNow()
suspend fun awaitTermination(timeout: kotlin.time.Duration)
suspend fun awaitTermination(timeout: java.time.Duration)
override fun close()

// Extension function:
inline fun <T> KTestWorkflowEnvironment.use(block: (KTestWorkflowEnvironment) -> T): T
```

**Test scenarios:**
- `start()` enables workflow execution
- State properties reflect correct lifecycle state
- `shutdown()` stops accepting new work
- `shutdownNow()` interrupts in-progress work
- `awaitTermination()` suspends until terminated
- `close()` combines shutdownNow + awaitTermination
- `use {}` auto-closes on block exit

---

### Commit 12: Add KTestWorkflowEnvironment advanced features

**Description:** Add search attributes, Nexus endpoints, and diagnostics.

**Files:**
- `KTestWorkflowEnvironment.kt` (modify)

**Content:**
```kotlin
// Add to KTestWorkflowEnvironment:
fun registerSearchAttribute(name: String, type: IndexedValueType): Boolean
fun createNexusEndpoint(name: String, taskQueue: String): Endpoint
fun deleteNexusEndpoint(endpoint: Endpoint)
fun getDiagnostics(): String
```

**Test scenarios:**
- Search attributes registered and queryable
- Nexus endpoints created and usable
- Nexus endpoints deleted successfully
- Diagnostics returns workflow histories

---

## Phase 4: KTestWorkflowExtension (Commits 13-18)

### Commit 13: Add KTestWorkflowExtension builder basics

**Description:** Add extension builder with workflow/activity registration.

**Files:**
```
temporal-kotlin-testing/src/main/kotlin/io/temporal/kotlin/testing/
└── KTestWorkflowExtension.kt
```

**Content:**
```kotlin
class KTestWorkflowExtension private constructor(config: ExtensionConfig) {
    private data class ExtensionConfig(...)

    class Builder {
        var namespace: String
        var initialTime: Instant?
        var useTimeskipping: Boolean
        var doNotStart: Boolean

        inline fun <reified T : Any> registerWorkflowImplementationTypes()
        inline fun <reified T : Any> registerWorkflowImplementationTypes(
            options: WorkflowImplementationOptions.Builder.() -> Unit
        )
        fun registerWorkflowImplementationTypes(vararg classes: Class<*>)
        fun setActivityImplementations(vararg activities: Any)
        fun setSuspendActivityImplementations(vararg activities: Any)
        fun setNexusServiceImplementations(vararg services: Any)
        fun build(): KTestWorkflowExtension
    }

    companion object {
        fun newBuilder(): Builder
    }
}

fun kTestWorkflowExtension(block: KTestWorkflowExtension.Builder.() -> Unit): KTestWorkflowExtension
```

**Test scenarios:**
- Builder creates extension with correct config
- DSL function `kTestWorkflowExtension {}` works
- Workflow types stored correctly
- Activity implementations stored correctly

---

### Commit 14: Add KTestWorkflowExtension service configuration

**Description:** Add worker, client, and service configuration DSLs.

**Files:**
- `KTestWorkflowExtension.kt` (modify)

**Content:**
```kotlin
// Add to Builder:
fun workerOptions(block: WorkerOptions.Builder.() -> Unit)
fun workerFactoryOptions(block: WorkerFactoryOptions.Builder.() -> Unit)
fun workflowClientOptions(block: WorkflowClientOptions.Builder.() -> Unit)
fun useInternalService()
fun useExternalService()
fun useExternalService(address: String)
fun searchAttributes(block: SearchAttributesBuilder.() -> Unit)
```

**Test scenarios:**
- Worker options flow through to worker creation
- Factory options configure WorkerFactory
- Client options configure WorkflowClient
- `useExternalService()` connects to real Temporal
- Search attributes registered on test server

---

### Commit 15: Add KTestWorkflowExtension lifecycle callbacks

**Description:** Implement JUnit 5 BeforeEach/AfterEach callbacks.

**Files:**
- `KTestWorkflowExtension.kt` (modify)

**Content:**
```kotlin
// Implement interfaces:
class KTestWorkflowExtension : BeforeEachCallback, AfterEachCallback {
    override fun beforeEach(context: ExtensionContext) {
        // Create test environment
        // Create worker with unique task queue
        // Register workflows and activities
        // Start if not doNotStart
        // Store in ExtensionContext.Store
    }

    override fun afterEach(context: ExtensionContext) {
        // Close test environment
    }
}
```

**Test scenarios:**
- Each test gets isolated environment
- Workers registered before test runs
- Environment closed after test completes
- Test isolation verified (no cross-test contamination)

---

### Commit 16: Add KTestWorkflowExtension basic parameter injection

**Description:** Implement ParameterResolver for core types.

**Files:**
- `KTestWorkflowExtension.kt` (modify)

**Content:**
```kotlin
// Implement ParameterResolver:
class KTestWorkflowExtension : ParameterResolver {
    override fun supportsParameter(parameterContext, extensionContext): Boolean {
        // Support: KTestWorkflowEnvironment, KWorkflowClient,
        //          KWorkflowOptions, KWorker, Worker
    }

    override fun resolveParameter(parameterContext, extensionContext): Any {
        // Return appropriate instance from store
    }
}
```

**Test scenarios:**
- `KTestWorkflowEnvironment` injected correctly
- `KWorkflowClient` injected correctly
- `KWorkflowOptions` injected with correct task queue
- `KWorker` injected correctly
- `Worker` (Java) injected correctly

---

### Commit 17: Add KTestWorkflowExtension workflow stub injection

**Description:** Add workflow interface stub injection.

**Files:**
- `KTestWorkflowExtension.kt` (modify)

**Content:**
```kotlin
// Enhance parameter resolution:
private val supportedParameterTypes: MutableSet<Class<*>>

// In constructor: populate from registered workflow types
// In supportsParameter: check workflow interfaces
// In resolveParameter: create workflow stub
```

**Test scenarios:**
- Workflow interface parameters injected as stubs
- Stubs have correct task queue
- Stubs can execute workflows
- Dynamic workflow support works

---

### Commit 18: Add KTestWorkflowExtension annotations and diagnostics

**Description:** Add WorkflowInitialTime support and test failure diagnostics.

**Files:**
- `KTestWorkflowExtension.kt` (modify)

**Content:**
```kotlin
// Implement TestWatcher:
class KTestWorkflowExtension : TestWatcher {
    override fun testFailed(context: ExtensionContext, cause: Throwable) {
        // Print diagnostics to stderr
    }
}

// In beforeEach:
// Check for @WorkflowInitialTime annotation
// Override initial time if present
```

**Test scenarios:**
- `@WorkflowInitialTime` overrides initial time for specific test
- Test failure prints workflow histories to stderr
- Diagnostics help debug failing tests

---

## Phase 5: KTestActivityEnvironment (Commits 19-24)

### Commit 19: Add KTestActivityEnvironment basic structure

**Description:** Add core activity test environment with registration.

**Files:**
```
temporal-kotlin-testing/src/main/kotlin/io/temporal/kotlin/testing/
└── KTestActivityEnvironment.kt
```

**Content:**
```kotlin
class KTestActivityEnvironment private constructor(
    private val testEnvironment: TestActivityEnvironment
) : Closeable {
    fun registerActivitiesImplementations(vararg activities: Any)
    fun registerSuspendActivities(vararg activities: Any)
    override fun close()

    companion object {
        fun newInstance(): KTestActivityEnvironment
        fun newInstance(options: KTestEnvironmentOptionsBuilder.() -> Unit): KTestActivityEnvironment
        fun newInstance(options: KTestEnvironmentOptions): KTestActivityEnvironment
    }
}
```

**Test scenarios:**
- Environment created with defaults
- Activities registered successfully
- Suspend activities wrapped and registered
- Environment closes cleanly

---

### Commit 20: Add KTestActivityEnvironment executeActivity (0-2 args)

**Description:** Add activity execution via method references.

**Files:**
- `KTestActivityEnvironment.kt` (modify)

**Content:**
```kotlin
// Add to KTestActivityEnvironment:
private fun <T> createActivityStub(activity: KFunction<*>, options: ActivityOptions): T

fun <T, R> executeActivity(activity: KFunction1<T, R>, options: KActivityOptions): R
fun <T, A1, R> executeActivity(activity: KFunction2<T, A1, R>, options: KActivityOptions, arg1: A1): R
fun <T, A1, A2, R> executeActivity(activity: KFunction3<T, A1, A2, R>, options: KActivityOptions, arg1: A1, arg2: A2): R
```

**Test scenarios:**
- Activity with no args executes correctly
- Activity with 1 arg executes correctly
- Activity with 2 args executes correctly
- Method reference extracts correct interface

---

### Commit 21: Add KTestActivityEnvironment executeActivity (3+ args)

**Description:** Add activity execution for higher arities.

**Files:**
- `KTestActivityEnvironment.kt` (modify)

**Content:**
```kotlin
// Add to KTestActivityEnvironment:
fun <T, A1, A2, A3, R> executeActivity(
    activity: KFunction4<T, A1, A2, A3, R>,
    options: KActivityOptions,
    arg1: A1, arg2: A2, arg3: A3
): R

// Additional arities as needed (4, 5, 6 args)
```

**Test scenarios:**
- Activity with 3 args executes correctly
- Activity with 4+ args executes correctly

---

### Commit 22: Add KTestActivityEnvironment suspend activity support

**Description:** Add suspend function overloads for activity execution.

**Files:**
- `KTestActivityEnvironment.kt` (modify)

**Content:**
```kotlin
// Add suspend overloads:
@JvmName("executeSuspendActivity0")
suspend fun <T, R> executeActivity(activity: KSuspendFunction1<T, R>, options: KActivityOptions): R

@JvmName("executeSuspendActivity1")
suspend fun <T, A1, R> executeActivity(activity: KSuspendFunction2<T, A1, R>, options: KActivityOptions, arg1: A1): R

// Continue for 2, 3+ args
```

**Test scenarios:**
- Suspend activity with no args executes
- Suspend activity with args executes
- Coroutine context preserved correctly

---

### Commit 23: Add KTestActivityEnvironment local activity support

**Description:** Add local activity execution methods.

**Files:**
- `KTestActivityEnvironment.kt` (modify)

**Content:**
```kotlin
// Add to KTestActivityEnvironment:
private fun <T> createLocalActivityStub(activity: KFunction<*>, options: LocalActivityOptions): T

fun <T, R> executeLocalActivity(activity: KFunction1<T, R>, options: KLocalActivityOptions): R
fun <T, A1, R> executeLocalActivity(activity: KFunction2<T, A1, R>, options: KLocalActivityOptions, arg1: A1): R
fun <T, A1, A2, R> executeLocalActivity(activity: KFunction3<T, A1, A2, R>, options: KLocalActivityOptions, arg1: A1, arg2: A2): R
fun <T, A1, A2, A3, R> executeLocalActivity(activity: KFunction4<T, A1, A2, A3, R>, options: KLocalActivityOptions, arg1: A1, arg2: A2, arg3: A3): R
```

**Test scenarios:**
- Local activity executes with correct options
- Local activity timeout behavior works
- Local activity retry behavior works

---

### Commit 24: Add KTestActivityEnvironment heartbeat and cancellation

**Description:** Add heartbeat testing and cancellation support.

**Files:**
- `KTestActivityEnvironment.kt` (modify)

**Content:**
```kotlin
// Add to KTestActivityEnvironment:
fun <T> setHeartbeatDetails(details: T)

inline fun <reified T> setActivityHeartbeatListener(noinline listener: (T) -> Unit)
fun <T> setActivityHeartbeatListener(detailsClass: Class<T>, detailsType: Type, listener: (T) -> Unit)

fun requestCancelActivity()
```

**Test scenarios:**
- `setHeartbeatDetails` provides checkpoint to activity
- Heartbeat listener receives heartbeat calls
- `requestCancelActivity` triggers cancellation on next heartbeat
- `ActivityCanceledException` thrown after cancellation

---

## Phase 6: KTestActivityExtension (Commits 25-26)

### Commit 25: Add KTestActivityExtension builder

**Description:** Add extension builder with DSL.

**Files:**
```
temporal-kotlin-testing/src/main/kotlin/io/temporal/kotlin/testing/
└── KTestActivityExtension.kt
```

**Content:**
```kotlin
class KTestActivityExtension private constructor(config: ExtensionConfig) {
    private data class ExtensionConfig(
        val testEnvironmentOptions: TestEnvironmentOptions,
        val activityImplementations: Array<Any>,
        val suspendActivityImplementations: Array<Any>
    )

    class Builder {
        fun testEnvironmentOptions(block: KTestEnvironmentOptionsBuilder.() -> Unit)
        fun setActivityImplementations(vararg activities: Any)
        fun setSuspendActivityImplementations(vararg activities: Any)
        fun build(): KTestActivityExtension
    }

    companion object {
        fun newBuilder(): Builder
    }
}

fun kTestActivityExtension(block: KTestActivityExtension.Builder.() -> Unit): KTestActivityExtension
```

**Test scenarios:**
- Builder creates extension with correct config
- DSL function works
- Activity implementations stored correctly

---

### Commit 26: Add KTestActivityExtension lifecycle and injection

**Description:** Implement JUnit 5 callbacks and parameter injection.

**Files:**
- `KTestActivityExtension.kt` (modify)

**Content:**
```kotlin
class KTestActivityExtension : ParameterResolver, BeforeEachCallback, AfterEachCallback {
    override fun supportsParameter(parameterContext, extensionContext): Boolean {
        // Support KTestActivityEnvironment
    }

    override fun resolveParameter(parameterContext, extensionContext): Any {
        // Return KTestActivityEnvironment from store
    }

    override fun beforeEach(context: ExtensionContext) {
        // Create environment
        // Register activities
        // Store in context
    }

    override fun afterEach(context: ExtensionContext) {
        // Close environment
    }
}
```

**Test scenarios:**
- `KTestActivityEnvironment` injected into test methods
- Each test gets isolated environment
- Activities callable via injected environment
- Environment closed after test

---

## Summary

| Phase | Commits | Description |
|-------|---------|-------------|
| 1. Foundation | 1-3 | Module setup, annotation, options |
| 2. KWorker | 4-6 | Worker wrapper with registrations |
| 3. KTestWorkflowEnvironment | 7-12 | Main test environment |
| 4. KTestWorkflowExtension | 13-18 | JUnit 5 workflow extension |
| 5. KTestActivityEnvironment | 19-24 | Activity test environment |
| 6. KTestActivityExtension | 25-26 | JUnit 5 activity extension |

**Total: 26 commits**

## Dependencies Graph

```
Commit 1 (module)
    └── Commit 2 (annotation)
    └── Commit 3 (options)
            └── Commits 4-6 (KWorker)
                    └── Commits 7-12 (KTestWorkflowEnvironment)
                            └── Commits 13-18 (KTestWorkflowExtension)
            └── Commits 19-24 (KTestActivityEnvironment)
                    └── Commits 25-26 (KTestActivityExtension)
```

## Testing Strategy

Each commit should include:

1. **Unit tests** for the new functionality
2. **Integration tests** where applicable (especially for environment/extension commits)
3. **Example usage** in test code demonstrating the API

Test files follow the pattern:
```
temporal-kotlin-testing/src/test/kotlin/io/temporal/kotlin/testing/
├── WorkflowInitialTimeTest.kt
├── KTestEnvironmentOptionsTest.kt
├── KWorkerTest.kt
├── KTestWorkflowEnvironmentTest.kt
├── KTestWorkflowExtensionTest.kt
├── KTestActivityEnvironmentTest.kt
└── KTestActivityExtensionTest.kt
```
