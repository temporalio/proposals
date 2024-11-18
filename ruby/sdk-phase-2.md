# Ruby - Phase 2

This proposal is for implementing workflows in the Ruby SDK.

See [phase 1](sdk-phase-1.md) for details on phase 1 which includes client and activities (granted some things may have
changed since first authored).

Notes for this proposal (like phase 1):

* Everything is subject to change both during proposal time and afterwards during implementation.
* For each place a decision is made, a "💭 Why X? ..." aside is present explaining why.
* For each place an open question exists, a "❓ X?" exists to ask it.

Here is a high-level overview of potentially controversial decisions:

* Base class for activities is now `Temporalio::Activity::Definition` to be consistent with the base class
* Class methods are dynamically made available for signals, queries, and updates to use from clients.
  * So `MyWorkflow.my_signal` can be used in a client, and it just returns a signal definition, unlike the instance
    form.
* By default `TracePoint` will be enabled for workflow threads that will make sure users are not calling illegal calls,
  but there is a way to disable for blocks of code.
* `Ractor`s will be used for state isolation by default assuming decent performance but easy to disable and mostly
  hidden from users.

These points are explained below.

## Workflow Definition/Usage

Examples below are taken from
[this Python sample](https://github.com/temporalio/samples-python/tree/main/message_passing/introduction), so not too
many comments about general non-Ruby behavior are inline.

Example definition:

```ruby
class CallGreetingServiceActivity < Temporalio::Activity::Definition
  GREETINGS = {
    arabic: 'مرحبا بالعالم',
    chinese: '你好，世界',
    english: 'Hello, world',
    french: 'Bonjour, monde',
    hindi: 'नमस्ते दुनिया',
    portuguese: 'Olá mundo',
    spanish: 'Hola mundo'
  }

  def execute(language)
    # Simulate a network call
    sleep(0.2)
    GREETINGS[language.to_sym]
  end
end

class GreetingWorkflow < Temporalio::Workflow::Definition
  workflow_query_attr_reader :language

  def initialize(name)
    @greetings = {
      chinese: '你好，世界',
      english: 'Hello, world'
    }
    @language = :english
    @mutex = Temporalio::Workflow::Mutex.new
  end

  def execute
    Temporalio::Workflow.wait_condition do
      @approved_for_release && Temporalio::Workflow.all_handlers_finished?
    end
    @greetings[@language]
  end

  workflow_query
  def languages(input)
    return CallGreetingServiceActivity::GREETINGS.keys.sort if input[:include_unsupported]
    @greetings.keys.sort
  end

  workflow_signal
  def approve(input)
    @approved_for_release = true
    @approver_name = input[:name]
  end

  workflow_update
  def set_language(language)
    previous, @language = @language, language.to_sym
    previous
  end

  workflow_update_validator(:set_language)
  def validate_set_language(language)
    raise "#{language} not supported" unless @greetings.include?(language.to_sym)
  end

  workflow_update
  def set_language_using_activity(language)
    language = language.to_sym
    unless @greetings.include?(language)
      @mutex.synchronize do
        greeting = Temporalio::Workflow.execute_activity(
          CallGreetingServiceActivity,
          language,
          start_to_close_timeout: 10
        )
        unless greeting
          raise Temporalio::Error::ApplicationError, "Greeting service does not support #{language}"
        end
        @greetings[language] = greeting
      end
    end
    previous, @language = @language, language
    previous
  end
end
```

Example worker:

```ruby
client = Temporalio::Client.connect('localhost:7233', 'my-namespace')
worker = Temporalio::Worker.new(
  client:,
  task_queue: 'my-task-queue',
  activities: [GreetingActivity],
  workflows: [GreetingWorkflow]
)
worker.run(shutdown_signals: ['SIGINT'])
```

Example client usage:

```ruby
client = Temporalio::Client.connect('localhost:7233', 'my-namespace')

# Start workflow
wf_handle = client.start_workflow(
  GreetingWorkflow,
  id: 'my-workflow-id',
  task_queue: 'my-task-queue'
)

# Send query
supported_languages = wf_handle.query(
  GreetingWorkflow.languages,
  { include_unsupported: false }
)
puts "Supported languages: #{supported_languages}"

# Execute update
previous_language = wf_handle.execute_update(
  GreetingWorkflow.set_language,
  :chinese
)
current_language = wf_handle.query(GreetingWorkflow.language)
puts "Language changed: #{previous_language} -> #{current_language}"

# Start update then wait for complete
update_handle = wf_handle.start_update(
  GreetingWorkflow.set_language_using_activity,
  :arabic,
  wait_for_stage: Temporalio::Client::WorkflowUpdateWaitStage::ACCEPTED
)
previous_language = update_handle.result
current_language = wf_handle.query(GreetingWorkflow.language)
puts "Language changed: #{previous_language} -> #{current_language}"

# Send signal
wf_handle.signal(
  GreetingWorkflow.approve,
  { name: 'some-approver-name' }
)
puts "Workflow result: #{wf_handle.result}"
```

Things to note about workflow definition:

* Workflows must extend (directly or indirectly) from `Temporalio::Workflow::Definition`.
  * It must implement `execute` which is the entry point.
  * Workflow can customize its name via `workflow_name <name>` in the workflow somewhere.
  * **NOTE** As part of this proposal, we are changing the activity base class from `Temporalio::Activity` class to
    `Temporalio::Activity::Definition` to be consistent with the base class for workflows.
  * 💭 Why a class?
    * This fits well with the Ruby mindset and many of our SDKs utilize classes to encapsulate workflows and their
      handlers/state.
* Workflow has several class methods that start with `workflow_` that can only be called during class definition time
  not runtime. See next section for list.
* When used in a client:
  * The class of the workflow can be provided instead of the name, e.g. `my_client.start_workflow(MyWorkflowClass, ...)`
  * The signal, query, or update can reference a no-arg class method of the same name as the instance method, e.g.
    `my_wf_handle.signal(MyWorkflowClass.my_signal, ...)`, which returns a signal/query/update definition
    * Are we ok with `respond_to_missing?` and `inherited` for class method access of these values? Is this too much
      magic?
* Workflow cannot be instantiated by users (i.e. outside of workflow environment)

## Workflow API

Approximate guess of how the `Workflow` module may look:

```ruby
module Temporalio
  module Workflow

    # Class users must extend for a workflow
    class Definition
      class << self
        # Protected because they are only for this implementation
        protected

        # Placed above handlers. See dynamic section for dynamic. Raw args means the
        # handlers will be given their arguments as RawValue instead of converted.
        #
        # ❓ Notice raw_args. We could instead make type hints this way, e.g. via
        # `args: [String, Integer]` or something and plumb that all the way through
        # to the converter for a user's custom converter to use (same for activities
        # and the workflow as a whole). If we did that we would also need to allow
        # return type hints. Do we want to support this hacky form of type hints?
        def self.workflow_signal(name: nil, dynamic: false, raw_args: false,
                                unfinished_policy: HandlerUnfinishedPolicy::WARN_AND_ABANDON)
        def self.workflow_query(name: nil, dynamic: false, raw_args: false)
        def self.workflow_update(name: nil, dynamic: false, raw_args: false,
                                unfinished_policy: HandlerUnfinishedPolicy::WARN_AND_ABANDON)
        def self.workflow_update_validator(update_method)

        # Exposes an attribute as a query. 💭 Why? We found this _very_ valuable in
        # .NET. Think of it as attr_reader for workflows. It was also decided there
        # was not enough value to have attr_accessor shortcut for update or
        # attr_writer shortcut for signals since both are not commonly just
        # getter/setter.
        def self.workflow_query_attr_reader(query_method)

        # Called in the workflow definition to change the name from the default.
        def self.workflow_name(name)

        # Placed above initialize to get start arguments.
        def self.workflow_init

        # See dynamic section.
        def self.workflow_dynamic

        # Called in the workflow definition for initialize and execute to get
        # RawValue arguments (useful for dynamic workflows).
        def self.workflow_raw_args
      end

      # User must implement
      def execute(*args)
    end

    ########
    # Class methods that can only be called during runtime, but don't have to be
    # in a workflow context
    ########

    # Whether in a workflow
    def self.in_workflow?

    ########
    # Class methods that can only be called during runtime in a workflow context
    ########

    # No start_activity because that can be in a future (see asynchrony section).
    def self.execute_activity(activity, *args, **left_off_for_brevity)
    def self.execute_local_activity(activity, *args, **left_off_for_brevity)

    # Returns ChildWorkflowHandle.
    def self.start_child_workflow(workflow, *args, **left_off_for_brevity)
    # Returns actual result.
    def self.execute_child_workflow(workflow, *args, **left_off_for_brevity)

    # These are a custom hash class that only supports []= mutation and
    # validates input as a signal/query/update definition. Basically they will
    # be simple delegators to frozen hashes only updatable via index. Symbol
    # keys or nil key for dynamic. All values are "definition" objects.
    def self.signal_handlers
    def self.query_handlers
    def self.update_handlers

    def self.info
    def self.current_update_info

    def self.search_attributes
    def self.upsert_search_attributes(*updates)
    def self.raw_memo
    def self.memo_value(name)
    def self.upsert_memo(*updates)

    def self.external_workflow_handle(id, run_id: nil)

    def self.patched(id)
    def self.deprecate_patch(id)

    def self.cancellation
    # Just a shortcut to getting a future that fails on cancel. Good for
    # Future.any_of use.
    def self.cancellation_future
    def self.logger
    def self.now
    def self.payload_converter
    def self.random
    def self.uuid
    def self.wait_condition(&)

    # See async primitives section later
    def self.sleep(summary: nil, cancellation: Workflow.cancellation)
    def self.timeout(sec, klass = nil, message = nil, summary: nil, cancellation: Workflow.cancellation, &)
    Timeout ::Timeout
    Mutex = ::Mutex
    ConditionVariable = ::ConditionVariable
    Queue = ::Queue
    SizedQueue = ::SizedQueue

    class ContinueAsNewError < Error
      def initialize(*args, workflow: nil, **left_off_for_brevity)
    end

    class Unsafe
      def replaying?
      # See TracePoint later on why this is present.
      def illegal_call_tracing_disabled(&)
    end

    # Other nested classes omitted for brevity
  end
end
```

Notes:

* Notice lack of `timeout` on `wait_condition`, we will support Ruby `Timeout` via the fiber scheduler.
* Notice lack of `sleep`, we will support Ruby `sleep` via the fiber scheduler.
* A `cancellation` can be provided to every async thing, but by default it's the workflow-level one.
* A workflow builds a `Workflow::Definition::Info` object which contains metadata about the structure including a set of
  `Workflow::Definition::Signal`s, `Workflow::Definition::Query`s, and `Workflow::Definition::Update`s built from the
  handlers (but of course handlers can be added/removed at runtime via the `_handlers` hashes).
* The `workflow_` methods above can only be called during class definition time not workflow runtime.
* The runtime class methods above can only be called during runtime.
* `respond_to_missing?` + `inherited` will be leveraged such that all definition-time defined handlers will return their
  definition if they are called as class methods. So `FooWorkflow.some_signal` will return a
  `Workflow::Definition::Signal` if an instance method of `some_signal` exists marked as a `workflow_signal`.
  * 💭 Why? It is helpful for callers/client-side to be able to reference something more explicit than a symbol, and it
    also helps with making sure if the name is changed we use that name instead of the method name. Symbols can always
    be used though.
  * ❓ Is this acceptable or too much magic?
  * ❓ Is there a better way to reference an interaction outside of the instance of the class that works well with Ruby
    generic typing frameworks, e.g. Sorbet?
    * We are trying to avoid the proxy model that Java takes because we have found it is too confusing to users to hide
      that method invocation is actually, say, activity invocation.

## Dynamic Workflows, Signals, Queries, and Updates

* Support dynamic pieces similar to how we have done in Python and .NET.
* Create a new `Temporalio::Converters::RawValue` object that is a pass-through object for raw values (still subject to
  payload codecs), and a `payload_converter` is available in workflow/activity context to convert it.
  * Handler methods will use `RawValue` for args if told to, similar with workflow `execute`/`initialize` if
    `workflow_raw_args` is set.
  * `RawValue` can be returned too.
* To mark a workflow as dynamic, `workflow_dynamic` class method is called. Only one dynamic workflow can be present for
  a worker. The workflow can retrieve its workflow type name via `Workflow.info`
* Dynamic signals, queries, and updates are enabled via `dynamic: true` on the calls before the methods.
  * Dynamic handlers first argument is the string name (it's not a symbol), and all successive arguments are the actual
    arguments.
  * Only one dynamic handler of a type (signal, query, or update) can be on a workflow.

## Workflow Asynchrony

Ruby does not have a built-in task/promise/future/etc concept. However it does have fibers and we can leverage those.

### Custom Fiber Scheduler and Async Primitives

We will write a custom Fiber scheduler. This will provide the following benefits:

* Will write custom fiber scheduler.
* Can leverage stdlib `Timeout`, `sleep`, `Queue`, `SizedQueue`, `Mutex`, and `ConditionVariable`, but also alias/wrap
  them inside `Workflow` module.
  * `sleep` and `timeout` are calls on `Workflow` that provide more options.
  * Classes are just aliased at this time.
  * 💭 Why not disable these and require use of `Workflow` equivalents like other async primitives?
    * We have seen some confusion in some languages for reusing async primitives, but this is a bit different because
      these are standard library items _expected_ to work in all concurrent environments (i.e. threads _and_ fibers).
  * 💭 Why alias/wrap?
    * For aliasing, there's not enough benefit to just copying every stdlib signature.
    * For wrapping, some of these will have extra options. For instance, sleep and timeout can have a "summary" visible
      in the UI.
* All blocking/timer things sent to scheduler that are part of stdlib items will have the cancellation assumed to be
  the workflow cancellation.
  * ❓ Should we have a way to change the current default cancellation "in scope" so users can override this?
* Able to fail some IO calls in Fiber scheduler, but most things rely on `TracePoint` (see later).
* While it will technically work, discourage use of https://github.com/socketry/async.
  * 💭 Why discourage use? After a lot of team discussion and learnings from Python and .NET, we learned:
    1. Non-Temporal asynchronous helpers can be confusing for users (because often only half can be used)
    2. The implementations can have surprising non-determinisms
    3. Implementations can make internal changes in incompatible ways in newer versions
    4. Java and Go have a very minimal set of async primitives and that is plenty for users

### Futures

Since Ruby does not have a concept of a task/promise/future, we have to create one. Users need all the common features
of a future without us depending on a library. Here's a high-level view of what the class may look like:

```ruby
class Future
  # Returns [Future, Setter].
  def new_with_setter

  # Returns future whose result is set to the first completed future's result or
  # failed with the first future's failure. Therefore, this will raise on
  # failure when `wait`ed.
  def self.any_of(*futures)
  # Returns future whose result is set to nil when all futures succeed or
  # has its failure set to the first failure. Therefore, this will raise on
  # failure when `wait`ed.
  def self.all_of(*futures)

  # Returns future whose result is set to the first future completed (so a
  # future in a future). Therefore, this will not raise on failure when
  # `wait`ed.
  def self.try_any_of(*futures)
  # Returns future whose result is set to nil when all futures complete
  # regardless of whether any future failed. Therefore, this will not raise on
  # failure when `wait`ed.
  def self.try_all_of(*futures)

  # Starts the provided block in the background. Block result will be future result,
  # block exception will be future failure.
  def initialize(&)

  # True even if the result was set with nil
  def result?
  # Nil if not yet set _or_ set with nil
  def result

  def failure?
  # Nil if not (yet) failed
  def failure

  # Raises on failure or returns result
  def wait
  # Returns result or nil on failure (does not raise)
  def wait_no_raise

  class Setter
    # Fails if this or failure are already set
    def result=
    # Fails if this or result are already set
    def failure=
  end
end
```

Notes:

* Cancellation can get confusing. We can either immediately cancel when waiting or we can let the futures cancel
  themselves.
  * How SDKs handle this today:
    * Go - Multi wait (`Selector.Get`) does not cancel immediately, and neither does `Future.Get`
    * Java - Multi wait (`Promise.anyOf`) does not cancel immediately, and neither does `Promise.get` (but there is
      `Promise.cancellableGet`)
    * TypeScript - Multi wait (`Promise.race`/`Promise.any`) does not cancel immediately, and neither does
      `await promise`
    * Python - Multi wait (`asyncio.wait` + `FIRST_COMPLETED`) does cancel immediately, and so does `await future`
    * .NET - Multi wait (`Workflow.WhenAny`) does not cancel immediately, and neither does `await task`
  * For Ruby we have chosen to match all non-Python and not interrupt on cancellation on any of the calls, but we do
    offer a `Workflow.cancellation_future` that can be used in `any_of`.
    * This has the added benefit that `async` library will continue to work well with our futures and vice-versa.
* We have chosen not to have additional combinators (e.g. `then` or `compose`) because these are easy to compose on
  their own and we can add later if we want, but we want a simple API at first.
* Nothing in the "Workflow API" returns these futures because it is easy enough to wrap.
* Unlike some other Ruby libraries (e.g `concurrent-ruby`), we do not wrap exceptions. That means, like our other SDKs,
  if you need to know in a `all_of` scenario which future failed, you either check the futures or put more detail into
  the thing raised from the future block.
  * 💭 Why not wrap exceptions? Because certain exception types are treated differently by the outer workflow failure
    handling logic to differentiate task failure from workflow failure, and we don't want to have special
    unwrap-from-future-fail in there. It can get confusing for users to catch too.
* We chose not to make whether `any_of` raises be configurable. There is a lot of confusion about what return value
  and exception situation should be across the industry in different languages. We're taking a very simple approach
  and if users struggle with `any_of` and needing to know which future succeeded/failed, they can be more specific in
  their return/raise inside their future block.
  * We chose to add an `try_any_of` that does not raise on `wait`.
    * 💭 Why not just an arg? Because it would change return value which is a confusing thing to do just based on arg.
    * 💭 Why not `any_of!`? Because it's not necessarily more dangerous needing `!`, just a different behavior.
* We chose not to make whether `all_of` raises be configurable. There is a lot of confusion about what return value
  and exception situation should be across the industry in different languages. We're taking a very simple approach
  and if users struggle with `all_of` need to wait for other futures to succeed when one fails, they need to make sure
  none fail (can return exception instead or something).
  * We chose to add an `try_all_of` that does not raise on `wait`.
    * 💭 Why not just an arg? Because we have `try_any_of` and this is consistent with that.
    * 💭 Why not `all_of!`? Because it's not necessarily more dangerous needing `!`, just a different behavior.

Example of running many activities and waiting on all to complete:

```ruby
class ManyActivityWorkflow < Temporalio::Workflow
  def execute(count)
    futures = count.times.map do
      Future.new do
        Workflow.execute_activity(MyActivity, 'some arg' start_to_close_timeout: 5)
      end
    end
    Temporalio::Workflow::Future.all_of(*futures).wait
  end
end
```

### Task Running

Temporal workflow tasks for the workflow worker portion are short-lived CPU-bound work. While these usually only take a
few milliseconds to run, they still use a thread and so we need to give the user some control over this.

* We will extract the thread pool from `Temporalio::Worker::ActivityExecutor::ThreadPool` to
  `Temporalio::Worker::ThreadPool` (and have activity executor use it).
* `Temporalio::Worker::WorkflowTaskExecutor` will exist with two implementations
  * `Temporalio::Worker::WorkflowTaskExecutor::Ractor` that runs workflows as Ractors.
    * This is the default workflow task executor for workers at this time. See "Ractors" section for more detail.
    * There is a `default` class method with a lazily created global default.
  * `Temporalio::Worker::WorkflowTaskExecutor::ThreadPool` that accepts a thread pool which defaults to max threads
    unbounded.
    * This is the executor to use to not use "Ractors".
    * There is a `default` class method with a lazily created global default.
    * ❓ Is this an acceptable default? Python uses `[Etc.nprocessors, 4].max` as the max threads, but we figure it can
      be unbounded here and remain bounded by the Core `max_concurrent_workflow_tasks` (TODO: expose this, it was left
      off in `main`).
    * ❓ Should the default share the same thread pool as activity executor?
* Worker option called `workflow_task_executor` will exist that accepts this.
  * Defaults to `Ractor` implementation. See the "Ractors" section.
* 💭 Why not hide some of this and just accept some worker options that govern them?
  * There is some value in reusing this across workers.
  * _Technically_ users may want to customize task running, but we should strongly discourage it.

## Ensuring Deterministic Workflows

Workflows must be deterministic. In every SDK, if there are non-intrusive ways to prevent non-deterministic code, we
apply them. Here are some things we do in other SDKs:

* Go - static analyzer checks things
* Java - static analyzer checks things (not yet incorporated into SDK as of this writing)
* TypeScript - v8 sandboxing
* Python - homemade sandbox (that is confusing for users to understand and work around)
* .NET - event listener that checks if you leave the single workflow thread

There are two primary ways determinism is violated:

* State sharing across workflow runs
* Making illegal calls (i.e. system time, rand, IO, threading, etc)

Here are some Ruby features that _could_ help and whether we will apply them or not:

* Monkey patching to prevent illegal calls.
  * Not really acceptable in a global way. Our library is used alongside other code, and even patching to do a
    thread-local check before delegating is unacceptable (we'd end up in people's backtraces and other bad things).
  * Technically acceptable in a Ractor, but even ignoring that Ractors are optional, it's expensive to redefine all the
    things ahead of time in every Ractor.
* Refinements to prevent illegal calls.
  * These are only scoped to the file/module/class where they are defined, not good enough for transitive checks we
    need.
  * Unacceptable performance hit to refine all we need to refine.
* `TracePoint` to prevent illegal calls.
  * Can be enabled on a specific thread which is nice to not affect other Ruby code.
  * We would only check `:call` events probably, so not as bad of performance as some other uses of TracePoint.
  * If running inside a Ractor, this only affects that Ractor which is nice.
  * This approach is similar to what we did in .NET.
  * We need to measure performance here.
* `Ractor`s to isolate state and prevent some illegal calls.
  * Ractors are experimental and upon first use give this warning: "warning: Ractor is experimental, and the behavior
    may change in future versions of Ruby! Also there are many implementation issues."
    * This will scare users.
  * Users to be able to not use Ractors. The question becomes which is the default, knowing we can never change the
    default even if Ractors do stabilize.
* `Binding` to isolate state and prevent some illegal calls.
  * We can create a binding and eval code within, but to do this transitively, we'd have to monkey patch `require` to
    force reload which is not acceptable.
  * This is effectively what we did with the Python sandbox and it is a big pain for users to understand when they want
    to reload vs "pass through".

So, after reviewing the options, only `TracePoint` and `Ractor` are viable in some ways, and are still subject to
performance evaluation.

### TracePoint

We will create a `TracePoint` and enable it for a thread only when a workflow task is running on that thread. This
should not have any performance impact outside of workflows. Currently it is believed we only need the `:call` event. It
will do a quick lookup on a hash (or a hash of hashes) to check whether the call is disallowed and if it is, an
exception will be raised.

If a user needs to disable this for any reason (e.g. OTel libraries or advanced metrics/logging calls), they can run
their code inside a block given to `Workflow::Unsafe.illegal_call_tracing_disabled`. There will also be
`disable_workflow_tracing` worker option that will default to `false`.

* ❓ Determine performance impact with this present vs not.

### Ractors

We will offer a way to run workflows in a `Ractor`. This will provide us protection against state mutation. The downside
is that not only are Ractors not stable and may have bugs, but they also give off a warning. A workflow instance will be
in a Ractor and Core activations will be communicated.

* The default task executor will be the Ractor task executor. 💭 Why?
  * We will never be able to change the default to a more-restrictive default later.
  * The value of state isolation and our non-advanced use of of Ractors outweighed Ractor stability concerns.
  * It was unreasonable to not have any default at all and force users to pick the workflow task executor.
  * Yes users will see the Ractor warning, which may actually be a good thing.
  * We will provide an easy, well-documented way to not use Ractors (it's just setting
    `workflow_task_executor: Temporalio::Worker::WorkflowTaskExecutor::ThreadPool.default` for worker).
  * Subject to benchmarking (i.e. if we find performance is terrible, we may change our decision).
* ❓ Determine performance impact with this present vs not.
