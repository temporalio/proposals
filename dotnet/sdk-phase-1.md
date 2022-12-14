# .NET SDK - Phase 1

The .NET SDK will be implemented in three loosely defined phases:

* Phase 1 - Initial project, activity worker, client, and test framework
* Phase 2 - Workflow worker and replayer
* Phase 3 - Deterministic workflow sandbox and/or static analyzer

This proposal is for phase 1.

Notes for this proposal:

* Intentionally loosely defined, everything subject to change
* Some decisions are justified at the end
* Lots of the code is not valid C# but has things like `/*...*/` for brevity or just empty implementations

## Overview

The .NET SDK will be backed by [sdk-core](https://github.com/temporalio/sdk-core), utilizing "P/Invoke" and a
custom-built bridge.

The high-level goals for the .NET SDK are:

* Be as simple as possible from a caller POV
* Be as lightweight as reasonable with regards to dependencies
* Be reasonably flexible with reasonable defaults
* Fit well into the .NET ecosystem
* Minimum versions supported: .NET Core 3.1, .NET Standard 2.0, and .NET Framework 4.6.2
* All common 64-bit platforms supported, 32-bit maybe later

## Repository Management

The existing repository at https://github.com/temporalio/sdk-dotnet has hundreds of commits, dozens of issues, open PRs,
GH pages, etc that don't align with this proposal necessarily. After some thought, it has been decided to move that
repository and create https://github.com/temporalio/sdk-dotnet again fresh.

## Namespace/Package

* Will publish as `Temporalio`
  * Need to reserve prefix `Temporalio` on NuGet, see
    https://learn.microsoft.com/en-us/nuget/nuget-org/id-prefix-reservation
* Namespace will be `Temporalio`
  * See discussion topics later about this being `Temporalio.Sdk` instead

## Workflow Definition

Here's a definition for an other-language-defined workflow (from Python README):

```csharp
namespace MyNamespace;

using System.Text.Json.Serialization;
using Temporalio.Workflow;

public record GreetingInfo
{
    [JsonPropertyName("salutation")]
    public string Salutation { get; init; } = "Hello";

    [JsonPropertyName("name")]
    public string Name { get; init; } = "<unknown>";
}

[Workflow]
public interface IGreetingWorkflow
{
    static readonly IGreetingWorkflow Ref = Refs<IGreetingWorkflow>.Instance;

    [WorkflowRun]
    Task<string> RunAsync(GreetingInfo info);

    [WorkflowSignal]
    Task UpdateInfoAsync(GreetingInfo info);

    [WorkflowSignal]
    Task CompleteWithGreetingAsync();

    [WorkflowQuery]
    string CurrentGreeting();
}
```

Notes:

* We use regular .NET JSON serialization (see data conversion later)
* Workflow attributes, and in the future workflow runtime features, are in the `Temporalio.Workflow` namespace
* We only support workflow interfaces right now because we don't have a workflow implementation yet
  * For now, everything non-static must have some form of `[Workflow` attribute, and not have a default implementation
* Every workflow interface must have the non-inheritable `Workflow` attribute
  * Optional `Name` positional property can be given. Default is the unqualified type name with the "I" prefix removed
    if it's an interface (which it has to be currently) and the next letter is also capital
    * So what does `IDWorkflow` become? Yes, `DWorkflow` :-( Weighed as an acceptably rare cost for obvious benefit
* Every workflow must explicitly have one and only one method with a non-inheritable `WorkflowRun` attribute
  * Can be in base class, but must also be overridden in this workflow class w/ the attribute even if it just delegates
    to super
  * Method must return a `Task`
* Workflow signals are methods with the non-inheritable `WorkflowSignal` attribute
  * Can be in base class, but if overridden, must also have the attribute
  * Method must return a `Task` and can accept arguments
  * Optional `Name` positional property can be given. Default is the unqualified method name with "Async" trimmed off if
    present.
* Workflow queries are methods with the non-inheritable `WorkflowQuery` attribute
  * Can be in base class, but if overridden, must also have the attribute
  * Method cannot return a `Task`, but can accept arguments
  * Optional `Name` positional property can be given. Default is the unqualified method name.
* Users are encouraged to set a `static` `readonly` `Ref` property for use by clients
  * `Refs<T>.Instance` is how it is obtained
    * Also will do validation which will be shared in the future by the workflow worker
    * `Refs` is in `Temporalio` not `Temporalio.Workflow`
  * This is backed by a dynamic proxy
  * Really old versions of .NET (i.e. would be rarely used by users, < C# 8), don't allow a `static readonly` property on the
    interface and therefore they have to make their `Ref` elsewhere

## Activity Definition

Common static definition:

```csharp
namespace MyNamespace;

using Temporalio.Activity;

public static class GreetingActivities
{
    [Activity(Name = "create_greeting_activity")]
    public static async Task<string> CreateGreetingAsync(GreetingInfo info)
    {
        return $"{info.Salutation}, {info.Name}!";
    }
}
```

Common instance definition:

```csharp
namespace MyNamespace;

using Temporalio.Activity;

public class GreetingActivities
{
    public static readonly GreetingActivities Ref = Refs<GreetingActivities>.Instance;

    [Activity(Name = "create_greeting_activity")]
    public async Task<string> CreateGreetingAsync(GreetingInfo info)
    {
        return $"{info.Salutation}, {info.Name}!";
    }
}
```

Notes:

* Activities can be on static or non-static methods
  * Even though our proxying library requires virtual methods for interception, we're never intercepting, only
    _referencing_.
    * This means if someone _does_ invoke an instance method on a `Ref`, it'd call it normally. We can't help this.
* All activities must have a non-inheritable `Activity` attribute
  * Optional `Name` positional property can be given. Default is unqualified method name with "Async" trimmed off the
    end if it returns a `Task`
* Activity classes can be/implement interfaces
  * There is no value to this from a Temporal perspective currently since the caller side of activities is not in this
    phase
* Activities do not have to be async, they will use the global thread pool otherwise (see worker later)
* Non-static activity classes are encouraged to set a `static` `readonly` `Ref` property for use by clients
  * Similar approach as workflows
  * Unlike workflow validation that checks every public method attribute, this only ensures there is at least one public
    activity
  * Not required for static activities because they can just be referenced on the class
* Any overridden instance activities from base classes or same-named static activities from base classes must have the
  exact same signature and attribute. This ensures people don't make mistakes accidentally overriding and removing the
  activity attribute. This also avoids a diamond problem or duplicate problem for statics.

### Activity Contextual Operations

The activity context looks like this:

```csharp
namespace Temporalio.Activity;

public class ActivityContext
{
    public static ActivityContext Current { get; }

    public static bool HasCurrent { get; }

    internal ActivityContext(
        ActivityInfo info,
        CancellationToken cancellationToken,
        Action<object[]> heartbeater) { /*...*/ }

    public ActivityInfo Info { get; }

    public CancellationToken CancellationToken { get; }

    public CancellationToken WorkerShutdownToken { get; }

    internal Action<object[]> Heartbeater { get; }

    public void Heartbeat(params object[] details) { /*...*/ }
}
```

Notes:

* The current activity context is on thread local or async local depending on whether activity is async or not
* All calls except `HasCurrent` fail if not in activity context
* `ActivityInfo` is an immutable record containing info
* `CancellationToken` and `WorkerShutdownToken` are usable by sync and async
  * `WorkerShutdownToken` is set on worker shutdown before cancellation token is set. If there is no graceful shutdown
    period, one is set immediately after the other
* Note the lack of logger here. See "Logging" later, but in general .NET doesn't have a logger in the standard library.
  We may make some kind of `IReadOnlyDictionary<string, string> ActivityInfo.LogInfo { get; }` that can be used with
  `ILogger.BeginScope` or similar.

### Async Completion

Simply `throw new Temporalio.Activity.CompleteAsyncException` from the activity.

## Client

Inside the `Temporalio.Client` namespace, we have the following types:

* `TemporalClient` - namespace-specific, stateless high-level client to Temporal
  * See later for most of its API design
  * Accepts `ITemporalConnection`
  * Implements `ITemporalClient` for DI use (which itself implements `Temporalio.Worker.IWorkerClient` for worker use)
* `TemporalConnection` - namespace-agnostic, stateful low-level client to Temporal
  * Has `WorkflowService`, `OperatorService`, etc for making raw gRPC calls
  * Supports lazy connectivity
  * Implements `ITemporalConnection` for DI use
* `WorkflowHandle` - high-level workflow-specific calls
* Many other supporting types

Example of starting the workflow defined earlier in document, signalling it, then waiting on its results:

```csharp
using Temporalio.Client;
using MyNamespace;

// Connect
var client = await TemporalClient.ConnectAsync(new("localhost:7233"));

// Start workflow
var handle = await client.StartWorkflowAsync(
    IGreetingWorkflow.Ref.RunAsync, "Temporal", new(ID: "my-workflow-id", TaskQueue: "my-task-queue"));

// Send signal
await handle.Signal(IGreetingWorkflow.Ref.CompleteWithGreetingAsync);

// Wait for result
Console.WriteLine(await handle.GetResultAsync());
```

Example of doing the same via already started workflow:

```csharp
using Temporalio.Client;
using MyNamespace;

// Connect
var client = await TemporalClient.ConnectAsync(new("localhost:7233"));

// Get workflow handle
var handle = await client.GetWorkflowHandle<string>("my-workflow-id");

// Send signal
await handle.Signal(IGreetingWorkflow.Ref.CompleteWithGreetingAsync);

// Wait for result
Console.WriteLine(await handle.GetResultAsync());
```

Note, this could have been just `client.GetWorkflowHandle("my-workflow-id")` + `handle.GetResultAsync<string>()` if the
user would rather not provide the type until fetching the result. See the definitions below.

### TemporalClient

Looks like:

```csharp
namespace Temporalio.Client;

public class TemporalClient : ITemporalClient
{
    public static async Task<TemporalClient> ConnectAsync(TemporalClientConnectOptions options) { /*...*/ }

    public TemporalClient(ITemporalConnection connection, TemporalClientOptions options) { /*...*/ }

    public string Namespace { get; }
    public DataConverter DataConverter { get; }
    public IBridgeClientProvider BridgeClientProvider { get; }
    public ITemporalConnection Connection { get; }
    public TemporalClientOptions Options { get; }

    // StartWorkflowAsync

    public async Task<WorkflowHandle<TResult>> StartWorkflowAsync<TResult>(
        string workflow, object[] args, StartWorkflowOptions options) { /*...*/ }

    public async Task<WorkflowHandle<TResult>> StartWorkflowAsync<TResult>(
        Func<Task<TResult>> workflow, StartWorkflowOptions options) { /*...*/ }

    public async Task<WorkflowHandle<TResult>> StartWorkflowAsync<T, TResult>(
        Func<T, Task<TResult>> workflow, T arg, StartWorkflowOptions options) { /*...*/ }

    public async Task<WorkflowHandle> StartWorkflowAsync(
        Func<Task> workflow, StartWorkflowOptions options) { /*...*/ }

    public async Task<WorkflowHandle> StartWorkflowAsync<T>(
        Func<T, Task> workflow, T arg, StartWorkflowOptions options) { /*...*/ }

    public async Task<WorkflowHandle> StartWorkflowAsync(
        string workflow, object[] args, StartWorkflowOptions options) { /*...*/ }

    public async Task<WorkflowHandle<TResult>> StartWorkflowAsync<TResult>(
        string workflow, object[] args, StartWorkflowOptions options) { /*...*/ }

    // GetWorkflowHandle

    public WorkflowHandle GetWorkflowHandle(
        string workflowID, string? runID = null, string? firstExecutionRunID = null) { /*...*/ }

    public WorkflowHandle<TResult> GetWorkflowHandle<TResult>(
        string workflowID, string? runID = null, string? firstExecutionRunID = null) { /*...*/ }

    // GetAsyncActivityHandle

    public AsyncActivityHandle GetAsyncActivityHandle(string workflowID, string? runID, string activityID) { /*...*/ }

    public AsyncActivityHandle GetAsyncActivityHandle(byte[] taskToken) { /*...*/ }

#if NETCOREAPP3_0_OR_GREATER

    // ListWorkflowsAsync

    public IAsyncEnumerator<WorkflowExecution> ListWorkflows(
        string query,
        ListWorkflowsOptions? options = null,
    ) { /*...*/ }

#endif
}
```

Notes:

* There is no lazy connection/client like there is in other languages
  * Originally the code had a `Lazy` connection option, but the team decided they wanted it removed
* There will be `ExecuteWorkflowAsync` helper methods for each `StartWorkflowAsync` overload there
* It was decided forcing an options object is easier than lots of parameters for start workflow
* Notice that there is a string-based workflow `StartWorkflowAsync` call that accepts a return type and one that
  doesn't. The user can specify a return type on `WorkflowHandle.GetResultAsync` if they
  want instead of at start time (or just never altogether if the return doesn't matter to the user).
* For string-based calls to `StartWorkflowAsync`, we are accepting all args at once via `object[]`. But since array
  types are covariant in .NET, this means you could have a workflow that accepts `string[]` and forget that needs to
  just be the first value of the object array.
  * Cannot think of a good way to make this better. We could:
    * Use varargs (i.e. `params`), but not having options as the last parameter is ugly DX
    * Use some kind of forced wrapper, e.g. `IArgumentCollection`, but it's ugly too
    * Accept args in options instead of as param, but that options set is reused for other calls
    * Accept both single-arg and multi-arg w/ "unset" defaults, but that is confusing and most .NET devs use their
      positional parameters unnamed
    * Have separate overloads for no-arg, 1-arg, and multi-arg but that's not any clearer
* For `GetWorkflowHandle`, we cannot accept a workflow reference because in .NET if you don't type all type arguments
  (i.e. including that parameter type), you have to help the type inferencer out. So since they'd have to provide a type
  argument anyways, we make it where they either can here or wait until `GetResultAsync` to do so.
  * We could have taken a proxy approach, but that would have made the code look like
    `client.GetWorkflowHandle<GreetingWorkflow>("my wf id", wf => wf.RunAsync)` which is not much better and is hard to
    get right with all of the overloads so you can have the lambda as the last param. This is what Azure Durable
    Entities does. There is discussion on this later.
* Cancellation tokens (and RPC metadata and RPC timeout and such) will be in the call options, not as the last parameter
  in a bunch of overloads like many other .NET methods
* Older versions of .NET don't have `IAsyncEnumerator` and we don't want to go out of our way to provide a special
  `ListWorkflows` for them
  * Older versions can just use raw gRPC or not have this feature. These older .NET versions are really old and we don't
    expect hardly any users on them.
  * Note, `ListWorkflows` is not `ListWorkflowsAsync` because the first page is lazily fetched on first iteration
  * We need an easy way to map this to histories. Maybe a `GetHandle` extension method on the execution (that accepts a
    client), and a `SelectHistories` extension method on `IAsyncEnumerator<WorkflowExecution>` that accepts a client.

### WorkflowHandle

Looks like:

```csharp
namespace Temporalio.Client;

public class WorkflowHandle
{
    public string ID { get; }
    public string? RunID { get; }
    public string? ResultRunID { get; }
    public string? FirstExecutionRunID { get; }

    public async Task GetResultAsync(
        bool followRuns = true, RPCOptions? options = null) { /*...*/ }

    public async Task<TResult> GetResultAsync<TResult>(
        bool followRuns = true, RPCOptions? options = null) { /*...*/ }

    public async Task SignalAsync(string signal, object[] args, RPCOptions? options = null) { /*...*/ }

    public async Task SignalAsync(Func<Task> signal, RPCOptions? options = null) { /*...*/ }

    public async Task SignalAsync<T>(Func<T, Task> signal, T arg, RPCOptions? options = null) { /*...*/ }

    public async Task<TQueryResult> QueryAsync<TQueryResult>(
      string query, object[] args, RPCOptions? options = null) { /*...*/ }

    public async Task<TQueryResult> QueryAsync<TQueryResult>(
      Func<TQueryResult> query, RPCOptions? options = null) { /*...*/ }

    public async Task<TQueryResult> QueryAsync<T, TQueryResult>(
      Func<T, TQueryResult> query, T arg, RPCOptions? options = null) { /*...*/ }

    public async Task CancelAsync(RPCOptions? options = null) { /*...*/ }

    public async Task TerminateAsync(
        string reason? = null, object[]? args = null, RPCOptions? options = null) { /*...*/ }

    public async Task<WorkflowExecutionDescription> DescribeAsync(RPCOptions? options = null) { /*...*/ }

#if NETCOREAPP3_0_OR_GREATER

    public async Task<WorkflowHistory> FetchHistoryAsync(
        WorkflowHistoryEventFilterType eventFilterType = WorkflowHistoryEventFilterType.AllEvents,
        bool skipArchival = false,
        RPCOptions? options = null) { /*...*/ }

    public IAsyncEnumerator<HistoryEvent> FetchHistoryEvents(
        bool waitNewEvent = false,
        WorkflowHistoryEventFilterType eventFilterType = WorkflowHistoryEventFilterType.AllEvents,
        bool skipArchival = false,
        RPCOptions? options = null) { /*...*/ }

#endif
}

public class WorkflowHandle<TResult> : WorkflowHandle
{
    public new async Task<TResult> GetResultAsync(
        bool followRuns = true, RPCOptions? options = null) { /*...*/ }
}
```

Notes:

* Notice you can provide a return type explicitly on the `GetResultAsync` call if the generic one on the handle isn't
  what you want
* Like start workflow, signal/query string-based calls accept an array of objects instead of trying to use varargs or
  separating single arg vs multi. This makes the overload count better and will give users compile time errors if it's
  not literally an object array
* Notice that `TerminateAsync` does not _require_ `args` like start, signal, and query calls that accept `args` arrays
  because we don't think it's important for users to explicitly send empty if they don't want them like we think they
  should for the others
* Same issue with `FetchHistory*` as `ListWorkflows` on client - no `IAsyncEnumerator` on really old .NET versions, but
  we're ok with that

## Worker

Usage:

```csharp
using Temporalio.Client;
using Temporalio.Worker;
using MyNamespace;

// Connect
var client = await TemporalClient.ConnectAsync(new("localhost:7233"));

// Build worker options
var options = new TemporalWorkerOptions("task queue");
options.AddActivities(new GreetingActivities());

// Run until Ctrl+C
var worker = new TemporalWorker(client, options);
var cts = new CancellationTokenSource();
Console.CancelKeyPress += (sender, eventArgs) => {
    eventArgs.Cancel = true;
    cts.Cancel();
};
await worker.ExecuteAsync(cts.Token);
```

Looks like:

```csharp
namespace Temporalio.Worker;

using Temporalio.Activity;

public class TemporalWorkerOptions
{
    public TemporalWorkerOptions() { /*...*/ }
    public TemporalWorkerOptions(string taskQueue) { /*...*/ }

    public string? TaskQueue { get; set; }

    public List<ActivityDefinition> ActivityDefinitions { get; set; } = new();

    public void AddActivities(params object[] activities) { /*...*/ }

    public void AddActivityDefinition(ActivityDefinition definition) { /*...*/ }

    // Many more options not listed
}

public class TemporalWorker
{
    public TemporalWorker(IWorkerClient client, TemporalWorkerOptions options) { /*...*/ }

    public Task ExecuteAsync(CancellationToken stoppingToken) { /*...*/ }
}
```

Notes:

* Like other options, technically all worker options are optional at compile time but we fail at runtime if task queue
  is not set
* Activity definitions are the underlying type of the activity collection (they have just a name and method to call) but
  most users will call `AddActivities`
* `AddActivities` intentionally take types or instances
  * For types, all `[Activity`s must be on static methods, no instance methods allowed
    * It was decided to do `AddActivities(typeof(MyStaticClass))` for all static method things than to have
    `AddActivities<MyStaticClass>()` overload. All-static activities may not be that common and adding overloads is
    unnecessary.
  * For instances, `[Activity`s can be on static or instance methods
  * Inheritance rules apply from the earlier activity definition section
  * Users can use the lower-level `AddActivityDefinition` but we left this name unwieldy on purpose, we prefer
    `AddActivities`
* Since workflows are not currently implemented, at least one activity is required
* Activities can be sync or async
  * For future `Workflow.ExecuteActivity` uses, we have confirmed .NET can disambiguate in an overload between `Task`
    return type and generic return type with no constraints
  * Async activities are executed using the normal scheduler
    * No need yet for a custom scheduler
  * Sync activities are executed with `ThreadPool`
    * No need yet for a custom executor
* As much validation and non-async initialization is done in the constructor as possible
* While it may be tempting to make `Worker` implement `IAsyncDisposable`, we want users to explicitly handle fatal
  errors out of `ExecuteAsync`
  * We can't throw out of `await using` blocks
* Notice a lack of `StartAsync`, we want users to handle fatal errors from `ExecuteAsync`
* Notice a lack of `ShutdownAsync`, we want users to use the cancellation token
* `ExecuteAsync(CancellationToken)` was specifically done this way to match
  `Microsoft.Extensions.Hosting.BackgroundService.ExecuteAsync`

## Replayer

Looks like:

```csharp
namespace Temporalio.Worker;

class WorkflowReplayer
{
    public WorkflowReplayer(TemporalWorkerOptions options) { /*...*/ }

    public async Task<WorkflowReplayResult> ReplayWorkflow(
        WorkflowHistory history, bool throwOnReplayFailure = true) { /*...*/ }

#if NETCOREAPP3_0_OR_GREATER

    public IAsyncEnumerator<WorkflowReplayResult> ReplayWorkflows(
      IAsyncEnumerator<WorkflowHistory> histories, bool throwOnReplayFailure = true) { /*...*/ }

#endif
}
```

Notes:

* We have intentionally called this `WorkflowReplayer` in .NET since this kind of wordiness is clearer
* Will need to accept a core runtime in the options here, not sure if we want that as part of worker options or if
  replayer really needs its own options set that's 99% the same with worker. Maybe just a param.

## Data Conversion

Looks like:

```csharp
namespace Temporalio.Converters;

public record DataConverter(
    IPayloadConverter PayloadConverter,
    IFailureConverter FailureConverter,
    IPayloadCodec? PayloadCodec
)
{
    public static readonly DataConverter Default = new();

    public DataConverter() :
        this(new PayloadConverter(), new FailureConverter(), null)
    { }
}

public interface IPayloadConverter
{
    Temporalio.Api.Common.V1.Payload ToPayload(object value);

    object? ToValue(Type type, Temporalio.Api.Common.V1.Payload payload);
}

public interface IEncodingPayloadConverter
{
    string Encoding { get; }

    bool TryToPayload(object value, out Temporalio.Api.Common.V1.Payload payload);

    object? ToValue(Type type, Temporalio.Api.Common.V1.Payload payload);
}

public record PayloadConverter(IEnumerable<IEncodingConverter> EncodingConverters) : IPayloadConverter
{
    public PayloadConverter() : this(new IEncodingConverter[] {
        new BinaryNullConverter(),
        new BinaryPlainConverter(),
        new JsonProtoConverter(),
        new BinaryProtoConverter(),
        new JsonPlainConverter() }) { /*...*/ }

    public Temporalio.Api.Common.V1.Payload ToPayload(object value) { /*...*/ }

    object? ToValue(Type type, Temporalio.Api.Common.V1.Payload payload) { /*...*/ }
}

public class BinaryNullConverter : IEncodingPayloadConverter { /*...*/ }
public class BinaryPlainConverter : IEncodingPayloadConverter { /*...*/ }
public class JsonProtoConverter : IEncodingPayloadConverter { /*...*/ }
public class BinaryProtoConverter : IEncodingPayloadConverter { /*...*/ }
public class JsonPlainConverter : IEncodingPayloadConverter { /*...*/ }

public interface IFailureConverter
{
    Temporalio.Api.Failure.V1.Failure ToFailure(
        Exception exception, IPayloadConverter payloadConverter);

    Exception ToException(
        Temporalio.Api.Failure.V1.Failure failure, IPayloadConverter payloadConverter);
}

public record FailureConverter(bool EncodeCommonAttributes = false) : IFailureConverter
{
    public Exception ToException(Temporalio.Api.Failure.V1.Failure failure, IPayloadConverter payloadConverter) { /*...*/ }

    public Temporalio.Api.Failure.V1.Failure ToFailure(Exception exception, IPayloadConverter payloadConverter) { /*...*/ }
}

public interface IPayloadCodec
{
    Task<IEnumerable<Temporalio.Api.Common.V1.Payload>> Encode(
        IReadOnlyCollection<Temporalio.Api.Common.V1.Payload> payloads);

    Task<IEnumerable<Temporalio.Api.Common.V1.Payload>> Decode(
        IReadOnlyCollection<Temporalio.Api.Common.V1.Payload> payloads);
}

public record CompositePayloadCodec(IEnumerable<IPayloadCodec> Codecs) : IPayloadCodec
{
    public Task<IEnumerable<Temporalio.Api.Common.V1.Payload>> Decode(
        IReadOnlyCollection<Temporalio.Api.Common.V1.Payload> payloads) { /*...*/ }
    
    public Task<IEnumerable<Temporalio.Api.Common.V1.Payload>> Encode(
        IReadOnlyCollection<Temporalio.Api.Common.V1.Payload> payloads) { /*...*/ }
}

public static class ConverterExtensions
{
    public static Task<IEnumerable<Temporalio.Api.Common.V1.Payload>> ToPayloads(
        this IDataConverter converter,
        IReadOnlyCollection<object> values) { /*...*/ }

    // The types are intentionally separated from the payloads here because they
    // can be different sizes since a codec can decode into a different sized
    // set of payloads than it was given.
    public static Task<IEnumerable<object>> ToValues(
        this IDataConverter converter,
        IReadOnlyCollection<IEnumerable<Temporalio.Api.Common.V1.Payload>> payloads,
        IReadOnlyCollection<Type> types) { /*...*/ }

    public static Task<Exception> ToException(
        this IDataConverter converter,
        Temporalio.Api.Failure.V1.Failure failure) { /*...*/ }

    public static Task<Temporalio.Api.Failure.V1.Failure> ToFailure(
        this IDataConverter converter,
        Exception exception) { /*...*/ }

    public static T? ToValue<T>(this IPayloadConverter converter, Temporalio.Api.Common.V1.Payload payload) { /*...*/ }

    public static Task EncodeFailure(this IPayloadCodec codec, Temporalio.Api.Failure.V1.Failure failure) { /*...*/ }

    public static Task DecodeFailure(this IPayloadCodec codec, Temporalio.Api.Failure.V1.Failure failure) { /*...*/ }
}
```

Notes:

* Should we prepare for some kind of .NET sandbox now by changing `DataConverter`'s `IPayloadConverter PayloadConverter`
  to instead be a `Type PayloadConverterType`? (don't think we want generics there though)

## Exceptions

Looks like:

```csharp
namespace Temporalio.Exceptions;

public abstract class TemporalException : Exception
{
    internal TemporalException(string? message = null, Exception? inner = null) : base(message, inner) { /*...*/ }
}

public class FailureException : TemporalException
{
    internal FailureException(
        string? message = null,
        Exception? inner = null,
        Temporalio.Api.Failure.V1.Failure? failure = null) : base(message, inner) { /*...*/ }

    public Temporalio.Api.Failure.V1.Failure? Failure { get; private init; }
}

// Intentionally extensible
public class AppException : FailureException
{
    public AppException(IEnumerable<object>? details = null, string? type = null, bool nonRetryable = false)
    {
        Type = type;
        NonRetryable = nonRetryable;
    }

    public string? Type { get; protected init; }

    public bool NonRetryable { get; protected init; }

    public bool HasDetails { get { /*...*/ } }

    public int DetailCount { get { /*...*/ } }

    public T GetDetail<T>(int index = 0) { /*...*/ }

    public IEnumerable<object>? OutboundDetails { get; protected init; }

    public IReadOnlyCollection<Temporalio.Api.Common.V1.Payload>? InboundDetails { get; protected init; }
}

// Many more not listed
```

Notes:
* Several more not listed. We will also include non-failure exceptions (e.g. `WorkflowAlreadyStartedException`) here
  instead of in the client area. This namespace is the .NET equivalent of
  https://pkg.go.dev/go.temporal.io/api/serviceerror + https://pkg.go.dev/go.temporal.io/sdk/temporal wrt errors.
* `AppException` is not `ApplicationException` to avoid clash with `System.ApplicationException`
* `AppException` is the only inheritable exception
  * All abstract exceptions will have `internal` constructors and non-abstract ones will be `sealed`
* We have to differentiate outbound (converted) details and inbound (not converted) details since, like some other SDKs,
  we cannot convert this stuff until the type is provided to do so
  * We offer `GetDetail` for getting detail values. For outbound exceptions this attempts a cast. For inbound
    exceptions, this exception object will carry a converter with it and convert as requested

## Interceptors

For client, looks like:

```csharp
namespace Temporalio.Client.Interceptors;

public interface IClientInterceptor
{
#if NETCOREAPP3_0_OR_GREATER
    ClientOutboundInterceptor InterceptClient(ClientOutboundInterceptor next)
    {
        return next;
    }
#else
    ClientOutboundInterceptor InterceptClient(ClientOutboundInterceptor next);
#endif
}

public abstract class ClientOutboundInterceptor
{
    private readonly ClientOutboundInterceptor? next;

    protected ClientOutboundInterceptor(ClientOutboundInterceptor next)
    {
        this.next = next;
    }

    private protected ClientOutboundInterceptor() { }

    protected ClientOutboundInterceptor Next
    {
        get { return next ?? throw new InvalidOperationException("No next interceptor"); }
    }

    public virtual Task<WorkflowHandle<TResult>> StartWorkflowAsync<TResult>(StartWorkflowInput input) { /*...*/ }

    // Lots more
}

public record StartWorkflowInput(
    string Workflow,
    IEnumerable<object> Args,
    string ID,
    string TaskQueue,
    // Lots more
);
```

Notes:

* Worker interceptors look very similar, though they are in `Temporalio.Worker.Interceptors` and have
  `IWorkerInterceptor.InterceptActivity(ActivityInboundInterceptor)` and
  `IWorkerInterceptor.InterceptWorkflow(WorkflowInboundInterceptor)`
* Like Go and Python, if an interceptor provided to a client implements both `IClientInterceptor` _and_
  `IWorkerInterceptor`, it will be used for worker interception too without having to be separately provided (nice for
  things like OTel)
* Support for default iface impls in all but the oldest .NET versions
* Decided abstract with virtuals was a clearer abstraction for the logic of the interceptors than interfaces with
  default impls (also helps those really old .NET versions that don't have default interface impl support)

## Testing

Looks like:

```csharp
namespace Temporalio.Testing

public class ActivityEnvironment
{
    public ActivityInfo Info { get; set; }

    public Action<object[]> Heartbeater { get; set; }

    public CancellationTokenSource CancellationTokenSource { get; }

    public CancellationTokenSource WorkflowShutdownTokenSource { get; }

    public void Run(Action func) { /*...*/ }
    public void Run<T>(Action<T> func, T arg) { /*...*/ }
    public TResult Run<TResult>(Func<TResult> func) { /*...*/ }
    public TResult Run<T, TResult>(Func<T, TResult> func, T arg) { /*...*/ }

    public async Task RunAsync(Action func) { /*...*/ }
    public async Task RunAsync<T>(Action<T> func, T arg) { /*...*/ }
    public async Task<TResult> RunAsync<TResult>(Func<TResult> func) { /*...*/ }
    public async Task<TResult> RunAsync<TResult>(Func<Task<TResult>> func) { /*...*/ }
    public async Task<TResult> RunAsync<T, TResult>(Func<TResult> func, T arg) { /*...*/ }
    public async Task<TResult> RunAsync<T, TResult>(Func<Task<TResult>> func, T arg) { /*...*/ }
}

#if NETCOREAPP3_0_OR_GREATER
public class WorkflowEnvironment : IAsyncDisposable
#else
public class WorkflowEnvironment
#endif
{
    public static async Task<WorkflowEnvironment> StartLocal(WorkflowEnvironmentStartLocalOptions options) { /*...*/ }

    public static async Task<WorkflowEnvironment> StartTimeSkipping(WorkflowEnvironmentStartTimeSkippingOptions options) { /*...*/ }

    public WorkflowEnvironment(TemporalClient client) { /*...*/ }

    public TemporalClient Client { get; protected init; }

    public virtual Task Delay(int millisecondsDelay, CancellationToken? cancellationToken = null) { /*...*/ }

    public virtual Task Delay(TimeSpan delay, CancellationToken? cancellationToken = null) { /*...*/ }

    public virtual DateTime Now { get; }
    public virtual DateTime UtcNow { get; }

    public virtual bool SupportsTimeSkipping { get; }

    public virtual IDisposable AutoTimeSkippingDisabled() { /*...*/ }

    public virtual Task ShutdownAsync() { /*...*/ }

#if NETCOREAPP3_0_OR_GREATER
    public async ValueTask DisposeAsync() { /*...*/ }
#endif

    internal class EphemeralServerBased : WorkflowEnvironment
    {
        public EphemeralServerBased(TemporalClient client) : base(client) { /*...*/ }
    }
}
```

Notes:

* We call the method `ActivityEnvironment.Run` instead of `ActivityEnvironment.RunActivity` to make it clear that we
  accept any code/lambda, it does not have to be an `[Activity` method
* `WorkflowEnvironment` is `IAsyncDisposable` in all but the oldest .NET versions, which means it can be used like
  `await using (var env = await WorkflowEnvironment.StartLocal()) { ...` (or just in the function without a block)
* While it may seem unnecessary to build this now, it will be very helpful during tests of the framework itself. So we
  should go ahead and build it

## Runtime Support/Extensions

.NET provides several
[extensions to the runtime library](https://learn.microsoft.com/en-us/dotnet/standard/runtime-libraries-overview#extensions-to-the-runtime-libraries)
which many users use when making apps. We discuss here some of those patterns and how we can support those, either by
our existing design, or with helpers in a `Temporalio.Extensions` namespace.

With DI and configuration and such, this is very analogous to Spring Boot for Java.

### Serialization

https://learn.microsoft.com/en-us/dotnet/standard/serialization/

* We use `System.Text.Json` by default and therefore support all customization/approaches it provides
* Our JSON payload converters may offer easy approaches to customize options to create new converters

### Dependency Injection

https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection

* We have `Temporalio.Client.ITemporalClient` and `Temporalio.Client.ITemporalConnection` to allow DI for these impls
* Should we also do this for `Temporalio.Client.WorkflowHandle`? Is there value in injecting that?
* Since activity instances are instantiated by the user upon registration, the user can use DI when creating those
  classes to, say, inject a logger
  * We'll need an example showing this
* When we start the workflow implementation side, we may need to revisit how DI may help users without forcing it

### Configuration

https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration

* We support the https://learn.microsoft.com/en-us/dotnet/core/extensions/options pattern with all of our `Options`
  classes
  * Some of the options things like activities method references can't by loaded from a file, so we should take a look
    at helpers for converting activity strings to activity classes reflectively
  * We need a sample showing configuring workers via config file akin to Spring Boot
* See the host section for how it all may come together inside a worker service

### Logging

https://learn.microsoft.com/en-us/dotnet/core/extensions/logging

* Unfortunately there is no logging in the standard library for .NET, therefore in order to support this we'd have to
  add a dependency on https://www.nuget.org/packages/Microsoft.Extensions.Logging
* NuGet does not support optional dependencies
* Should we add the dependency?
  * For:
    * It's pretty common, e.g. Azure durable task framework has it (well, `Microsoft.Extensions.Logging.Abstractions`)
      but a really old version from 4 years ago
  * Against:
    * We don't like extra dependencies, even these tiny ones
    * We will have a rudimentary `Temporalio.ITemporalLogger` with a simple console implementation by default
      * Could have a separate `Temporalio.Extensions` project that had a `ITemporalLogger` impl for `ILogger`, but this
        is so simple it can just be a sample
  * Leaning towards "Against"

### HostBuilder and Worker Services

https://learn.microsoft.com/en-us/dotnet/core/extensions/generic-host and
https://learn.microsoft.com/en-us/dotnet/core/extensions/workers

* Same discussion around dependencies as logging, this would need `Microsoft.Extensions.Hosting`
* Our `Temporalio.Worker.TemporalWorker` is not a subclass of `BackgroundService` to avoid the dependency
  * `TemporalWorker.ExecuteAsync` matches `BackgroundService.ExecuteAsync` very intentionally, so this is incredibly
    easy for a user to create and we will of course have a sample

## General Decision Justifications/Discussion

#### Why method references instead of proxy lambdas

Some utilities like Azure Durable Entities support invoking a method on a proxied version of an item instead of just
referencing the method. There are pros and cons. To discuss, here are examples and cons of each approach:

##### With method references

```csharp
// Start a workflow
var handle = await client.StartWorkflowAsync(
    IMyWorkflow.Ref.RunAsync, "some arg", new(ID: "my-workflow-id", TaskQueue: "my-task-queue"));

// Send a signal
await handle.Signal(
    IMyWorkflow.Ref.SignalAsync, "some arg");

// Invoke activity from workflow (future guess)
await ExecuteActivity(
    MyActivities.Ref.Activity, "some arg", new(StartToCloseTimeout: TimeSpan.FromHours(5)));
```

Cons:

* You have to make a reference to the class whose methods you need to reference
* You can't have the handle typed with the workflow class
  * So for example you won't get a compile-time failure if you invoke a signal from some other workflow
  * With lambdas we might be able to have them typed though
* Can only support 0 or 1 parameters
  * Can technically add generic overloads for more parameters, but you have to stop somewhere
  * This is an inherent problem in .NET in several things and why you often see a dozen overloads for a method

##### With lambda

```csharp
// Start a workflow
var handle = await client.StartWorkflowAsync<IMyWorkflow>(
    myWf => myWf.RunAsync("some arg"), new(ID: "my-workflow-id", TaskQueue: "my-task-queue"));

// Send a signal
await handle.Signal(
    myWf => myWf.SignalAsync("some arg"));

// Invoke activity from workflow (future guess)
await ExecuteActivity<MyActivities>(
    myAct => myAct.Activity("some arg"), new(StartToCloseTimeout: TimeSpan.FromHours(5)));
```

Cons:

* Every method must be virtual or on an interface
  * Cannot proxy regular methods which is a bit off-putting. This works for Azure because they make you opt-in to the
    typed approach
    [by forcing interfaces](https://learn.microsoft.com/en-us/azure/azure-functions/durable/durable-functions-dotnet-entities#accessing-entities-through-interfaces) which we don't want to do
  * Cannot proxy static methods
    * We should support static activities, so you'd have method references anyways probably
* We cannot control what a user calls in the lambda
  * Would we prevent multiple proxied calls?
  * Even if we do provide a "must make one and only one proxied call", it's a runtime check not a compile-time one
* You cannot proxy static calls
  * We should support static activities, so you'd have method references anyways probably
* Not having lambdas as the last parameter is a bit rough looking sometimes

#### Why `Temporalio` namespace instead of `Temporal`?

* The NuGet `Temporal` package was already taken, and after discussion the team thought `Temporal` would accidentally
  encourage people to get the wrong package
* We do it in other SDKs where there are single-named packages

#### Why `Temporalio` namespace and not `Temporalio.Sdk` namespace?

* After team discussion, decided this is simpler even though we intentionally violate
  https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/names-of-namespaces

#### Why suffix all the async calls with "Async"?

* Literally a 50/50 decision at this point. Blog posts, projects, etc have been poured over and arguments can be
  provided for both ways
* Suffix was chosen because other similar projects in the space do and it became a "when in Rome" situation
* This proposal has gone back and forth on this and amended each way until we gave up and settled on "Async" suffix to
  feel familiar to .NET developers however ugly/unnecessary the suffix may be

#### Why suffix all async workflow/activity methods with "Async" and prefix all workflow interfaces with "I" in samples?

* Because we do it everywhere else

#### Why prefix TemporalConnection, TemporalClient, and TemporalWorker with "Temporal"?

* See
  https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/names-of-namespaces#namespaces-and-type-name-conflicts
* Not only are we avoiding name conflicts with the package, but also avoiding naming conflicts with users' other
  libraries
* This is standard practice in .NET, and of course this doesn't apply everywhere, just these three pieces that are most
  likely to be instantiated at a high level

#### Why have Temporalio.Client, Temporalio.Worker, Temporalio.Converters, and Temporalio.Exceptions as separate namespaces?

* While it'd be fairly normal to have all of these types just in the top-level `Temporalio` namespace in .NET, the list
  just grew too large
* For the dozen exceptions alone it became annoying and also tempting to put them as inner classes just to keep file
  count reasonable
* These are reasonable boundaries of separation
* We still will keep common pieces like `Runtime`, `WorkflowHistory`, `RetryOptions`, etc in the top-level `Temporalio`
  namespace

#### Why put interceptors in Temporalio.Client.Interceptors and Temporalio.Worker.Interceptors?

* The class count is too high for those input types and I didn't want huge inner classes
* It's a logical separation since most won't use interceptors
* .NET does not have circular import concerns. Like Java packages, namespaces of a common assembly can reference each
  other circularly

#### Why not an existing Rust-to-.NET helper library?

* There are none that meet our needs and are robust enough
  * https://github.com/ralfbiedert/interoptopus doesn't give much and has limitations
  * https://github.com/Diggsey/rnet has concerns on future support
* It's not that hard to make a C layer that .NET can use
  * But our use is too limited to make a general purpose open source bridging library other Rust+.NET devs can use
  * This bridge could be used via CGo and JNI too

#### Why not reuse the "Bridge FFI" already in SDK core?

* That crate made when working on a generic bridge solution
  * It used protos in/out for _all_ calls because a stretch goal of that project was "core remote". This is technically
    fine, but most C FFI can use structs which improves performance (though protos are still used as a common in/out in
    core)
* We want the bridge in the .NET repo since it's the only SDK using it
  * This allows more rapid iteration during development
  * If we do another SDK needing a C FFI layer, we should definitely move it back to core
  * Opened https://github.com/temporalio/sdk-core/issues/447 to delete the `bridge-ffi` crate
* A POC of this bridge has already been developed for .NET
  * The Rust/C side has nothing .NET specific though and can be repurposed