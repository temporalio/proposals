# Python SDK - Phase 1

The Python SDK will be implemented in three loosely defined phases:

* Phase 1 - Initial project, activity worker, and client
* Phase 2 - Workflow worker, local activities, async activity completion, etc
* Phase 3 - Deterministic workflow sandbox, replayer, test suite (some parts may be combined with phase 2)

This proposal is for phase 1. It is intentionally loosely defined and all aspects are subject to discussion/change.

## Overview

The Python SDK will be backed by [sdk-core](https://github.com/temporalio/sdk-core), utilizing a bridge based on
[PyO3](https://github.com/PyO3/PyO3) similar to `sdk-typescript`'s `neon`-based bridge.

The high-level goals for the Python SDK are:

* Be as simple as possible from a caller POV
* Be as lightweight as reasonable with regards to dependencies
* Be reasonably flexible with reasonable defaults
* Support only Python >= 3.7
* Be friendly to REPL/interpreter use cases

The stack/approach looks like:

* Python >= 3.7 (so may need `typing_extension` for things like `ParamSpec`)
* Poetry packaging, black formatting
  * Pipenv originally considered
* PyO3 + sdk-core
* asyncio direct (i.e. no need for anyio-style wrapper)
* Type annotations everywhere
* Decorator-based activity and workflow definitions

An example of a client (intentionally missing _a lot_ of features):

```python
import temporalio

async def main():
    client = await temporalio.Client.create("localhost:7233", namespace="MyNamespace")
    result = await client.execute_workflow("MyWorkflow", "arg1", id="someid", task_queue="somequeue")
    print("Result", result)
```

An example of an activity and registration (also missing a lot of features):

```python
import temporalio

def say_hello(name: str) -> str:
  return f"Hello, {name}!"

async def main():
    core = await temporalio.Core.create("localhost:7233", namespace="MyNamespace")
    worker = temporalio.Worker(core, task_queue="somequeue")
    worker.register_activity(say_hello)
    await worker.run()
```

## API Definitions

A lot of loosely-defined API definitions are below. They are intentionally lacking details.

High-level notes:

* For demonstration/simplicity here we are leaving off a lot of proper typings (e.g. `Optional`) that the real version
  will have
* We leave off a lot of options on calls for this high-level proposal
* We are not using proper function documentation, but rather inline comments for easier discussion
* **NOTE: These will have proper docs and types when developed!**

### Client

Exported from `temporalio` (but probably in `temporalio/client/client.py`, exported from `temporalio.client` then
exported from `temporalio`):

```python
class Client:
    @staticmethod
    async def create(
        addr: str,
        *,
        namespace: str = "default",
        default_task_queue: str = None,
        identity: str = None
        # ... additional options omitted for brevity
    ) -> Client:
        # Actually dials gRPC here
        pass

    def __init__(
        self,
        service: workflowservice.WorkflowService,
        *,
        namespace: str = "default",
        default_task_queue: str = None,
        identity: str = None
        # ... additional options omitted for brevity
    ) -> None:
        pass

    # Raw gRPC service
    @property
    def service(self) -> workflowservice.WorkflowService:
        pass

    async def start_workflow(
        self,
        workflow: str,
        *args,
        id: str = None,
        task_queue: str = None,
        retry_policy: RetryPolicy = None,
        # Note, we are embedding signal-with-start in here
        start_signal: str = None,
        start_signal_args=[],
        # ... additional options omitted for brevity
    ) -> WorkflowHandle[Any]:  # This result defines __await__ among other things
        pass

    # In a future phase:
    # @overload
    # async def start_workflow(workflow: Callable[P, T], *args: P.args, ...) -> WorkflowHandle[T]
    #
    # @overload
    # async def start_workflow(workflow: T, *args) -> T

    # Just a wrapper for start workflow that awaits the handle
    async def execute_workflow(
        self,
        workflow: str,
        *args,
        # ... additional options omitted for brevity
    ) -> Any:
        return await (await self.start_workflow(workflow, *args))

    # Does not validate whether a workflow exists
    def get_workflow_handle(
        workflow_id: str,
        run_id: str = None
        # ...
    ) -> WorkflowHandle[Any]:
        pass


class WorkflowHandle(Generic[T]):
    def __init__(
        self,
        client: Client,
        workflow_id: str,
        *,
        run_id: str = None
        # ...
    ) -> None:
        pass

    def __await__(self) -> T:
        pass

    async def cancel(self):
        pass

    async def describe(self):
        pass

    async def query(self, name: str, *args):
        pass

    async def signal(self, name: str, *args):
        pass

    async def terminate(self, *, reason: str = None):
        pass
```

Notes:

* We are intentionally defining a `Client` instead of a `WorkflowClient` since this will be general purpose
  * Having a general purpose client keeps things simple, but at least for now I can't see defining any more than the two
    methods and the one property
  * We could make an abstract base class if we want for typing/purposes that just has the `service` property
    unimplemented
* We call it `start_workflow` instead of just `start` to be clearer
* We have an `execute_workflow` to combine start + result waiting
* We have embedded `start_signal` and `start_signal_args` as parameters, so if the former is present we will perform a
  signal with start. Is this ok?
  * This is an intentional deviation from other SDKs, but makes logical sense
* The client supports a default task queue, do we want this?

### Core

Exported from `temporalio` (but probably in `temporalio/core/core.py`, exported from `temporalio.core` then
exported from `temporalio`):

```python
class Core:
    async def create(
        addr: str,
        *,
        namespace: str = "default"
        # ... All the same options as Client.create
    ) -> Core:
        pass
```

Notes:

* If we could use Core to back our API client, then this would not be needed
  * Even if we didn't, maybe if the worker feature is enabled we can create a core instance during client creation? Then
    we can pass a client to worker instead of core which would be much cleaner
* While we could implicitly create this, say, per address I think each core instance has enough uniqueness to require
  manual user management
* We could flip the wording of this a bit and have a "worker" not be task queue specific and be 1:1 with core, then have
  the concept of a "task queue worker" that then lets you register activities and such.
  * Probably deviates too much from the norm. Still, it's quite unfortunate to have a two-step process to create a
    worker.
* Is there any harm in creating one core instance per worker? We could do away with this if not.
  * Do we lose some of the shared core benefits by only registering one worker for each core instance?
  * I assume there is a meaningful difference between 1000 core instances that we poll on each and just 1?
* Any other ideas on removing Core from explicit creation by users while still allowing multiple workers on different
  server addresses?
  * We can't do something like one-core-per-server-addr because there are different core options than just addr
  * Should we just make the `core` optional in worker and have a global one that they can init (and hope they do so
    before starting worker)?

### Worker

Exported from `temporalio` (but probably in `temporalio/worker/worker.py`, exported from `temporalio.worker` then
exported from `temporalio`):

```python

class Worker:
    def __init__(
        self,
        client: temporalio.Client,
        *,
        # Uses default in client if not present (or errors if no default)
        task_queue: str = None,
        # Can be anything accepted by register_activities
        activities=None,
        # An executor to be used for synchronous activities. If set, the worker
        # does not shut this down. If unset, the worker may use a thread pool
        # internally.
        activity_executor=None,
        # Whether to use the given/defaulted executor for async activities as
        # well.
        use_activity_executor_on_async: bool = False,
        # ...
    ) -> None:
        pass

    # Cannot be called after run started. Typings and separate @overload
    # signatures omitted for brevity.
    def register_activity(
        # This must be a callable. Can be a lambda.
        activity,
        *,
        # Set the name override. If not set, uses the @activity.run decorator
        # name. If that's not set, uses the function/method name or class name
        # if it has __call__. If it's a lambda, a name must be provided (or it
        # can be manually decorated).
        name: str = None
        # ...
    ) -> None:
        pass

    # Cannot be called after run started. Typings and separate @overload
    # signatures omitted for brevity.
    def register_activities(
        # This must be an object or list or dictionary. If an object, this only
        # uses methods with @activity.run decorators. Dictionaries and lists
        # don't require the decorator. If a dictionary, the key is the name.
        # This is just a helper and is the equivalent of just calling
        # register_activity with all applicable functions.
        activities,
        # ...
    ) -> None:
        pass

    async def run() -> None:
        pass
```

Notes:

* We have left off workflow registration until a later phase
* Stopping the worker is done via cancellation of the run task/future
* Internally, activities will run in the same event loop `run()` is called on
* By default will fail already-registered activities
* We also accept a set of activities to register in `__init__` and caller can choose preferred approach
* Does exporting `temporalio.Worker` directly cause any packaging issues if we want to separate the client as its own
  published package?
  * I believe we can catch an import error
* We allow a custom executor and potentially even default one for sync activities
  * Should we default an executor for sync?
  * Is it ok to not default an executor for async? Or should we use it for them too?

### Activity Utilities

These are all top-level calls in `temporalio.activity`:

```python
# Whether the current code is in an activity
def in_activity() -> bool:
    pass


def info() -> Info:
    pass


class Info:
    # Other fields/properties skipped for brevity

    @property
    def cancelled(self) -> bool:
        pass

    @property
    def cancellation() -> asyncio.Task:
        pass


# Adapter that extracts info() only when available in context
class LoggerAdapter(logging.LoggerAdapter):
    pass


_logger = LoggerAdapter(logging.getLogger(__name__))

# Logger that activities can use w/ activity context info instead of making
# their own (though making your own is recommended)
def logger() -> logging.Logger:
    return _logger


def heartbeat(*details) -> None:
    pass
```

Notes:

* These all uses `contextvars` to get activity info or throw otherwise
  * We will make the contextual state open to caller injection to support test mocking. The details are undecided atm.

### Activity Definition/Registration

```python
from temporalio import activity

# This adds activity details if they are present. Maybe we should have a
# temporalio.LoggerAdapter that works for activities _and_ workflows?
my_activity_logger = activity.LoggerAdapter(logging.getLogger(__name__))


def simple_activity(arg1, arg2):
    # Uses contextvars internally, which means it'll fail in another context but
    # we will provide the ability to set this for testing situations
    attempts = activity.info().attempts
    # This logger has an adapter to include custom details but still named after
    # this module which is a common pattern
    my_activity_logger.debug("Attempt %s", attempts)
    # This logger, on the activity module, uses the name of the activity module.
    # So that's why we offer either the adapter or the logger.
    activity.logger().debug("Attempt %s", attempts)


@activity.run(name="MyActivity")
async def another_activity(arg1):
    # Showing heartbeat and cancellation. In Python 3.7 we cannot give a
    # specific error to Task/Future.cancel (only in 3.9). So activity
    # cancellations appear like any other asyncio cancellations (which may be a
    # good thing anyways).
    try:
        while True:
            await asyncio.sleep(1)
            activity.heartbeat("some details")
    except asyncio.CancelledError as exc:
        raise RuntimeError("someone cancelled me!") from exc

class MyCallableClass:
    def __call__(self):
        pass

@activity.run(name="ManualClassName")
class AnotherCallableClass:
    def __call__(self):
        pass

class MyActivities:
    @activity.run
    def activity1():
        pass

    def not_automatically_registered():
        pass

def register_all(worker):
    # Registers as "simple_activity"
    worker.register_activity(simple_activity)
    # Using customized name
    worker.register_activity(another_activity)
    # Registers as "MyCallableClass"
    worker.register_activity(MyCallableClass())
    # Registers as "ManualClassName"
    worker.register_activity(AnotherCallableClass())
    # Manual name
    worker.register_activity(another_activity, name="ManualActivityName")
    # Lambda w/ name
    worker.register_activity(lambda arg1: arg1, name="MyLambda")
    # Lambda can of course manually apply decorator
    worker.register_activity(activity.run(name="MyLambda2")(lambda arg1: arg1))
    # Methods work just like top-level methods
    worker.register_activity(MyActivities().not_automatically_registered)
    # Nested function registers as "nested_activity"
    def nested_activity():
        pass
    worker.register_activity(nested_activity)

    # Fails because it's not callable
    worker.register_activity(MyActivities())
    # Fails because it's a lambda w/ no name
    worker.register_activity(lambda arg1: arg1)

    # Registers only "activity1"
    worker.register_activities(MyActivities())
    # As if calling register_activity on each
    worker.register_activities([another_activity, MyCallableClass()])
    # As if calling register_activity with a custom name on each
    worker.register_activities({'activity_name': simple_activity})

    # Fails, has no @activity.run method
    worker.register_activities(MyCallableClass())
```

Notes:

* We use `@activity.run` from `temporalio.activity` instead of just `@activity` from because:
  * We want `activity` to be a module because we want it usually imported as `from temporalio import activity` so
    top-level calls like `activity.info()` read well
  * When we get to workflows, we will do similar with `@workflow.run` vs `@workflow.signal` vs `@workflow.query`, etc
    and `workflow.info()`
* Cancellation is task cancellation
  * We need to research whether, in Python 3.7, we can interrupt an async task w/ our own error reliably
* Heartbeat is a synchronous call
  * Should we throw a cancellation error if we know the activity is cancelled when they try to heartbeat?
    * is this something core should be returning from `record_heartbeat` instead of lang?

### Payload Converters

Exported from `temporalio` (but maybe in `temporalio/converter/converter.py`, exported from `temporalio.converter`
then exported from `temporalio`):

```python
class PayloadConverter(ABC):
    # This can be sync or async. Always takes a list. Can return a single
    # payload or a list of payloads with the same size as the input list or None
    # if the value cannot be converted with this converter. Any other result
    # causes an error. Any error raised is bubbled.
    @abstractmethod
    async def encode(self, *values):
        pass

    # This can be sync or async. Always takes a list. Can return a single value
    # or a list of values with the same size as the input list or None if the
    # value cannot be converted with this converter. Any other result causes an
    # error. Any error raised is bubbled.
    @abstractmethod
    async def decode(self, *payloads):
        pass


class CompositePayloadConverter(PayloadConverter):
    def __init__(self, converters) -> None:
        pass

    async def encode(self, *values):
        pass

    async def decode(self, *payloads):
        pass


PayloadConverter.default = CompositePayloadConverter(
    [
        BinaryNullPayloadConverter(),
        BinaryPlainPayloadConverter(),
        JSONProtoPayloadConverter(),
        BinaryProtoPayloadConverter(),
        JSONPlainPayloadConverter(),
    ]
)
```

Notes:

* May be a bit difficult to allow async and non-async converter w/ same base but we can
  * Ref https://stackoverflow.com/questions/47555934/how-require-that-an-abstract-method-is-a-coroutine
* This is a combination of the otherwise separate concepts of "DataConverter" and "PayloadConverter" from other SDKs
  since the extra abstraction seems unnecessary, is that ok?

### Other API Items

The following API items aren't in the proposal because their use should be straightforward:

* We'll extend exception and properly convert to/from for most errors at
  https://pkg.go.dev/go.temporal.io/api/serviceerror