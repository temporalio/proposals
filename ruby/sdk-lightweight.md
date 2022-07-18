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

```ruby
class CalculatorActivity < Temporal::Activity
  # Generate custom stubs to be used in workflows:
  # - CalculatorActivity.add
  # - CalculatorActivity.subtract
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
    SumActivity.execute(a, b, start_to_close_timeout: 10)
  end
end
```

#### Alternative approaches

- For the same exact reasons it is not feasible to use non-namespaced methods for workflow

- Similar to activities it should be possible to define multiple workflows per class, however I
  don't think this would be used often


## Start a workflow

```ruby
require 'temporal/client'
require 'sum_workflow'

connection = Temporal::Connection.new('localhost:7233')
client = Temporal::Client.new(connection, namespace: 'demo')

# workflow is referenced with a stub, not just class
handle = client.start_workflow(SumWorkflow.execute(1, 2), id: 'id-1', task_queue: 'demo')
handle.result # => 3
```


## Start a worker

```ruby
require 'temporal/worker'
require 'sum_workflow'
require 'sum_activity'

connection = Temporal::Connection.new('localhost:7233')
worker = Temporal::Worker.new(
  connection,
  namespace: 'demo',
  task_queue: 'demo',
  workflows: [SumWorkflow], # registers all workflows in the class
  activities: [SumActivity] # registers all activities in the class
)

worker.run
```


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

    workflow.on_query('get_value') do
      value
    end

    workflow.wait_for { value >= 42 }
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
handle.signal('add', 8)
handle.query('get_value') # => 8
```
