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
- ✅ Signal handler registration with suspend support
- ✅ Query methods (annotation-based and dynamic)
- ✅ Update methods with validators

---

## Phase 2: Typed APIs & Full Feature Set

### 2.1 Typed Activity Execution
- `KFunction`-based `executeActivity()` overloads
- Type extraction from method references
- Local activity support with `executeLocalActivity()`

### 2.2 Typed Child Workflow Execution
- `executeChildWorkflow()` with method references
- `startChildWorkflow()` returning `KChildWorkflowHandle<T, R>`
- `getChildWorkflowHandle()` for existing child workflows
- `KChildWorkflowHandle<T, R>` interface (signal, cancel, result)

### 2.3 Client API
- `KWorkflowClient` - Kotlin client with suspend functions and DSL constructor
- `KWorkflowHandle<T>` - typed handle for signals/queries/updates
- `KTypedWorkflowHandle<T, R>` - extends KWorkflowHandle with typed result
- `WorkflowHandle` - untyped handle (string-based operations)
- `KUpdateHandle<R>` - handle for async update execution
- `startWorkflow()`, `executeWorkflow()` suspend functions
- `signalWithStart()` and `updateWithStart()`
- `getWorkflowHandle()` and `getUntypedWorkflowHandle()`

### 2.4 Worker API
- `KWorkerFactory` - Kotlin worker factory with KotlinPlugin pre-configured
- DSL builders for worker options

### 2.5 Kotlin Activity Wrappers
- `KActivity` object (entry point for activity APIs)
- `KActivityContext` with suspend `heartbeat()`
- `KActivityInfo` with null safety

---

## Phase 3: Testing Framework & Interceptors

### 3.1 Test Environment
- Kotlin-friendly test workflow environment
- Coroutine test utilities integration

### 3.2 Mocking Support
- Activity mocking with suspend functions
- Time skipping utilities

### 3.3 Interceptors
- `KWorkerInterceptor` interface
- `KWorkflowInboundCallsInterceptor` with suspend functions
- `KWorkflowOutboundCallsInterceptor`
- `KActivityInboundCallsInterceptor`

---

## Cross-Cutting Concerns (All Phases)

- Documentation and examples
- Migration guide from Java SDK
- Integration tests
- Compatibility testing (Java ↔ Kotlin interop)
