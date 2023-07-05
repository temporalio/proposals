<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Nexus RPCs - short recap](#nexus-rpcs---short-recap)
- [Operation identifiers](#operation-identifiers)
  - [Caller generated identifiers](#caller-generated-identifiers)
    - [Handler addressability](#handler-addressability)
      - [Mapping from client to handler identifiers](#mapping-from-client-to-handler-identifiers)
  - [Handler generated identifiers](#handler-generated-identifiers)
    - [Cancel before started](#cancel-before-started)
  - [Comparing the approaches](#comparing-the-approaches)
    - [Handler Id qualification](#handler-id-qualification)
    - [Ids as inputs](#ids-as-inputs)
    - [Caller friendliness](#caller-friendliness)
    - [Data sensitivity](#data-sensitivity)
- [Proposal](#proposal)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Nexus RPCs - short recap

At the fundamental level, the Nexus protocol is a synchronous RPC protocol. Asynchronous operations are modelled on top
of a set of pre-defined RPCs.

A Nexus **caller** calls a **handler**. The handler may respond inline or return a reference for a future, asynchronous
operation. These asynchronous operations can be cancelled and checked for their outcomes and current state. The caller
can also specify a callback URL, which the handler uses to asynchronously deliver the result of an operation's when it
is ready.

## Operation identifiers

Since an asynchronous operation is modelled on top of synchronous RPCs, it must be addressable (identifiable) by both
the caller and the handler. There are two approaches for generating identifiers, caller side and handler side.

### Caller generated identifiers

With this approach, the caller provides an Id to each of the pre-defined RPCs.

The handler _should_ qualify an identifier when dealing with untrusted sources and multi-tenant applications.

The following set of RPCs would be needed to model asynchronous operations using client generated Ids:

- `Start(operation, id, input, callbackURL)` - handler responds inline or indicates that an async operation was started
- `Cancel(operation, id)` - cancel operation by Id
- `GetResult(operation, id)` - get operation result by Id
- `Describe(operation, id)` - get operation status by Id
- `DeliverResult(token)` - deliver a result of an async operation using a token in the Start request's callback URL

Example invocations:

```js
Start(
  'charge',
  transactionId,
  { customerId: 'someCustomerId', amount: 5000 },
  'nexus://caller.example.com/callback?token=' + token
);
Cancel('charge', transactionId);
```

#### Handler addressability

In some cases, the handler might require more than just a single identifier for a given operation, e.g. when an
operation is backed by a workflow update, which requires both a workflow Id and an update Id. In order to avoid
maintaining a handler side persistent mapping between caller and handler identifiers, the handler may choose to "leak"
this detail to the caller, which would need to concatinate multiple identifiers for a given call. The example above
becomes:

```js
Start(
  'charge',
  customerId + '/' + transactionId,
  { amount: 5000 },
  'nexus://caller.example.com/callback?token=' + token
);
Cancel('charge', customerId + '/' + transactionId);
```

> NOTE: This looks a lot like a nested REST style URL, e.g: `/customers/{customerId}/charges/{transactionId}`.

> To take this approach to the extreme, `operation` and `id` could be combined into a single `path` argument, as shown
> below:
>
> - `Start(path, input, callbackURL)`
> - `Cancel(path)`
> - `GetResult(path)`
> - `Describe(path)`

##### Mapping from client to handler identifiers

To avoid leaking the identifier construction logic to the client, the handler would need a mapping of client identifiers
to handler identifiers. Temporal can provide a strongly consistent store out of the box for this mapping.

A single execution would need to map to multiple client identifiers to account for workflow starts and updates.

Looking up an identifier in persistent storage added latency, and should be opted in to.

### Handler generated identifiers

With this approach, the handler returns a reference Id in response to a start call, which the caller should persist for
use with the pre-defined RPCs as shown below:

- `Start(operation, input, callbackURL, cancelBeforeStarted)` - handler responds inline or returns a reference Id
  ([`*`](#cancel-before-started))
- `Cancel(reference_id)` - cancel operation by handler provided reference Id
- `GetResult(reference_id)` - get operation result by handler provided reference Id
- `Describe(reference_id)` - get operation status by handler provided reference Id
- `DeliverResult(token)` - deliver a result of an async operation using a token in the Start request's callback URL

The handler _should_ either sign or qualify caller-provided reference Ids when dealing with untrusted sources and
multi-tenant applications.

In order to support stateless clients, the handler may provide an additional set of APIs to resolve client input to a
reference Id. This may be something that is built into the protocol or implemented ad-hoc. To support this at the
protocol level, we would need to add the following APIs:

- `Resolve(operation, input) -> reference_id`

-- OR --

- `Cancel(operation, input)` - cancel operation by handler derived Id
- `GetResult(operation, input)` - get operation result by handler derived Id
- `Describe(operation, input)` - get operation status by handler derived Id

NOTE: This looks a lot like the APIs for the "client generated Ids" approach, except the ID is structured instead of a
single string.

#### Cancel before started

A caller may cancel an operation before it obtains a reference Id, e.g. if it is uncertain that the operation has been
already started due to crashes and timeouts. Because the caller doesn't have a referencable Id or knowledge of which
input fields are used to derive the Id, it would need to pass in the entire Start call input.

This is especially important when we want to automate cancellations of workflow initiated operations, Temporal server
cannot derive the Id from opaque input.

### Comparing the approaches

#### Handler Id qualification

With handler generated Ids, to support stateless clients, the handler would need to be able to map an operation and
input to a reference Id. It would also need to qualify a reference Id or securely issue the reference Ids when callers
cannot be trusted. With caller generated Ids, the handler would only need to qualify an Id based on the caller context
(e.g by concatinating it with a tenant Id).

#### Ids as inputs

With the caller generated Id approach, if the Id is used for handler side addressability, the handler would need to
parse it and merge with the request's input.

#### Caller friendliness

Shifting the responsibility for creating a handler addressable Id to the caller makes an API harder to use.

If we can map arbitrary client Ids to handler addressable resources, the client generated Id approach is easiest to use
from stateless clients. The SDK can generate deterministic Ids for calls started from workflows.

Handler generated Ids is the least friendly approach for stateless clients without additional APIs for mapping input to
a handler addressable resources.

#### Data sensitivity

If a client is expected to provide a business meaningful Id that encodes sensitive information to address an operation,
the Id would need to be encrypted making it harder to use.

Both handler generated Ids and caller generated Ids with handler mapping options avoid the data sensitivity issue.

## Proposal

- Require client generated Ids for any call that starts an asynchronous operation.
- API will be based on the rough draft in [Caller generated identifiers](#caller-generated-identifiers).
- Temporal exposes a strongly consistent mapping of caller to handler identifiers that handlers may choose to leverage.
