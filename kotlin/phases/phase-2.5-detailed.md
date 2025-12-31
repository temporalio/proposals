# Phase 2.5: Kotlin Wrappers - Detailed Plan

## Overview

Implement Kotlin wrapper types for activity context and info, providing null-safe APIs and idiomatic Kotlin access patterns.

## Prerequisites

- Phase 2.4 complete (Client API available)

## Changes

### Change 1: Implement KActivityInfo

**Summary:** Create Kotlin wrapper for ActivityInfo with null safety

**Scope:**
- Add `KActivityInfo` interface in `io.temporal.kotlin.activity`
- Replace `Optional<T>` with nullable types
- Add properties: activityId, activityType, workflowId, attempt, etc.
- Add `getHeartbeatDetails(): Payloads?`

**Tests:**
- Test all property accessors
- Test nullable properties
- Test heartbeat details retrieval

**Dependencies:** None

---

### Change 2: Implement KActivityContext

**Summary:** Create Kotlin wrapper for ActivityExecutionContext

**Scope:**
- Add `KActivityContext` interface
- Add `info: KActivityInfo` property
- Add `heartbeat(details: Any?)` suspend function
- Add `doNotCompleteOnReturn()` method

**Tests:**
- Test info access
- Test heartbeat call
- Test do not complete flag

**Dependencies:** Change 1

---

### Change 3: Implement KActivity Object

**Summary:** Create KActivity object as entry point for activity APIs

**Scope:**
- Add `KActivity` object in `io.temporal.kotlin.activity`
- Add `getContext(): KActivityContext` function
- Add `getInfo(): KActivityInfo` shortcut
- Add internal context storage (thread-local or coroutine context)

**Tests:**
- Test context retrieval in activity
- Test info shortcut
- Test context not available outside activity

**Dependencies:** Change 2

---

### Change 4: Implement Suspend Activity Support

**Summary:** Support suspend functions in activity implementations

**Scope:**
- Detect suspend activity methods in registration
- Execute suspend activities with coroutine dispatcher
- Integrate with activity heartbeat

**Tests:**
- Test suspend activity execution
- Test suspend activity with I/O
- Test heartbeat from suspend activity

**Dependencies:** Change 3

---

### Change 5: Implement @KActivityImpl Annotation

**Summary:** Add annotation for parallel activity interface pattern

**Scope:**
- Add `@KActivityImpl(activities = KClass)` annotation
- Link suspend interface to non-suspend interface
- Support registration of implementations

**Tests:**
- Test annotation processing
- Test interface linking
- Test registration with annotation

**Dependencies:** Change 4

---

### Change 6: Implement Activity Registration Extensions

**Summary:** Add worker extensions for registering Kotlin activity implementations

**Scope:**
- Add `Worker.registerActivitiesImplementations()` extension
- Auto-detect suspend activities
- Support both direct and @KActivityImpl patterns

**Tests:**
- Test direct suspend activity registration
- Test @KActivityImpl registration
- Test mixed registration

**Dependencies:** Change 5

---

### Change 7: Documentation and Examples

**Summary:** Add comprehensive documentation for activity patterns

**Scope:**
- Document Option A (pure Kotlin) pattern
- Document Option B (Java interop) pattern
- Add example activity implementations
- Add migration guide section

**Tests:**
- Example code compiles
- Examples pass execution tests

**Dependencies:** Change 6
