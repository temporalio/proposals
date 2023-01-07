# Workflow Task Completion Metadata

We have a need to attach various bits of metadata to workflow task completions. There are a number
of usecases in which the SDK would like to save some information for itself, or tell server about
something, but this information does not influence replay or the reconstitution of workfow state in
any way. Thus, it shouldn't go in a marker or some new kind of history event, because this would
violate the (useful) idea that history events are primarily concerned with recreating workflow
state.

## Use cases

### Reporting currently-being-awaited commands & facts about them

Right now, besides a query, there's no simple way for a user to understand what their workflow is
actively waiting on. Solving this would make it much easier for users to have insight into why
their workflow is or isn't making progress, and could be nicely exposed in the UI.

In particular, understanding what's going on while your workflow is currently running local
activities and performing WFT heartbeats is very opaque. This would make that much more clear.

Imagine being able to get information like this (and do useful things with it in the UI):

```
waiting_on: [
    { command_type: "local_activity", activity_name: "la_func", id: 1, retries: 0, location: "my_file.py:23" },
    { command_type: "local_activity", activity_name: "la_func", id: 2, retries: 5, location: "my_file.py:23" },
    { command_type: "timer", id: 3, duration: "5s", location: "my_file.py:42" },
]
```

### SDK internal versioning

We would like to be able to make SDK changes which affect how history is written, which means
flagging our behavior based on what version of the SDK the history was produced with. Note: *not*
relating to concepts of versioning a *user's* code, but rather the SDK itself.

This internal version could easily slot into this metadata.

Note: This could potentially go in `temporal.api.taskqueue.v1.VersionId` too, but that's more
intended to relate to user code.

### Dynamic config adjustments

Allow the worker to set configurable things which don't directly impact determinism or workflow
state. For example, changing the WFT timeout for the next task.

### Various debugging / analysis information

There's a whole world of little bits of info that could be useful to enable selectively to help
users debug their workflows, help us learn about performance information, etc.

Some examples:
* Emit the OTel span id that was associated with the WFT - now the user can go easily look up any
  logs/events that were emitted as part of that WFT.
* Metrics work great for all sorts of latency measurements, but what if you wanted to know about
  how long a _specific_ WFT took? You could emit that.
* Interceptors could pipe whatever arbitrary data the user wants into there, for use cases where
  memo / search attributes / side effects may not be appropriate.

### Things we haven't thought of

Having this metadata be suitably generic means we dont need to update the API repo for every
possible usecase. Particularly ones where the SDK is the only one who needs to be able to read it.

## Implementation Proposal

We'd add a new metadata field to the
[WFT response](https://github.com/temporalio/api/blob/master/temporal/api/workflowservice/v1/request_response.proto#L274).
And the [WFT completed event](https://github.com/temporalio/api/blob/f0350f8032ad2f0c60c539b3b61ea37f412f1cf7/temporal/api/history/v1/message.proto#L186).
Though the completion event need not necessarily contain all the info sent in the completion. If
it's known and understood that a particular metadata field is simply telling server something
ephemeral, that could be stripped before writing the event.

With the following proto as its type:

```protobuf
message StructuredMetadata {
  // For JSON-esque data representations that can be easily decoded by anyone. Could contain user
  // data that they'd like to show up the UI, for example.
  map<string, google.protobuf.Struct> struct_metadata = 1;
  // For better typed / more efficient binary serialization of types that are expected to be known
  // by their consumers.
  map<string, google.protobuf.Any> proto_metadata = 2;
}
```

Having both fields seems useful here, since `Any` is useful for the SDK making notes to itself which
it knows the type of. `Struct` is essentially just a more efficient JSON representation, and can
be used for arbitrary data that can easily be rendered.

Since `Any` can also be `Struct`, we could have just one field, but this wastes some bytes on the
`type_url` field if we are throwing a lot of structs in there. Keeping them separate also makes
it clear what you can decode without any type knowledge, rather than walking the whole map looking
for struct types in case you want to decode them - that way you only look in the `Any` map when you
know you're looking for something specific.

### Why not just add more fields to WFT completion response?

* Things that the SDK only needs to write down for itself (ex: the versioning usecase) can now be
  made without requiring changes to the API repo, updating the server, releasing it, and ensuring
  that that version is in use. That's real nice.
* Supports arbitrary user-originated data (TBD if we actually want to allow this, but with this
  approach it's easy to add if we do).

### Why not use markers?

This is mentioned above, but I want to reiterate it: 

I think it's very important that history events stay focused on recreating workflow state. The
usecases mentioned here don't impact workflow state, and so they shouldn't get dedicated events
in history. Anything which *does* directly impact workflow state or the recreation of, should indeed
be represented as an event.

You might reasonable argue "Hey! The SDK internal versioning usecase you mentioned earlier in some
sense does or can impact workflow state, why doesn't that get a marker?". I think it's worth
drawing a distinction between "things that impact workflow state and are a consequence of user
code", "things that indirectly impact workflow state but are not a consequence of user code" , and
"things that don't impact state at all". I think only the first of those deserve top-level
representation as history events. The others can be stored as metadata, or not at all.

## Drawbacks
* No dedicated fields means no docstrings for those fields, and less type safety. Though this is
  much less of a concern when the writer and reader are the same person. Type safety can be achieved
  with the `Any` valued map - and should be used for data that is expected to be interpreted by
  more than one component.
* Potential to bloat history.

## Adoption / teaching / etc

Not applicable to this proposal since developers will not *directly* interact with this, but rather
it's just providing a mechanism for ourselves. The "what are we wating on" usecase has obvious and
big value to users, but what exactly gets written there and how we expose it in the UI etc ought to
be another proposal.
