# Phase 1.2: Kotlin Coroutine Runtime - Detailed Plan

## Overview

Implement the core coroutine-based workflow execution runtime in the temporal-kotlin module. This provides deterministic coroutine execution that integrates with Temporal's replay mechanism.

## Prerequisites

- Phase 1.1 complete (WorkflowImplementationFactory interface available)

## Changes

### Change 1: Add Coroutines Dependency and Base Infrastructure

**Summary:** Add kotlinx-coroutines dependency and base internal classes

**Scope:**
- Add `kotlinx-coroutines-core` dependency to temporal-kotlin
- Create `io.temporal.kotlin.internal` package
- Add internal marker annotations

**Tests:**
- Verify dependency resolution
- Basic coroutine compilation test

**Dependencies:** None

---

### Change 2: Implement KotlinWorkflowContext

**Summary:** Create internal context that wraps ReplayWorkflowContext for Kotlin workflows

**Scope:**
- Add `KotlinWorkflowContext` internal class
- Wrap timer creation, activity execution, side effects
- Expose workflow info and current time

**Tests:**
- Unit tests for context method delegation
- Test timer creation
- Test activity execution delegation

**Dependencies:** Change 1

---

### Change 3: Implement KotlinCoroutineDispatcher

**Summary:** Create deterministic coroutine dispatcher for workflow execution

**Scope:**
- Add `KotlinCoroutineDispatcher` implementing `CoroutineDispatcher`
- Implement ready queue for deterministic execution
- Implement event loop processing
- Add deadlock detection

**Tests:**
- Test deterministic execution order
- Test multiple coroutines queuing
- Test deadlock detection timeout

**Dependencies:** Change 2

---

### Change 4: Implement KotlinDelay

**Summary:** Create Delay implementation that maps to Temporal timers

**Scope:**
- Add `KotlinDelay` implementing `kotlinx.coroutines.Delay`
- Map `delay()` calls to `KotlinWorkflowContext.createTimer()`
- Handle cancellation of timers

**Tests:**
- Test delay creates Temporal timer
- Test delay cancellation
- Test delay completion resumes coroutine

**Dependencies:** Change 3

---

### Change 5: Implement KotlinWorkflowDefinition

**Summary:** Create metadata class for Kotlin workflow types

**Scope:**
- Add `KotlinWorkflowDefinition` class
- Extract workflow type name from annotations
- Extract workflow method and parameter types
- Handle suspend function detection

**Tests:**
- Test workflow type extraction
- Test suspend function detection
- Test parameter type extraction

**Dependencies:** Change 4

---

### Change 6: Implement KotlinReplayWorkflow

**Summary:** Create ReplayWorkflow implementation using coroutines

**Scope:**
- Add `KotlinReplayWorkflow` implementing `ReplayWorkflow`
- Create coroutine scope with custom dispatcher
- Implement start(), eventLoop(), getOutput(), cancel(), close()
- Handle workflow completion and failure

**Tests:**
- Test workflow start and completion
- Test workflow cancellation
- Test workflow failure handling
- Test event loop execution

**Dependencies:** Change 5

---

### Change 7: Implement KotlinWorkflowImplementationFactory

**Summary:** Create WorkflowImplementationFactory for Kotlin coroutine workflows

**Scope:**
- Add `KotlinWorkflowImplementationFactory` implementing `WorkflowImplementationFactory`
- Implement `supportsType()` for suspend function detection
- Implement workflow registration and creation
- Wire up KotlinReplayWorkflow creation

**Tests:**
- Test suspend function detection
- Test workflow registration
- Test workflow instance creation
- Integration test: full workflow execution

**Dependencies:** Change 6
