# Phase 1.3: Core Kotlin APIs - Detailed Plan

## Overview

Implement the public Kotlin APIs for workflow development including the KWorkflow object, info wrappers, activity handles, and duration extensions.

## Prerequisites

- Phase 1.2 complete (Kotlin coroutine runtime available)

## Changes

### Change 1: Add Duration Extensions

**Summary:** Add extension functions for Kotlin/Java Duration conversion

**Scope:**
- Add `DurationExt.kt` in `io.temporal.kotlin` package
- Add `KotlinDuration.toJava()` extension
- Add `JavaDuration.toKotlin()` extension
- Add DSL property extensions for Options builders

**Tests:**
- Test conversions in both directions
- Test edge cases (zero, max values)
- Test DSL usage in builders

**Dependencies:** None

---

### Change 2: Implement KWorkflowInfo

**Summary:** Create Kotlin wrapper for WorkflowInfo with null safety

**Scope:**
- Add `KWorkflowInfo` interface in `io.temporal.kotlin.workflow`
- Replace `Optional<T>` with nullable types
- Add properties: workflowId, runId, parentWorkflowId?, parentRunId?, etc.
- Add internal implementation wrapping Java WorkflowInfo

**Tests:**
- Test all property accessors
- Test nullable properties with and without values
- Test memo and search attribute access

**Dependencies:** Change 1

---

### Change 3: Implement KActivityHandle

**Summary:** Create handle type for async activity execution

**Scope:**
- Add `KActivityHandle<R>` interface
- Add `await(): R` suspend function
- Add `cancel()` method
- Add `isCompleted` property
- Add internal implementation wrapping CompletableFuture

**Tests:**
- Test await completion
- Test cancellation
- Test isCompleted state transitions

**Dependencies:** Change 2

---

### Change 4: Implement KWorkflow Object - Core Methods

**Summary:** Create KWorkflow object with basic workflow utilities

**Scope:**
- Add `KWorkflow` object in `io.temporal.kotlin.workflow`
- Add `getInfo(): KWorkflowInfo`
- Add `currentTime(): Instant`
- Add `randomUUID(): UUID`
- Add `getVersion()`, `sideEffect()`, `upsertSearchAttributes()`

**Tests:**
- Test getInfo() returns correct values
- Test currentTime() during replay
- Test sideEffect determinism
- Test getVersion() marker recording

**Dependencies:** Change 3

---

### Change 5: Implement KWorkflow.executeActivity (String-based)

**Summary:** Add string-based activity execution to KWorkflow

**Scope:**
- Add `executeActivity<R>(name, options, vararg args): R` suspend function
- Add reified generic for return type extraction
- Wire to KotlinWorkflowContext.executeActivity()
- Add CompletableFuture.await() extension

**Tests:**
- Test activity execution and result
- Test activity failure propagation
- Test activity timeout
- Test generic type handling

**Dependencies:** Change 4

---

### Change 6: Implement KWorkflow.startActivity (String-based)

**Summary:** Add async activity execution returning handle

**Scope:**
- Add `startActivity<R>(name, options, vararg args): KActivityHandle<R>`
- Return handle immediately, execution in background
- Support parallel activity execution

**Tests:**
- Test handle returned immediately
- Test parallel execution with multiple handles
- Test await on handle
- Test cancellation via handle

**Dependencies:** Change 5

---

### Change 7: Implement KWorkflow.awaitCondition

**Summary:** Add awaitCondition suspend function

**Scope:**
- Add `awaitCondition(condition: () -> Boolean)` suspend function
- Add `awaitCondition(timeout: Duration, condition: () -> Boolean): Boolean`
- Wire to `Async.await()` Promise and suspend

**Tests:**
- Test condition completion when true
- Test condition with timeout - success case
- Test condition with timeout - timeout case
- Test condition re-evaluation after events

**Dependencies:** Change 6

---

### Change 8: Implement Local Activity Execution

**Summary:** Add local activity execution methods

**Scope:**
- Add `executeLocalActivity<R>(name, options, vararg args): R`
- Add `startLocalActivity<R>(name, options, vararg args): KActivityHandle<R>`
- Wire to local activity execution in context

**Tests:**
- Test local activity execution
- Test local activity options (timeout, retry)
- Test local activity failure

**Dependencies:** Change 7
