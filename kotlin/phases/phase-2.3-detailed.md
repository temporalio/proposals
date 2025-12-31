# Phase 2.3: Child Workflows - Detailed Plan

## Overview

Implement child workflow execution with both typed (method reference) and untyped (string-based) APIs.

## Prerequisites

- Phase 2.2 complete (Signals/Queries/Updates available)

## Changes

### Change 1: Add ChildWorkflowOptions DSL

**Summary:** Create Kotlin DSL builder for ChildWorkflowOptions

**Scope:**
- Add `ChildWorkflowOptions` DSL builder function
- Support Kotlin Duration for timeouts
- Include all options: workflowId, taskQueue, retryOptions, parentClosePolicy, etc.

**Tests:**
- Test DSL builds correct options
- Test Duration conversion
- Test all option properties

**Dependencies:** None

---

### Change 2: Implement KChildWorkflowHandle

**Summary:** Create handle type for child workflow execution

**Scope:**
- Add `KChildWorkflowHandle<R>` interface
- Add `await(): R` suspend function for result
- Add `signal()` methods for signaling child
- Add `workflowId` and `runId` properties

**Tests:**
- Test await completion
- Test signal delivery
- Test handle properties

**Dependencies:** Change 1

---

### Change 3: Implement KWorkflow.executeChildWorkflow (String-based)

**Summary:** Add string-based child workflow execution

**Scope:**
- Add `executeChildWorkflow<R>(workflowType, options, vararg args): R`
- Wire to `KotlinWorkflowContext.executeChildWorkflow()`
- Handle result deserialization

**Tests:**
- Test child workflow execution
- Test child workflow failure propagation
- Test child workflow cancellation

**Dependencies:** Change 2

---

### Change 4: Implement KWorkflow.startChildWorkflow (String-based)

**Summary:** Add async child workflow execution returning handle

**Scope:**
- Add `startChildWorkflow<R>(workflowType, options, vararg args): KChildWorkflowHandle<R>`
- Return handle after child workflow started
- Support parallel child workflows

**Tests:**
- Test handle returned after start
- Test parallel child workflows
- Test await on handle

**Dependencies:** Change 3

---

### Change 5: Add Workflow Metadata Extraction Utilities

**Summary:** Create utilities for extracting workflow metadata from KFunction

**Scope:**
- Add `WorkflowMetadataExtractor` internal class
- Extract workflow type from `@WorkflowMethod` or method name
- Extract return type and parameter types

**Tests:**
- Test type extraction with annotation
- Test type extraction without annotation
- Test return type handling

**Dependencies:** Change 4

---

### Change 6: Implement KWorkflow.executeChildWorkflow (Typed)

**Summary:** Add KFunction-based child workflow execution

**Scope:**
- Add `executeChildWorkflow<T, A1, R>(KFunction2<T, A1, R>, options, A1): R`
- Add overloads for KFunction1-7
- Extract metadata and delegate to string-based

**Tests:**
- Test typed child workflow execution
- Test type inference
- Test with various argument counts

**Dependencies:** Change 5

---

### Change 7: Implement KWorkflow.startChildWorkflow (Typed)

**Summary:** Add KFunction-based async child workflow execution

**Scope:**
- Add `startChildWorkflow<T, A1, R>(KFunction2<T, A1, R>, options, A1): KChildWorkflowHandle<R>`
- Add overloads for KFunction1-7
- Return typed handle

**Tests:**
- Test typed handle
- Test parallel typed child workflows
- Test signal on typed handle

**Dependencies:** Change 6

---

### Change 8: Implement Continue-As-New

**Summary:** Add continue-as-new support for Kotlin workflows

**Scope:**
- Add `KWorkflow.continueAsNew(vararg args)` function
- Add typed `KWorkflow.continueAsNew(KFunction, args)` overloads
- Throw `ContinueAsNewException` equivalent

**Tests:**
- Test continue-as-new execution
- Test with different arguments
- Test typed continue-as-new

**Dependencies:** Change 7
