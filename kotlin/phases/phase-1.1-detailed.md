# Phase 1.1: Java SDK Refactoring - Detailed Plan

## Overview

Refactor the Java SDK to support pluggable workflow execution models. This enables the Kotlin module to provide coroutine-based workflow execution without modifying Java SDK internals.

This phase must ensure full backwards compatibility for existing applications using Java SDK.

## Prerequisites

- None (this is the foundational phase)

## Status

- [x] Change 1: Add WorkflowImplementationFactory Interface
- [x] Change 2: Extract POJOWorkflowImplementationFactory
- [x] Change 3: Add Factory Registry to Worker
- [x] Change 4: Implement CompositeReplayWorkflowFactory
- [N/A] Change 5: ~~Expose ReplayWorkflow Interface for SPI~~ (Kotlin module accesses internal classes directly)
- [N/A] Change 6: ~~Expose ReplayWorkflowContext for SPI~~ (Kotlin module accesses internal classes directly)
- [Skip] Change 7: Add Async.await() Methods (implemented elsewhere)

## Changes

### Change 1: Add WorkflowImplementationFactory Interface ✓

**Summary:** Define the pluggable factory interface for creating workflow implementations

**Scope:**
- Add `io.temporal.internal.worker.WorkflowImplementationFactory` interface (internal package - Kotlin module accesses directly)

**Tests:**
- Compilation test for interface
- Javadoc validation

**Dependencies:** None

---

### Change 2: Extract POJOWorkflowImplementationFactory ✓

**Summary:** Refactor existing POJO workflow creation to implement the new interface

**Scope:**
- Modify `POJOWorkflowImplementationFactory` to implement `WorkflowImplementationFactory`
- Extract workflow type registration logic
- No public API changes

**Tests:**
- All existing workflow tests must pass
- Unit tests for factory method contracts

**Dependencies:** Change 1

---

### Change 3: Add Factory Registry to Worker ✓

**Summary:** Update Worker to maintain a registry of workflow implementation factories

**Scope:**
- Add `Worker.registerWorkflowImplementationFactory()` method
- Add internal factory registry
- Default factory remains `POJOWorkflowImplementationFactory`

**Tests:**
- Test registering custom factory
- Test factory ordering/priority
- Existing tests unchanged

**Dependencies:** Change 2

---

### Change 4: Implement CompositeReplayWorkflowFactory ✓

**Summary:** Create composite factory that delegates to registered factories

**Scope:**
- Add `CompositeReplayWorkflowFactory` internal class
- Modify `SyncWorkflowWorker` to use composite factory
- Consult factories in registration order

**Tests:**
- Test with multiple factories
- Test fallback to default factory
- Test workflow type routing

**Dependencies:** Change 3

---

### Change 5: ~~Expose ReplayWorkflow Interface for SPI~~ [N/A]

**Status:** Not applicable - Kotlin module accesses internal classes directly. No SPI package needed.

---

### Change 6: ~~Expose ReplayWorkflowContext for SPI~~ [N/A]

**Status:** Not applicable - Kotlin module accesses internal classes directly. No SPI package needed.

---

### Change 7: Add Async.await() Methods

**Summary:** Add Promise-returning await methods to Async class for coroutine support

**Scope:**
- Add `Async.await(Supplier<Boolean> condition): Promise<Void>`
- Add `Async.await(Duration timeout, Supplier<Boolean> condition): Promise<Boolean>`
- Integrate with existing condition tracking mechanism

**Tests:**
- Unit tests for Promise completion on condition
- Unit tests for timeout behavior
- Integration test with workflow execution

**Dependencies:** Change 6
