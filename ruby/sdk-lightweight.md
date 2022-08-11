# Ruby SDK (lightweight overview)

This is a lightweight proposal for the Ruby SDK. The intention for this proposal is to give everyone
an end-to-end feel for the Ruby SDK. Many aspects of this proposal will probably change in the more
detailed versions later.


## Types

After many experiments we've decided to not proceed with Ruby typing at this point. This decision
will be revisited when Ruby's typing system matures to support non-basic use-cases.


## Defining an activity

Activities are defined as classes ([a very common practise](https://guides.rubyonrails.org/active_job_basics.html)
given that the language is object-oriented).

`sum_activity.rb`

```ruby
class SumActivity < Temporal::Activity
  # This will generate a default class-level stub SumActivity.execute to be used in workflows
  def execute(a, b)
    a + b
  end
end
```

#### Alternative approaches

- Using plain methods as activities. This is not feasible in Ruby since non-namespaced methods
  are global without a clear way to reference them (would have to be `method(:my_activity)`)

- It is possible to allow multiple activities per class, for example:

'calculator_activities.rb'

```ruby
class CalculatorActivities < Temporal::Activity
  # Generate custom stubs on the class to be used in workflows:
  # - CalculatorActivities.add
  # - CalculatorActivities.subtract
  activities :add, :subtract

  def add(a, b)
    a + b
  end

  def subtract(a, b)
    a - b
  end
end
```


## Defining a workflow

Similar to activities, workflows are also represented as classes.

`sum_workflow.rb`

```ruby
require 'sum_activity'

class SumWorkflow < Temporal::Workflow
  def execute(a, b)
    # - .execute! is a shorthand for .execute().await
    # - only positional arguments are supported (inline with other languages), keyword
    #   arguments are reserved for options
    SumActivity.execute!(a, b, start_to_close_timeout: 10)
  end
end
```

#### Alternative approaches

- For the same exact reasons it is not feasible to use non-namespaced methods for workflow

- Similar to activities it should be possible to define multiple workflows per class, however this
  will not be allowed to avoid a perception of a shared state between workflows


## Start a workflow

```ruby
require 'temporal/client'
require 'sum_workflow'

connection = Temporal::Connection.new('localhost:7233')
client = Temporal::Client.new(connection, namespace: 'demo')

# workflow is referenced via a stub, not just a class
handle = client.start_workflow(SumWorkflow.execute(1, 2), id: 'id-1', task_queue: 'demo')
handle.result # => 3
```

#### Alternative approaches

- Starting a foreign workflow from a string name

```ruby
client.start_workflow(Temporal::Workflow.execute('my.workflow', 1, 2), id: 'id-1', task_queue: 'demo')
```

- Starting a foreign workflow with the help of a stub

```ruby
class MyWorkflow < Temporal::Workflow
  workflow 'my.workflow'
end

client.start_workflow(MyWorkflow.execute('my.workflow', 1, 2), id: 'id-1', task_queue: 'demo')
```


## Start a worker

```ruby
require 'temporal/worker'
require 'sum_workflow'
require 'sum_activity'
require 'calculator_activities'

connection = Temporal::Connection.new('localhost:7233')
worker = Temporal::Worker.new(
  connection,
  namespace: 'demo',
  task_queue: 'demo',
  workflows: [SumWorkflow], # registers all workflows in the class
  activities: [SumActivity, CalculatorActivities] # registers all activities in the class
)

worker.run
```

#### Alternative approach

To support passing additional context to the activity classes a worker can be initialized with an
instance of the activity class (only available for activities).

```ruby
redis = Redis.new('localhost:6379')

Temporal::Worker.new(
  ...,
  activities: [CalculatorActivities.new(redis)]
)
```

*NOTE: This however will come with a heavy warning — the activity must be strcitly thread-safe as
the provided instance will be called from multiple threads (and possibly at the same exact time).*


## Activity heartbeats & cancellations

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

This approach uses `Thread#raise` that will eject the execution out of the current context. In cases
where this is not acceptable we will allow to ewither wrap a critical code in an `activity.shield`
block (that will not raise until the block has executed) or opt-out of this default behaviour
altogether and use `activity.cancelled?` flag to determine when an activity was cancelled.

Here is what it will look like from a workflow perspective:

```ruby
class MyWorkflow < Temporal::Activity
  def execute
    future = MyActivity.execute

    workflow.sleep(10)

    future.cancel!
  end
end
```

*NOTE: `future.cancel` returns a cancellation future that can be used as any other future.*


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
    ChildWorkflow.execute!('parent', id: 'id-2')
  end
end
```


## Async workflow

Calling `#execute` (rather than `#execute!`) on activities and workflows results in their
non-blocking execution.

```ruby
require 'sum_activity'

class AsyncWorkflow < Temporal::Workflow
  def execute
    activity_future = SumActivity.execute
    workflow_future = ParentWorkflow.execute

    workflow.wait_for(activity_future, workflow_future)

    activity_future.result # => 3
    workflow_future.result # => 'Hello, parent!'
  end
end
```


## Register signal and query handlers

`calculator_workflow.rb`

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

#### Alternative approach

To provide extra flexibility in handling signals and queries we will allow to defined signal and
query handlers as methods:

```ruby
class CalculatorWorkflow < Temporal::Workflow
  # Both signal and query handlers can be defined as Symbols (when the name matches the
  # method) or a Hash when name is different (or can not be used as a method name)
  signals :add, 'my.signal.subtract' => :subtract
  queries :get_value, 'my.query.value' => :get_value

  # It is preferrable in this case to initialize the values before the execution to
  # support starting a workflow with a signal
  def initialize
    @value = 0
  end

  def execute
    workflow.wait_for { value >= 42 }
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


## Signal and query a workflow

```ruby
require 'calculator_workflow'

connection = Temporal::Connection.new('localhost:7233')
client = Temporal::Client.new(connection, namespace: 'demo')

handle = client.start_workflow(SumWorkflow.execute(1, 2), id: 'id-1', task_queue: 'demo')
handle.signal('add', 34)
handle.query('get_value') # => 34
handle.signal('subtract', 4)
handle.query('get_value') # => 30
handle.signal('add', 12)
handle.query('get_value') # => 42
```
