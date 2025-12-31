# Phase 1.4: Worker Integration - Detailed Plan

## Overview

Implement the worker integration layer that enables registration and execution of Kotlin coroutine workflows alongside Java workflows.

## Prerequisites

- Phase 1.3 complete (Core Kotlin APIs available)

## Changes

### Change 1: Implement KotlinPlugin Interface

**Summary:** Define plugin interface for Kotlin coroutine support

**Scope:**
- Add `KotlinPlugin` class in `io.temporal.kotlin.worker`
- Define configuration options (interceptors placeholder)
- Create factory for `KotlinWorkflowImplementationFactory`

**Tests:**
- Test plugin instantiation
- Test configuration options
- Test factory creation

**Dependencies:** None

---

### Change 2: Add Plugin Support to WorkflowClient Extensions

**Summary:** Extend WorkflowClient DSL to accept plugins

**Scope:**
- Modify `WorkflowClientExt.kt` to support plugins parameter
- Store plugin reference for worker factory access
- Pass plugin configuration through client options

**Tests:**
- Test client creation with plugin
- Test plugin accessible from client

**Dependencies:** Change 1

---

### Change 3: Implement Suspend Function Detection

**Summary:** Create utility for detecting suspend workflow methods

**Scope:**
- Add `SuspendFunctionDetector` internal utility
- Check for `kotlin.coroutines.Continuation` parameter
- Validate workflow interface annotations

**Tests:**
- Test detection of suspend functions
- Test detection of non-suspend functions
- Test mixed interface handling

**Dependencies:** Change 2

---

### Change 4: Add Worker Extension for Kotlin Workflows

**Summary:** Add extension function for registering Kotlin workflow types

**Scope:**
- Add `Worker.registerWorkflowImplementationTypes(vararg KClass<*>)` extension
- Auto-detect suspend functions and route to Kotlin factory
- Fall back to Java factory for non-suspend workflows

**Tests:**
- Test Kotlin workflow registration
- Test Java workflow registration unchanged
- Test mixed registration

**Dependencies:** Change 3

---

### Change 5: Implement Automatic Factory Registration

**Summary:** Automatically register KotlinWorkflowImplementationFactory when plugin is active

**Scope:**
- Detect KotlinPlugin in WorkerFactory
- Auto-register `KotlinWorkflowImplementationFactory` with workers
- Ensure factory is registered before workflow types

**Tests:**
- Test automatic factory registration
- Test factory precedence
- Test without plugin (Java-only behavior)

**Dependencies:** Change 4

---

### Change 6: End-to-End Integration Test

**Summary:** Create comprehensive integration test for Kotlin workflow execution

**Scope:**
- Add integration test module/package
- Test full workflow: client → worker → workflow → activity → result
- Test workflow with delays, conditions, parallel activities
- Test alongside Java workflows on same worker

**Tests:**
- E2E test: simple workflow
- E2E test: workflow with timer
- E2E test: workflow with parallel activities
- E2E test: mixed Java/Kotlin worker

**Dependencies:** Change 5
