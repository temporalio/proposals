# Python SDK - Phase 2

The Python SDK will be implemented in three loosely defined phases:

* Phase 1 - Initial project, activity worker, and client
* Phase 2 - Workflow worker, local activities, async activity completion, etc
* Phase 3 - Deterministic workflow sandbox, replayer, test suite (some parts may be combined with phase 2)

This proposal is for phase 2. It is intentionally loosely defined and all aspects are subject to discussion/change.

## Overview

Following up from phase 1 and known implementation changes since then, this phase will implement the actual workflow
worker/code and other advanced features.

A simple example of a workflow definition and worker run:

```python
from datetime import timedelta
from temporalio import activity, workflow
from temporalio.client import Client
from temporalio.worker import Worker

@activity.defn
def say_hello(name: str) -> str:
    return f"Hello, {name}!"

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(arg1: str) -> str:
        return await workflow.execute_local_activity(
            say_hello, arg1, start_to_close_timeout=timedelta(seconds=5)
        )


async def main(stop_event: asyncio.Event):
    client = await Client.connect("http://localhost:7233")
    async with Worker(
        client,
        task_queue="somequeue",
        activities=[say_hello],
        workflows=[MyWorkflow],
    ):
        await stop_event.wait()
```

## Workflow Definitions

A workflow is a class.

Here is an example of a class-based workflow that calls a local activity to get
a greeting with a signal to update the prefix and a query to get the latest
greeting:

```python
import asyncio
from datetime import timedelta
from temporalio import activity, workflow
from temporalio.client import Client
from temporalio.worker import Worker

@activity.defn
def create_greeting_activity(salutation: str, name: str) -> str:
    return f"{salutation}, {name}!"

@workflow.defn
class GreetingWorkflow:
    def __init__() -> None:
        self._salutation = "Hello"
        self._salutation_update = asyncio.Event()
        self._complete = asyncio.Event()

    @workflow.run
    async def run(self, name: str) -> str:
        while True:
            # Store greeting (this is typed)
            self._current_greeting = await workflow.execute_local_activity(
                create_greeting_activity,
                self._salutation,
                name,
                start_to_close_timeout=timedelta(seconds=5),
            )
            workflow.logger.debug("Greeting set to %s", self._current_greeting)
            
            # Wait for salutation update or complete signal (this can be
            # cancelled)
            await asyncio.wait(
                [self._salutation_update.wait(), self._complete.wait()],
                return_when=asyncio.FIRST_COMPLETED,
            )
            if self._salutation_update.is_set():
                self._salutation_update.clear()
            if self._complete.is_set():
                return self._current_greeting

    @workflow.signal
    async def update_salutation(self, salutation: str) -> None:
        self._salutation = salutation
        self._salutation_update.set()

    @workflow.signal
    async def complete_with_greeting(self) -> None:
        self._complete.set()

    @workflow.query
    async def current_greeting(self) -> str:
        return self._current_greeting

def test_workflow(client: Client) -> None:
    # Start the workflow
    handle = await client.start_workflow(GreetingWorkflow.run, "John")

    # Confirm the current greeting
    assert "Hello, John!" == await handle.query(GreetingWorkflow.current_greeting)

    # Change the salutation part
    await handle.signal(GreetingWorkflow.update_salutation, "Hola")

    # Now tell it to complete with the new greeting
    await handle.signal(GreetingWorkflow.complete_with_greeting)

    # Check result
    assert "Hola, John!" == await handle.result()

def create_worker(client: Client) -> Worker:
    return Worker(
      client=client,
      activities=[create_greeting_activity],
      workflows=[GreetingWorkflow],
    )
```

Notes:

* Workflows are classes
  * Consideration was given to making workflows be functions (in addition to classes or having the class equivalent sit
    on top) with several possibilities for defining signals and queries, but all were too ugly/complicated
* `@activity.defn`
  * Must be on function and accepts an optional activity `name` which defaults to function `__name__`
  * This was originally not wanted in the activity impl (phase 1) due to complaints of the name not being obvious
  * We need to define the activity name on the activity for execution by the workflow
  * Is it ok to now make this required? Is it ok to now make the name implicit? Is it ok to now use a list instead of a
    dict to specify activities for the worker?
* `@workflow.defn`
  * Must be on class and accepts an optional workflow `name` which defaults to class `__name__`
  * This is required to clearly mark the class as a workflow
  * No base classes can have this value
* `@workflow.run`
  * Must be on a single async method (regardless of inheritance level) and accepts no params
  * The params represent the workflow params and the response represents the workflow response
    * Is it too annoying that the params aren't on `__init__` instead? The problem with being on a constructor is you
      can't do async logic there so that's annoying too.
  * An additional helper for `@workflow.start` was considered to allow "async complete" of workflow via another call but
    it became too confusing
  * The reference to this function is used for starting a workflow with a typed handle
* `@workflow.signal`
  * Can be on any number of methods (async or not, can be inherited)
  * Can have an optional `name` which defaults to function `__name__`
  * Params are signal params (only positional params allowed), cannot return value
  * Can have optional `dynamic` boolean which, if set to true, means the signal is a catch-all for otherwise unhandled
    signals. `name` cannot be present and there must be two params: a name param and a varargs param
    * An alternative approach that is similarly Pythonic would be to have a `__temporal_signal__` function that could be
      defined to catch them, but the decorator is clearer
  * The reference to this function is used for typed signalling
  * Technically a `@property` setter can be a signal too
* `@workflow.query`
  * Can be on any number of methods (only non-async, can be inherited)
    * TypeScript doesn't allow async here either and there should be no reason to need async here
  * Can have an optional `name` which defaults to function `__name__`
  * Params are query params (only positional params allowed) and should return a value (cannot enforce this though)
  * Can have optional `dynamic` boolean which, if set to true, means the query is a catch-all for otherwise unhandled
    queries. `name` cannot be present and there must be two params: a name param and a varargs param
  * The reference to this function is used for typed signalling
  * Technically a `@property` getter can be a query too
* Everything is typed as much as possible (see "API Updates")

## API Updates

### Client

#### WorkflowHandle

Updated with the following generics:

```python
class WorkflowHandle(Generic[WorkflowType, WorkflowReturnType]):
```

The workflow type is used for typing the "self" of signal/query methods and the return type is for result

#### Client.start_workflow

The following overload _would_ be added to client:

```python
    @overload
    async def start_workflow(
        self,
        workflow: Callable[Concatenate[WorkflowType, LocalParamType], Awaitable[WorkflowReturnType]],
        *args: LocalParamType.args,
        #...
    ) -> WorkflowHandle[WorkflowType, WorkflowReturnType]:
        pass
```

Where `LocalParamType` is a `ParamSpec`. But since `Concatenate` is
[not yet supported in mypy](https://github.com/python/mypy/issues/11833), we instead have two overloads:

```python
    # Overload for no-param workflow
    # TODO(cretz): Fix when https://github.com/python/mypy/issues/11833 fixed
    @overload
    async def start_workflow(
        self,
        workflow: Callable[[WorkflowType], Awaitable[WorkflowReturnType]],
        /,
        *,
        # ...
    ) -> WorkflowHandle[WorkflowType, WorkflowReturnType]:
        pass

    # Overload for single-param workflow
    # TODO(cretz): Fix when https://github.com/python/mypy/issues/11833 fixed
    @overload
    async def start_workflow(
        self,
        workflow: Callable[[WorkflowType, LocalParamType], Awaitable[WorkflowReturnType]],
        arg: LocalParamType,
        /,
        *,
        # ...
    ) -> WorkflowHandle[WorkflowType, WorkflowReturnType]:
        pass
```
Where `LocalParamType` is a `TypeVar`. This means that multi-param workflows are not currently type-able which is
probably an acceptable limitation for now.

#### Client.get_workflow_handle_for

Due to the same no-mypy-`Concatenate` problem as `start_workflow`, this has a union for the param:

```python
    def get_workflow_handle_for(
        self,
        workflow: Union[
            Callable[[WorkflowType, Any], Awaitable[WorkflowReturnType]],
            Callable[[WorkflowType], Awaitable[WorkflowReturnType]],
        ],
        workflow_id: str,
        *,
        run_id: Optional[str] = None,
        first_execution_run_id: Optional[str] = None,
    ) -> WorkflowHandle[WorkflowType, WorkflowReturnType]:
        return self.get_workflow_handle(
            workflow_id, run_id=run_id, first_execution_run_id=first_execution_run_id
        )
```

Notes:

* This cannot be an overload for `get_workflow_handle` because this takes an extra workflow param that does not
* Anything else we want to call this? Is it ok that `get_workflow_handle` is the untyped one and
  `get_workflow_handle_for` is the typed one or do we want different names?
* Start workflow takes params after the workflow but this takes the workflow ID. For a single-param workflow this
  _could_ be confusing because you have `client.start_workflow(MyWorkflow.run_func, "myparam", id="myid")` and
  `client.get_workflow_handle_for(MyWorkflow.run_func, "myid")`. Is there anything we want to change here concerning
  param names or order of params? Currently as described is the clearest.


#### WorkflowHandle.result

This is already typed and doesn't really change, but the type name changed so it looks like:

```python
    async def result(self, *, follow_runs: bool = True) -> WorkflowReturnType:
      pass
```

#### WorkflowHandle.signal

Due to the same no-mypy-`Concatenate` problem as `start_workflow`, this has two overloads:

```python
    # Overload for no-param signal
    # TODO(cretz): Fix when https://github.com/python/mypy/issues/11833 fixed
    @overload
    async def signal(
        self,
        signal: Callable[[WorkflowType], Union[Awaitable[None], None]],
        /,
    ) -> None:
        pass

    # Overload for single-param signal
    # TODO(cretz): Fix when https://github.com/python/mypy/issues/11833 fixed
    @overload
    async def signal(
        self,
        signal: Callable[[WorkflowType, LocalParamType], Union[Awaitable[None], None]],
        arg: LocalParamType,
        /,
    ) -> None:
        pass
```

#### WorkflowHandle.query

Due to the same no-mypy-`Concatenate` problem as `start_workflow`, this has two overloads:

```python
    # Overload for no-param query
    # TODO(cretz): Fix when https://github.com/python/mypy/issues/11833 fixed
    @overload
    async def query(
        self,
        query: Callable[[WorkflowType], Union[Awaitable[LocalReturnType], LocalReturnType]],
        /,
        *,
        reject_condition: Optional[temporalio.common.QueryRejectCondition] = None,
    ) -> LocalReturnType:
        pass

    # Overload for single-param query
    # TODO(cretz): Fix when https://github.com/python/mypy/issues/11833 fixed
    @overload
    async def query(
        self,
        query: Callable[[WorkflowType, LocalParamType], Union[Awaitable[LocalReturnType], LocalReturnType]],
        arg: LocalParamType,
        /,
        *,
        reject_condition: Optional[temporalio.common.QueryRejectCondition] = None,
    ) -> LocalReturnType:
        pass
```

### Worker

#### Worker.__init__.activities

Currently `activities` are accepted as `Mapping[str, Callable]`. Due to `@activity.defn` we will change this to
`Iterable[Callable]` and require all activities have `@activity.defn`. See the overview for notes/discussion on this.

#### Worker.__init__.workflows

Workers will accept a `workflows` param which is `Iterable[Type]`. These will be classes that have `@workflow.defn` and
they are validated at runtime.

#### Worker.__init__.workflow_runner

Optional class (not shown) that can be used to invoke workflows. Hopefully, the default for this will be a deterministic
sandbox in phase 3. But in the meantime this is just an abstraction in preparation. It's not called "executor" because
`activity_executor` already exists which uses the literal "concurrent executors" from Python.

#### temporalio.worker.Interceptor

Will add `intercept_workflow` to this and support all inbound and outbound interception.

### temporalio.workflow

The workflow package will contain functions that can only be called from inside a workflow.

#### temporalio.workflow.start_activity()

```python

class ActivityHandle(Generic[ActivityReturnType], Cancellable):
    async def result(self) -> ActivityReturnType:
        pass

    async def cancel(self) -> None:
        pass

# Overload for async no-param activity
# TODO(cretz): Fix when https://github.com/python/mypy/issues/11833 fixed
@overload
def start_activity(
    activity: Callable[[], Awaitable[ActivityReturnType]],
    /,
    *,
    # ...
) -> ActivityHandle[ActivityReturnType]:
    pass

# Overload for sync no-param activity
# TODO(cretz): Fix when https://github.com/python/mypy/issues/11833 fixed
@overload
def start_activity(
    activity: Callable[[], ActivityReturnType],
    /,
    *,
    # ...
) -> ActivityHandle[ActivityReturnType]:
    pass

# Overload for async single-param activity
# TODO(cretz): Fix when https://github.com/python/mypy/issues/11833 fixed
@overload
def start_activity(
    activity: Callable[[LocalParamType], Awaitable[ActivityReturnType]],
    arg: LocalParamType,
    /,
    *,
    # ...
) -> ActivityHandle[ActivityReturnType]:
    pass

# Overload for sync single-param activity
# TODO(cretz): Fix when https://github.com/python/mypy/issues/11833 fixed
@overload
def start_activity(
    activity: Callable[[LocalParamType], ActivityReturnType],
    arg: LocalParamType,
    /,
    *,
    # ...
) -> ActivityHandle[ActivityReturnType]:
    pass

# Overload for string activity
@overload
def start_activity(
    activity: str,
    *args: Any,
    # ...
) -> ActivityHandle[Any]:
    pass

def start_activity(
    activity: Any,
    *args: Any,
    activity_id: Optional[str] = None,
    namespace: Optional[str] = None,
    task_queue: Optional[str] = None,
    schedule_to_close_timeout: Optional[timedelta] = None,
    schedule_to_start_timeout: Optional[timedelta] = None,
    start_to_close_timeout: Optional[timedelta] = None,
    heartbeat_timeout: Optional[timedelta] = None,
    retry_policy: Optional[temporalio.common.RetryPolicy] = None,
    cancellation_type: ActivityCancellationType = ActivityCancellationType.TRY_CANCEL,
) -> ActivityHandle[Any]:
    # Do stuff
```

Notes:

* `ActivityHandle` approach was chosen to simplify cancellation. See "temporalio.workflow Scoped Cancellation" for more
  discussion.
* Why does does mypy only work here when we separate out async from sync, but allows the use of `Union` for
  `WorkflowHandle.query`?

#### temporalio.workflow.execute_activity()

Async shortcut for `temporalio.workflow.start_activity()` + `handle.result()`.

#### temporalio.workflow.ActivityConfig

`TypedDict` of `start_activity`/`execute_activity` configuration options.

#### temporalio.workflow.start_local_activity()

Same as `start_activity`, except no `heartbeat_timeout` param. For now, we will reuse `ActivityHandle` for the result
since there would be nothing unique about a `LocalActivityHandle`.

#### temporalio.workflow.execute_local_activity()

Shortcut for `temporalio.workflow.start_local_activity()` + `handle.result()`.

#### temporalio.workflow.LocalActivityConfig

`TypedDict` of `start_local_activity`/`execute_local_activity` configuration options.

#### temporalio.workflow.start_child_workflow()

```python
class ChildWorkflowHandle(Generic[WorkflowType, WorkflowReturnType], Cancellable):

    @property
    def id(self) -> str:
        pass

    @property
    def original_run_id(self) -> Optional[str]:
        pass

    # Include same typed overloads as WorkflowHandle
    async def signal(self, signal: Any, *args: Any) -> None:
        pass

    async def result(self) -> WorkflowReturnType:
        pass

    async def cancel(self) -> None:
        pass

# Overload for no-param workflow
# TODO(cretz): Fix when https://github.com/python/mypy/issues/11833 fixed
@overload
async def start_child_workflow(
    self,
    workflow: Callable[[WorkflowType], Awaitable[WorkflowReturnType]],
    /,
    *,
    # ...
) -> ChildWorkflowHandle[WorkflowType, WorkflowReturnType]:
    pass

# Overload for single-param workflow
# TODO(cretz): Fix when https://github.com/python/mypy/issues/11833 fixed
@overload
async def start_child_workflow(
    self,
    workflow: Callable[
        [WorkflowType, LocalParamType], Awaitable[WorkflowReturnType]
    ],
    arg: LocalParamType,
    /,
    *,
    # ...
) -> ChildWorkflowHandle[WorkflowType, WorkflowReturnType]:
    pass

# Overload for string-name workflow
@overload
async def start_child_workflow(
    self,
    workflow: str,
    *args: Any,
    # ...
) -> ChildWorkflowHandle[Any, Any]:
    pass

async def start_child_workflow(
    self,
    workflow: Any,
    *args: Any,
    id: str,
    task_queue: Optional[str] = None,
    cancellation_type: ChildWorkflowCancellationType = ChildWorkflowCancellationType.WAIT_CANCELLATION_COMPLETED,
    parent_close_policy: ParentClosePolicy = ParentClosePolicy.TERMINATE,
    execution_timeout: Optional[timedelta] = None,
    run_timeout: Optional[timedelta] = None,
    task_timeout: Optional[timedelta] = None,
    id_reuse_policy: temporalio.common.WorkflowIDReusePolicy = temporalio.common.WorkflowIDReusePolicy.ALLOW_DUPLICATE,
    retry_policy: Optional[temporalio.common.RetryPolicy] = None,
    cron_schedule: str = "",
    memo: Optional[Mapping[str, Any]] = None,
    search_attributes: Optional[Mapping[str, Any]] = None,
    header: Optional[Mapping[str, Any]] = None,
) -> ChildWorkflowHandle[Any, Any]:
    # Do stuff
```

Notes:

* `ChildWorkflowHandle.signal` will have the same typed overloads that `WorkflowHandle.signal` does
* `ChildWorkflowHandle.cancel` is present to simplify cancellation. See "temporalio.workflow Scoped Cancellation" for
  more discussion.
  * How does TypeScript return a failure if the child workflow cancel
* `start_child` was considered instead of `start_child_workflow`, but this seems clearer. Can be convinced otherwise.

#### temporalio.workflow.execute_child_workflow()

Shortcut for `temporalio.workflow.start_child_workflow()` + `handle.result()`

#### temporalio.workflow.ChildWorkflowConfig

`TypedDict` of `start_child_workflow`/`execute_child_workflow` configuration options.

#### temporalio.workflow.continue_as_new()

```python
# Overload for self (cannot type args)
@overload
def continue_as_new(
    *args: Any,
    # ... (excludes "workflow" kwarg)
) -> NoReturn:
    pass

# Overload for no-param workflow
# TODO(cretz): Fix when https://github.com/python/mypy/issues/11833 fixed
@overload
def continue_as_new(
    *,
    workflow: Callable[[WorkflowType], Any],
    # ...
) -> NoReturn:
    pass

# Overload for single-param workflow
# TODO(cretz): Fix when https://github.com/python/mypy/issues/11833 fixed
@overload
def continue_as_new(
    arg: LocalParamType,
    /,
    *,
    workflow: Callable[[WorkflowType, LocalParamType], Any],
    # ...
) -> NoReturn:
    pass

# Overload for string workflow
@overload
def continue_as_new(
    *args: Any,
    workflow: str,
    # ...
) -> NoReturn:
    pass

def continue_as_new(
    *args: Any,
    workflow: Union[None, Callable, str] = None,
    task_queue: Optional[str] = None,
    memo: Optional[Mapping[str, Any]] = None,
    search_attributes: Optional[Mapping[str, Any]] = None,
    run_timeout: Optional[timedelta] = None,
    task_timeout: Optional[timedelta] = None,
) -> NoReturn:
    # Do stuff
```

Notes:

* Like all other SDK languages so far, we can't reasonably provide types for args on the "self" continue as new
* More investigation is needed on whether I can stop the event loop inside the continue as new without it returning
  * I probably can't so I probably need to make this call `async`, but I probably don't have to throw
  * While I thought I could just stop the event loop and then return, that doesn't prevent the next line of code from
    potentially setting local state that could change a query result
  * This will be subject to implementation-time research. The goal is to try to never return from the function (if it's
    `async` that implies never return from an `await` on it) and if possible do not raise an error.

#### temporalio.workflow.ContinueAsNewConfig

`TypedDict` of `continue_as_new` configuration options.

#### temporalio.workflow.get_external_workflow_handle

```python
class ExternalWorkflowHandle(Generic[WorkflowType], Cancellable):

    @property
    def id(self) -> str:
        pass

    @property
    def run_id(self) -> Optional[str]:
        pass

    # Include same typed overloads as WorkflowHandle
    async def signal(self, signal: Any, *args: Any) -> None:
        pass

    async def cancel(self) -> None:
        pass

def get_external_workflow_handle_for(
    workflow: Union[
        Callable[[WorkflowType, Any], Awaitable[Any]],
        Callable[[WorkflowType], Awaitable[Any]],
    ],
    workflow_id: str,
    *,
    run_id: Optional[str] = None,
) -> ExternalWorkflowHandle[WorkflowType]:
    return get_external_workflow_handle(workflow_id, run_id=run_id)

def get_external_workflow_handle(
    workflow_id: str,
    *,
    run_id: Optional[str] = None,
) -> ExternalWorkflowHandle[Any, Any]:
    # Do stuff
```

Notes:

* This intentionally matches the client API

#### temporalio.workflow.upsert_search_attributes

```python
def upsert_search_attributes(attrs: Mapping[str, Any]) -> None:
    pass
```

Notes:

* I prefer `set` over `upsert` here, but not enough to fight for it
* Originally there was concern that I couldn't report data conversion failure on search attributes, but since custom
  converters are not allowed, I can just make sync calls to the JSON data converter

#### temporalio.workflow Async Utilities

```python
async def sleep(delay: float, result: T = None) -> T:
  pass

async def wait_condition(fn: Callable[[], Awaitable[bool]], *, timeout: Optional[float] = None):
    pass
```

Notes:

* See discussion in "Runtime - Workflow Stepped Execution" on whether to reuse `asyncio.sleep`
* Like `temporal.activity.wait*` we choose the "wait_" prefix here as Python often does, e.g. for events which this is
  most analogous to

#### temporalio.workflow Miscellaneous

```python

@dataclass(frozen=True)
class Info:
    pass

def is_replaying() -> bool:
    pass

def info() -> Info:
    pass

def now() -> datetime:
    pass

logger = LoggerAdapter(logging.getLogger(__name__), None)
```

Notes:

* Fields of `Info` not shown, but notably absent is `is_replaying` so it can remain immutable
  * Instead, like Java and Go, we move that to the package level
* Should we move `is_replaying` to a place that makes it more clear it's unsafe?
* It's clearer to require uses of `temporalio.workflow.now()` than to wait for and require overriding `datetime.now()`
  when a deterministic sandbox appears. It is clearer to disallow deterministic calls than implicitly replace some.
* `logger` uses a special adapter that is skipped during replay

#### temporalio.workflow.CancellationScope

Rough sketch:

```python
class CancellationScope:
    @property
    @staticmethod
    def current() -> CancellationScope:
        pass

    def __init__(
        self,
        *,
        # Default is current
        parent: Optional[CancellationScope] = None,
        detached: bool = False,
        timeout: Optional[timedelta] = None,
    ) -> None:
        pass

    def _push(self) -> None:
        pass

    def _pop(self) -> None:
        pass

    await def run(self, fn: Callable[..., Union[Awaitable[T], T]]) -> T:
        pass

    def __enter__(self) -> CancellationScope:
        pass

    def __exit__(self) -> None:
        pass

    def cancel(self) -> None:
        pass

    @property
    def cancelled(self) -> bool:
        pass
```

Notes:

* Unlike TypeScript, Python still allows you to explicitly cancel individual activities and child workflows if you
  started them with `start_`
  * The consistency of having everything that has a `start_` be cancellable has value. I still expect most will use the
    `execute_` form though
* The workflow will have a root scope
* This will work using `with CancellationScope()` and similar and is powered by `contextvars`
  * `run` is async because the callable may have an async result, but `with` is the preferred approach for explicit use
* `start_activity`/`execute_activity`/`start_child_workflow`/`execute_child_workflow` will implicitly use the current
  cancellation scope
* Do we need extra capabilities such as:
  * Ability to explicitly add cancellables?
  * Ability to unset the current instead of just forcing a detached one each time you want to opt out?
* Should we disallow the `parent` to even be set in the constructor?
  * Thinking we probably shouldn't allow you to set that
* Cancellation of a workflow or a scope causes all things started with that to be issued a cancel
  * Originally we weren't gonna use cancellation scopes but instead reuse the `asyncio` cancel feature but that throws
    inside of awaited things and we want to cancel whether awaited or not
  * This means `asyncio` cancellation (and `shield` etc) affects only in-workflow tasks awaited on, _not_ the actual
    underlying activity/child being executed
    * We could disable these features of `asyncio` so people aren't confused by their concept of cancellation and ours,
      but there is still value in cancelling just the tasks

## Runtime

### Workflow Stepped Execution

Notes:

* We are gonna use `asyncio`, but whether we have to use our own event loop remains to be seen
  * Have shown at https://github.com/cretz/python-determinism-runner basically using the approach from
    https://stackoverflow.com/a/29797709 that we can run a single step and enforce that we have yielded only at
    workflow-acceptable spots
* Do want to prevent use of `asyncio.sleep`, `asyncio.wait_for`, and similar that are based on system time?
  * This is much clearer than replacing their implementations so that people aren't confused about why a 50ms wait does
    not work
  * We may not be able to block everything until we use a sandbox (see next section)
  * Making alternatives is a tad ugly, e.g. one can use `asyncio.gather()` without timeout but they can't with timeout,
    instead they'd have to have a sleep or something

### Workflow Deterministic Execution

Notes:

* A full workflow execution sandbox may not occur until phase 3
  * Some work on doing this via `eval` are at https://github.com/cretz/python-determinism-runner
* We will, however, go ahead and abstract the "runner" so that we can make it pluggable/opt-out if the caller chooses