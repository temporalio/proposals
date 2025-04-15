# Python Nexus design proposal

This is an early-stage design document for how Nexus functionality will be exposed in the Nexus Python SDK and in the Temporal Python SDK. The design
is still evolving, and feedback is welcome.

The design proposed here is being prototyped in this draft PR:
[https://github.com/temporalio/samples-python/pull/174](https://github.com/temporalio/samples-python/pull/174)

# Introduction

A Nexus service is a collection of Nexus operations, each of which supports the four verbs `start`, `fetch_info`, `fetch_result`, and `cancel`.

On the handler side of Nexus, users need to be able to:

1. **Define a service interface**
    
    This will be consumed by caller code to create a type-safe client, and by the service implementation to verify that the interface has been implemented.
    
2. **Implement an operation in a service**

This document focuses on these two areas (they’re the most complex aspects of Nexus SDK design).

Note that this document discusses Temporal-specific Nexus at the end. Everything before that is intended to stand on its own, i.e. the part before the Temporal section is intended to make sense without any implication that Temporal is in the background.

# 1. Defining a service interface

The team writing the Nexus service will define the interface in Python (This Python definition will be the target of codegen from future Nexus service IDL).

The interface will be defined in a dataclass-like style [thanks @cretz for this idea]:

```python
import nexusrpc

@nexusrpc.service
class MyNexusService:
    echo: nexusrpc.Operation[EchoInput, EchoOutput]
    hello: nexusrpc.Operation[HelloInput, HelloOutput]
```

Note that:

- What the user actually writes here defines the operations as purely type-level constructs: the decorator creates `NexusOperation` instances at import time that can be referenced by the caller-side Nexus service client.

The interface will be used by the caller as follows:

```python
from my_nexus_service import EchoInput, EchoOutput, MyNexusService

@workflow.defn
class EchoCallerWorkflow:
    def __init__(self):
        self.nexus_client = NexusClient(
            MyNexusService,  # or string name "my-nexus-service",
            "my-nexus-endpoint-name",
            schedule_to_close_timeout=timedelta(seconds=30),
        )

    @workflow.run
    async def run(self, message: str) -> EchoOutput:
        return await self.nexus_client.execute_operation(
            MyNexusService.echo,
            EchoInput(message),
        )

```

**[ALTERNATIVES CONSIDERED]** One might consider using a traditional (`typing.Protocol` / `abc.ABC`) interface (as Java does). However, while the caller-side Nexus service client might conform to those signatures, the handler-side service implementation would not (see below, but for at least two reasons: (1) operations are not represented by their start methods but rather by nullary factory functions returning an operation instance, and (2) even if the handler-side signature were that of the start method, it contains an option container from the request that would be extraneous in an interface definition).

# 2. Implementing a Nexus operation

Traditionally, in order to define an RPC/HTTP handler, you specify a function to act as the handler, and you arrange for a service or operation instance with a lifetime equal to that of the server, containing state created at server-start time, to be in-scope in the function body. For Python examples, see [gRPC,](https://github.com/grpc/grpc/blob/4e9357bca1408596663a218c0c608a4c0560a867/examples/python/route_guide/route_guide_server.py#L65) [xmlrpc [stdlib]](https://docs.python.org/3/library/xmlrpc.server.html#simplexmlrpcserver-example), [starlette/FastAPI](https://www.starlette.io/applications/#storing-state-on-the-app-instance), [Django class-based-views](https://docs.djangoproject.com/en/5.1/topics/class-based-views/). So, a Python developer writing an RPC/HTTP handler will expect to write something like

```python
# This code (from Python gRPC docs) is not part of the proposal
class MyService:  # instantiated at server-start time
    def my_handler(self, my_input, context) -> MyResult: ...
```

However, unlike traditional RPC/HTTP handlers, a Nexus operation represents a long-running execution and must support three additional verbs (`get_info`, `get_result`, `cancel`), and must support `start` returning both synchronously and asynchronously (including making that decision at request-handling time).

## 2a. Fully manual class-based operation definition

The “fully manual” way we will support this in Nexus Python is that a user will define a class for the service, and a class for each operation.

**[ALTERNATIVES CONSIDERED]** None. Giving the user the option to define classes at both levels for maximum implementation flexibility is the natural choice for Python (as it was in Java).

```python
import nexusrpc.handler

@nexusrpc.handler.service(interface=interface.MyNexusService, name="my-service")  # import-time check that interface was implemented
class MyNexusService: # instantiated when instantiating worker
    # User is free to define custom constructor

    @nexusrpc.handler.operation(name="my-invalid-python-identifier")
    def echo(self) -> nexusrpc.handler.Operation[EchoInput, EchoOutput]:  # typing.Protocol interface
        # Factory called when instantiating worker
        return EchoOperation()  # User can pass anything to operation constructor

class EchoOperation: # interface declaration optional; see below
    # User is free to define custom constructor

    async def start(self, input: EchoInput, options: nexusrpc.handler.StartOperationOptions) -> EchoOutput:
        return EchoOutput(input.message)

    async def fetch_info(self, token: str, options: nexusrpc.handler.FetchOperationInfoOptions) -> nexusrpc.handler.OperationInfo:
        raise NotImplementedError

    async def fetch_result(self, token: str, options: nexusrpc.handler.FetchOperationResultOptions) -> EchoOutput:
        raise NotImplementedError

    async def cancel(self, token: str, options: nexusrpc.handler.CancelOperationOptions) -> None:
        raise NotImplementedError
```

- User chooses whether to implement any verb other than `start`. When `start` always returns synchronously (as here), the other verbs will typically not be used, but the spec doesn’t rule it out.

Here’s what Temporal worker start-time might look like:

```python
worker = Worker(
    client,
    task_queue=task_queue,
    workflows=[HelloWorkflow],
    # User has defined custom service and operation constructors,
    # passing the service instance or the db client through
    # to give verb handlers access to this db client
    nexus_services=[MyNexusService(db_client=MyDBClient.connect(...))],
)
await worker.run()
```

An operation must implement the `nexusrpc.handler.Operation` interface:

```python
class Operation(Protocol, Generic[I, O]):
    # start either returns the result synchronously, or returns an operation token. Which path is
    # taken may be decided at operation handling time.
    async def start(self, input: I, options: StartOperationOptions) -> Union[O, StartOperationResult]: ...
    async def fetch_info(self, token: str, options: FetchOperationInfoOptions) -> OperationInfo: ...
    async def fetch_result(self, token: str, options: FetchOperationResultOptions) -> O: ...
    async def cancel(self, token: str, options: CancelOperationOptions) -> None: ...

```

These signatures most closely follow Go in that the primary input (start payload or token) is always pulled out as a separate parameter, and options structs contain everything relevant from the Nexus request.

- `StartOperationOptions`
    
    ```python
    @dataclass
    class StartOperationOptions:
        """Options passed by the Nexus caller when starting an operation."""
    
        headers: dict[str, str] = field(default_factory=dict)
    
        # A callback URL is required to deliver the completion of an async operation. This URL should be
        # called by a handler upon completion if the started operation is async.
        callback_url: Optional[str] = None
    
        # Optional header fields set by the caller to be attached to the callback request when an
        # asynchronous operation completes.
        callback_header: dict[str, str] = field(default_factory=dict)
    
        # Request ID that may be used by the server handler to dedupe a start request.
        # By default a v4 UUID will be generated by the client.
        request_id: Optional[str] = None
    
        # Links contain arbitrary caller information. Handlers may use these links as
        # metadata on resources associated with an operation.
        links: list[Link] = field(default_factory=list)
    
    ```
    

`typing.Protocol` provides structural typing: static type checkers will verify at *usage sites* that the operation implements the `nexusrpc.handler.Operation` interface correctly. The user may optionally choose to inherit from the interface, which gives in-situ static verification of the operation definition itself (although, for VSCode’s popular Pyright type-checker, only when set to the non-default strict mode):

```python
class EchoOperation(nexusrpc.handler.Operation[EchoInput, EchoOutput]):
    ...
```


## 2b. Convenience utilities for shorthand operation definition

In a way, this is the most interesting design question. While it’s true that in general, Nexus operations must support four verb handlers with custom implementations, in practice, If you’re implementing an always-sync operation, you probably don’t need to implement any verb other than `start`. (Temporal-specific Nexus is relevant here too; we’ll discuss it below).

What’s needed here is a way to define a service along with its operations “in one go”. Probably as one service class, but not with one class per operation. This will suffice for most always-sync operations, and it will serve the community well in pedagogical contexts.

So, recall the familiar Python options linked above:  [gRPC,](https://github.com/grpc/grpc/blob/4e9357bca1408596663a218c0c608a4c0560a867/examples/python/route_guide/route_guide_server.py#L65) [xmlrpc [stdlib]](https://docs.python.org/3/library/xmlrpc.server.html#simplexmlrpcserver-example), [starlette/FastAPI](https://www.starlette.io/applications/#storing-state-on-the-app-instance), [Django class-based-views](https://docs.djangoproject.com/en/5.1/topics/class-based-views/). Python programmers are accustomed to implementing an operation handler as a method on some sort of service class: 

```python
# This code (from Python gRPC docs) is not part of the proposal
class MyService:  # instantiated at server-start time
    def my_handler(self, my_input, context) -> MyResult: ...
```

In addition to the fully manual style, we’ll support defining Nexus operations like in traditional RPC/HTTP services: by implementing the `start` handler as a method on the *service*:

```python
@nexusrpc.handler.service(interface=interface.MyNexusService)
class MyNexusService:
    # User can pass anything to service constructor at worker-start time

    @nexusrpc.handler.sync_operation  # decorator returns factory method: (service) -> Operation 
    async def echo(self, input: EchoInput, _: nexusrpc.handler.StartOperationOptions) -> EchoOutput:
        return EchoOutput(input.message)
        
    @nexusrpc.handler.sync_operation
    async def another_op(self, input: AnotherInput, _: nexusrpc.handler.StartOperationOptions) -> AnotherOutput:
        return AnotherOutput(input.message)
 
```

For comparison, here’s the “fully manual” style again:

```python
@nexusrpc.handler.service(interface=interface.MyNexusService)
class MyNexusService:
    # User can pass anything to service constructor at worker-start time

    @nexusrpc.handler.operation
    def echo(self) -> nexusrpc.handler.Operation[EchoInput, EchoOutput]:
        return EchoOperation()  # user can pass anything to operation constructor at worker-start time
        
    @nexusrpc.handler.operation
    def another_op(self) -> nexusrpc.handler.Operation[AnotherInput, AnotherOutput]:
        return AnotherOperation()

class EchoOperation:
    async def echo(self, input: EchoInput, _: nexusrpc.handler.StartOperationOptions) -> EchoOutput:
        return EchoOutput(input.message)
    
class AnotherOperation:
    async def another_op(self, input: AnotherInput, _: nexusrpc.handler.StartOperationOptions) -> AnotherOutput:
        return AnotherOutput(input.message)

```

Note that:

- In both styles, the `start` handler has access to shared state created at Worker-start time.
- In the “fully manual” case, this shared state (`self`) is an operation instance (the user may have chosen to also make the service instance accessible from operation verb handlers)
- In the shorthand form, the shared state (`self`) is the service instance; a user using this definition style has no access to an operation instance, as in Go and Java.
- In both cases, the signatures written by the user are non-magical and completely explicit; they’ve chosen to define the `start` handler as a method on an operation/service class respectively.
- In the shorthand form, the decorator takes in the `start` handler method and returns a factory method `(Service) -> Operation` (that factory method takes care of creating an operation with the specified start method). Thus at run-time, the method on their service has a signature that differs from what they wrote under the decorator. Decorators in Python are used to effect fairly radical transformations: for example `@property`, or `@contextlib.contextmanager` in the standard library. But the main point in defense of the radicalness of this decorator transformation is that the user is not expected to call this method: it is called by the framework.
- The decorator propagates type annotations on the start method defined on the service to become run-time type annotation objects on the methods defined on the operation [[nexus-sdk PR](https://github.com/nexus-rpc/sdk-python/blob/e318efeb5b615a7dab916af1c5f01fe97ffff841/src/nexusrpc/handler.py#L294), [sdk-python PR](https://github.com/temporalio/sdk-python/blob/08430098aac4d92c3744b1245c5585819abadad3/temporalio/nexus/handler.py#L155-L169)]. This allows, e.g. a Nexus worker to instantiate the correct Python type from payloads received over the wire.

**[ALTERNATIVES CONSIDERED]**

See table below. Go uses an operation constructor that takes in an anonymous function, and Java retains the nullary factory function signature that all operations have, and uses an operation constructor that takes in an anonymous function.

The thing to note here is that in Python, the body of an anonymous function must be an expression; statement-based blocks are not supported. So the start method is definitely going to be an `async def` somewhere. If we wanted to follow Java, it would look something like

```python
@nexusrpc.handler.service(interface=interface.MyNexusService)
class MyNexusService:
    @nexusrpc.handler.operation
    def echo(self) -> nexusrpc.handler.Operation[EchoInput, EchoOutput]:
        async def start(input: EchoInput, _: StartOperationOptions) -> EchoOutput:
            # ...
            # ... many lines of user application logic
            # ...
            return EchoOutput(input.message)

        return SyncOperation(start)
```

This isn’t attractive or Pythonic. Firstly, inline function `def`s, where necessary, should be short in Python; our users shouldn’t be forced to implement their own complex application logic in a function `def` inlined in a method body. Secondly, users are going to want to give `start` a `self` first parameter, but having that together with the service instance `self` that it’s closing over is much too confusing. Even if they get the `self`-lessness right, it would leave the `start` method defined inline not matching the signature that it “normally” has when defined on an operation class.

<img width="1314" alt="Image" src="https://github.com/user-attachments/assets/6c2aee0a-f1be-47ed-bfb5-8e738304a418" />


# Temporal Nexus

Currently, the SDK functionality that we’re implementing related to Temporal is (a) the ability for workflow callers to start, cancel, and receive the results from Nexus operations, and (b) on the handler side, a Nexus worker that receives (non-durable) Nexus tasks and routes them to the requested verb handler for the requested operation in the requested service.

The operations may be implemented as described above (although with support for `start` and `cancel` only; status is obtained from caller-side in-workflow futures, and async results are delivered via the Nexus protocol callback, which is a purely server-side concern).

Alternatively, the author of a Temporal Nexus service may choose to define an always-async operation backed by a Temporal execution primitive. Workflow is the only such backing primitive we will launch with, but we plan to offer operations backed by updates, signals, and probably our top-level activity/task and other future features, when they exist.

It’s the “always-async operation backed by a Temporal execution primitive” that we’re discussing in this section. We’re going to provide a convenience shorthand, analogous to the one above for defining sync operations, that implements a workflow-backed operation in an opinionated way. For users who want an unopinionated interaction with workflows and other Temporal primitives, a Temporal client will be available via a `ContextVar` in the vanilla `start` methods and they can do whatever they want with it, as long as they return their result synchronously (this has a `10s` limit). In contrast, our utility will do the right thing w.r.t. e.g. request-ID-based deduplication, and will be the only way to implement an arbitrary-duration async operation in a Temporal Nexus service.

The proposal here follows the  [2b. Convenience utilities for shorthand operation definition](#2b-convenience-utilities-for-shorthand-operation-definition) `@nexusrpc.handler.sync_operation` decorator above:

```python
@nexusrpc.handler.service(interface=interface.MyNexusService)
class MyNexusService:
    @temporalio.nexus.handler.workflow_operation
    async def hello(
        self, input: HelloInput, options: nexusrpc.handler.StartOperationOptions
    ) -> nexusrpc.handler.StartOperationResult[HelloOutput]:
        workflow_id = my_get_workflow_id(input)
        return await temporalio.nexus.handler.start_workflow(
            HelloWorkflow.run, input, workflow_id, options
        )

```

Note that:

- As with `@nexusrpc.handler.sync_operation`, users define their workflow-backed operation by implementing the `start` handler as a method on the service.
- As with `@nexusrpc.handler.sync_operation`, the decorator takes in the start method and returns a factory method.
- This time, the decorator also injects an appropriate `cancel` implementation (extract the workflow ID from the token (we encoded it) and use it to cancel the workflow)

[[sdk-python PR](https://github.com/temporalio/sdk-python/blob/08430098aac4d92c3744b1245c5585819abadad3/temporalio/nexus/handler.py#L155-L169)]

### I’ve been using the shorthand style. How do I implement a custom `cancel` handler?

Create a fully manual operation class, and move your `start` method from the service to your operation class.


**[ALTERNATIVES CONSIDERED]**

Another possibility is this, which the Temporal Python SDK exemplifies with its update validators:

```python
@nexusrpc.handler.service(interface=interface.MyNexusService)
class MyNexusService:
    @temporalio.nexus.handler.workflow_operation
    async def hello(
        self, input: HelloInput, options: nexusrpc.handler.StartOperationOptions
    ) -> nexusrpc.handler.StartOperationResult[HelloOutput]:
        # workflow start implementation
    
    # Not required: workflow_operation provides a default cancel implementation
    @hello.cancel
    async def cancel_hello(self, token: str, options: nexusrpc.handler.CancelOperationOptions) -> None:
        # workflow cancel implementation

```
