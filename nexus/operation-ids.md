<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Nexus RPCs - short recap](#nexus-rpcs---short-recap)
- [Operation identifiers](#operation-identifiers)
  - [Identifier requirements](#identifier-requirements)
    - [Sharing identifiers between clients](#sharing-identifiers-between-clients)
  - [Caller generated identifiers](#caller-generated-identifiers)
    - [Handler addressability](#handler-addressability)
  - [Handler generated identifiers](#handler-generated-identifiers)
    - [Cancel before started](#cancel-before-started)
  - [Comparing the approaches](#comparing-the-approaches)
    - [Handler ID qualification](#handler-id-qualification)
    - [IDs as inputs](#ids-as-inputs)
    - [Caller friendliness](#caller-friendliness)
    - [Data sensitivity](#data-sensitivity)
- [Proposal](#proposal)
  - [API draft](#api-draft)
  - [Notes](#notes)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Nexus RPCs - short recap

At the fundamental level, the Nexus protocol is a synchronous RPC protocol. Arbitrary length operations are modelled on
top of a set of pre-defined synchronous RPCs.

A Nexus **caller** calls a **handler**. The handler may respond inline or return a reference for a future, asynchronous
operation. The caller can cancel an asynchronous operation, check for its outcome, or fetch its current state. The caller
can also specify a callback URL, which the handler uses to asynchronously deliver the result of an operation when it
is ready.

## Operation identifiers

Since an asynchronous operation is modelled on top of synchronous RPCs, it must be addressable (identifiable) by both
the caller and the handler. There are two approaches for generating identifiers, caller side and handler side.

### Identifier requirements

#### Sharing identifiers between clients

The may be situations where it's desirable to safely share access between different clients, e.g. start an operation
with one client and get the result with another using the same identifier.
In those cases identifiers should be unguessable, so that they can behave as an object capability.

This is a non-goal and out of scope for Nexus at the moment but can optionally be implemented on either the caller or
handler sides.

Note that it's the handler's responsibility to qualify identifiers of different tenants in the system and they may
choose to allow cross-tenant sharing.

### Caller generated identifiers

With this approach, the caller provides an operation ID to each of the pre-defined RPCs.

The handler _should_ qualify an identifier when dealing with untrusted sources and multi-tenant applications.

The following set of RPCs would be needed to model asynchronous operations using client generated IDs:

- `Start(service, operation, id, input, callbackURL)` - handler responds inline or indicates that an async operation was started
- `Cancel(service, operation, id)` - cancel operation by ID
- `GetResult(service, operation, id)` - get operation result by ID
- `Describe(service, operation, id)` - get operation status by ID
- `DeliverResult(token, result)` - deliver a result of an async operation using a token in the Start request's callback URL

Example invocations:

```js
Start(
  "payments",
  "charge",
  transactionId,
  { customerId: "someCustomerId", amount: 5000 },
  "nexus://caller.example.com/callback?token=" + token
);
Cancel("payments", "charge", transactionId);
```

#### Handler addressability

In some cases, the handler might require more than just a single identifier for a given operation, e.g. when an
operation is backed by a workflow update, which requires both a workflow ID and an update ID.
The handler may deal with this in a couple ways:

1. Maintain a persistent mapping between caller and handler identifiers incurring overhead for every call.
   Temporal may provide a strongly consistent store out of the box for this mapping or require wrapping these operations in another workflow execution.

   A single workflow execution may be mapped to many client identifiers to account for workflow starts and updates.

2. "Leak" this detail to the caller, which would need to concatenate multiple identifiers for a given call. The example
   above becomes:

   ```js
   Start(
     "payments",
     "charge",
     customerId + "/" + transactionId,
     { amount: 5000 },
     "nexus://caller.example.com/callback?token=" + token
   );
   Cancel("payments", "charge", customerId + "/" + transactionId);
   ```

   > NOTE: This looks a lot like a nested REST style URL, e.g: `/payments/customers/{customerId}/charges/{transactionId}`.

   > To take this approach to the extreme, `service`, `operation` and `id` could be combined into a single `path` argument, as shown
   > below:
   >
   > - `Start(path, input, callbackURL)`
   > - `Cancel(path)`
   > - `GetResult(path)`
   > - `Describe(path)`

### Handler generated identifiers

With this approach, the handler returns a reference ID in response to a start call, which the caller should persist for
use with the pre-defined RPCs as shown below:

- `Start(operation, input, callbackURL, cancelBeforeStarted)` - handler responds inline or returns a reference ID
  ([`*`](#cancel-before-started))
- `Cancel(reference_id)` - cancel operation by handler provided reference ID
- `GetResult(reference_id)` - get operation result by handler provided reference ID
- `Describe(reference_id)` - get operation status by handler provided reference ID
- `DeliverResult(token)` - deliver a result of an async operation using a token in the Start request's callback URL

The handler _should_ either sign or qualify caller-provided reference IDs when dealing with untrusted sources and
multi-tenant applications.

In order to support stateless clients, the handler may provide an additional set of APIs to resolve client input to a
reference ID. This may be something that is built into the protocol or implemented ad-hoc. To support this at the
protocol level, we would need to add the following APIs:

- `Resolve(operation, input) -> reference_id`

-- OR --

- `Cancel(operation, input)` - cancel operation by handler derived ID
- `GetResult(operation, input)` - get operation result by handler derived ID
- `Describe(operation, input)` - get operation status by handler derived ID

NOTE: This looks a lot like the APIs for the "client generated IDs" approach, except the ID is structured instead of a
single string.

#### Cancel before started

A caller may cancel an operation before it obtains a reference ID, e.g. if it is uncertain that the operation has been
already started due to crashes and timeouts. Because the caller doesn't have a referencable ID or knowledge of which
input fields are used to derive the ID, it would need to pass in the entire Start call input.

This is especially important when we want to automate cancellations of workflow initiated operations, Temporal server
cannot derive the ID from opaque input.

### Comparing the approaches

#### Handler ID qualification

With handler generated IDs, to support stateless clients, the handler would need to be able to map an operation and
input to a reference ID. It would also need to qualify a reference ID or securely issue the reference IDs when callers
cannot be trusted. With caller generated IDs, the handler would only need to qualify an ID based on the caller context
(e.g by concatenating it with a tenant ID).

#### IDs as inputs

With the caller generated ID approach, if the ID is used for handler side addressability, the handler would need to
parse it and merge with the request's input.

#### Caller friendliness

Shifting the responsibility for creating a handler addressable ID to the caller makes an API harder to use.

If we can map arbitrary client IDs to handler addressable resources, the client generated ID approach is easiest to use
from stateless clients. The SDK can generate deterministic IDs for calls started from workflows.

Handler generated IDs is the least friendly approach for stateless clients without additional APIs for mapping input to
a handler addressable resources.

#### Data sensitivity

If a client is expected to provide a business meaningful ID that encodes sensitive information to address an operation,
the ID would need to be encrypted making it harder to use.

Both handler generated IDs and caller generated IDs with handler mapping options avoid the data sensitivity issue.

## Proposal

### API draft

```
Start(service, operation, (optional) operation_id, input, ...) -> operation_id | result
Cancel(service, operation, operation_id)
GetResult(service, operation, operation_id)
Describe(service, operation, operation_id)
...
```

### Notes

- Caller identifiers are optional. If not provided with an ID, the handler must generate one. Handlers may reject (with
  an error) caller generated IDs for certain operations (e.g. low latency use cases with complex identifiers or when
  multiple calls are backed by a single operation).
- Operations are addressed by service, operation name, operation ID, and caller information (e.g. tenant ID).
- Temporal _may_ at some point expose a strongly consistent mapping of caller to handler identifiers that handlers may
  choose to leverage, this will be required to alleviate the caller burden of generating addressable IDs for workflow
  updates.
  We may start by requiring wrapping update requests with another workflow execution, which achieves the same effect.
  Note that there are still open questions around using workflow updates over Nexus (e.g. guarateed callback delivery in
  case of workflow termination).
- When starting operations from a Temporal workflow, there's no need to provide an ID, Temporal will persist the handler
  generated ID on the workflow's behalf. If an ID is provided from a workflow, the handler can use it for deduping
  purposes.
- `GetResult` may be used to long poll for the result or eagerly return if not ready yet.
- `Describe` and `GetResult` may be merged into a single request.
- `DeliverResult`, which was mentioned above, may be added in the full API proposal.
