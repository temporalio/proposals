# Phase 3.2: Mocking Support - Detailed Plan

## Overview

Implement activity mocking and time manipulation utilities for comprehensive workflow testing.

## Prerequisites

- Phase 3.1 complete (Test environment available)

## Changes

### Change 1: Implement Activity Mocking Interface

**Summary:** Create interface for mocking activity behavior

**Scope:**
- Add `KActivityMock<T>` interface
- Support mocking by activity interface type
- Support mocking by activity name (string)

**Tests:**
- Test mock interface creation
- Test type-safe mock setup

**Dependencies:** None

---

### Change 2: Implement Activity Mock Registration

**Summary:** Add mock registration to test worker

**Scope:**
- Add `Worker.registerActivityMock<T>(mock)` extension
- Add `Worker.registerActivityMock(name, handler)` for untyped
- Mocks take precedence over real implementations

**Tests:**
- Test mock registration
- Test mock precedence
- Test mixed mock and real

**Dependencies:** Change 1

---

### Change 3: Implement Mock Response Builders

**Summary:** Create DSL for configuring mock responses

**Scope:**
- Add `KActivityMock.returns(value)` for success
- Add `KActivityMock.throws(exception)` for failure
- Add `KActivityMock.answers { args -> result }` for dynamic

**Tests:**
- Test static return value
- Test exception throwing
- Test dynamic answers

**Dependencies:** Change 2

---

### Change 4: Implement Suspend Activity Mocking

**Summary:** Support mocking suspend activity functions

**Scope:**
- Add `KActivityMock.coAnswers { args -> result }` for suspend
- Support delay simulation in mocks
- Handle coroutine context in mocks

**Tests:**
- Test suspend mock
- Test mock with delay
- Test mock cancellation

**Dependencies:** Change 3

---

### Change 5: Implement Mock Verification

**Summary:** Add verification capabilities for mock calls

**Scope:**
- Add `KActivityMock.verify(times)` for call count
- Add `KActivityMock.verifyArgs(matcher)` for argument verification
- Add `KActivityMock.verifyNever()` shortcut

**Tests:**
- Test call count verification
- Test argument verification
- Test verify never called

**Dependencies:** Change 4

---

### Change 6: Implement Time Skipping

**Summary:** Add time manipulation for test environment

**Scope:**
- Add `KTestWorkflowEnvironment.skipTime(duration)` function
- Add `KTestWorkflowEnvironment.skipUntil(instant)` function
- Advance workflow timers without real delay

**Tests:**
- Test skip by duration
- Test skip to instant
- Test timer advancement

**Dependencies:** Change 5

---

### Change 7: Implement Auto Time Skipping

**Summary:** Add automatic time advancement mode

**Scope:**
- Add `KTestWorkflowEnvironment.autoTimeSkipping` property
- Automatically advance time when workflow blocked on timer
- Configurable skip increment

**Tests:**
- Test auto skip enabled
- Test skip increment configuration
- Test disable auto skip

**Dependencies:** Change 6

---

### Change 8: Implement Test Clock Access

**Summary:** Expose test clock for assertions

**Scope:**
- Add `KTestWorkflowEnvironment.currentTime` property
- Add `KTestWorkflowEnvironment.setCurrentTime(instant)` for setup
- Coordinate with workflow's `KWorkflow.currentTime()`

**Tests:**
- Test read current time
- Test set initial time
- Test time consistency in workflow

**Dependencies:** Change 7

---

### Change 9: Documentation and Examples

**Summary:** Add comprehensive testing documentation

**Scope:**
- Document activity mocking patterns
- Document time skipping strategies
- Add complete test examples
- Add troubleshooting guide

**Tests:**
- Example code compiles
- Examples pass execution

**Dependencies:** Change 8
