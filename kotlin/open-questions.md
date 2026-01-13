# Open Questions

This document tracks API design questions that need discussion and decisions before implementation.

---

## Default Parameter Values Not Allowed

**Status:** Decided

### Decision

**Default parameter values are not allowed** in workflow methods, activity methods, signal handlers, update handlers, and query handlers. This restriction is enforced at worker registration time via reflection (`KParameter.isOptional`).

```kotlin
// ✗ NOT ALLOWED - will fail at registration
@ActivityMethod
suspend fun processOrder(orderId: String, priority: Int = 0)  // Error!

// ✓ CORRECT - use a parameter object with optional fields
data class ProcessOrderParams(
    val orderId: String,
    val priority: Int? = null
)

@ActivityMethod
suspend fun processOrder(params: ProcessOrderParams)
```

### Rationale

1. **Replay Safety** - If default values change between deployments, replayed workflows behave differently, violating determinism
2. **Serialization Ambiguity** - Unclear whether the caller serializes defaults or the worker applies them
3. **Cross-Language Compatibility** - Other languages calling the activity/workflow don't know about Kotlin defaults
4. **SDK Consistency** - Python SDK explicitly disallows default parameters; Go/Java don't have them

### Validation

The SDK validates at registration time using Kotlin reflection:

```kotlin
fun validateNoDefaultParameters(function: KFunction<*>) {
    val paramsWithDefaults = function.parameters
        .filter { it.kind == KParameter.Kind.VALUE }
        .filter { it.isOptional }

    if (paramsWithDefaults.isNotEmpty()) {
        throw IllegalArgumentException(
            "Default parameter values are not allowed. " +
            "Use a parameter object with optional fields instead."
        )
    }
}
```

### Recommended Pattern

Use a single parameter object with nullable/optional fields:

```kotlin
data class OrderParams(
    val orderId: String,
    val priority: Int? = null,  // Optional via nullability
    val retryCount: Int? = null
)

@WorkflowMethod
suspend fun processOrder(params: OrderParams): OrderResult
```

This pattern:
- Allows adding new optional fields without breaking existing callers
- Makes all parameters explicit in serialization
- Works consistently across all Temporal SDKs

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

## Type-Safe Activity/Workflow Arguments

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

### Options

Three options are being considered:

---

### Option A: Keep Current Varargs (No Change)

Keep the current vararg approach:

```kotlin
KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,
    KActivityOptions(startToCloseTimeout = 30.seconds),
    "Hello", "World"  // vararg Any?
)
```

**Pros:**
- Simple API, no wrapper classes
- Familiar pattern

**Cons:**
- No compile-time type safety
- Wrong argument types/count only caught at runtime

---

### Option B: Direct Overloads (0-7 Arguments)

Provide separate overloads for each arity with direct arguments:

```kotlin
// 0 arguments
KWorkflow.executeActivity(
    GreetingActivities::getDefault,
    KActivityOptions(startToCloseTimeout = 30.seconds)
)

// 1 argument
KWorkflow.executeActivity(
    GreetingActivities::greet,
    "World",
    KActivityOptions(startToCloseTimeout = 30.seconds)
)

// 2 arguments
KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,
    "Hello", "World",
    KActivityOptions(startToCloseTimeout = 30.seconds)
)

// 3 arguments
KWorkflow.executeActivity(
    OrderActivities::process,
    orderId, customer, items,
    KActivityOptions(startToCloseTimeout = 30.seconds)
)
```

**Overloads:**
```kotlin
object KWorkflow {
    suspend fun <T, R> executeActivity(
        activity: KFunction1<T, R>,
        options: KActivityOptions
    ): R

    suspend fun <T, A, R> executeActivity(
        activity: KFunction2<T, A, R>,
        arg: A,
        options: KActivityOptions
    ): R

    suspend fun <T, A1, A2, R> executeActivity(
        activity: KFunction3<T, A1, A2, R>,
        arg1: A1, arg2: A2,
        options: KActivityOptions
    ): R

    suspend fun <T, A1, A2, A3, R> executeActivity(
        activity: KFunction4<T, A1, A2, A3, R>,
        arg1: A1, arg2: A2, arg3: A3,
        options: KActivityOptions
    ): R

    // ... up to 7 arguments
}
```

**Pros:**
- Full compile-time type safety
- Clean call syntax, no wrapper classes
- Natural reading order

**Cons:**
- Many overloads (8 per method × 3 call types = 24 overloads)
- Options always last (can't use trailing lambda syntax if options were a builder)

---

### Option C: KArgs Wrapper Classes

Use typed `KArgs` classes for multiple arguments:

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

**Pros:**
- Full compile-time type safety
- Fewer overloads than Option B (only 0, 1, and KArgs variants = 3 per method)
- Works with Kotlin's type inference

**Cons:**
- Requires `kargs(...)` wrapper for 2+ arguments
- Additional classes in the API

---

### Comparison

| Aspect | Option A (Varargs) | Option B (Direct) | Option C (KArgs) |
|--------|-------------------|-------------------|------------------|
| Type safety | Runtime only | Compile-time | Compile-time |
| Call syntax (2+ args) | `"a", "b"` | `"a", "b"` | `kargs("a", "b")` |
| Overloads per method | 1 | 8 | 3 |
| Total overloads | 3 | 24 | 9 |
| Additional classes | None | None | KArgs2-7 |

### Related Sections

- [Activity Definition](./activities/definition.md#type-safe-activity-arguments)

---

## Data Classes vs Builder+DSL for Options/Config Classes

**Status:** Decision needed

### Problem Statement

Data classes are convenient for options/config classes due to named parameters and `copy()`:

```kotlin
data class KActivityOptions(
    val startToCloseTimeout: Duration? = null,
    val scheduleToCloseTimeout: Duration? = null,
    // ...
)

val options = KActivityOptions(startToCloseTimeout = 10.minutes)
```

However, the Kotlin team doesn't recommend using data classes as part of library APIs because adding a new field (even an optional one) is always a **binary breaking change**. This happens because:

- Adding a new property requires a new constructor parameter
- Even with default values, this changes the constructor signature
- Existing compiled code calling the old constructor breaks at runtime
- The auto-generated `copy()` method has the same issue

Libraries like Jackson started with constructors with named parameters and later deprecated them in favor of a DSL/builder combo.

### Proposed Alternative: Builder + DSL Pattern

```kotlin
class KActivityOptions
private constructor(builder: Builder) {
    val startToCloseTimeout: Duration?
    val scheduleToCloseTimeout: Duration?
    // ...

    init {
        startToCloseTimeout = builder.startToCloseTimeout
        scheduleToCloseTimeout = builder.scheduleToCloseTimeout
        // ...
    }

    class Builder {
        var startToCloseTimeout: Duration? = null
        var scheduleToCloseTimeout: Duration? = null
        // ...

        fun build(): KActivityOptions {
            require(startToCloseTimeout != null || scheduleToCloseTimeout != null) {
                "At least one of startToCloseTimeout or scheduleToCloseTimeout must be specified"
            }
            return KActivityOptions(this)
        }
    }
}

inline fun KActivityOptions(init: KActivityOptions.Builder.() -> Unit): KActivityOptions {
    return KActivityOptions.Builder().apply(init).build()
}
```

This gives an ABI-safe equivalent for data class named constructor parameters:

```kotlin
val options = KActivityOptions {
    startToCloseTimeout = 10.minutes
    // ...
}
```

### Benefits of Builder+DSL

- Adding new optional properties to the `Builder` class is binary compatible
- The inline factory function provides the same ergonomic DSL syntax as data class constructors
- Validation can happen in `build()` before object construction
- `copy` can be implemented safely if needed (via a `toBuilder()` method)

### Enhanced Nested DSL Ergonomics

With the Builder+DSL pattern, extension methods can provide cleaner syntax for nested options:

```kotlin
// Without extension method - requires assignment
val options = KActivityOptions {
    startToCloseTimeout = 10.minutes
    retryOptions = KRetryOptions {
        initialInterval = 10.seconds
        backoffCoefficient = 1.5
    }
}

// With extension method - no assignment needed
val options = KActivityOptions {
    startToCloseTimeout = 10.minutes
    retryOptions {
        initialInterval = 10.seconds
        backoffCoefficient = 1.5
    }
}
```

The extension method:

```kotlin
inline fun KActivityOptions.Builder.retryOptions(init: KRetryOptions.Builder.() -> Unit) {
    this.retryOptions = KRetryOptions(init)
}
```

This provides slightly better ergonomics for nested configuration while maintaining full type safety.

### Trade-offs

- More boilerplate code to write and maintain
- Loses data class conveniences (`equals`, `hashCode`, `toString`, `componentN`)
  - Though these can be manually implemented or generated
- Slightly more complex internal implementation

### Precedent

This pattern is used by:
- kotlinx.serialization
- Ktor
- Jackson (migrated from named parameters to this pattern)
