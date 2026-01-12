# Activity Definition

## String-based Activity Execution

For calling activities by name (useful for cross-language interop or dynamic activity names):

```kotlin
// Execute activity by string name - suspend function, awaits result
val result = KWorkflow.executeActivity<String>(
    "activityName",
    KActivityOptions(
        startToCloseTimeout = 30.seconds,
        retryOptions = KRetryOptions(
            initialInterval = 1.seconds,
            maximumAttempts = 3
        )
    ),
    arg1, arg2
)

// Parallel execution - use standard coroutineScope { async {} }
val results = coroutineScope {
    val d1 = async { KWorkflow.executeActivity<String>("activity1", options, arg1) }
    val d2 = async { KWorkflow.executeActivity<String>("activity2", options, arg2) }
    awaitAll(d1, d2)  // Returns List<String>
}
```

## Typed Activities

The typed activity API uses direct method references - no stub creation needed. This approach:
- Provides full compile-time type safety for arguments and return types
- Allows different options (timeouts, retry policies) per activity call
- Works with both Kotlin `suspend` and Java non-suspend activity interfaces
- Similar to TypeScript and Python SDK patterns

```kotlin
// Define activity interface
@ActivityInterface
interface GreetingActivities {
    @ActivityMethod
    suspend fun composeGreeting(greeting: String, name: String): String

    @ActivityMethod
    suspend fun sendEmail(email: Email): SendResult

    @ActivityMethod
    suspend fun log(message: String)
}

// In workflow - direct method reference, no stub needed
val greeting = KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,  // Direct reference to interface method
    KActivityOptions(startToCloseTimeout = 30.seconds),
    "Hello", "World"
)

// Different activity, different options
val result = KWorkflow.executeActivity(
    GreetingActivities::sendEmail,
    KActivityOptions(
        startToCloseTimeout = 2.minutes,
        retryOptions = KRetryOptions(maximumAttempts = 5)
    ),
    email
)

// Void activities work too
KWorkflow.executeActivity(
    GreetingActivities::log,
    KActivityOptions(startToCloseTimeout = 5.seconds),
    "Processing started"
)
```

## Type Safety

The API uses `KFunction` reflection to extract method metadata and provides compile-time type checking:

```kotlin
// Compile error! Wrong argument types
KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,
    options,
    123, true  // ✗ Type mismatch: expected String, String
)
```

## Parallel Execution

Use standard `coroutineScope { async { } }` for concurrent execution:

```kotlin
override suspend fun parallelGreetings(names: List<String>): List<String> = coroutineScope {
    names.map { name ->
        async {
            KWorkflow.executeActivity(
                GreetingActivities::composeGreeting,
                KActivityOptions(startToCloseTimeout = 10.seconds),
                "Hello", name
            )
        }
    }.awaitAll()  // Standard kotlinx.coroutines.awaitAll
}

// Multiple different activities in parallel
val (result1, result2) = coroutineScope {
    val d1 = async { KWorkflow.executeActivity(Activities::operation1, options, arg1) }
    val d2 = async { KWorkflow.executeActivity(Activities::operation2, options, arg2) }
    awaitAll(d1, d2)
}
```

> **Note:** We use standard Kotlin `async` instead of a custom `startActivity` method. The workflow's deterministic dispatcher ensures correct replay behavior.

## Java Activity Interoperability

Method references work regardless of whether the activity is defined in Kotlin or Java:

```kotlin
// Java activity interface works seamlessly
// public interface JavaPaymentActivities {
//     PaymentResult processPayment(String orderId, BigDecimal amount);
// }

val result: PaymentResult = KWorkflow.executeActivity(
    JavaPaymentActivities::processPayment,
    KActivityOptions(startToCloseTimeout = 2.minutes),
    orderId, amount
)
```

## Activity Execution API

The `KWorkflow` object provides type-safe overloads using `KFunction` types:

```kotlin
object KWorkflow {
    // 1 argument
    suspend fun <T, A1, R> executeActivity(
        activity: KFunction2<T, A1, R>,
        options: KActivityOptions,
        arg1: A1
    ): R

    // 2 arguments
    suspend fun <T, A1, A2, R> executeActivity(
        activity: KFunction3<T, A1, A2, R>,
        options: KActivityOptions,
        arg1: A1, arg2: A2
    ): R

    // ... up to 6 arguments

    // String-based overloads
    suspend inline fun <reified R> executeActivity(
        activityName: String,
        options: KActivityOptions,
        vararg args: Any?
    ): R
}
```

## Related

- [Local Activities](./local-activities.md) - Short-lived local activities
- [Workflows](../workflows/README.md) - Calling activities from workflows

---

## Open Questions (Decision Needed)

### Interfaceless Activity Definition

**Status:** Decision needed | [Full discussion](../open-questions.md#interfaceless-workflows-and-activities)

Currently, activities require interface definitions:

```kotlin
// Current approach - requires interface
@ActivityInterface
interface GreetingActivities {
    suspend fun composeGreeting(greeting: String, name: String): String
}

class GreetingActivitiesImpl : GreetingActivities {
    override suspend fun composeGreeting(greeting: String, name: String) = "$greeting, $name!"
}
```

**Proposal:** Allow defining activities directly on implementation classes without interfaces, similar to Python SDK:

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

**Benefits:**
- Reduces boilerplate (no separate interface file)
- More similar to Python SDK experience
- Kotlin-only feature, no Java SDK changes required

**Trade-offs:**
- Different from Java SDK convention
- Activity name derived from method name (convention-based, respects `@ActivityMethod(name = "...")`)

---

### Type-Safe Activity Arguments

**Status:** Decision needed | [Full discussion](../open-questions.md#type-safe-activityworkflow-arguments)

Three options for compile-time type-safe activity arguments:

**Option A:** Keep current varargs (no type safety)

**Option B:** Direct overloads (0-7 arguments each)
```kotlin
KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,
    "Hello", "World",  // Direct args - type checked
    KActivityOptions(startToCloseTimeout = 30.seconds)
)
```

**Option C:** KArgs wrapper classes
```kotlin
KWorkflow.executeActivity(
    GreetingActivities::composeGreeting,
    kargs("Hello", "World"),  // KArgs2<String, String>
    KActivityOptions(startToCloseTimeout = 30.seconds)
)
```

See [full discussion](../open-questions.md#type-safe-activityworkflow-arguments) for comparison.

---

**Next:** [Activity Implementation](./implementation.md)
