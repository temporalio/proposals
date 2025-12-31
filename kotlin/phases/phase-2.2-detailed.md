# Phase 2.2: Signals, Queries, Updates - Detailed Plan

## Overview

Implement support for workflow signals, queries, and updates with suspend function support for signal and update handlers.

## Prerequisites

- Phase 2.1 complete (Typed activity stubs available)

## Changes

### Change 1: Implement Signal Handler Registration

**Summary:** Support @SignalMethod with suspend functions in Kotlin workflows

**Scope:**
- Extend `KotlinWorkflowDefinition` to extract signal methods
- Support both suspend and non-suspend signal handlers
- Register handlers with `ReplayWorkflowContext`

**Tests:**
- Test signal handler registration
- Test suspend signal handler
- Test non-suspend signal handler
- Test signal with arguments

**Dependencies:** None

---

### Change 2: Implement Signal Dispatch in KotlinReplayWorkflow

**Summary:** Handle incoming signals in coroutine context

**Scope:**
- Add signal dispatch to `KotlinReplayWorkflow`
- Launch signal handlers as child coroutines
- Handle signal handler exceptions

**Tests:**
- Test signal delivery to handler
- Test multiple signals queued
- Test signal handler exception handling

**Dependencies:** Change 1

---

### Change 3: Implement Query Handler Registration

**Summary:** Support @QueryMethod including property syntax

**Scope:**
- Extend `KotlinWorkflowDefinition` to extract query methods
- Support Kotlin property getters as queries
- Queries are always synchronous (never suspend)

**Tests:**
- Test query method registration
- Test query property registration
- Test query with arguments
- Test query return value

**Dependencies:** Change 2

---

### Change 4: Implement Query Dispatch

**Summary:** Handle incoming queries in workflow

**Scope:**
- Add query dispatch to `KotlinReplayWorkflow`
- Execute query synchronously (not in coroutine)
- Return serialized result

**Tests:**
- Test query execution
- Test query during workflow execution
- Test query exception handling

**Dependencies:** Change 3

---

### Change 5: Implement Update Handler Registration

**Summary:** Support @UpdateMethod with suspend functions

**Scope:**
- Extend `KotlinWorkflowDefinition` to extract update methods
- Support `@UpdateValidatorMethod` for validation
- Register handlers with context

**Tests:**
- Test update handler registration
- Test update validator registration
- Test update with arguments

**Dependencies:** Change 4

---

### Change 6: Implement Update Validation

**Summary:** Execute update validators before update handlers

**Scope:**
- Call validator synchronously before accepting update
- Validators are never suspend
- Reject update if validator throws

**Tests:**
- Test validator called before handler
- Test validator rejection
- Test validator with arguments

**Dependencies:** Change 5

---

### Change 7: Implement Update Dispatch

**Summary:** Handle incoming updates in coroutine context

**Scope:**
- Add update dispatch to `KotlinReplayWorkflow`
- Launch update handlers as coroutines
- Return update result to caller

**Tests:**
- Test update execution
- Test update result returned
- Test update exception handling
- Test concurrent updates

**Dependencies:** Change 6

---

### Change 8: Integration Tests for Signals/Queries/Updates

**Summary:** End-to-end tests for all handler types

**Scope:**
- Integration test combining signals, queries, updates
- Test interaction between handlers and main workflow
- Test state visibility in queries during updates

**Tests:**
- E2E: signal triggers workflow progress
- E2E: query returns current state
- E2E: update modifies and returns state

**Dependencies:** Change 7
