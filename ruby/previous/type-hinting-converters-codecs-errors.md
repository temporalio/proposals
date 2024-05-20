# Ruby SDK - Type hinting, Converters, Codecs and Errors

This proposal goes into details regarding the implementation of data conversion pipeline (including
type hints, converters and codecs) as well as outlines the hierarchy of exception classes.

## Type hinting

The Ruby typing system is not something we can currently rely on for specifying the types of all the
inputs and outputs. Instead we will add custom "annotations" (technically these are just method
calls) to the activity/workflow definitions in order to provide type hinting. Here's the basic
example:

```ruby
class SumActivity < Temporal::Activity
  input Integer, Integer
  output Integer

  def execute(a, b)
    a + b
  end
end
```

We will support most basic Ruby types (e.g. `Integer`, `Float`, `String`, `Symbol`, `Boolean`,
`Array`, `Hash`, etc). This will allow the SDK to perform a runtime check of the arguments and
return values to ensure they match the specified types.

We will also leverage this system to allow SDK users to specify their own types:

```ruby
class MyInput < Struct.new(:a, :b)
  def self.load(hash)
    new(hash['a'], hash['b'])
  end

  def dump
    { 'a' => a, 'b' => b } # explicit for illustration purposes, can use #to_h instead
  end
end

class MyOutput < Struct.new(:sum)
  def self.load(sum)
    new(sum.to_i)
  end

  def dump
    sum.to_s # string used for illustration purposes, can use Integer directly instead
  end
end

class MyWorkflow < Temporal::Workflow
  input MyInput
  output MyOutput

  def execute(input)
    MyOutput.new(input.a + input.b)
  end
end
```

Custom types are expected to implement the following interface:

```ruby
interface _CustomType[U]
  # Take a primitive type and return an instance of the implementing class
  def self.load: (U) -> instance

  # Returns a trivially serializable type representing the custom object
  def dump: -> U
end
```

The same exact concept applies to signals and queries:

```ruby
class MyWorkflow < Temporal::Workflow
  signal :add, input: Integer
  query :get_sum, output: MyOutput

  def execute
    ...
  end
end
```

Notes:

- This feature is 100% optional. Without these definitions the output from converters will be used
  directly as arguments and return values
- The full potential of this solution is obviously limited to a single language SDKs
- When sending a custom input type to another SDK, workflow/activity definitions (without the
  implementation) can still be leveraged
- A custom output type sent to another SDK can still be `dump`ed into a matching JSON or other
  serializable structure
- The same approaches apply to inputs and outputs received from other SDKs


## Payload handling

Ruby SDK will use the model proposed [here](https://docs.temporal.io/concepts/what-is-a-data-converter)
to distinguish between payload converters and codecs.

The main difference is that a Converter translates between any Ruby object and a Payload, while
a Codec is a lower level construct that encodes/decodes from a Payloads protobuf to a Payloads
protobuf. The former is intended to support specific serialisation formats, while the latter is for
modifying a binary that is transmitted over the wire.


### Converters

A payload converter is expected to implement the following interface:

```ruby
interface _PayloadConverter[U]
  # Takes any Ruby object and returns a Payload object
  def to_payload: (U) -> Temporal::Payload

  # Takes a Payload object and returns a Ruby object
  def from_payload: (Temporal::Payload) -> U
end
```

The SDK will provide an implementation of basic converters — Null (for `nil`s), Bytes (any stream of
bytes) and JSON (using the `oj` gem and potentially allowing the SDK user to specify the
[mode](https://github.com/ohler55/oj/blob/develop/pages/Modes.md)). We will also provide a
`Composite` converter to combine multiple converters behind the same interface.

In most cases the SDK users are expected to use the `Composite` converter and add their custom
converters to it. These are expected to have a slightly different interface:

```ruby
interface _EncodingPayloadConverter[U]
  # Returns a MIME type that this converter provides
  def encoding: -> String

  # Takes any Ruby object and returns a Payload object or nil
  # A nil response indicates that this converter was unable to convert the given value
  def to_payload: (U) -> Temporal::Payload?

  # Takes a Payload object and returns a Ruby object
  def from_payload: (Temporal::Payload) -> U
end
```

While a top-level converter is expected to convert any value to a Payload and back (or throw an
error otherwise), an encoding payload converter (the one used with the `Composite` converter) is
only expected to handle values and Payload matching it's specified encoding.


#### JSON Converter

The default JSON converter will respect [the interface](https://ruby-doc.org/stdlib-3.1.2/libdoc/json/rdoc/JSON.html#module-JSON-label-Custom+JSON+Additions)
provided by the Ruby's JSON module to serialize/deserialize an object.


### Codecs

And a payload codec is expected to implement this interface:

```ruby
interface _PayloadCodec
  # Takes an array of Payload objects and returns an array of encoded Payload object
  # The resulting Array is expected to hold at least one Payload
  def encode: (Array[Temporal::Payload]) -> Array[Temporal::Payload]

  # Takes an array of Payloads object and returns an array of decoded Payload object
  # The resulting Array is expected to hold at least one Payload
  def decode: (Array[Temporal::Payload]) -> Array[Temporal::Payload]
end
```


## Errors

Here's the Error hierarchy that is planned for the Ruby SDK:

```ruby
module Temporal
  # top level error superclass
  class Error < StandardError

  # superclass for all errors within the SDK itself
  class InternalError < Error

  # errors specific to Client
  class ClientError < Error

  # errors specific to Worker
  class WorkerError < InternalError

  # superclass for connection, network and response errors
  class RPCError < Error
  class UnexpectedError < RPCError

  # superclass for all API failure responses
  class FailureError < Error

  # type hinting errors
  class TypeError < Error

  # superclass for workflow errors
  class WorkflowError < Error
```

Notes:

- This list is not exhaustive, more errors will be added as parts of the SDK are getting built
- Some concrete error class placement might be confusing and will be clarified later in the process


### Converting API Failures

Similar to other SDKs we will decode `Failure` proto messages to native error classes. All `cause`s
will be decoded recursively and the result will form a hierarchy identical to the one in the proto
response. These error classes will all be subclasses of an `APIError` and will have names matching
the original protobuf messages (while replacing `Failure` with `Error` for consistency within Ruby):

```ruby
module Temporal
  class ApplicationError < FailureError
  class TimeoutError < FailureError
  class CanceledError < FailureError
  class TerminatedError < FailureError
  class ServerError < FailureError
  class ResetWorkflowError < FailureError
  class ActivityError < FailureError
  class ChildWorkflowExecutionError < FailureError
end
```

At this point we are not going to be converting user errors back to their original classes. These
will be decoded into `ApplicationError`s while keeping the original class name, message, stack trace
and other details. Here's an example of handling an activity error:

```ruby
class ProcessPaymentActivity < Temporal::Activity
  class InsufficientFunds < Temporal::NonRetryableError; end
  class PaymentNetworkError < Temporal::RetryableError; end

  def execute(account, amount)
    if amount < balance_of(account.number)
      raise InsufficientFunds, "Account #{account.number} does not have enough funds"
    end

    response = process_payment(account.number, amount)
    if response.failure?
      raise PaymentNetworkError, response.message, response.status
    end

    ...
  end
end

class RenewSubscriptionWorkflow < Temporal::Workflow
  def execute
    ...

    begin
      workflow.execute_activity(ProcessPaymentActivity, account, amount)
    rescue Temporal::ActivityError => error
      if error.cause.is_a?(Temporal::ApplicationError)
        case error.cause.type
        when 'ProcessPaymentActivity::InsufficientFunds'
          # handle insufficient funds error here
        when 'ProcessPaymentActivity::PaymentNetworkError'
          # handle payment network error
          # notice that status is not available
        end
      end

      # You'll need to re-raise the error in case it wasn't handled
      raise
    end

    ...
  end
end
```

To allow customisation of this behaviour we will expose an interface for failure conversion:

```ruby
interface _FailureConverter
  # Takes any Ruby error and returns a Failure object
  def to_failure: (StandardError) -> Temporal::Failure

  # Takes a Failure object and returns a Ruby error
  def from_failure: (Temporal::Failure) -> StandardError
end
```

A default `FailureConverter` will be provided by the SDK that will decode a `Failure` similar to its
representation in the protobuf. For example a child workflow failure that was caused by a user
raised error (e.g. `MyError`) within an activity would be decoded as:

```
ChildWorkflowExecutionError
  -> ActivityError
    -> ApplicationError(type: 'MyError')
```

Notes:

- A better way to handle user errors will be provided across all SDKs at a later stage
- There's currently no way to pass additional error details apart from it's type, message and a
  stack trace. This is a known limitation across all SDKs
- A default


### Configuring client/worker

In order to use the defined converters and codecs, these need to be supplied to a client and worker.

```ruby
converter = Temporal::Converters::Composite.new(
  Temporal::Converters::Null,
  Temporal::Converters::Bytes,
  MyProtobufConverter.new
)
codecs = [EncryptionCodec.new(KEY_ID), CompressionCodec]

connection = Temporal::Connection.new('http://localhost:7233')
client = Temporal::Client.new(
  connection,
  'my-namespace',
  payload_converter: converter,
  payload_codecs: codecs,
  failure_converter: MyFailureConverter.new,
)

worker = Temporal::Worker.new(
  connection,
  namespace: 'demo',
  task_queue: 'demo',
  workflows: [...],
  activities: [...],
  payload_converter: converter,
  payload_codecs: codecs
)
```

*This does indeed involve some duplication and we might simplify this initialization later
on. But it's outside the scope for this proposal.*

Notes:

- All converters and codecs are optional and defaults will be used in case none are provided
- Converters and codecs both can be classes and class instances as long as the given object
  implements the required interface
- The order of both the `Composite` encoding converters and payload codecs matters
- This API is still being figured out to accommodate future features and configuration params


## Data conversion

All the previously outlined modules are required to facilitate the process of data conversion.
Here's the diagram representing it:

![Data conversion](./images/data-conversion.png)

This describes the process that every piece of data (workflow/activity args and return values,
signal inputs, query results, headers, memos, etc) goes through getting transformed from the
user-land object to something that can be transmitted over the wire.

*NOTE: As mentioned previously, the "Type hints" are optional and will be omitted altogether unless
defined.*

The reverse process is applied when converting the data from a protobuf received over the wire back
to a use-land object.
