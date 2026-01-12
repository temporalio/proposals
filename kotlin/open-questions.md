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
