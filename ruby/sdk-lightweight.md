# Ruby SDK (lightweight overview)

This is a lightweight proposal for the Ruby SDK. The intention for this proposal is to give everyone
an end-to-end feel for the Ruby SDK. Many aspects of this proposal will probably change in the more
detailed versions later.


## Types

After many experiments we've decided to not proceed with Ruby typing at this point. This decision
will be revisited when Ruby's typing system matures to support non-basic use-cases.


## Defining an activity

Activities are defined as classes ([a very common practice](https://guides.rubyonrails.org/active_job_basics.html)
given that the language is object-oriented). Activities are expected to implement an `#execute`
method that will be called to execute an activity.

`sum_activity.rb`

```ruby
# The activity class name will be used as activity name unless overridden
class SumActivity < Temporal::Activity
  # Optionally override the name
  activity 'sum-activity'

  # return value of the #execute method will be used as an activity result
  def execute(a, b)
    a + b
  end
end
```

#### Alternative approaches

- Using plain methods as activities. This is not feasible in Ruby since non-namespaced methods
  are global without a clear way to reference them (would have to be `method(:my_activity)`)

- It is possible to allow multiple activities per class, however we've decided against this because
  there's an extra complexity to the invocation (extra argument representing the method) and it
  complicates the use of class-level "decorators" (e.g. for specifying activity name or other
  options)


## Defining a workflow

Similar to activities, workflows are also represented as classes.

`sum_workflow.rb`

```ruby
require 'sum_activity'

# Similar to activities the class name will be used as a workflow name unless overridden
class SumWorkflow < Temporal::Workflow
  # Optionally override the name
  workflow 'sum-workflow'

  def execute(a, b)
    # - Positional arguments passed to activity (inline with other SDKs)
    # - Keyword arguments are reserved for options
    # - This call is blocking
    workflow.execute_activity(SumActivity, a, b, start_to_close_timeout: 10)

    # - Starting an activity by its name rather than a class
    # - The result of this activity will be used as a workflow result (Ruby standard)
    workflow.execute_activity('sum-activity', a, b, start_to_close_timeout: 10)
  end
end
```

#### Alternative approaches

- For the same exact reasons it is not feasible to use non-namespaced methods for workflow

- Similar to activities it should be possible to define multiple workflows per class, however this
  will not be allowed to avoid a perception of a shared state between workflows and allow for
  class-level "decorators"


## Start a workflow

```ruby
require 'temporal/client'
require 'sum_workflow'

connection = Temporal::Connection.new('localhost:7233')
client = Temporal::Client.new(connection, namespace: 'demo')

# workflow is referenced by the class
handle = client.start_workflow(SumWorkflow, 1, 2, id: 'id-1', task_queue: 'demo')
handle.result # => 3
```

#### Alternative approaches

- Starting a foreign workflow from a string name

```ruby
client.start_workflow('sum-workflow', 1, 2, id: 'id-1', task_queue: 'demo')
```

- Starting a foreign workflow with the help of a stub

```ruby
class MyWorkflow < Temporal::Workflow
  # Optionally override the name of the workflow
  workflow 'my.workflow'
end

client.start_workflow(MyWorkflow, 1, 2, id: 'id-1', task_queue: 'demo')
```


## Start a worker

```ruby
require 'temporal/worker'
require 'sum_workflow'
require 'some_other_workflow'
require 'sum_activity'
require 'some_other_activity'

connection = Temporal::Connection.new('localhost:7233')
worker = Temporal::Worker.new(
  connection,
  namespace: 'demo',
  task_queue: 'demo',
  workflows: [SumWorkflow, SomeOtherWorkflow],
  activities: [SumActivity, SomeOtherActivity]
)

worker.run
```

#### Alternative approach

To support passing additional context to the activity classes a worker can be initialised with an
instance of the activity class (only available for activities).

```ruby
redis = Redis.new('localhost:6379')

Temporal::Worker.new(
  ...,
  activities: [CalculatorActivities.new(redis)]
)
```

*NOTE: This however will come with a heavy warning — the activity must be strictly thread-safe as
the provided instance will be called from multiple threads (and possibly at the same exact time).*


## Execute a child workflow

`parent_workflow.rb`

```ruby
class ChildWorkflow < Temporal::Workflow
  def execute(name)
    "Hello, #{name}!"
  end
end

class ParentWorkflow < Temporal::Workflow
  def execute
    workflow.execute_workflow(ChildWorkflow, 'parent', id: 'id-2')
  end
end
```


## Async workflow

Ruby doesn't have a standard (or at least very popular) framework for async execution of the code.
Because of this we can assume that most Ruby engineers using the SDK won't be immediately familiar
with writing async code. Because of this we have decided to make async execution opt-in, keeping
everything synchronous by default.

We have also chosen an eager execution pattern where any `async` block is started immediately and
performed until blocked before proceeding with the execution. This is a bit easier to get a hold of
and eliminates the risk of forgetting to actually start an async block. However this means that
we'll need to find a solution for unhandled promise rejections, which we'll cover separately in a
more detailed workflow proposal.

We will introduce a helper method `async` to execute a block of code asynchronously:

```ruby
require 'sum_activity'

class AsyncWorkflow < Temporal::Workflow
  def execute
    activity_promise = async { workflow.execute_activity(SumActivity, 1, 2) }
    workflow_promise = async { workflow.execute_workflow(ChildWorkflow, 'parent') }

    # Block execution until both promises are resolved
    workflow.wait_for(activity_promise, workflow_promise)

    activity_promise.result # => 3
    workflow_promise.result # => 'Hello, parent!'
  end
end
```

A bit more involved example:

```ruby
class AnotherAsyncWorkflow < Temporal::Workflow
  def execute
    promise_1 = async { wait_and_sum(1, 2, delay: 10) }
    promise_2 = async { wait_and_sum(3, 4, delay: 15) }

    # The same exact method can be called in a blocking fashion
    wait_and_sum(5, 6, delay: 5) # => 11

    # Block execution until any promise is resolved
    async.wait_for(async.any(promise_1, promise_2))

    promise_1.result # => 3

    # Because of the longest delay this would block until resolved
    promise_2.result # => 7
  end

  private

  def wait_and_sum(a, b, delay:)
    workflow.sleep(delay)
    workflow.execute_activity(SumActivity, a, b)
  end
end
```


## Activity heartbeats & cancellations

This approach uses `Thread#raise` that will eject the execution out of the current context. In cases
where this is not acceptable we will allow to either wrap a critical code in an `activity.shield`
block (that will not raise until the block has executed) or opt-out of this default behaviour
altogether and use `activity.cancelled?` flag to determine when an activity was cancelled.

```ruby
class MyActivity < Temporal::Activity
  def execute
    loop do
      sleep 1
      activity.heartbeat('ping')
    end
  rescue Temporal::Error::ActivityCancelled
    raise 'this activity is cancelled'
  end
end
```

Here is what it will look like from a workflow perspective:

```ruby
class MyWorkflow < Temporal::Activity
  def execute
    # Async blocks double as cancellation scopes
    promise = async { workflow.execute_activity(LongRunningActivity) }

    workflow.sleep(10)

    # Blocking call
    promise.cancel
  end
end
```

*NOTE: While `promise.cancel` is blocking, it can be wrapped in an `async` block for non-blocking
cancellations.*

#### Alternative approaches

- Overall using `Thread#raise` is considered bad practice because it might raise in the
  middle of some process. We might want to consider opting in to this behaviour instead


## Workflow cancellations

To handle external workflow cancellations (requested by a client or another workflow) we will use a
similar approach to activities. By default the cancellation will attempt to cancel all currently
executing fibers. To protect critical functionality from cancellations a `workflow.shield` method
can be used. In which case cancellation will raise after the block is executed:


```ruby
class MyWorkflow < Temporal::Activity
  def execute
    workflow.execute_activity(SomeActivity)

    workflow.shield do
      promise_1 = async { workflow.execute_activity(AnotherActivity) }
      promise_2 = async { workflow.execute_activity(SomeOtherActivity) }

      workflow.wait_for(promise_1, promise_2)
    end
  rescue Temporal::Error::WorkflowCancelled
    ...
  end
end
```


## Register signal and query handlers

`calculator_workflow.rb`

```ruby
class CalculatorWorkflow < Temporal::Workflow
  # Both signal and query handlers can be defined as Symbols (when the name matches the
  # method) or a Hash when name is different (or cannot be used as a method name)
  signals :add, 'my.signal.subtract' => :subtract
  queries :get_value, 'my.query.value' => :get_value

  # It is preferable in this case to initialize the values before the execution to
  # support starting a workflow with a signal
  def initialize
    @value = 0
  end

  def execute
    workflow.wait_for { @value >= 42 }
  end

  private

  def add(val)
    @value += val
  end

  def subtract(val)
    @value -= val
  end

  def get_value
    @value
  end
end
```

#### Alternative approach

To provide extra flexibility in handling signals and queries (especially from external classes and
methods) we will allow to define signals and queries from the workflow context:

```ruby
class CalculatorWorkflow < Temporal::Workflow
  def execute
    value = 0

    workflow.on_signal('add') do |val|
      value += val
    end

    workflow.on_signal('subtract') do |val|
      value -= val
    end

    workflow.on_query('get_value') do
      value
    end

    # A condition block will pause until the enclosed statement returns true
    workflow.wait_for { value >= 42 }
  end
end
```


## Signal and query a workflow

```ruby
require 'calculator_workflow'

connection = Temporal::Connection.new('localhost:7233')
client = Temporal::Client.new(connection, namespace: 'demo')

handle = client.start_workflow(SumWorkflow, 1, 2, id: 'id-1', task_queue: 'demo')
handle.signal(:add, 34)
handle.query(:get_value) # => 34
handle.signal(:subtract, 4) # This will send a 'my.signal.subtract' signal as defined
handle.query(:get_value) # => 30
handle.signal(:add, 12)
handle.query(:get_value) # => 42
```

Performing these operations on a child workflow looks very similar:

```ruby
class ParentWorkflow < Temporal::Workflow
  def execute
    # Note that we're using #start_workflow here instead of an #execute_workflow to
    #   obtain a handle rather than a result
    handle = workflow.start_workflow(SumWorkflow, 1, 2, id: 'id-1', task_queue: 'demo')

    # All these calls are blocking, but can be executed in an async block
    handle.signal(:add, 34)
    handle.query(:get_value) # => 34
    handle.signal(:subtract, 4) # This will send a 'my.signal.subtract' signal as defined
    handle.query(:get_value) # => 30
    handle.signal(:add, 12)
    handle.query(:get_value) # => 42

    # Block until workflow finishes
    handle.result
  end
end
```


## Extensibility

To allow extending existing classes with the workflow code without passing workflow context
explicitly we will expose a module with all the necessary mixins:

```ruby
require 'temporal/workflow/concern'

class MyClass
  include Temporal::Workflow::Concern

  def run
    promise = async { workflow.sleep(10) }
    ...
  end
end
```

#### Alternative approach

- We've decided against defining `workflow` and `async` methods globally, since that is considered a
  bad practice
- Mixin is a good compromise that allows developers to interact with implicit workflow context,
  however the coupling is intentionally made visible
