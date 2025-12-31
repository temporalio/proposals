# Phase 2.1: Typed Activity Stubs - Detailed Plan

## Overview

Implement type-safe activity execution using Kotlin method references. This provides compile-time type checking for activity arguments and return types without requiring stub creation.

## Prerequisites

- Phase 1 complete (Core infrastructure and string-based activities working)

## Changes

### Change 1: Add KFunction Metadata Extraction Utilities

**Summary:** Create utilities for extracting activity metadata from KFunction references

**Scope:**
- Add `ActivityMetadataExtractor` internal class
- Extract activity name from `@ActivityMethod` annotation or method name
- Extract return type (handling generic types with `typeOf`)
- Extract declaring interface class

**Tests:**
- Test name extraction with annotation
- Test name extraction without annotation
- Test return type extraction (simple types)
- Test return type extraction (generic types)

**Dependencies:** None

---

### Change 2: Implement KWorkflow.executeActivity with KFunction1

**Summary:** Add typed activity execution for 0-argument activities

**Scope:**
- Add `executeActivity<T, R>(KFunction1<T, R>, options): R` overload
- Extract metadata using utilities from Change 1
- Delegate to string-based execution

**Tests:**
- Test 0-arg activity execution
- Test type inference for return type
- Test activity not found error

**Dependencies:** Change 1

---

### Change 3: Implement KWorkflow.executeActivity with KFunction2-4

**Summary:** Add typed activity execution for 1-3 argument activities

**Scope:**
- Add `executeActivity<T, A1, R>(KFunction2<T, A1, R>, options, A1): R`
- Add `executeActivity<T, A1, A2, R>(KFunction3<T, A1, A2, R>, options, A1, A2): R`
- Add `executeActivity<T, A1, A2, A3, R>(KFunction4<T, A1, A2, A3, R>, options, A1, A2, A3): R`

**Tests:**
- Test 1-arg activity with correct types
- Test 2-arg activity with correct types
- Test 3-arg activity with correct types
- Test compile-time type errors (manual verification)

**Dependencies:** Change 2

---

### Change 4: Implement KWorkflow.executeActivity with KFunction5-7

**Summary:** Add typed activity execution for 4-6 argument activities

**Scope:**
- Add overloads for KFunction5, KFunction6, KFunction7
- Follow same pattern as Change 3

**Tests:**
- Test 4-arg activity
- Test 5-arg activity
- Test 6-arg activity

**Dependencies:** Change 3

---

### Change 5: Implement KWorkflow.startActivity with KFunction Overloads

**Summary:** Add async typed activity execution returning handles

**Scope:**
- Add `startActivity<T, A1, R>(KFunction2<T, A1, R>, options, A1): KActivityHandle<R>`
- Add overloads for KFunction1-7
- Return handle for async await

**Tests:**
- Test handle returned with correct type
- Test parallel typed activities
- Test await on typed handle

**Dependencies:** Change 4

---

### Change 6: Implement Typed Local Activity Execution

**Summary:** Add KFunction-based local activity execution

**Scope:**
- Add `executeLocalActivity` overloads with KFunction1-7
- Add `startLocalActivity` overloads with KFunction1-7
- Wire to local activity execution

**Tests:**
- Test typed local activity execution
- Test local activity options respected
- Test local activity return types

**Dependencies:** Change 5

---

### Change 7: Add Java Activity Interface Support

**Summary:** Ensure typed execution works with Java-defined activity interfaces

**Scope:**
- Test and fix any issues with Java interface method references
- Handle Java Optional return types if present
- Document interop behavior

**Tests:**
- Test calling Java activity interface from Kotlin workflow
- Test Java activity with various return types
- Integration test with Java activity implementation

**Dependencies:** Change 6
