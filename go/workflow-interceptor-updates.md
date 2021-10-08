# Go SDK Workflow Interceptor Updates and OpenTelemetry Tracing Support

This proposal is for updates to Go workflow interceptors with the following features:

* Support for and implementation of OpenTelemetry tracing
* Support idiomatic Go interceptor design
* Provide feature parity with Java SDK and other missing features (see https://github.com/temporalio/sdk-go/issues/529)
* Add activity interceptors
* Make inbound interceptors future-proof for argument addition

**These updates are known to NOT be backwards-compatible**

## Interceptor Proposed Updates

### WorkflowInterceptor.InterceptWorkflow

Current:

```go
InterceptWorkflow(info *WorkflowInfo, next WorkflowInboundCallsInterceptor) WorkflowInboundCallsInterceptor
```

Proposal:

```go
InterceptWorkflow(ctx Context, next WorkflowInboundCallsInterceptor) WorkflowInboundCallsInterceptor
```

Why: Callers can use the context to get workflow info.

### WorkflowXCallsInterceptor

Proposal: Change the name to `WorkflowXInterceptor`. Why: `Calls` just adds noise (more accepted in Java, not Go).

### WorkflowInboundCallsInterceptor.ExecuteWorkflow

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
* Workflows can only return a value + error or just an error and this makes it more explicit what the error is

### WorkflowInboundCallsInterceptor.ProcessSignal

Current:

```go
ProcessSignal(ctx Context, signalName string, arg interface{}) error
```

Proposal:

```go
type SignalInput struct {
  SignalName string
  Arg interface{}
  EventID string
}

HandleSignal(ctx Context, input *SignalInput) error
```

Also, this will be called to handle the signal with the last invocation in the chain passing the signal to the workflow.

Why:

* `HandleSignal` matches Java nomenclature and new behavior better
* Currently sending is sent separate and async, so the current version doesn't wrap the handling. Instead this will be
  part of the async call and documentation will make clear it needs to be safe for concurrent invocation.
* The Java version provides the event ID so we will too

### WorfkflowInboundCallsInterceptor.HandleQuery

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

### WorkflowOutboundCallsInterceptor

We can leave everything the way it is because, while it doesn't make the interceptor parameters future-proof with struct
wrappers, it mimics the actual calls that aren't going to have backwards-compatible alterations.

### WorkflowOutboundCallsInterceptor.GetWorkflowInfo

Current:

```go
GetWorkflowInfo(ctx Context) *WorkflowInfo
```

Proposal:

```go
GetInfo(ctx Context) *WorkflowInfo
```

Why: All other calls match `workflow` package, why not this?

### ActivityInterceptor

Proposal:

```go
type ActivityInterceptor interface {
	InterceptActivity(ctx context.Context, next ActivityInboundInterceptor) ActivityInboundInterceptor
}
```

Why: Mimics `WorkflowInterceptor` but for activities.

### ActivityInboundInterceptor

Proposal:

```go
type ActivityInput struct {
  Args []interface{}
}

type ActivityInboundInterceptor interface {
	Init(outbound ActivityOutboundInterceptor) error

	ExecuteActivity(ctx context.Context, input *ActivityInput) (interface{}, error)
}
```

Why: Mimics `WorkflowInboundInterceptor` but for activities.

### ActivityOutboundInterceptor

Proposal:

```go
type ActivityOutboundInterceptor interface {
  GetInfo(ctx context.Context) ActivityInfo
  GetLogger(ctx Context) log.Logger
  GetMetricsScope(ctx Context) tally.Scope
	RecordHeartbeat(ctx context.Context, details ...interface{})
  HasHeartbeatDetails(ctx context.Context) bool
  GetHeartbeatDetails(ctx context.Context, d ...interface{}) error
  GetWorkerStopChannel(ctx context.Context) <-chan struct{}
}
```

Also a `ActivityOutboundInterceptorBase` implementation with expected delegation.

Why:

* Mimics `WorkflowOutboundInterceptor` but for activities.

For discussion `GetInfo` returns expensive copies because `activity.GetInfo` does. Is this ok? This is inconsistent with
workflow info which is a pointer.

## Interceptor Possible Updates

### Forced Base Embedding

Proposal: Force the base struct to be embedded in all interface implementations. This can be done via a private
interface method that is only implemented by the base struct.

Why: In the newer gRPC service interfaces this is done to allow interface additions to always be forward compatible. See
[this](https://github.com/grpc/grpc-go/blob/03ca7b7d00cada2ff8a3ea7348fe6c3a2b2ee4fb/examples/helloworld/helloworld/helloworld_grpc.pb.go#L52)
as an example.

### WorkerInterceptor

Current:

```go
type WorkflowInterceptor interface {
	InterceptWorkflow(info *WorkflowInfo, next WorkflowInboundCallsInterceptor) WorkflowInboundCallsInterceptor
}
```

Proposal:

```go
type WorkerInterceptor interface {
  InterceptActivity(ctx context.Context, next ActivityInboundInterceptor) ActivityInboundInterceptor
  InterceptWorkflow(ctx Context, next WorkflowInboundInterceptor) WorkflowInboundInterceptor
}
```

Then change `WorkerOptions.WorkflowInterceptorChainFactories []WorkflowInterceptor` to
`WorkerOptions.Interceptors []WorkerInterceptor`.

For discussion:

* This maps to what Java does
* Would we want a `WorkerInterceptorBase` with default impls? Why doesn't Java have this?

## OpenTelemetry Implementation

Proposal in separate `opentelemetry` package:

```go
// Added to existing internal.ClientOptions struct
type ClientOptions struct {
  OpenTelemetry OpenTelemetryClientOptions
}

type OpenTelemetryClientOptions struct {
  Enabled bool
  Options []otelgrpc.Option
}

// Wraps only the calls implemented in spans, delegates the rest
func NewTracingClient(opts) client.Client

func (cl) ExecuteWorkflow(ctx context.Context, options client.StartWorkflowOptions, workflow interface{}, args ...interface{}) (client.WorkflowRun, error)
func (cl) SignalWithStartWorkflow(ctx context.Context, workflowID string, signalName string, signalArg interface{},
	options client.StartWorkflowOptions, workflow interface{}, workflowArgs ...interface{}) (client.WorkflowRun, error)

// Wraps only the calls implemented in spans, delegates the rest
func NewTracingActivityInterceptor(opts) interceptors.ActivityInterceptor
func NewTracingWorkflowInterceptor(opts) interceptors.WorkflowInterceptor

func (i) InterceptActivity(ctx context.Context, next interceptors.ActivityInboundInterceptor) interceptors.ActivityInboundInterceptor
func (i) InterceptWorkflow(ctx workflow.Context, next interceptors.WorkflowInboundInterceptor) interceptors.WorkflowInboundInterceptor

func (aii) ExecuteActivity(ctx context.Context, input *interceptors.ActivityInput) (interface{}, error)

func (wii) ExecuteWorkflow(ctx workflow.Context, input *interceptors.WorkflowInput) (interface{}, error)

func (woi) ExecuteActivity(ctx workflow.Context,activityType string, args ...interface{}) workflow.Future
func (woi) ExecuteLocalActivity(ctx workflow.Context, activityType string, args ...interface{}) workflow.Future
func (woi) ExecuteChildWorkflow(ctx workflow.Context, childWorkflowType string, args ...interface{}) workflow.ChildWorkflowFuture
```

For discussion:

* This matches Java feature-wise, is this enough? Does Java impl not trace anything we might want to?
* Do we want to do anything with the existing `opentracing` stuff as part of this?
