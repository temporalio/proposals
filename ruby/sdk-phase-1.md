# Ruby - Phase 1

The Ruby SDK will be implemented in two loosely defined phases:

* Phase 1 - Initial project, activity worker, client, and test framework
* Phase 2 - Workflow worker and replayer

This proposal is for phase 1. While proposals and SDK may be done in large phases, work is actually incremental.

Notes for this proposal:

* Everything is subject to change both during proposal time and afterwards during implementation.
* For each place a decision is made, a "💭 Why X? ..." aside is present explaining why.
* For each place an open question exists, a "❓ X?" exists to ask it.

## Overview

The Ruby SDK will be backed by Rust [sdk-core](https://github.com/temporalio/sdk-core) and will follow the model set by
other SDKs.

Much of the work for this proposal and the implementation comes the past proposals in [previous](previous)
and the implementation built from that. 💭 Why start a new proposal/implementation instead of adapting that? The
constraints, approach, and requirements changed enough to justify a clean slate and while many things may be leveraged,
it never went beyond alpha anyways.

Lots of approaches taken here are similar to recent Python and .NET SDKs.

### Requirements

These are the general requirements of the project

* Ruby >= 3.1
  * 💭 Why not older versions? They are all EOL'd and we need Ractors and other things that come with 3.x.
* Limited dependencies
  * This means we will try to make `google-protobuf` the only dependency. We should not depend on `async` or anything
    else if we can help it.
  * 💭 Why? Our dependencies as a library have transitive effects on our users, so we have a responsibility to be
    lightweight.
* Must be both thread-blocking/thread-safe and async-capable
  * PoC shows that this is most easily done with Rust block/callback to `Queue` `push`/`pop` since in modern Ruby
    `Queue.pop` does not block fibers and many other things don't either. Therefore many SDK features like clients and
    codecs don't have to distinguish between sync/async.
  * Activities need to work in both ways and _do_ have to make a distinction (discussed later).
  * 💭 Why async-capable? Core and all SDKs are very parallel and so we want to give that benefit to users if they want
    it.
  * 💭 Why thread-blocking? That's the most common way Ruby is used.
* Be as type-safe as possible with RBS
  * All SDKs leverage generics to try to catch mistyped arguments for, say, calling a workflow/activity and we should
    too.
  * It is acknowledged that RBS and Ruby type hinting in general is rough at this time, but we must do our best.
  * We may be able to leverage https://github.com/AaronC81/sord or similar to not have to duplicate docs and sig files,
    but in general Ruby typing right now is a mess and we likely will hit bugs or advanced cases a yard/RBS combination
    library won't work with.
    * ❓ How hard do we want to work to avoid duplicate yard/RBS typing?
  * 💭 Why not Sorbet? Sorbet can come later or provided separately, but RBS seems to be the newer movement.
* Everything is in the `Temporalio` module and released as a `temporalio` gem starting at 0.2.0
  * 💭 Why 0.2.0? 0.1.x versions already in use at https://rubygems.org/gems/temporalio.
* Internal code will be in `Temporalio::Internal` module including bridge which is in `Temporalio::Internal::Bridge`
  * 💭 Why? It is easier in yard to mark `@api private` on entire module and it avoids cluttering the API docs and other
    modules with internal things.
* Avoid cluttering the top-level `Temporalio` module with many small classes, but some are ok as we try to avoid a
  `Temporalio::Common` module
  * So `Temporalio::RetryPolicy` is preferred over `Temporalio::Common::RetryPolicy`.
  * All search attribute things should be under `Temporalio::SearchAttribute` (e.g. `Temporalio::SearchAttribute::Key`)
    and all metric things under `Temporalio::Metric` (e.g. `Temporalio::Metric::Meter`).
  * 💭 Why not top-level? Cluttering top-level module makes discoverability difficult and API docs unclear.
  * 💭 Why no `Temporalio::Common`? Ruby expects to have common things where they make sense instead of under a `Common`
    module.
  * ❓ Do we want plural, e.g. `Temporalio::SearchAttributes` and `Temporalio::Metrics`? While there is no such thing as
    a `SearchAttribute`, there is such thing as a `SearchAttributes` (i.e. search attributes collection). And there is
    such thing as a `Metric` (i.e. base class for counter, gauge, and histogram). So it could be
    `Temporalio::SearchAttributes` (the collection) and `Temporalio::Metric` (the base class), and they are not modules
    but classes with the nested pieces underneath like we do elsewhere.
* No compatibility with any existing Ruby SDK
  * Migration guides/docs may appear as needed.
  * 💭 Why? Need a clean slate to develop a high-quality SDK from first principles.
* Rust bridge uses [rb-sys](https://github.com/oxidize-rb/rb-sys) and [magnus](https://github.com/matsadler/magnus)
  * 💭 Why not just `ruby.h` directly or just `rb-sys`? There are many things difficult to get right with data
    conversion and we don't feel as if using either library is compromising  our ability to move later if needed.
* Obvious general repo/project rules apply.
  * Linting and auto-formatting (Rubocop check/autocorrect but have to customize Rubocop a lot because its defaults are
    very dogmatic).
  * Type checking (Steep).
  * Deployed to RubyGems as separate gems for pure source, x64 linux, x64 darwin, x64 windows (i.e. mingw-ucrt), aarch64
    linux (i.e. arm64), and arm64 darwin.
  * CI against supported platforms on oldest and newest Ruby versions supported.
  * MIT licensed.
  * Full docs as README.
  * No need for ruby.temporal.io, https://www.rubydoc.info/gems/temporalio is acceptable.
  * Full integration test suite.

### Basic Features

By the very first version, the Ruby SDK should have feature parity with every other SDK (except in cases where we have
decided other features in other SDKs will never be ported). Here's a non-exhaustive list of features we should include
that are not discussed later:

* Interceptors and an OpenTelemetry implementation
* Custom metrics and optional metrics buffer for custom processing
* Typed search attributes, memos, headers, etc
* API key, RPC metadata, HTTP CONNECT proxy support, etc
* Loggers with contextual information
* Full error hierarchy with `Temporalio::Error` as the root
* ❓ Are there any Ruby libraries so widely adopted they might as well be in the standard library and therefore deserve
  optional support (e.g. like Go/Python SDK contrib or .NET SDK extensions)?

## Runtime

* `Temporalio::Runtime` is the full Core runtime.
* Will have class instance variable of `default` that can be set and is lazily created upon first access.
  * Client (technically connection) accepts a runtime and if unset it defaults to `default`
* Initialization of the runtime class starts a Ruby thread that just runs the command loop from Rust.
  * 💭 Why does a runtime need to eat a Ruby thread? The Rust side needs to have a way to make Ruby calls, and only Ruby
    can start a Ruby thread. So on the Rust side there is essentially a loop with a channel waiting without holding the
    GVL with things to run on the Ruby side.
  * 💭 Why do this in a constructor? That is the Ruby way, a constructed object is ready for use.
  * 💭 Why only a single thread? We expect callbacks to Ruby from Rust to be short (hopefully only a block invocation
    that is a `Queue.push`) so we don't expect making all of these run serial is an issue. However if it does become an
    issue, we can use multiple threads and a Rust approach which allows multiple channel consumers.
* Users can create their own runtime with their own telemetry options and such and pass that to clients.
  * 💭 Why not a singleton? Technically users may want different runtimes, though hopefully not ever. Still, tests do
    and it doesn't make sense in many cases to have a singleton that a user creates/initializes.

## Clients

`Temporalio::Client` is a namespace-specific client and `Temporalio::Client::Connection` is a namespace-independent
connection. The former has shortcut for creating the latter while it creates itself. Here's how both may look:

```ruby
module Temporalio
  class Client
    attr_reader :connection, :namespace

    # Connect a client (i.e. Connection.new + Client.new)
    def self.connect(target_host:, namespace: 'default', runtime: nil, ...)
      ...
    end

    # Create client with existing connection
    def initialize(connection, namespace: 'default', ...)
      ...
    end

    # Duped hash of keyword args of constructor
    def options
      ...
    end

    # Returns workflow handle
    def start_workflow(
      workflow,
      *args,
      id:,
      task_queue:,
      ...
    )
      ...
    end

    # Returns result
    def execute_workflow(
      workflow,
      *args,
      id:,
      task_queue:,
      ...
    )
      ...
    end

    # Returns workflow handle
    def workflow_handle(id, run_id: nil, ...)
      ...
    end

    # Lots more
  end

  class Client
    class Connection
      # Perform connection
      def initialize(target_host:, runtime: nil, ...)
        ...
      end

      # Duped hash of keyword args of constructor
      def options
        ...
      end

      # Access to raw workflow service
      def workflow_service
        ...
      end
    end

    class WorkflowHandle
      # Wait for result
      def result(follow_runs: true)
        ...
      end

      # Wait for result
      def result(follow_runs: true)
        ...
      end

      # Lots more
    end
  end
end
```

* There are many things missing here, but the idea is clear.
* We expect most users and most samples to just use `Client.connect`.
  * 💭 Why not make users create a connection themselves instead of maintaining similar options sets across
    `Connection.initialize` and `Client.connect`? We have found most people only need a single client per connection.
* Users that want raw service access need to use `client.connection.workflow_service` similar to .NET.
* Workflow handles exist with all relevant calls.
* Note that we prefer large sets of keyword arguments over hashes or options/config objects.
  * 💭 Why? This is the Ruby preference and clearer to users.
* Must make clear in docs which things issue an RPC call (e.g. start workflow) vs ones that don't (e.g. get workflow
  handle).

### Workflows in Client

Early thoughts on workflows are that they'll be Ractors. For the purposes of this phase, all that may matter is how
workflows are defined so they can be used in a type-safe/custom-named way from a client. All SDKs support defining
workflows without their body and Ruby should as well.

Most of this TBD until next phase, but for early designs for referencing from clients, this probably looks like:

```ruby
class MyWorkflow < Temporalio::Workflow
  workflow_query_attr_reader :some_other_query

  def execute(arg)
    raise NoMethodError
  end

  workflow_signal
  def some_signal(arg)
    raise NoMethodError
  end

  workflow_query 'custom-query-name'
  def some_query(arg)
    raise NoMethodError
  end
end
```

And client usage may look like:

```ruby
# Connect client
client = Client.connect('localhost:7233')

# Start workflow
handle = client.start_workflow(
  MyWorkflow,
  "some arg",
  id="wf-#{SecureRandom.uuid}",
  task_queue='my_task_queue',
)

# Send signal
handle.signal(MyWorkflow.some_signal, "some arg")
```

* This leverages a `method_added` approach to "decorate" methods.
* This will probably create class-method equivalents for each item that will return "definitions" for use in clients.
* We will not spend much time getting this right at first.

## Data Conversion

Like other SDKs, the following classes will exist:

* `Temporalio::Converter::DataConverter` - Accepts a payload converter (must be Ractor shareable), failure converter
  (must be Ractor shareable), and a payload codec
  * 💭 Why use `Temporalio::Converter` module instead of just `Temporalio::DataConverter`? There are many files that are
    included in conversion and most regular users won't ever use them.
  * 💭 Why duplicate words instead of `Temporalio::Converter::Data`? `Temporalio::Converter` is not a base class and a
    `DataConverter` is a completely separate thing from, say, a `PayloadConverter`.
  * ❓ Would we prefer `Temporalio::Conversion` as the module name?
* `Temporalio::Converter::PayloadConverter` - Default composite payload implementation accepting a collection of
  encoding payload converters accepted in constructor, with a default class attr that has a default set.
  * Users are expected to extend this and override conversion methods as needed. Default instantiation of this is 0
    encoding converters and a `NotImplementedError` if either is called.
  * 💭 Why not have a separate base class instead of combining the composite one with the one to override? This was a
    50/50 call, but most users will probably add an encoding impl instead of override at this level. This is admittedly
    a slight deviation from other SDKs.
* `Temporalio::Converter::PayloadConverter::Encoding` - Base unimplemented encoding converter
  * ❓ Would we prefer `Temporalio::Converter::EncodingPayloadConverter`?
* `Temporalio::Converter::PayloadConverter::JSON`, `Temporalio::Converter::PayloadConverter::JSONProto`, etc  - All
  common encoding converters
* `Temporalio::Converter::FailureConverter` - Default failure converter, can be overridden
* `Temporalio::Converter::PayloadCodec` - Unimplemented base codec
  * Important for implementers to ensure this is async capable if using async activities anywhere
* `Temporalio::Converter::RawValue` - Can be used as way to move around unconverted payloads

#### Temporalio::Converter::PayloadConverter::JSON

* Ruby has a `JSON` module in the standard library, but by default it's only primitives, arrays, hashes, etc and not
  classes.
  * There is a concept of "additions", but they set a `json_class` field on the object which makes the JSON not
    cross-language compatible.
  * There are not any good JSON-to-object conversion approaches in Ruby beyond this.
  * Therefore, very unfortunately, it is unreasonable at this time for any area where conversion from payload to value
    is needed to specify the type to convert to. Users can use type hints in their RBS files and such, but that has no
    runtime check/effect.
* The JSON encoding converter initializer will have a way to set parse and generate options.
* The payload converter will have a way to let the default be created with JSON parse and generate options for the JSON
  encoding converter.
  * 💭 Why? Users wanting to simply set JSON options shouldn't have to go through the mess of recreating the default
    list of encoding converters.

## Activities

A simple, heartbeating activity that calls a separate thing:

```ruby
class MyActivity < Temporalio::Activity
  # Can customize name, e.g.
  # activity_name 'custom-name'

  # Can customize executor, e.g.
  # activity_executor :fiber

  # Can make an activity dynamic, e.g.
  # activity_dynamic true

  def initialize(db_client)
    @db_client = db_client
  end

  def execute(arg)
    loop do
      db_result = @db_client.do_thing(arg)
      if db_result
        return db_result
      end
      sleep 1
      Temporalio::Activity::Context.heartbeat
    end
  end
end
```

* Activities are defined as classes.
  * 💭 Why classes instead of methods/functions like every other SDK? There are tradeoffs to both approaches. As
    classes, they are more easily referenced, a bit more easily typed in RBS, and metadata can be applied more easily at
    the class level. This comes at a cost of not being able to easily share state across classes, but users can provide
    something in the constructor multiple activities use. Open to considering activity methods instead.
  * ❓ Would we prefer activities as methods knowing they may not be able to be typed/referenced well? We can't really
    take the workflow signal-ish approach of those pseudo-decorators making class methods unless we say activities must
    be instance methods (since we would allow class methods as activities).
* Activity classes are instantiated at registration time, not for each invocation.
  * 💭 Why? Existing Temporal Ruby SDK does instantiate for each activity task, but this discourages use of shared
    objects or state to be referenced. This does have the tradeoff our other SDKs have of requiring the function to be
    thread safe.
* `Temporalio::Activity::Context` is a thread/fiber-local context available to activities.
  * It has instance methods for info, heartbeat, etc.
  * It has a class method for `current` that returns from thread/fiber-local and class method shortcuts for all instance
    methods.
    * 💭 Why class methods equivalents? `Temporalio::Activity::Context.heartbeat` is easier to read than
      `Temporalio::Activity::Context.current.heartbeat`. In .NET we made them get current instance first because that's
      normal there, and in Python we only offered package-level methods because that's normal there.
    * 💭 Why allow access to an instance? Some users want to pass the activity context to another thread.
  * 💭 Why `Temporalio::Activity::Context` instead of just `Temporalio::Activity` or putting helpers on base class or
    something? It is a common requirement in our SDKs to be able to access the activity context from the environment.
    Also, it is a common requirement to be able to do that from utility methods outside of the explicit activity call.
* Activity can choose its executor, default is `:default`.
  * See worker section for more information on executors.
* Cancellation is reported to the executor.
  * For thread pool executor (the default), this raises a cancellation exception via `Thread.raise`.
  * For fiber executor, this is done via `Fiber.raise`.
  * A method on the activity context, `shield`, can be given a block that will hold off on cancelling until after it is
    done. Nested `shield` calls only raise after the last one is complete.
* Type-safe invocation from workflows is TBD.

## Workers

```ruby
module Temporalio
  class Worker
    # Run multiple workers until signal reached, block optional
    def self.run(*workers, shutdown_signals: [], &block)
      ...
    end

    def initialize(
      client,
      task_queue:,
      activities: [],
      activity_executors: nil,
      ...,
    )
      ...
    end

    # Run until shutdown called or block completed (which calls shutdown)
    def run(&block)
      ...
    end

    # Shutdown worker
    def shutdown()
      ...
    end
  end
end
```

* Following the API of the current Temporal Ruby SDK, workers can be run individually, but we will also provide a class
  method to run several at once.
  * 💭 Why is something needed to run multiple workers for the user? Because in Ruby they don't have easy ways of
    running multiple blocking things at once without external libraries or forcing threads on users.
* Like other SDK methods, `run` is async-capable.
* `activity_executors` can be a hash of `Temporalio::Worker::ActivityExecutor`s to run certain types of activities.
  * Default is `{:default: Temporalio::Worker::ActivityExecutor::ThreadPool.new(max_concurrent_activities), :fiber: Temporalio::Worker::ActivityExecutor::Fiber.DEFAULT}`
  * Activity can choose its executor, default is `:default`.
  * Registration time will fail if activity references an executor that does not exist.
  * Worker run will fail immediately before even starting if it is not run with a fiber scheduler present but any
    activities reference a `Fiber` executor.
    * 💭 Why wait until worker run to fail? Workers can be created outside of an async environment, it's just important
      that they are run within an async environment if there are async activities.
    * ❓ Or should we just enforce this at worker instantiation time too?
  * 💭 Why this executor concept? Ruby has multiple ways of running code and many people use libraries, so we are better
    off supporting multiple executors and just having sane defaults.
* Worker shutdown and all that entails is the same as any other SDK.
* 💭 Why does a worker need a client instead of a connection? Clients have several options like namespace, interceptors,
  and data converter that the worker also needs.

## Testing

* `Temporalio::Testing::ActivityEnvironment` will exist for mocking activity context while testing activity code.
* `Temporalio::Testing::WorkflowEnvironment` will also exist for time-skipping and such, but it's really only useful as
  a way to start a local dev server.