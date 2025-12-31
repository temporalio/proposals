# Phase 3.1: Test Environment - Detailed Plan

## Overview

Implement a Kotlin-friendly test environment for workflow testing, integrating with kotlinx-coroutines-test utilities.

## Prerequisites

- Phase 2 complete (Full Kotlin SDK API available)

## Changes

### Change 1: Add Test Dependencies

**Summary:** Add kotlinx-coroutines-test and test infrastructure

**Scope:**
- Add `kotlinx-coroutines-test` dependency
- Add test utility package `io.temporal.kotlin.testing`
- Set up test module structure

**Tests:**
- Verify dependency resolution
- Basic compilation test

**Dependencies:** None

---

### Change 2: Implement KTestWorkflowEnvironment

**Summary:** Create Kotlin wrapper for TestWorkflowEnvironment

**Scope:**
- Add `KTestWorkflowEnvironment` class
- Wrap Java `TestWorkflowEnvironment`
- Add Kotlin DSL for configuration
- Add `client` property returning Kotlin client

**Tests:**
- Test environment creation
- Test configuration options
- Test client access

**Dependencies:** Change 1

---

### Change 3: Implement Test Worker Registration

**Summary:** Add test worker with Kotlin workflow support

**Scope:**
- Add `KTestWorkflowEnvironment.newWorker(taskQueue)` returning configured worker
- Auto-register Kotlin plugin for test workers
- Support workflow and activity registration

**Tests:**
- Test worker creation
- Test workflow registration
- Test activity registration

**Dependencies:** Change 2

---

### Change 4: Implement runWorkflowTest DSL

**Summary:** Create DSL for writing workflow tests

**Scope:**
- Add `runWorkflowTest { }` top-level function
- Auto-create environment and clean up
- Provide `environment`, `client`, `worker` in scope
- Integrate with coroutine test dispatcher

**Tests:**
- Test DSL usage
- Test auto-cleanup
- Test coroutine integration

**Dependencies:** Change 3

---

### Change 5: Implement Test Workflow Execution Helpers

**Summary:** Add helper methods for common test patterns

**Scope:**
- Add `KTestWorkflowEnvironment.executeWorkflow()` with timeout
- Add `KTestWorkflowEnvironment.startWorkflow()` returning test handle
- Add assertion helpers for workflow state

**Tests:**
- Test execute with result
- Test start and interact
- Test timeout handling

**Dependencies:** Change 4

---

### Change 6: Implement Test Activity Environment

**Summary:** Add support for testing activities in isolation

**Scope:**
- Add `KTestActivityEnvironment` class
- Support testing suspend activities
- Provide mock heartbeat recording

**Tests:**
- Test activity execution
- Test heartbeat recording
- Test activity failure

**Dependencies:** Change 5

---

### Change 7: Integration with JUnit 5

**Summary:** Add JUnit 5 extension for Kotlin workflow tests

**Scope:**
- Add `@KTemporalTest` annotation
- Add `KTemporalTestExtension` implementing JUnit extension
- Auto-inject test environment into test class

**Tests:**
- Test annotation processing
- Test environment injection
- Test lifecycle management

**Dependencies:** Change 6
