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
    async with temporalio.Client("localhost:7233") as client:
        result = await client.execute_workflow(
            "MyWorkflow", "arg1", id="someid", task_queue="somequeue"
        )
        print("Result", result)
```

An example of an activity and registration (also missing a lot of features):

```python
import temporalio


def say_hello(name: str) -> str:
    return f"Hello, {name}!"


async def main():
    async with temporalio.Client("localhost:7233") as client:
        worker = temporalio.Worker(
            client, task_queue="somequeue", activities={"say_hello": say_hello}
        )
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
    # Basically __init__ + __aenter__, caller must close themselves
    @staticmethod
    async def connect(
        addr: str,
        *,
        namespace: str = "default"
        # ... additional options omitted for brevity
    ) -> Client:
        pass

    # Should only be used with async with
    def __init__(
        self,
        addr: str,
        *,
        namespace: str = "default"
        # ... additional options omitted for brevity
    ) -> None:
        pass

    async def __aenter__(self) -> Client:
        pass

    async def __aexit__(self) -> None:
        await self.close()

    async def close(self) -> None:
        pass

    # Raw gRPC access
    @property
    def service(self) -> temporalio.WorkflowService:
        pass

    async def start_workflow(
        self,
        workflow: str,
        *args: Any,
        task_queue: str,
        id: Optional[str] = None,
        retry_policy: Optional[temporalio.RetryPolicy] = None,
        # Note, we are embedding signal-with-start in here
        start_signal: Optional[str] = None,
        start_signal_args: list[Any] = [],
        # ... additional options omitted for brevity
    ) -> temporalio.WorkflowHandle[Any]:
        pass

    # In a future phase maybe:
    # @overload
    # async def start_workflow(workflow: Callable[P, T], *args: P.args, ...) -> temporalio.WorkflowHandle[T]
    #
    # @overload
    # async def start_workflow(workflow: T, *args) -> T

    # Just a wrapper for start workflow that awaits the result
    async def execute_workflow(
        self,
        workflow: str,
        *args: Any,
        # ... additional options omitted for brevity
    ) -> Any:
        handle = await self.start_workflow(workflow, *args)
        return handle.result()

    # Does not validate whether a workflow exists
    def get_workflow_handle(
        workflow_id: str,
        run_id: Optional[str] = None
        # ...
    ) -> temporalio.WorkflowHandle[Any]:
        pass


class WorkflowService:
    # All calls from https://github.com/temporalio/api/blob/master/temporal/api/workflowservice/v1/service.proto
    # but unfortunately we may not be able to match the pure Python gRPC
    # signatures.
    pass


class WorkflowHandle(Generic[T]):
    def __init__(
        self,
        client: Client,
        workflow_id: str,
        *,
        run_id: Optional[str] = None
        # ...
    ) -> None:
        pass

    # This is not memoized, each invocation calls the server
    async def result(self) -> T:
        pass

    async def cancel(self):
        pass

    async def describe(self) -> temporalio.WorkflowExecution:
        pass

    async def query(self, name: str, *args: Any) -> Any:
        pass

    async def signal(self, name: str, *args: Any):
        pass

    async def terminate(self, *, reason: Optional[str] = None):
        pass
```

Notes:

* This API supports `async with` or just `Client.connect` + `client.close()`, user's preference
* We have chosen to, at first, only use Core's gRPC layer
  * The generated API/gRPC code for the pure Python gRPC client is still available for use, just not by this wrapper
* We are intentionally defining a `Client` instead of a `WorkflowClient` since this will be general purpose
  * Having a general purpose client keeps things simple, but this will probably only ever contain the pieces above (and
    overloads thereof) and async activity heartbeat/complete
* We call it `start_workflow` instead of just `start` to be clearer
* We have an `execute_workflow` to combine start + result waiting just as a shortcut
* We have embedded `start_signal` and `start_signal_args` as parameters, so if the former is present we will perform a
  signal with start. After discussion, it was determined this is acceptable.
* After discussion, we determined that the concept of a "default task queue" at the client level is not worth it right
  now.

### Worker

Exported from `temporalio` (but probably in `temporalio/worker/worker.py`, exported from `temporalio.worker` then
exported from `temporalio`):

```python
class Worker:
    def __init__(
        self,
        client: temporalio.Client,
        *,
        task_queue: str,
        # Must be a mapping with the key as the activity name and the value as a
        # callable to be called when the activity is invoked.
        activities: Mapping[str, Callable[P, T]] = {},
        # An executor to be used for synchronous activities. If set, the worker
        # does not shut this down. If unset, the worker may use a thread pool
        # internally.
        activity_executor: Optional[concurrent.futures.Executor] = None,
        # Same as activity_executor but for asynchronous activities.
        async_activity_executor: Optional[concurrent.futures.Executor] = None,
        # ...
    ) -> None:
        pass

    # Just start + shutdown on finally (so can be cancelled via asyncio cancel)
    async def run(self) -> None:
        pass

    async def start(self) -> None:
        pass

    async def shutdown(self) -> None:
        pass

    async def __aenter__(self) -> Worker:
        await self.start()
        return self

    async def __aexit__(self) -> None:
        await self.shutdown()
```

Notes:

* We have left off workflow registration until a later phase
* Can be used as `async with` or just via `await run()` which supports cancelling the task causing shutdown
* No current protection against multiple workers on the same task queue and client
  * Should we protect against that?
  * Any different-config reasons to have two workers for the same task queue and client? Maybe a stick and non-sticky
    one?
* Internally, activities will run in the same event loop `start()` is called on
* We allow a custom executor for sync activities and one for async activities
  * It was assumed that even though the activities may be async, they may want an executor too because they may have CPU
    bound work
  * Should combine the executors in the params instead of having caller provide separate?

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
    def cancellation(self) -> asyncio.Task:
        pass


# Adapter that extracts info() only when available in context
class LoggerAdapter(logging.LoggerAdapter):
    pass


_logger = LoggerAdapter(logging.getLogger(__name__))

# Logger that activities can use w/ activity context info instead of making
# their own (though making your own is recommended)
def logger() -> logging.Logger:
    return _logger


def heartbeat(*details: Any) -> None:
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


class MyActivities:
    def activity1():
        pass


def create_my_worker(client: temporalio.Client) -> temporalio.Worker:
    return temporalio.Worker(
        client,
        taskqueue="MyTaskQueue",
        activities={
            # The names can be any value
            "simple_activity": simple_activity,
            # Can use async function
            "another_activity": another_activity,
            # Can use callable class
            "callable_class": MyCallableClass(),
            # Can use method
            "activity1_method": MyActivities().activity1,
            # Can use lambda
            "lambda": lambda arg1: arg1,
            # Fails because not callable
            "not_callable": MyActivities(),
        },
    )
```

Notes:

* Cancellation is task cancellation
  * We need to research whether, in Python 3.7, we can interrupt an async task w/ our own error reliably
* Heartbeat is a synchronous call
* There were a lot of discussions around registering of activities, here are the results:
  * At least to start with, we want explicit names during register instead of the callable's `__name__` to avoid
    name-registration surprises that plague other languages
    * It was decided we can always be more flexible later or provided utilities if we must
  * A decorator (e.g. `@activity.defn`) was gonna help with naming, but:
    * Since we decided to use a mapping in the constructor instead of an iterable, name is always there
    * So the decorator would have no current purpose except as a "marker" to implementers to beware how it is used,
      which we decided was unnecessary at this time but we can revisit
  * We still have to have discussions around activity invocation from a worker, because just what appears to be a normal
    Python invocation turning to an `ExecuteActivity` or not based on decorator or similar alone may not be explicit
    enough

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
    async def encode(
        self, *values: Any
    ) -> Union[temporalio.Payload, list[temporalio.Payload]]:
        pass

    # This can be sync or async. Always takes a list. Can return a single value
    # or a list of values with the same size as the input list or None if the
    # value cannot be converted with this converter. Any other result causes an
    # error. Any error raised is bubbled.
    @abstractmethod
    async def decode(self, *payloads: temporalio.Payload) -> Union[Any, list[Any]]:
        pass


class CompositePayloadConverter(PayloadConverter):
    def __init__(self, converters) -> None:
        pass


class PicklePayloadConverter(PayloadConverter):
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
  since the extra abstraction seems unnecessary. After discussion, this was deemed acceptable.
* We intentionally don'ty put the `PicklePayloadConverter` in the composite set because it is not other-SDK compatible

### Other API Items

The following API items aren't in the proposal because their use should be straightforward:

* We'll extend exception and properly convert to/from for most errors at
  https://pkg.go.dev/go.temporal.io/api/serviceerror