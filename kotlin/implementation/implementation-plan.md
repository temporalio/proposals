# Kotlin SDK Implementation Plan

## Phase 1: Core Coroutine Infrastructure ✅ COMPLETE

### 1.1 Java SDK Refactoring
- ✅ Add `WorkflowImplementationFactory` interface
- ✅ Update `Worker` to support multiple factories
- ✅ Update `SyncWorkflowWorker` with composite factory
- ✅ Add `Async.await()` methods returning `Promise`
- ✅ Expose `ReplayWorkflow` and `ReplayWorkflowContext` for SPI

### 1.2 Kotlin Coroutine Runtime
- ✅ Implement `KotlinCoroutineDispatcher` (deterministic execution with `Delay`)
- ✅ Implement `KotlinReplayWorkflow`
- ✅ Implement `KotlinWorkflowContext`
- ✅ Implement `KotlinWorkflowImplementationFactory`

### 1.3 Core Kotlin APIs
- ✅ `KWorkflow` object with string-based activity/child workflow execution
- ✅ `KWorkflowInfo` wrapper with null safety
- ✅ Duration extensions (`kotlin.time.Duration` ↔ `java.time.Duration`)
- ✅ `KWorkflow.awaitCondition()` suspend function
- ✅ Standard `delay()` support via `Delay` interface
- ✅ Standard `coroutineScope { async { } }` for parallel execution

### 1.4 Worker Integration
- ✅ `KotlinPlugin` for enabling coroutine support
- ✅ Worker extension for registering Kotlin workflows
- ✅ Suspend function detection in registration

### 1.5 Signals, Queries, Updates
- ✅ Signal handler registration (annotation-based and dynamic) with suspend support
- ✅ Query methods (annotation-based and dynamic)
- ✅ Update methods (annotation-based only)

---

## Phase 2: Typed APIs & Full Feature Set ✅ COMPLETE

### 2.1 Typed Activity Execution ✅
- ✅ `KFunction`-based `executeActivity()` overloads (0-6 args)
- ✅ Type extraction from method references
- ✅ Local activity support with `executeLocalActivity()`
- ✅ Suspend activity support with `registerSuspendActivities()`

### 2.2 Typed Child Workflow Execution ✅
- ✅ Typed `executeChildWorkflow()` with method references
- ✅ `startChildWorkflow()` returning `KChildWorkflowHandle<T, R>`
- ✅ `KChildWorkflowHandle<T, R>` interface (signal, cancel, result)
- ✅ Optional `KChildWorkflowOptions` (uses defaults when omitted)

### 2.3 Update Enhancements ✅
- ✅ Dynamic update handler registration (`registerUpdateHandler`, `registerDynamicUpdateHandler`)
- ✅ Update validator support (`@UpdateValidatorMethod`) - Uses Java SDK annotations
- ✅ `KEncodedValues` for dynamic handlers to access raw payloads

### 2.4 Client API ✅
- ✅ `KWorkflowClient` - Kotlin client with suspend functions and DSL constructor
- ✅ `KWorkflowHandle<T>` - typed handle for signals/queries/updates
- ✅ `KTypedWorkflowHandle<T, R>` - extends KWorkflowHandle with typed result
- ✅ `WorkflowHandle` - untyped handle (string-based operations)
- ✅ `KUpdateHandle<R>` - handle for async update execution
- ✅ `startWorkflow()`, `executeWorkflow()` suspend functions (0-6 args)
- ✅ `signalWithStart()`
- ✅ `updateWithStart()` - Atomically start workflow + send update
  - ✅ `withStartWorkflowOperation()` factory methods (0-6 workflow args, regular and suspend)
  - ✅ `startUpdateWithStart()` / `executeUpdateWithStart()` with `KUpdateWithStartOptions` (0-6 update args)
  - ✅ `KWithStartWorkflowOperation<T, R>` to capture workflow start metadata
  - ✅ `KUpdateWithStartOptions<T, R, UR>` with waitForStage and updateId options
- ✅ `getWorkflowHandle()` and `getUntypedWorkflowHandle()`

### 2.5 Worker API ✅
- ✅ `KWorkerFactory` - Kotlin worker factory with KotlinPlugin pre-configured
- ✅ `KWorker` - Kotlin worker wrapper with reified generics, KClass support, DSL options for workflow/activity/Nexus registration
- ✅ `KWorkerFactory.newWorker()` returns `KWorker` for idiomatic Kotlin usage
- ✅ DSL builders for worker options

### 2.6 Kotlin Activity API ✅
- ✅ `KActivityContext.current()` (entry point for activity APIs)
- ✅ `ctx.info`, `ctx.heartbeat()`, `ctx.lastHeartbeatDetails<T>()` methods
- ✅ MDC populated automatically with activity context for standard logging
- ✅ `KActivityInfo` with null safety
- ✅ Suspend activity support via `SuspendActivityWrapper`

### 2.7 Kotlin Workflow API ✅
- ✅ MDC populated automatically with workflow context for standard logging
- ✅ `KWorkflow.async {}` for eager parallel execution
- ✅ `KWorkflow.continueAsNew()` with `KContinueAsNewOptions`
- ✅ `KWorkflow.retry()` for workflow-level retry with exponential backoff

---

## Phase 3: Testing Framework & Interceptors ✅ COMPLETE

### 3.1 Test Environment ✅ COMPLETE
- ✅ `KTestActivityEnvironment` - typed executeActivity/executeLocalActivity, suspend activity support, heartbeat/cancellation testing
- ✅ `KTestWorkflowEnvironment` - worker creation (returns `KWorker`), client access, time manipulation, delayed callbacks, lifecycle management
- ✅ `KTestEnvironmentOptions` and `KTestEnvironmentOptionsBuilder` - DSL configuration
- ✅ `KTestActivityExtension` - JUnit 5 extension with parameter resolution and lifecycle management
- ✅ `KTestWorkflowExtension` - JUnit 5 extension with workflow stub injection, diagnostics on failure
- ✅ `@WorkflowInitialTime` annotation for test-specific initial time
- ✅ Time skipping utilities (`sleep()`, `registerDelayedCallback()`)
- ✅ Search attribute registration in test environment

### 3.2 Mocking Support ✅ COMPLETE
- ✅ `KActivityMockRegistry` - thread-safe registry for activity mocks
- ✅ `KMockDynamicActivityHandler` - dynamic activity handler routing calls to mocks
- ✅ Support for both regular and suspend activity mocks
- ✅ Integration with `KTestWorkflowExtension` for automatic mock registration

### 3.3 Interceptors ✅ COMPLETE (see [interceptors.md](../configuration/interceptors.md))
- ✅ `KWorkerInterceptor` interface with `KWorkerInterceptorBase`
- ✅ `KWorkflowInboundCallsInterceptor` with suspend functions and input/output data classes
- ✅ `KWorkflowOutboundCallsInterceptor` with full API (activities, child workflows, timers, side effects, etc.)
- ✅ `KActivityInboundCallsInterceptor` with suspend support
- ✅ Base classes for convenience (`*Base` classes)
- ✅ `RootWorkflowOutboundCallsInterceptor` - terminal outbound interceptor implementation
- ✅ `WorkflowContextElement` - ThreadContextElement for workflow context propagation to interceptors
- ✅ `KEncodedValues` for dynamic handlers to access raw payloads
- ✅ Interceptor chain integration in `KotlinReplayWorkflow`
- ✅ KWorkflow static methods routed through outbound interceptor (newRandom, randomUUID, currentTimeMillis)
- ✅ Integration test: `TracingInterceptorIntegrationTest`

---

## Cross-Cutting Concerns (All Phases)

- Documentation and examples
- Migration guide from Java SDK
- Integration tests
- Compatibility testing (Java ↔ Kotlin interop)
