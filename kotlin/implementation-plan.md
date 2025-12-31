# Kotlin SDK Implementation Plan

## Phase 1: Core Coroutine Infrastructure

### 1.1 Java SDK Refactoring
- Add `WorkflowImplementationFactory` interface
- Update `Worker` to support multiple factories
- Update `SyncWorkflowWorker` with composite factory
- Add `Async.await()` methods returning `Promise`
- Expose `ReplayWorkflow` and `ReplayWorkflowContext` for SPI

### 1.2 Kotlin Coroutine Runtime
- Implement `KotlinCoroutineDispatcher` (deterministic execution)
- Implement `KotlinDelay` (timer integration)
- Implement `KotlinReplayWorkflow`
- Implement `KotlinWorkflowContext`
- Implement `KotlinWorkflowImplementationFactory`

### 1.3 Core Kotlin APIs
- `KWorkflow` object with string-based activity execution
- `KWorkflowInfo` wrapper with null safety
- `KActivityHandle<R>` for async activity execution
- Duration extensions (`kotlin.time.Duration` ↔ `java.time.Duration`)
- `KWorkflow.awaitCondition()` suspend function

### 1.4 Worker Integration
- `KotlinPlugin` for enabling coroutine support
- Worker extension for registering Kotlin workflows
- Suspend function detection in registration

---

## Phase 2: Typed APIs & Full Feature Set

### 2.1 Typed Activity Stubs
- `KFunction`-based `executeActivity()` overloads
- Type extraction from method references
- Local activity support

### 2.2 Signals, Queries, Updates
- Signal handler registration with suspend support
- Query methods (including property syntax)
- Update methods with validators

### 2.3 Child Workflows
- `executeChildWorkflow()` with method references
- `startChildWorkflow()` returning handle
- `ChildWorkflowOptions` DSL

### 2.4 Client API
- `KWorkflowHandle<T>` and `KTypedWorkflowHandle<T, R>`
- `WorkflowClient` extensions for Kotlin
- `signalWithStart` and `updateWithStart`

### 2.5 Kotlin Wrappers
- `KActivity` object and `KActivityContext`
- `KActivityInfo` with null safety
- `KUpdateHandle<R>`

---

## Phase 3: Testing Framework

### 3.1 Test Environment
- Kotlin-friendly test workflow environment
- Coroutine test utilities integration

### 3.2 Mocking Support
- Activity mocking with suspend functions
- Time skipping utilities

---

## Cross-Cutting Concerns (All Phases)

- Documentation and examples
- Migration guide from Java SDK
- Integration tests
- Compatibility testing (Java ↔ Kotlin interop)
