# Go SDK Workflow Interceptor Updates and OpenTelemetry Tracing Support

This proposal is for updates to Go workflow interceptors with the following features:

* Support for and implementation of OpenTelemetry tracing
* Support idiomatic Go interceptor design
* Provide feature parity with Java SDK and other missing features (see https://github.com/temporalio/sdk-go/issues/529)
* Add activity interceptors
* Make inbound interceptors future-proof for argument addition
* Examples for altering headers both via interceptors and client wrappers

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

Why: Callers can use the context to get workflow info in addition to other things (e.g. loggers, metricsm, etc). Also
using the context as the first parameter is good Go practice and allows for more contextual information to be provided
in the future.

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
}

HandleSignal(ctx Context, input *SignalInput) error
```

Also, this will be called to handle the signal with the last invocation in the chain passing the signal to the workflow.

Why:

* `HandleSignal` matches Java nomenclature and new behavior better
* Currently the sending of the signal to the handler is done after the interceptor not allowing the interceptor to
  actually intercept and alter/prevent the send. We will change to have the last interceptor do the actual send.

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

### WorkflowOutboundCallsInterceptor.NewContinueAsNewError

Currently this doesn't exist. Proposal:

```go
NewContinueAsNewError(ctx Context, wfn interface{}, args ...interface{}) error
```

Why: This is needed for the later tracing piece that adds headers to the context.


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

Also a `ActivityInboundInterceptorBase` implementation with expected delegation.

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

For discussion: `GetInfo` returns expensive copies because `activity.GetInfo` does. Is this ok? This is inconsistent
with workflow info which is a pointer.

## Interceptor Possible Updates

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
* Would we want a `WorkerInterceptorBase` with default impls that return instances of `ActivityInboundInterceptorBase`
  and `WorkflowInboundInterceptorBase`? Why doesn't Java have this?

### ClientCallsInterceptor

This has intentionally been avoided because the same thing can be done just wrapping a client. For example, you can
have:

```go
type MyClient struct { client.Client }

func (m *MyClient) ExecuteWorkflow(
  ctx context.Context,
  options client.StartWorkflowOptions,
  workflow interface{},
  args ...interface{},
) (client.WorkflowRun, error) {
  // Change the headers (see tracing section)
  myHeaderVal, err := converters.GetDefaultDataConverter().ToPayload("myheaderval")
  if err != nil {
    return nil, err
  }
  interceptors.Header(ctx)["myheaderkey"] = myHeaderVal
  return m.Client.ExecuteWorkflow(ctx, options, workflow, args...)
}
```

If we must have such a thing, we can have:

```go
type ClientCallsInterceptor interface { client.Client }

type ClientCallsInterceptorBase struct { client.Client }
```

But it makes little sense.

Arguably were the Go SDK completely redesigned, the entire "interceptor" concept would be replaced with a more idiomatic
concept of "middleware" even though it'd behave the same way in practice but would be named a bit different so as not to
seem confusing that the last "interceptor" in the chain implements all the real business logic instead of just
"intercepting".

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
* A `tracing` package will be created with:
  * `WorkerInterceptor` implementations for OpenTracing and OpenTelemetry tracers
    * Wraps the same inbound/outbound calls in spans that are otherwise wrapped by the tracer today
    * On inbound `ExecuteActivity` and `ExecuteWorkflow` span context is unmarshaled from header
    * On outbound `ExecuteActivity`, `ExecuteLocalActivity`, `ExecuteChildWorkflow`, and `NewContinueAsNewError` span
      context is marshaled into header
  * `Client` implementations for OpenTracing and OpenTelemetry tracers
    * Wraps the same calls in spans that are otherwise wrapped by the tracer today
    * On `ExecuteWorkflow` and `SignalWithStartWorkflow` span context is marshaled into header

```go
package interceptors

// Header returns nil if this context does not have the header on it (meaning
// they cannot be mutated by an interceptor).
func Header(ctx interface { Value(interface{}) interface{} }) map[string]*commonpb.Payload
```

```go
package tracing

func NewOpenTracingClient(c client.Client, tracer opentracing.Tracer) client.Client
func NewOpenTracingInterceptor(tracer opentracing.Tracer) interceptors.WorkerInterceptor

func NewOpenTelemetryClient(c client.Client, tracer trace.Tracer) client.Client
func NewOpenTelemetryInterceptor(tracer trace.Tracer) interceptors.WorkerInterceptor
```

For discussion:

* Is the approach of `workflow.Header` and `activity.Header` acceptable or do we want to combine them somehow?
* This effectively deprecates the `ClientOptions.Tracer` field, shall we remove it completely?
  * If not, should we gut the existing `opentracing` impl and have it default to this implementation (i.e. if
    `ClientOptions.Tracer` is present, implicitly wrap the client and add the interceptor)?
* This effectively deprecates `ContextPropagator`s, shall we remove them completely?
* Is a `tracing` package ok, or would we rather separate`opentracing` and `opentelemetry` packages?
* We technically could make this a separate module if the dependencies were too onerous for those not wanting tracing,
  but it's probably fine in the primary module
* We could add a `InterceptClient(next client.Client) client.Client` to `WorkerInterceptor` and remove the concept of
  `NewXClient` above? Thoughts? (note Java separates client call interceptors and worker interceptors currently)