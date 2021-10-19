# Go SDK Workflow Interceptor Updates and OpenTelemetry Tracing Support

This proposal is for updates to Go workflow interceptors with the following features:

* Support for and implementation of OpenTelemetry tracing
* Support idiomatic Go interceptor design
* Provide feature parity with Java SDK and other missing features (see https://github.com/temporalio/sdk-go/issues/529)
* Add activity interceptors
* Add client interceptors
* Make inbound interceptors future-proof for argument addition
* Support for using workflow/activity proto headers from interceptors
  * One notable use case for this is to support validation (e.g. authz) and erroring out based on workflow/activity
    header contents

**These updates are known to NOT be backwards-compatible**

## Interceptor Proposed Updates

### Interceptor

Currently does not exist.

Proposal:

```go
type Interceptor interface {
  ClientInterceptor
  WorkerInterceptor
}
```

There will be an `InterceptorBase` but embedding will not be required (unlike all other interfaces).

Why: This allows one to have a single interceptor for all. See later for explanation of worker and client interceptors.

### WorkerInterceptor

Current:

```go
type WorkflowInterceptor interface {
  InterceptWorkflow(/*...*/)
}
```

Proposal:

```go
type WorkerInterceptor interface {
  InterceptActivity(/*...*/)
  InterceptWorkflow(/*...*/)

  mustEmbedWorkerInterceptorBase()
}
```

There will also be a `WorkerInterceptorBase` which must be embedded. See later for explanation of forced embeds and
activity interceptors.

Why: Maps to what Java does.

### WorkerInterceptor.InterceptWorkflow

Current:

```go
InterceptWorkflow(info *WorkflowInfo, next WorkflowInboundInterceptor) WorkflowInboundInterceptor
```

Proposal:

```go
InterceptWorkflow(ctx Context, next WorkflowInboundInterceptor) WorkflowInboundInterceptor
```

Why: Callers can use the context to get workflow info in addition to other things (e.g. loggers, metricsm, etc). Also
using the context as the first parameter is good Go practice and allows for more contextual information to be provided
in the future.

### WorkflowXInterceptor

Proposal: Change the name from `WorkflowXCallsInterceptor` to `WorkflowXInterceptor`. Why: `Calls` just adds noise (more
accepted in Java, not Go).

### WorkflowInboundInterceptor.ExecuteWorkflow

Current:

```go
ExecuteWorkflow(ctx Context, workflowType string, args ...interface{}) []interface{}
```

Proposal:

```go
type WorkflowInput struct {
  Args []interface{}
}

ExecuteWorkflow(ctx Context, input *WorkflowInput) (interface{}, error)
```

Why:

* Workflow type can be derived from the context _or_ the info first given to `InterceptWorkflow`
  * We are currently not allowing workflow type to be changed here, but it has been mentioned and we can add that to
    `WorkflowInput` at a later time if necessary
* Workflows can only return a value + error or just an error and this makes it more explicit what the error is

### WorkflowInboundInterceptor.HandleSignal

Current:

```go
ProcessSignal(ctx Context, signalName string, arg interface{}) error
```

Proposal:

```go
type SignalInput struct {
  SignalName string
  Arg interface{}
}

HandleSignal(ctx Context, input *SignalInput) error
```

Also, this will be called to handle the signal with the last invocation in the chain passing the signal to the workflow.

Why:

* `HandleSignal` matches Java nomenclature and new behavior better
* Currently the sending of the signal to the handler is done after the interceptor not allowing the interceptor to
  actually intercept and alter/prevent the send. We will change to have the last interceptor do the actual send.
* We will need an integration test to confirm that this is invoked on start-with-signal workflow that has a sync receive
  as the first statement

### WorfkflowInboundInterceptor.HandleQuery

Current:

```go
HandleQuery(ctx Context, queryType string, args *commonpb.Payloads,
  handler func(*commonpb.Payloads) (*commonpb.Payloads, error)) (*commonpb.Payloads, error)
```

Proposal:

```go
type QueryInput struct {
  QueryType string
  Args []interface{}
}

HandleQuery(ctx Context, input *QueryInput) (interface{}, error)
```

Why:

* All other calls convert the payload outside of the interceptor call, this can too
* No need to pass a handler, that is just part of the last item in the interceptor chain (i.e. when calling next)

### WorkflowOutboundInterceptor

We can leave everything the way it is because, while it doesn't make the interceptor parameters future-proof with struct
wrappers, it mimics the actual calls that aren't going to have backwards-compatible alterations.

### WorkflowOutboundInterceptor.GetInfo

Current:

```go
GetWorkflowInfo(ctx Context) *WorkflowInfo
```

Proposal:

```go
GetInfo(ctx Context) *WorkflowInfo
```

Why: All other calls match `workflow` package, why not this?

Note: We need to make sure we document that this returns *workflow.Info since internal names can be confusing.

### WorkerInterceptor.InterceptActivity

Proposal:

```go
InterceptActivity(ctx context.Context, next ActivityInboundInterceptor) ActivityInboundInterceptor
```

Why: Mimics `InterceptWorkflow` but for activities.

### ActivityInboundInterceptor

Proposal:

```go
type ActivityInput struct {
  Args []interface{}
}

type ActivityInboundInterceptor interface {
  Init(outbound ActivityOutboundInterceptor) error

  ExecuteActivity(ctx context.Context, input *ActivityInput) (interface{}, error)

  mustEmbedActivityInboundInterceptorBase()
}
```

Also a `ActivityInboundInterceptorBase` implementation with expected delegation.

Why: Mimics `WorkflowInboundInterceptor` but for activities.

### ActivityOutboundInterceptor

Proposal:

```go
type ActivityOutboundInterceptor interface {
  GetInfo(ctx context.Context) ActivityInfo
  GetLogger(ctx context.Context) log.Logger
  GetMetricsScope(ctx context.Context) tally.Scope
  RecordHeartbeat(ctx context.Context, details ...interface{})
  HasHeartbeatDetails(ctx context.Context) bool
  GetHeartbeatDetails(ctx context.Context, d ...interface{}) error
  GetWorkerStopChannel(ctx context.Context) <-chan struct{}

  mustEmbedActivityOutboundInterceptorBase()
}
```

Also a `ActivityOutboundInterceptorBase` implementation with expected delegation.

Why:

* Mimics `WorkflowOutboundInterceptor` but for activities.

For discussion: `GetInfo` returns expensive copies because `activity.GetInfo` does. Is this ok? This is inconsistent
with workflow info which is a pointer.

### ClientInterceptor

Proposal:

```go
type ClientInterceptor interface {
  InterceptClient(next ClientOutboundInterceptor) ClientOutboundInterceptor

  mustEmbedClientInterceptorBase()
}
```

Why:

* This kinda mimics `WorkerInterceptor` calls, but note it only provides an outbound interceptor because all client
  calls are outbound by their nature so there is no inbound equivalent

### ClientOutboundInterceptor

Proposal:

```go
type ClientOutboundInterceptor interface {
  ExecuteWorkflow(ctx context.Context, options StartWorkflowOptions, workflow interface{}, args ...interface{}) (WorkflowRun, error)
  GetWorkflow(ctx context.Context, workflowID string, runID string) WorkflowRun
  SignalWorkflow(ctx context.Context, workflowID string, runID string, signalName string, arg interface{}) error
  SignalWithStartWorkflow(ctx context.Context, workflowID string, signalName string, signalArg interface{}, options StartWorkflowOptions, workflow interface{}, workflowArgs ...interface{}) (WorkflowRun, error)
  CancelWorkflow(ctx context.Context, workflowID string, runID string) error
  TerminateWorkflow(ctx context.Context, workflowID string, runID string, reason string, details ...interface{}) error
  GetWorkflowHistory(ctx context.Context, workflowID string, runID string, isLongPoll bool, filterType enumspb.HistoryEventFilterType) HistoryEventIterator
  CompleteActivity(ctx context.Context, taskToken []byte, result interface{}, err error) error
  CompleteActivityByID(ctx context.Context, namespace, workflowID, runID, activityID string, result interface{}, err error) error
  RecordActivityHeartbeat(ctx context.Context, taskToken []byte, details ...interface{}) error
  RecordActivityHeartbeatByID(ctx context.Context, namespace, workflowID, runID, activityID string, details ...interface{}) error
  ListClosedWorkflow(ctx context.Context, request *workflowservice.ListClosedWorkflowExecutionsRequest) (*workflowservice.ListClosedWorkflowExecutionsResponse, error)
  ListOpenWorkflow(ctx context.Context, request *workflowservice.ListOpenWorkflowExecutionsRequest) (*workflowservice.ListOpenWorkflowExecutionsResponse, error)
  ListWorkflow(ctx context.Context, request *workflowservice.ListWorkflowExecutionsRequest) (*workflowservice.ListWorkflowExecutionsResponse, error)
  ListArchivedWorkflow(ctx context.Context, request *workflowservice.ListArchivedWorkflowExecutionsRequest) (*workflowservice.ListArchivedWorkflowExecutionsResponse, error)
  ScanWorkflow(ctx context.Context, request *workflowservice.ScanWorkflowExecutionsRequest) (*workflowservice.ScanWorkflowExecutionsResponse, error)
  CountWorkflow(ctx context.Context, request *workflowservice.CountWorkflowExecutionsRequest) (*workflowservice.CountWorkflowExecutionsResponse, error)
  GetSearchAttributes(ctx context.Context) (*workflowservice.GetSearchAttributesResponse, error)
  QueryWorkflow(ctx context.Context, workflowID string, runID string, queryType string, args ...interface{}) (converter.EncodedValue, error)
  QueryWorkflowWithOptions(ctx context.Context, request *QueryWorkflowWithOptionsRequest) (*QueryWorkflowWithOptionsResponse, error)
  DescribeWorkflowExecution(ctx context.Context, workflowID, runID string) (*workflowservice.DescribeWorkflowExecutionResponse, error)
  DescribeTaskQueue(ctx context.Context, taskqueue string, taskqueueType enumspb.TaskQueueType) (*workflowservice.DescribeTaskQueueResponse, error)
  ResetWorkflowExecution(ctx context.Context, request *workflowservice.ResetWorkflowExecutionRequest) (*workflowservice.ResetWorkflowExecutionResponse, error)
  Close()

  mustEmbedClientOutboundInterceptorBase()
}
```

Matches `client.Client` interface (embed notwithstanding) by intention. There will be a `ClientOutboundInterceptorBase`.

Why:

* We could have just used the existing `Client` interface but that causes package dependency and doesn't allow us to
  grow just the interceptor
* Like other outbound interceptors, this does not follow Java in making every input param a struct for forward
  compatibility because if any of these signatures changed, so would their actual caller-visible counterparts which
  would be a bigger change

### ClientOptions and WorkerOptions

Currently there are no interceptors on the client options and only workflow interceptors on the worker options.

Proposal:

```go
type ClientOptions struct {
  // ...

  // Interceptors to apply to the client. Any interceptors that also implement Interceptor (meaning they implement
  // WorkerInterceptor in addition to ClientInterceptor) will be used for worker interception as well. When interceptors
  // are here and in worker options, these interceptors are applied first.
  Interceptors []ClientInterceptor
}
```

```go
type WorkerOptions struct {
  // ...

  // Interceptors to apply to the worker. Any interceptors that also implement Interceptor (meaning they implement
  // ClientInterceptor in addition to WorkerInterceptor) will be used for client interception as well. When interceptors
  // are here and in client options, the client interceptors are applied first.
  Interceptors []WorkerInterceptor
}
```

### Forced Base Embedding

Proposal: Force the base struct to be embedded in all interface implementations. This can be done via a private
interface method that is only implemented by the base struct.

Why: In the newer gRPC service interfaces this is done to allow interface additions to always be forward compatible. See
[this](https://github.com/grpc/grpc-go/blob/03ca7b7d00cada2ff8a3ea7348fe6c3a2b2ee4fb/examples/helloworld/helloworld/helloworld_grpc.pb.go#L52)
as an example.

#### Explanation of Forced Embeds

To explain this concept a little further, imagine there is an interface in a library you want to implement:

```go
type MyInterface interface {
  DoSomething() error
}

type MyInterfaceBase struct{}
func (MyInterfaceBase) DoSomething() error { return nil }
```

And you implement it but without embedding the base struct:

```go
type MyImpl struct{}
var _ otherlib.MyInterface = MyImpl{}
func (MyImpl) DoSomething() error { return nil }
```

Now if the library goes back and changes the interface to:

```go
type MyInterface interface {
  DoSomething() error
  DoAnotherThing() error
}

type MyInterfaceBase struct{}
func (MyInterfaceBase) DoSomething() error { return nil }
func (MyInterfaceBase) DoAnotherThing() error { return nil }
```

You'd upgrade the dependency and then your compilation would break making the library's interface alteration not as
compatible as it could be. But if the library had originally defined its interface and base as:

```go
type MyInterface interface {
  DoSomething() error
  mustEmbedBase()
}

type MyInterfaceBase struct{}
func (MyInterfaceBase) DoSomething() error { return nil }
func (MyInterfaceBase) mustEmbedBase() {}
```

Then you'd have _no choice_ but to embed `MyInterfaceBase`:

```go
type MyImpl struct{ otherlib.MyInterfaceBase }
// This will fail to compile if you hadn't done the embed
var _ otherlib.MyInterface = MyImpl{}
func (MyImpl) DoSomething() error { return nil }
```

So now, when the library adds a new method to the interface like:

```go
type MyInterface interface {
  DoSomething() error
  DoAnotherThing() error
  mustEmbedBase()
}

type MyInterfaceBase struct{}
func (MyInterfaceBase) DoSomething() error { return nil }
func (MyInterfaceBase) DoAnotherThing() error { return nil }
func (MyInterfaceBase) mustEmbedBase() {}
```

The library knows all implementations of the interface embedded the struct they had to for forwards compatibility and it
knows that nobody's compilation will fail because they didn't embed the base. This is what gRPC and other libraries are
starting to do to force forward compatibility of interfaces.

## Tracing and Context Propagation

Current:

* A concept called a context propagator handles marshalling to/from workflow and activity proto "headers" (a construct
  in the body not to be confused with actual HTTP headers)
* Client options accept an OpenTracing tracer
* An internal context propagator is creating for the OpenTracing tracer that marshals to/from a span context to a
  special key in the headers
* The tracer is sent all throughout the contextual work of workflows and activities so that spans can be created at
  different times

Proposal:

* A new ability to retrieve a mutable set of proto "headers" on the context will be made so that interceptors can set
  workflow/activity headers in either direction
  * Note, the reason this is on the context instead of the input is because it is contextual information that flows
    through the system instead of literal parameters. We do the same for other bits of contextual information.
* Internally, headers will be obtained from the context by the last interceptor
  * So headers are set on the context before interceptor invocation for mutation by interceptors
* `opentracing` and `opentelemetry` packages will be creating and have tracer interceptor implementations that
  intercept the same things that are intercepted for tracing today. The header marshaling will be:
  * Inbound `ExecuteActivity` and `ExecuteWorkflow` to unmarshal a span context from the header
  * Outbound `ExecuteActivity`, `ExecuteLocalActivity`, and `ExecuteChildWorkflow` to marshal the span context into the
    header
  * Client `ExecuteWorkflow` and `SignalWithStartWorkflow` to marshal the span context into the header
* At implementation time, special care must be taken to ensure continue-as-new is properly connected to the existing
  trace

```go
package interceptors

func WorkflowHeader(workflow.Context) map[string]*commonpb.Payload
func ActivityHeader(context.Context) map[string]*commonpb.Payload
```

These header calls retrieve the header for reading _and_ writing only calls that support a header. Otherwise they are
nil. This was originally just one call with a parameter of `interface { Value(interface{}) interface{} }` but it was
decided that was too complicated for users to understand that could be used for both contexts.

```go
package opentracing

func NewInterceptor(tracer opentracing.Tracer) interceptors.Interceptor
```

```go
package opentelemetry

func NewTracingInterceptor(tracer trace.Tracer) interceptors.Interceptor
```

For discussion:

* This effectively deprecates the `ClientOptions.Tracer` field, shall we remove it completely?
  * If not, should we gut the existing `opentracing` impl and have it default to this implementation (i.e. if
    `ClientOptions.Tracer` is present, implicitly wrap the client and add the interceptor)?
  * Yes, we can remove it
* This effectively deprecates `ContextPropagator`s, shall we remove them completely?
  * No, they should be left (but can be implemented as interceptors)
* Is a `tracing` package ok, or would we rather separate`opentracing` and `opentelemetry` packages?
  * We prefer separate packages
