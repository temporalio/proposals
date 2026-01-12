# Open Questions

This document tracks API design questions that need discussion and decisions before implementation.

## Interfaceless Workflows and Activities

**Status:** Decision needed

### Problem Statement

Currently, workflows and activities require interface definitions with annotations, which adds boilerplate:

```kotlin
// Current approach - requires interface
@ActivityInterface
interface GreetingActivities {
    suspend fun composeGreeting(greeting: String, name: String): String
}

class GreetingActivitiesImpl : GreetingActivities {
    override suspend fun composeGreeting(greeting: String, name: String) = "$greeting, $name!"
}

@WorkflowInterface
interface GreetingWorkflow {
    @WorkflowMethod
    suspend fun getGreeting(name: String): String
}

class GreetingWorkflowImpl : GreetingWorkflow {
    override suspend fun getGreeting(name: String): String {
        // implementation
    }
}
```

### Proposal

Allow defining activities and workflows directly on implementation classes without interfaces, similar to Python SDK:

**Activities:**

```kotlin
// Proposed approach - no interface required
class GreetingActivities {
    @ActivityMethod
    suspend fun composeGreeting(greeting: String, name: String) = "$greeting, $name!"
}

// In workflow - call using method reference to impl class
val result = KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,
    KActivityOptions(startToCloseTimeout = 30.seconds),
    "Hello", "World"
)
```

**Workflows:**

```kotlin
// Proposed approach - no interface required
class GreetingWorkflow {
    @WorkflowMethod
    suspend fun getGreeting(name: String): String {
        return KWorkflow.executeActivity(
            GreetingActivities::composeGreeting,
            KActivityOptions(startToCloseTimeout = 10.seconds),
            "Hello", name
        )
    }
}

// Client call using method reference to impl class
val result = client.executeWorkflow(
    GreetingWorkflow::getGreeting,
    KWorkflowOptions(workflowId = "greeting-123", taskQueue = "greetings"),
    "World"
)
```

### Benefits

- Reduces boilerplate (no separate interface file)
- More similar to Python SDK experience
- Kotlin-only feature, no Java SDK changes required

### Trade-offs

- Different from Java SDK convention
- Activity/workflow type names derived from method/class names (convention-based)
- Respects `@ActivityMethod(name = "...")` and `@WorkflowMethod(name = "...")` annotations if present

### Related Sections

- [Activity Definition](./activities/definition.md#interfaceless-activity-definition)
- [Workflow Definition](./workflows/definition.md#interfaceless-workflow-definition)

---

## Type-Safe Activity Arguments with KArgs

**Status:** Decision needed

### Problem Statement

The current activity execution API uses varargs which are not compile-time type-safe:

```kotlin
// Current approach - vararg, no compile-time type checking
KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,
    KActivityOptions(startToCloseTimeout = 30.seconds),
    "Hello", "World"  // vararg Any? - wrong types only caught at runtime
)
```

### Proposal

Use typed argument classes (`KArgs`) to provide compile-time type safety:

**Activities:**
```kotlin
// 0 arguments - just method reference and options
KWorkflow.executeActivity(
    GreetingActivities::getDefaultGreeting,
    KActivityOptions(startToCloseTimeout = 30.seconds)
)

// 1 argument - passed directly
KWorkflow.executeActivity(
    GreetingActivities::greet,
    "World",
    KActivityOptions(startToCloseTimeout = 30.seconds)
)

// Multiple arguments - use kargs()
KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,
    kargs("Hello", "World"),
    KActivityOptions(startToCloseTimeout = 30.seconds)
)
```

**Child Workflows:**
```kotlin
// 0 arguments
KWorkflow.executeChildWorkflow(
    ChildWorkflow::run,
    KChildWorkflowOptions(workflowId = "child-1")
)

// 1 argument
KWorkflow.executeChildWorkflow(
    ChildWorkflow::process,
    order,
    KChildWorkflowOptions(workflowId = "child-1")
)

// Multiple arguments
KWorkflow.executeChildWorkflow(
    ChildWorkflow::processWithConfig,
    kargs(order, config),
    KChildWorkflowOptions(workflowId = "child-1")
)
```

**Client Workflow Execution:**
```kotlin
// 0 arguments
client.executeWorkflow(
    MyWorkflow::run,
    KWorkflowOptions(workflowId = "wf-1", taskQueue = "main")
)

// 1 argument
client.executeWorkflow(
    MyWorkflow::process,
    input,
    KWorkflowOptions(workflowId = "wf-1", taskQueue = "main")
)

// Multiple arguments
client.executeWorkflow(
    MyWorkflow::processWithConfig,
    kargs(input, config),
    KWorkflowOptions(workflowId = "wf-1", taskQueue = "main")
)
```

**KArgs classes:**
```kotlin
sealed interface KArgs

data class KArgs2<A1, A2>(val a1: A1, val a2: A2) : KArgs
data class KArgs3<A1, A2, A3>(val a1: A1, val a2: A2, val a3: A3) : KArgs
data class KArgs4<A1, A2, A3, A4>(val a1: A1, val a2: A2, val a3: A3, val a4: A4) : KArgs
data class KArgs5<A1, A2, A3, A4, A5>(val a1: A1, val a2: A2, val a3: A3, val a4: A4, val a5: A5) : KArgs
data class KArgs6<A1, A2, A3, A4, A5, A6>(val a1: A1, val a2: A2, val a3: A3, val a4: A4, val a5: A5, val a6: A6) : KArgs
data class KArgs7<A1, A2, A3, A4, A5, A6, A7>(val a1: A1, val a2: A2, val a3: A3, val a4: A4, val a5: A5, val a6: A6, val a7: A7) : KArgs

// Factory functions
fun <A1, A2> kargs(a1: A1, a2: A2) = KArgs2(a1, a2)
fun <A1, A2, A3> kargs(a1: A1, a2: A2, a3: A3) = KArgs3(a1, a2, a3)
// ... up to 7
```

**Execute overloads (activities):**
```kotlin
object KWorkflow {
    // 0 arguments
    suspend fun <T, R> executeActivity(
        activity: KFunction1<T, R>,
        options: KActivityOptions
    ): R

    // 1 argument - direct
    suspend fun <T, A, R> executeActivity(
        activity: KFunction2<T, A, R>,
        arg: A,
        options: KActivityOptions
    ): R

    // 2 arguments - KArgs2 types must match KFunction3 params
    suspend fun <T, A1, A2, R> executeActivity(
        activity: KFunction3<T, A1, A2, R>,
        args: KArgs2<A1, A2>,
        options: KActivityOptions
    ): R

    // ... up to 7
}
```

**Execute overloads (child workflows):**
```kotlin
object KWorkflow {
    // 0 arguments
    suspend fun <T, R> executeChildWorkflow(
        workflow: KFunction1<T, R>,
        options: KChildWorkflowOptions
    ): R

    // 1 argument
    suspend fun <T, A, R> executeChildWorkflow(
        workflow: KFunction2<T, A, R>,
        arg: A,
        options: KChildWorkflowOptions
    ): R

    // 2 arguments
    suspend fun <T, A1, A2, R> executeChildWorkflow(
        workflow: KFunction3<T, A1, A2, R>,
        args: KArgs2<A1, A2>,
        options: KChildWorkflowOptions
    ): R

    // ... up to 7
}
```

**Execute overloads (client):**
```kotlin
class KWorkflowClient {
    // 0 arguments
    suspend fun <T, R> executeWorkflow(
        workflow: KFunction1<T, R>,
        options: KWorkflowOptions
    ): R

    // 1 argument
    suspend fun <T, A, R> executeWorkflow(
        workflow: KFunction2<T, A, R>,
        arg: A,
        options: KWorkflowOptions
    ): R

    // 2 arguments
    suspend fun <T, A1, A2, R> executeWorkflow(
        workflow: KFunction3<T, A1, A2, R>,
        args: KArgs2<A1, A2>,
        options: KWorkflowOptions
    ): R

    // ... up to 7
}
```

**Compile-time safety examples:**
```kotlin
interface MyActivities {
    suspend fun greet(name: String): String
    suspend fun compose(greeting: String, name: String): String
}

// COMPILES - types match
KWorkflow.executeActivity(MyActivities::greet, "World", options)
KWorkflow.executeActivity(MyActivities::compose, kargs("Hello", "World"), options)

// COMPILE ERROR - wrong type
KWorkflow.executeActivity(MyActivities::greet, 123, options)
// Error: Type mismatch. Required: String, Found: Int

// COMPILE ERROR - wrong arg types in kargs
KWorkflow.executeActivity(MyActivities::compose, kargs("Hello", 123), options)
// Error: Type mismatch. Required: KArgs2<String, String>, Found: KArgs2<String, Int>

// COMPILE ERROR - wrong arity
KWorkflow.executeActivity(MyActivities::compose, kargs("Hello", "World", "Extra"), options)
// Error: Type mismatch. Required: KArgs2<String, String>, Found: KArgs3<String, String, String>
```

### Benefits

- Full compile-time type safety for activity arguments
- Errors caught at compile time, not runtime
- Natural reading order: "execute activity X with args Y using options Z"
- Works with Kotlin's type inference

### Trade-offs

- More verbose for multi-argument calls (`kargs(...)` wrapper)
- Multiple overloads needed (8 for each: 0-7 arguments)
- Different from current vararg approach

### Related Sections

- [Activity Definition](./activities/definition.md#type-safe-activity-arguments-with-kargs)
