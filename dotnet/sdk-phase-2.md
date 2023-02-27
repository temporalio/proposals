# .NET SDK - Phase 2

The .NET SDK will be implemented in three loosely defined phases:

* Phase 1 - Initial project, activity worker, client, and test framework
* Phase 2 - Workflow worker and replayer
* Phase 3 - Deterministic workflow sandbox and/or static analyzer and source generation

This proposal is for phase 2. It is intentionally loosely defined and all aspects are subject to discussion/change.

## "Workflow" Class and Namespace Rename

For activities it is decided that, like Java, users can get a static reference to a
`Temporalio.Activity.ActivityContext` instance for things like heartbeating and cancellation token. This is because this
context may need to be passed around in ways that `AsyncLocal` does not propagate (same with Java `ThreadLocal`).

For workflows it is decided that, like Java, users can make static calls on a `Workflow` class to do things like
starting activities and getting info. The reason for say, getting info, is `Workflow.Info` instead of
`WorkflowContext.Current.Info` is:

* We always have access to our environment in a workflow, so there is no benefit to a context instance class over static
  calls
  * Also added benefit of no extension methods which could confuse devs on which primitives are supported
* In .NET we often see contexts as instances in workflow engines and just in general, but this doesn't work for Temporal
  because:
  * There is no benefit to mocking or abstracting the workflow context since Temporal has full control of its underlying
    representation even in tests
  * We prefer interceptors over wrapping/inheriting a context for custom behavior
  * It is so often used its presence is implied and therefore forcing every user to manually DI makes no sense
  * We do not want to support constructor-based DI which ruins `[WorkflowInit]` behavior
  * We do not want to support function-based DI which ruins typing of method references
* It matches Java more clearly
* It is less wordy

We are intentionally taking a different tack in Temporal .NET SDK over other workflow engines with static calls and no
context. However, since the `Workflow` class can't reasonably be in the `Temporalio.Workflow` namespace due to clash, we
are renaming two namespaces:

* `Temporalio.Activity` renamed to `Temporalio.Activities`
* `Temporalio.Workflow` renamed to `Temporalio.Workflows`

TODO(cretz): Alternative options for discussion:

* Call it `WorkflowContext` instead of `Workflow` but keep as static
  * Mismatches Java
  * Inconsistent with `ActivityContext`
  * Not really a context instance if static
* Require `WorkflowContext.Current` everywhere
  * Mismatches Java
  * No benefit since it will always be present in a workflow
  * Wordy
* Find some way to DI the `WorkflowContext`
  * Mismatches Java
  * Basically required DI since 99% of workflows will use it, so unnecessary user work
  * No good place to DI it and still keep reasonably typed method references
* Rename `ActivityContext` to just `Activity`?
  * Mismatches Java
  * May be strange that `Temporalio.Activities.Activity` is an instance to access with `Current` whereas
    `Temporalio.Workflows.Workflow` is static

## Workflow Definition Overview

In phase 1 there was an example of an interface defining a workflow. But you can use a class instead and you can even
have a constructor with the init params. Example:

```csharp
namespace MyNamespace;

using System;
using System.Threading.Tasks;
using System.Threading.Tasks.Dataflow;
using Temporalio.Activities;
using Temporalio.Workflows;

public record GreetingInfo
{
    [JsonPropertyName("salutation")]
    public string Salutation { get; init; } = "Hello";

    [JsonPropertyName("name")]
    public string Name { get; init; } = "<unknown>";
}

// Activities can be static without ref, this is just for demonstration of
// instance activities
public class Activities
{
    public static readonly Activities Ref = ActivityRefs.Create<Activities>();

    [Activity]
    public string CreateGreeting(GreetingInfo info) => return $"{info.Salutation}, {info.Name}!";
}

[Workflow]
public class GreetingWorkflow
{
    public static readonly GreetingWorkflow Ref = WorkflowRefs.Create<GreetingWorkflow>();

    private readonly BufferBlock<GreetingInfo> updates = new();
    private readonly string name;
    private string currentGreeting = "<unset>";

    [WorkflowInit]
    public GreetingWorkflow(string name)
    {
        this.name = name;
        updates.Post(new(Name: name));
    }

    [WorkflowRun]
    public async Task<string> RunAsync(string _)
    {
        // Continually update greetings while updates made available
        while (await updates.OutputAvailableAsync())
        {
            // Store current greeting
            currentGreeting = await Workflow.ExecuteActivityAsync(
                Activities.Ref.CreateGreeting,
                await updates.ReceiveAsync(),
                new(StartToCloseTimeout: TimeSpan.FromSeconds(5)));
            Workflow.Logger.LogDebug("Greeting set to {Greeting}", currentGreeting);
        }
        return currentGreeting;
    }

    [WorkflowSignal]
    public Task UpdateSalutationAsync(string salutation) =>
        updates.SendAsync(new(Salutation: salutation, Name: name));

    [WorkflowSignal]
    public Task CompleteWithGreetingAsync()
    {
        updates.Complete();
        return Task.CompletedTask;
    }

    [WorkflowQuery]
    public string CurrentGreeting() => currentGreeting;
}
```

Some things to note about the above code (much copied from phase 1):

* Every workflow must have the non-inheritable `[Workflow]` attribute
  * Optional `Name` positional property can be given. Default is the unqualified type name with the "I" prefix removed
    if it's an interface and the next letter is also capital
    * So what does `IDWorkflow` become? Yes, `DWorkflow` :-( Weighed as an acceptably rare cost for obvious benefit
  * Non-inheritable means just because the interface or base class defines `[Workflow]`, the registered one must too
* Workflows can have a single public constructor with `[WorkflowInit]` that take the exact same parameters as the
  `[WorkflowRun]` method
  * This is not required and most workflows probably won't use it but it is nice for those wanting to build readonly
    properties instead of waiting until run
  * If this is not present, a public parameterless constructor must be present (default of course in C# when no
    constructors present)
  * Ignored if in base class
* Every workflow must explicitly have one and only one public method with a non-inheritable `WorkflowRun` attribute
  * Can be in base class, but must also be overridden in this workflow class w/ the attribute even if it just delegates
    to super
  * Method must return a `Task`
* Workflow signals are public async methods with the non-inheritable `[WorkflowSignal]` attribute
  * Can be in base class, but if overridden, must also have the attribute
  * Method must return a `Task` and can accept arguments
    * It is a bit annoying to force Task on people that may not be doing an async thing but:
      * They may change it later so might as well require it (especially since the "Async" suffix is usually present)
      * Causes too many overloads if we accept `Task` and `void`
  * Optional `Name` positional property can be given. Default is the unqualified method name with "Async" trimmed off if
    present.
* Workflow queries are public methods with the non-inheritable `[WorkflowQuery]` attribute
  * Can be in base class, but if overridden, must also have the attribute
  * Method cannot return a `Task`, but can accept arguments
  * Optional `Name` positional property can be given. Default is the unqualified method name.
  * Would love to put this on properties, but they aren't referenceable as delegates
* Users are encouraged to set a `static` `readonly` `Ref` property for use by clients
  * Phase 1 had this use `Temporalio.Refs` (and we since changed from `<T>.Instance` to `.Create<T>()`) but we are now
    going to split this into `Temporalio.Workflows.WorkflowRefs` and `Temporalio.Activities.ActivityRefs`
    * In addition to not having "refs" for other purposes, this allows eager validation of workflow and activity
      definitions
  * This is backed by a dynamic proxy
    * Since the constructor may be `[WorkflowInit]`, we use
      `System.Runtime.Serialization.FormatterServices.GetUninitializedObject`, ref
      [this issue](https://github.com/castleproject/Core/issues/588)
* Notice all the cool uses of `System.Threading.Tasks.Dataflow`

## .NET Workflow Worker

Plan:

* Create `WorkflowInstance` that is a custom .NET `TaskScheduler` that executes deterministically, until all are
  idle, and properly executes wait-condition and such
  * The scheduler will be the current scheduler and no workflow work is allowed on any other scheduler
  * Each task run will be synchronous on a single thread so deadlock detection can work
  * All task scheduling should then work, e.g. `Task.Delay`, Dataflow stuff, etc
* Follow Python and others' example of task ordering/distribution/etc
* Not creating a `WorkflowRunner` abstraction like in Python because we have no reasonable expectation for a sandbox in
  the future
  * This abstraction can be created later, but since .NET does not have AppDomain anymore, there is no way to build a
    good sandbox, so we will rely on custom analyzers instead

Additions to `TemporalWorkerOptions`:

```csharp
namespace Temporalio.Worker;

public class TemporalWorkerOptions : ICloneable
{
    // ... phase 1 pieces omitted ...

    public IList<Type> Workflows { get; set; } = new List<Type>();

    public TemporalWorkerOptions AddWorkflow(Type type) { /*... */ }

    public int MaxCachedWorkflows { get; set; } = 10000;

    public int MaxConcurrentWorkflowTasks { get; set; } = 100;

    public bool DisableRemoteActivities { get; set; }

    public TimeSpan StickyQueueScheduleToStartTimeout { get; set; } = TimeSpan.FromSeconds(10);

    internal static bool DebugModeEnvironmentVariable { get; } = /*...*/;

    public bool DebugMode { get; set; } = DebugModeEnvironmentVariable;
}
```

Notes:

* Intentionally leaving off `NonStickyToStickyPollRatio` and `MaxConcurrentWorkflowTaskPolls`

## Workflow API

```csharp
namespace Temporalio.Workflows;

public static class Workflow
{
    public static bool InWorkflow { get; }

    public static WorkflowInfo Info { get; }

    // Activities
    // (assume all duplicated with "Local" before activity for local activities)

    public static Task ExecuteActivityAsync(
        Action activity, ActivityStartOptions options) { /*...*/ }

    public static Task ExecuteActivityAsync<T>(
        Action<T> activity, T arg, ActivityStartOptions options) { /*...*/ }

    public static Task<TResult> ExecuteActivityAsync<TResult>(
        Func<TResult> activity, ActivityStartOptions options) { /*...*/ }

    public static Task<TResult> ExecuteActivityAsync<TResult>(
        Func<Task<TResult>> activity, ActivityStartOptions options) { /*...*/ }

    public static Task<TResult> ExecuteActivityAsync<T, TResult>(
        Func<T, TResult> activity, T arg, ActivityStartOptions options) { /*...*/ }

    public static Task<TResult> ExecuteActivityAsync<T, TResult>(
        Func<T, Task<TResult>> activity, T arg, ActivityStartOptions options) { /*...*/ }

    public static Task ExecuteActivityAsync(
        string activity, object[] args, ActivityStartOptions options) { /*...*/ }

    public static Task<TResult> ExecuteActivityAsync<TResult>(
        string activity, object[] args, ActivityStartOptions options) { /*...*/ }

    // Child workflows

    public static Task<ChildWorkflowHandle> StartChildWorkflowAsync(
        Func<Task> workflow, ChildWorkflowStartOptions options) { /*...*/ }

    public static Task<ChildWorkflowHandle> StartChildWorkflowAsync<T>(
        Func<T, Task> workflow, T arg, ChildWorkflowStartOptions options) { /*...*/ }

    public static Task<ChildWorkflowHandle<TResult>> StartChildWorkflowAsync<TResult>(
        Func<Task<TResult>> workflow, ChildWorkflowStartOptions options) { /*...*/ }

    public static Task<ChildWorkflowHandle<TResult>> StartChildWorkflowAsync<T, TResult>(
        Func<T, Task<TResult>> workflow, T arg, ChildWorkflowStartOptions options) { /*...*/ }

    public static Task<ChildWorkflowHandle> StartChildWorkflowAsync(
        string workflow, object[] args, ChildWorkflowStartOptions options) { /*...*/ }

    public static Task<ChildWorkflowHandle<TResult>> StartChildWorkflowAsync<TResult>(
        string workflow, object[] args, ChildWorkflowStartOptions options) { /*...*/ }

    public static Task ExecuteChildWorkflowAsync(
        Func<Task> workflow, ChildWorkflowStartOptions options) { /*...*/ }

    public static Task ExecuteChildWorkflowAsync<T>(
        Func<T, Task> workflow, T arg, ChildWorkflowStartOptions options) { /*...*/ }

    public static Task<TResult> ExecuteChildWorkflowAsync<TResult>(
        Func<Task<TResult>> workflow, ChildWorkflowStartOptions options) { /*...*/ }

    public static Task<TResult> ExecuteChildWorkflowAsync<T, TResult>(
        Func<T, Task<TResult>> workflow, T arg, ChildWorkflowStartOptions options) { /*...*/ }

    public static Task ExecuteChildWorkflowAsync(
        string workflow, object[] args, ChildWorkflowStartOptions options) { /*...*/ }

    public static Task<TResult> ExecuteChildWorkflowAsync<TResult>(
        string workflow, object[] args, ChildWorkflowStartOptions options) { /*...*/ }

    // Signal and query handlers

    public bool TryGetSignalHandler(string name, out Delegate handler) { /*...*/ }

    public void SetSignalHandler(string name, Func<Task> handler) { /*...*/ }

    public void SetSignalHandler<T>(string name, Func<T, Task> handler) { /*...*/ }

    public void RemoveSignalHandler(string name) { /*...*/ }

    public bool TryGetDynamicSignalHandler(out Func<string, Payload[], Task> handler) { /*...*/ }

    public void SetDynamicSignalHandler(Func<string, Payload[], Task> handler) { /*...*/ }

    public void RemoveDynamicSignalHandler() { /*...*/ }

    public bool TryGetQueryHandler(string name, out Delegate handler) { /*...*/ }

    public void SetQueryHandler<TResult>(string name, Func<TResult> handler) { /*...*/ }

    public void SetQueryHandler<T, TResult>(string name, Func<T, TResult> handler) { /*...*/ }

    public void RemoveQueryHandler(string name) { /*...*/ }

    public bool TryGetDynamicQueryHandler<TResult>(out Func<string, Payload[], TResult> handler) { /*...*/ }

    public void SetDynamicQueryHandler<TResult>(Func<string, Payload[], TResult> handler) { /*...*/ }

    public void RemoveDynamicSignalHandler() { /*...*/ }

    // Search attributes and memo

    public static SearchAttributes TypedSearchAttributes { get; }

    public static void UpsertTypedSearchAttributes(params SearchAttributeUpdate[] updates) { /*...*/ }

    public static IDictionary<string, Payload> RawMemo { get; }

    public static T GetMemoValue<T>(string key) { /*...*/ }

    public static object? GetMemoValue(string key, Type valueType) { /*...*/ }

    public static bool TryGetMemoValue<T>(string key, out T value) { /*...*/ }

    public static bool TryGetMemoValue(string key, Type valueType, out object? value) { /*...*/ }

    public static void UpsertMemo(params MemoUpdate[] updates) { /*...*/ }

    // External workflow handle

    public ExternalWorkflowHandle GetExternalWorkflowHandle(
        string workflowID, string? runID = null) { /*...*/ }

    // Versioning

    public static bool Patched(string id) { /*...*/ }

    public static void DeprecatePatch(string id) { /*...*/ }

    // Misc

    public static CancellationToken CancellationToken { get; }

    public static ILogger Logger { get; }

    public static DateTime UtcNow { get; }

    public static Random Random { get; }

    public static Guid NewGuid() { /*...*/ }

    public static Task WaitCondition(Func<bool> func) { /*...*/ }
}

public class ChildWorkflowHandle
{
    public string ID { get; }

    public string FirstExecutionRunID { get; }

    public Task GetResultAsync() { /*...*/ }

    public Task<TResult> GetResultAsync<TResult>() { /*...*/ }

    public Task SignalAsync(
        Func<Task> signal, ChildWorkflowSignalOptions? options = null) { /*...*/ }

    public Task SignalAsync<T>(
        Func<T, Task> signal, T arg, ChildWorkflowSignalOptions? options = null) { /*...*/ }

    public Task SignalAsync<T>(
        string signal, object[] args, ChildWorkflowSignalOptions? options = null) { /*...*/ }
}

public class ChildWorkflowHandle<TResult> : ChildWorkflowHandle
{
    public new Task<TResult> GetResultAsync() { /*...*/ }
}

public class ExternalWorkflowHandle
{
    public string ID { get; }

    public string? RunID { get; }

    public Task CancelAsync(ExternalWorkflowCancelOptions? options = null) { /*...*/ }

    public Task SignalAsync(
        Func<Task> signal, ExternalWorkflowSignalOptions? options = null) { /*...*/ }

    public Task SignalAsync<T>(
        Func<T, Task> signal, T arg, ExternalWorkflowSignalOptions? options = null) { /*...*/ }

    public Task SignalAsync<T>(
        string signal, object[] args, ExternalWorkflowSignalOptions? options = null) { /*...*/ }
}

public class ContinueAsNewException : TemporalException
{
    public static ContinueAsNewException Create(
        Func<Task> workflow, ContinueAsNewOptions? options = null) { /*...*/ }
    public static ContinueAsNewException Create<T>(
        Func<T, Task> workflow, T arg, ContinueAsNewOptions? options = null) { /*...*/ }
    public static ContinueAsNewException Create<TResult>(
        Func<Task<TResult>> workflow, ContinueAsNewOptions? options = null) { /*...*/ }
    public static ContinueAsNewException Create<T, TResult>(
        Func<T, Task<TResult>> workflow, T arg, ContinueAsNewOptions? options = null) { /*...*/ }
    public static ContinueAsNewException Create(
        string workflow, object[] args, ContinueAsNewOptions? options = null) { /*...*/ }

    private ContinueAsNewException(
        string workflow, IReadOnlyCollection<object?> args, ContinueAsNewOptions? options) { /*...*/ }

    public string Workflow { get; private init; }

    public IReadOnlyCollection<object?> Args { get; private init; }

    public ContinueAsNewOptions? Options { get; private init; }
}
```

Notes about the above code:

* Activities and child workflows can be provided cancellation tokens in their options
  * Technically we could put `CancellationTokenSource` on the handles, but the current approach seems more .NET like
* Since activities have no reason for an `ActivityHandle`, there is no `StartActivity`
  * Python has `start_activity` + `ActivityHandle` because that language allows you to cancel the task
  * The cancellation token in the options and the result of the task are enough to support all current activity features
  * `StartActivity` + `ActivityHandle` may be added in the future if we ever allow doing things to activities more than
    just cancelling and getting result
* After discussion, we have decided to have `ActivityOptions` and `ChildWorkflowOptions` instead of
  `ActivityStartOptions` and `ChildWorkflowStartOptions`
  * This means we will also be renaming `WorkflowStartOptions` to `WorkflowOptions` on the client side
* Signal/query handlers
  * We could have made dynamic signal/query handler get/set a property but it's more consistent with non-dynamic to use
    methods
  * We could have returned/accepted null for unset, but this approach is more .NET like
  * We currently have no public way to get all signal/query handlers from inside a workflow (same as Python)
* There's no value in accepting workflow type in `GetExternalWorkflowHandle` at this time because we can only signal and
  cancel it currently. And signal is not currently scoped to the workflow at compile time.
* We expect users to `throw ContinueAsNewException.Create(RunAsync, )` instead of have some helper
  * This is the .NET preferred approach (same for `throw new CompleteAsyncException()` for activities)
* A `CancellationToken` can be provided on every async call made, but if not set, by default workflow cancellation token
  is the token used. This allows it to be overridden with a token not related to workflow cancellation.

## Workflow Replayer API

```csharp
namespace Temporalio.Worker;

public class WorkflowReplayer
{
    public WorkflowReplayer(WorkflowReplayerOptions options) { /*...*/ }

    public Task<WorkflowReplayResult> ReplayWorkflowAsync(
        WorkflowHistory history, WorkflowReplayOptions? options = null) { /*...*/ }
}

public class WorkflowReplayOptions : ICloneable
{
    public bool ThrowOnReplayFailure { get; set; }
}

public record WorkflowReplayResult(Exception? ReplayFailure = null);
```

Notes about the above code:

* We call this `WorkflowReplayer` instead of `Replayer` like we do in Python
  * TODO(cretz): Should we call this `Replayer` instead? I think I still like `ReplayWorkflowAsync` instead of just
    `ReplayAsync` regardless of class name.
* `WorkflowReplayerOptions` shares many options with `TemporalWorkerOptions`, but not enough (and a few extra from
  client) to justify any code sharing
* `ReplayWorkflowAsync` is thread safe and we'll document this instead of making an overload of this that accepts an
  iterator
* Unlike Python we choose not to provide the history on the `WorkflowReplayResult` because we don't aggregate for the
  user (they have LINQ ways to run many in parallel and they can correlate as desired)