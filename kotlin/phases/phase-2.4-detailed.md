# Phase 2.4: Client API - Detailed Plan

## Overview

Implement the Kotlin client API for starting workflows, getting handles, and interacting with running workflows.

## Prerequisites

- Phase 2.3 complete (Child workflows available)

## Changes

### Change 1: Implement WorkflowHandle (Untyped)

**Summary:** Create untyped workflow handle for string-based operations

**Scope:**
- Add `WorkflowHandle` interface in `io.temporal.kotlin.client`
- Add `result<R>()` suspend function
- Add `signal(name, vararg args)` method
- Add `query<R>(name, vararg args)` method
- Add `cancel()`, `terminate()` methods

**Tests:**
- Test result retrieval
- Test signal by name
- Test query by name
- Test cancel/terminate

**Dependencies:** None

---

### Change 2: Implement KWorkflowHandle<T> (Typed)

**Summary:** Create typed workflow handle for method reference operations

**Scope:**
- Add `KWorkflowHandle<T>` interface extending base operations
- Add `signal(KFunction, args)` overloads
- Add `query(KFunction): R` overloads
- Add `result<R>()` requiring explicit type

**Tests:**
- Test typed signal
- Test typed query
- Test property query syntax

**Dependencies:** Change 1

---

### Change 3: Implement KTypedWorkflowHandle<T, R>

**Summary:** Create handle with captured result type from startWorkflow

**Scope:**
- Add `KTypedWorkflowHandle<T, R>` extending `KWorkflowHandle<T>`
- Add `result(): R` with inferred type
- Returned by `startWorkflow` with method reference

**Tests:**
- Test result type inference
- Test no explicit type needed

**Dependencies:** Change 2

---

### Change 4: Implement KUpdateHandle<R>

**Summary:** Create handle for async update operations

**Scope:**
- Add `KUpdateHandle<R>` interface
- Add `updateId` property
- Add `result(): R` suspend function

**Tests:**
- Test update result retrieval
- Test update ID access

**Dependencies:** Change 3

---

### Change 5: Add Update Methods to KWorkflowHandle

**Summary:** Add update execution methods to workflow handles

**Scope:**
- Add `executeUpdate(KFunction, args): R` to `KWorkflowHandle`
- Add `startUpdate(KFunction, args): KUpdateHandle<R>`
- Add `getKUpdateHandle<R>(updateId)` for existing updates

**Tests:**
- Test execute update and wait
- Test start update async
- Test get existing update handle

**Dependencies:** Change 4

---

### Change 6: Implement WorkflowClient.startWorkflow

**Summary:** Add Kotlin extension for starting workflows with method references

**Scope:**
- Add `WorkflowClient.startWorkflow(KFunction, args, options): KTypedWorkflowHandle<T, R>`
- Capture result type from method reference
- Support KFunction1-7 overloads

**Tests:**
- Test workflow start
- Test handle type inference
- Test various argument counts

**Dependencies:** Change 5

---

### Change 7: Implement WorkflowClient.executeWorkflow

**Summary:** Add extension for starting and waiting for workflow result

**Scope:**
- Add `WorkflowClient.executeWorkflow(KFunction, args, options): R`
- Start workflow and immediately await result
- Support KFunction1-7 overloads

**Tests:**
- Test execute and wait
- Test result type inference
- Test failure propagation

**Dependencies:** Change 6

---

### Change 8: Implement WorkflowClient.getKWorkflowHandle

**Summary:** Add extension for getting typed handle to existing workflow

**Scope:**
- Add `WorkflowClient.getKWorkflowHandle<T>(workflowId): KWorkflowHandle<T>`
- Add optional runId parameter
- Return typed handle for signal/query operations

**Tests:**
- Test get handle by ID
- Test typed operations on handle
- Test with specific runId

**Dependencies:** Change 7

---

### Change 9: Implement signalWithStart

**Summary:** Add atomic signal-with-start operation

**Scope:**
- Add `WorkflowClient.signalWithStart(workflow, workflowArg, signal, signalArg, options): KTypedWorkflowHandle`
- Atomically start or signal existing workflow
- Return typed handle

**Tests:**
- Test start new workflow with signal
- Test signal existing workflow
- Test handle operations after

**Dependencies:** Change 8

---

### Change 10: Implement updateWithStart

**Summary:** Add atomic update-with-start operation

**Scope:**
- Add `WorkflowClient.updateWithStart(workflow, workflowArg, update, updateArg, options): Pair<KTypedWorkflowHandle, UpdateResult>`
- Atomically start or update existing workflow
- Return handle and update result

**Tests:**
- Test start new workflow with update
- Test update existing workflow
- Test both return values

**Dependencies:** Change 9
