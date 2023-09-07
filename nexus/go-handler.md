# Temporal Go SDK - Nexus Handler

## Overview

An addition to the [Temporal Go SDK][temporal-go-sdk] that exposes the ability for users to handle Nexus API requests.

**Goals**

- Expose a simple, high level API for binding Nexus operations to common Temporal constructs
- Support for starting and canceling operations
- Support multi-tenant applications with minimal boilerplate

**Non-Goals**

- Support for getting an operation's result or info
- API definitions for other SDKs
- API for invoking Nexus calls - refer to the [Nexus Go SDK][nexus-go-sdk] for an out-of-workflow reference client
- Server implementation details
- Worker / server API contract
- Allow advanced users to implement Nexus inbound and outbound request proxies for cross-organization calls where
  data converters are not shared and data is not exposed to Temporal server.

  This will quickly become a requirement for production use cases, especially with Temporal Cloud's zero trust model. It
  will be addressed shortly after Nexus becomes available for preview.

> NOTE: These are non-goals for _this_ proposal, but they will be defined in follow up proposals / PRs.

## Background

Nexus is a thin protocol on top of HTTP, defined in [this spec][nexus-http-api]. Temporal serves as an HTTP proxy,
translating Nexus requests into tasks that can be polled on by an SDK worker on its configured task queue.
Due to the synchronous nature of HTTP, the generated tasks are not persisted, and require an available worker
to be processed.

The process of translating requests into tasks and delivering them to workers is out of scope for this proposal.

## SDK Additions

The Temporal Go SDK exposes a `Worker` interface that embeds a `Registry` interface defined as:

```go
type Registry interface {
	WorkflowRegistry
	ActivityRegistry
}
```

Add and embed a third registry type: `OperationRegistry` with the following method:

```go
type OperationRegistry interface {
	RegisterOperation(operation string, handler operation.Handler)
	// Alternative: get the operation name from handler.Name()
	// RegisterOperation(handler operation.Handler)
}
```

`operation.Handler` is an interface with a minimal definition of:

```go
package operation // go.temporal.io/sdk/operation

type Handler interface {
	StartOperation(context.Context, *StartOperationRequest) (OperationResponse, error)
	CancelOperation(context.Context, *CancelOperationRequest) error
	// Later we will add GetResult and GetInfo as well
}

// Maps almost 1:1 to the Nexus Go SDK StartOperationRequest, exposing HTTP header and body directly instead of the HTTP
// Request object.
type StartOperationRequest struct {
	Operation   string
	RequestID   string
	CallbackURL string

	URL    *url.URL
	Header http.Header
	Body   []byte
}

// Maps almost 1:1 to the Nexus Go SDK CancelOperationRequest, exposing HTTP header and body directly instead of the
// HTTP Request object.
type CancelOperationRequest struct {
	Operation   string
	OperationID string

	URL    *url.URL
	Header http.Header
}

type OperationResponse interface {
	// private methods
}

// Indicates that an operation completed successfully. Implements OperationResponse.
type OperationResponseSync struct {
	// Header to deliver in the HTTP response.
	Header http.Header
	// Body conveying the operation result.
	// If it is an io.Closer, it will be automatically closed by the framework.
	// Note that we accept a reader instead of bytes here to keep the future possiblity of supporting streaming of large
	// payloads.
	Body io.Reader
}

// Indicates that an operation has been accepted and will complete asynchronously. Implements OperationResponse.
type OperationResponseAsync struct {
	OperationID string
}
```

To minimize the amount of boilerplate required to map operations to common Temporal constructs, the SDK exposes default
handler implementations.

### Workflow Run

```go
package operation // go.temporal.io/sdk/operation

type WorkflowStartOptions struct {
	// Options to start the workflow with. TaskQueue defaults to the current worker's task queue.
	// The workflow ID used here will be returned as the operation ID by default.
	client.WorkflowStartOptions
	// Type of workflow to start.
	WorkflowType string
	// Input to provide to the workflow.
	Input        []any
	// TODO: Should Temporal Header be settable here?
}

// Returns a Handler that can maps and operation to a workflow that can be started and canceled.
// Handles HTTP request to payload deserialization for input of type `T`.
func NewWorkflowRunHandler[T any](func(context.Context, T, *StartOperationRequest) (*WorkflowStartOptions, error)) Handler
```

**Basic usage:**

```go
w.RegisterOperation("provision-cell", NewWorkflowRunHandler(
	func(ctx context.Context, input Input, request *StartOperationRequest) (*WorkflowStartOptions, error) {
		return &WorkflowStartOptions{
			Input:        []any{input},
			WorkflowType: "provision-cell",
			StartWorkflowOptions: StartWorkflowOptions{
				ID: fmt.Sprintf("%s-%s", request.Operation, input.CellID),
			},
		}, nil
	}))
```

### Workflow Query

```go
package operation // go.temporal.io/sdk/operation

type WorkflowQueryOptions struct {
	WorkflowID           string
	// Optionally expose RunID too
	QueryType            string
	QueryRejectCondition enums.QueryRejectCondition
	// Input to provide to the query.
	Input                []any
	// TODO: Should Temporal Header be settable here?
}

func NewWorkflowQueryHandler[T any](func(context.Context, T, *StartOperationRequest) (*WorkflowQueryOptions, error)) Handler
```

**Basic usage:**

```go
w.RegisterOperation("get-cell-status", NewWorkflowQueryHandler(
	func(ctx context.Context, input Input, request *StartOperationRequest) (*WorkflowQueryOptions, error) {
		return &WorkflowQueryOptions{
			Input:      []any{input},
			QueryType:  "get-cell-status",
			WorkflowID: fmt.Sprintf("%s-%s", "provision-cell", input.CellID),
		}, nil
	}))
```

### Workflow Signal

```go
package operation // go.temporal.io/sdk/operation

type WorkflowSignalOptions struct {
	WorkflowID           string
	// Optionally expose RunID too
	SignalType            string
	// Input to provide to the query.
	Input                []any
	// TODO: Should Temporal Header be settable here?
}

func NewWorkflowSignalHandler[T any](func(context.Context, T, *StartOperationRequest) (*WorkflowSignalOptions, error)) Handler
```

**Basic usage:**

```go
w.RegisterOperation("update-cell-config", NewWorkflowSignalHandler(
	func(ctx context.Context, input Input, request *StartOperationRequest) (*WorkflowSignalOptions, error) {
		return &WorkflowSignalOptions{
			Input:      []any{input},
			SignalType: "update-cell-config",
			WorkflowID: fmt.Sprintf("%s-%s", "provision-cell", input.CellID),
		}, nil
	}))
```

### Workflow Update

Not defined yet. We can easily support sync update, but async update would require more thought on the guarantees
Temporal provides for callback delivery on update completion.

### Multi-tenant handlers

This section introduces a couple of additional concepts, failing handler requests, and operation interceptors.

Handlers should be able to fail requests in a meaningful way, providing the proper HTTP response code to convey errors
such as bad request and unauthorized. To control request failure, handlers can return a `nexus.HandlerError` with an
HTTP status code and failure object.
Returning any other error from a handler should result in an internal server error and the error details omitted from
the response.

Interceptors are used to share logic across all registered operations. i.e, interceptors can enforce authorized access
to operations making them ideal for low boilerplate multi-tenant application development.

```go
package interceptor // go.temporal.io/sdk/interceptor

type OperationInboundInterceptor interface {
	StartOperation(ctx context.Context, request *StartOperationRequest) (StartOperationResponse, error)
	CancelOperation(ctx context.Context, request *CancelOperationRequest) error

	mustEmbedOperationInboundInterceptorBase()
}
```

**Example:**

```go
import (
  "github.com/nexus-rpc/go-sdk/nexus"
  "go.temporal.io/sdk/interceptor"
  "go.temporal.io/sdk/operation"
)

type operationAuthorizationInterceptor struct {
	interceptor.OperationInboundInterceptorBase
}

func (*operationAuthorizationInterceptor) CancelOperation(ctx context.Context, request *CancelOperationRequest) error {
	// Use the request headers to extract and authenticate the tenant.
	// Temporal may alter the received HTTP request, adding headers such as Temporal-Source-Namespace and X-Forwarded-For
	// that handlers can trust.
	tenantID, err := getTenantID(ctx, request.Header)
	if err != nil {
		return &nexus.HandlerError{StatusCode: http.StatusUnauthorized, Failure: &nexus.Failure{Message: "unauthorized"}}
	}
	// Enforce a specific pattern.
	if !strings.HasPrefix(request.OperationID, fmt.Sprintf("%s-%s-", request.Operation, tenantID)) {
		return &nexus.HandlerError{StatusCode: http.StatusUnauthorized, Failure: &nexus.Failure{Message: "unauthorized"}}
	}
	return nil
}

w.RegisterOperation("provision-cell", NewWorkflowRunHandler(
	func(ctx context.Context, input Input, request *StartOperationRequest) (*WorkflowStartOptions, error) {
		tenantID, err := getTenantID(ctx, request.Header)
		if err != nil {
			return nil, &nexus.HandlerError{StatusCode: http.StatusUnauthorized, Failure: &nexus.Failure{Message: "unauthorized access"}}
		}

		return &WorkflowStartOptions{
			Input:        []any{input},
			WorkflowType: "provision-cell",
			StartWorkflowOptions: StartWorkflowOptions{
				// Add the tenant ID as part of the workflow ID.
				// The returned ID is mapped directly to the operation ID, an interceptor can be used to manipulate it.
				ID: fmt.Sprintf("%s-%s-%s", request.Operation, tenantID, input.CellID),
			},
		}, nil
	}))
```

### Operation context

The context provided to `operation.Handler` methods can be used to extract the client, logger, metrics handler, and data
converter from the worker, similiarly to how the [activity package][activity-package] exposes similar methods.

```go
package operation // go.temporal.io/sdk/operation

func GetClient(context.Context) client.Client
func GetDataConverter(context.Context) converter.DataConverter
func GetLogger(context.Context) log.Logger
func GetMetricsHandler(context.Context) metrics.Handler
```

All of these methods panic if called outside of an operation handler.

[temporal-go-sdk]: https://github.com/temporal/sdk-go
[nexus-go-sdk]: https://github.com/nexus-rpc/sdk-go
[nexus-http-api]: https://github.com/nexus-rpc/api/TODO
[activity-package]: https://pkg.go.dev/go.temporal.io/sdk@v1.24.0/activity#pkg-functions
