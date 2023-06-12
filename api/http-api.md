# HTTP API

## Overview

Temporal has a gRPC API but no HTTP API. We need an HTTP API.

**Goals**

* Expose existing API over HTTP in addition to gRPC
* Ensure new API calls are automatically adopted
* Expose HTTP API in server by default for all to use like gRPC, but have option to disable
* Support all existing interceptors and auth methods

**Non-Goals**

* Design a high-quality REST API from first principles
* grpc-web (browser-only gRPC workaround that requires server-side support)
* Make an easy call to get workflow result
* gRPC stream support (maybe later)
* Poll calls (maybe later)

**Unresolved Research**

* Can payloads be made in non-base64 form without over-complicating the effort?

## Approach

This project will use https://github.com/grpc-ecosystem/grpc-gateway and annotations inspired by work already done on
the UI server for similar purpose at https://github.com/temporalio/ui-server. After review of the UI server's
annotations, they so closely match our goals that many things won't change.

Since namespace is required for most calls and is usually URL safe, we have decided to put the namespace in the URL
instead of as an HTTP header. This makes URL's large and a bit unwieldy, but calls like from `curl` would have to have
`-H Temporal-Namespace: <my-ns>` which is even more unwieldy.

The bodies of requests are proto JSON of the request messages and responses are full proto JSON of the response
messages. While we try to somewhat follow REST principles, this is not a full RESTful API necessarily. Developers adding
new API will need to add the gRPC gateway annotations for their RPC calls.

For the initial version, we will only be doing workflow service. Operator service and cloud APIs may come soon after
though.

### Rules

* Naming
  * Multi-word URL paths use kebab-case
  * Multi-word query parameters use camelCase (only first letter of abbreviations capitalized if not first word)
  * Do not assume any names reserved. So we can't have `/workflows/{workflow_id}` and `/workflows/general-call` in case
    there's a workflow named `general-call`.
  * Use plural nouns where an identifier may be provided to differentiate
    * But singular nouns are not _required_ in other places, can still be plural
* Response codes
  * 201 success if a creation
  * 202 if action eventually consistent
  * 200 other all other successes
  * Do not use 204 for no response, even if there's no response because we may add response later, just 200 everything
* Methods:
  * `GET` if read-only
    * Noun as last URL term
    * Use query parameters for commonly set items to avoid relying on request bodies (but still rely on bodies as
      needed). This may require some gRPC gateway customization.
  * `PUT` if strongly consistent add/update on fixed-URL w/ idempotency
    * Noun as last URL term
  * `DELETE` if item is actually deleted (i.e. unreachable from `GET`)
    * Noun as last URL term
  * `POST` for everything else
    * Noun as last URL term if for a create, verb if for an action
  * `PATCH` is not needed because we don't adhere to common CRUD
    * TODO(cretz): Needs discussion

### RPCs

Below is list of gRPC calls to HTTP calls so far and some notes/questions beneath each. Some notes/questions beneath one
actually apply to many but we are not repeating ourselves too much here.

* Namespaces:
  * `RegisterNamespace` - `POST /api/v1/namespaces`
  * `DescribeNamespace` - `GET /api/v1/namespaces/{namespace}`
  * `ListNamespaces` - `GET /api/v1/namespaces`
  * `UpdateNamespace` - `PUT /api/v1/namespaces/{namespace}`
    * TODO(cretz): Confirm strongly consistent and idempotent or not
  * `DeprecateNamespace` - `DELETE /api/v1/namespaces/{namespace}`
    * Is this eventually consistent? Will determine response code
    * Does this prevent returning from `GET`? Will determine HTTP method
* Workflows:
  * `StartWorkflowExecution` - `POST /api/v1/namespaces/{namespace}/workflows/{workflow_id}`
    * May accept header as `identity` and `request_id` on these calls
  * `GetWorkflowExecutionHistory` - `GET /api/v1/namespaces/{namespace}/workflows/{workflow_id}/history`
    * `?nextPageToken` can be a query param even though it's big
  * `GetWorkflowExecutionHistoryReverse` - `GET /api/v1/namespaces/{namespace}/workflows/{workflow_id}/history-reverse`
  * `RequestCancelWorkflowExecutionRequest` - `POST /api/v1/namespaces/{namespace}/workflows/{workflow_id}/cancel`
    * Intentionally not taking the run ID in the URL, but should it be `?runId=` query param?
  * `SignalWorkflowExecution` - `POST /api/v1/namespaces/{namespace}/workflows/{workflow_id}/signal/{signal_name}`
  * `SignalWithStartWorkflowExecution` - `POST /api/v1/namespaces/{namespace}/workflows/{workflow_id}/signal-with-start/{signal_name}`
  * `ResetWorkflowExecution` - `POST /api/v1/namespaces/{namespace}/workflows/{workflow_id}/reset`
  * `TerminateWorkflowExecution` - `POST /api/v1/namespaces/{namespace}/workflows/{workflow_id}/terminate`
  * `ListOpenWorkflowExecutions` - Intentionally not exposed (deprecated)
  * `ListClosedWorkflowExecutions` - Intentionally not exposed (deprecated)
  * `ListWorkflowExecutions` - `GET /api/v1/namespaces/{namespace}/workflows`
    * Accepts `?query=` query parameter
  * `ListArchivedWorkflowExecutions` - `GET /api/v1/namespaces/{namespace}/archived-workflows`
    * Intentionally did not do `/workflows/archived` due to ambiguity
  * `CountWorkflowExecutions` - `GET /api/v1/namespaces/{namespace}/workflow-count`
  * `QueryWorkflow` - `POST /api/v1/namespaces/{namespace}/workflows/{workflow_id}/query/{query_name}`
  * `DescribeWorkflowExecution` - `GET /api/v1/namespaces/{namespace}/workflows/{workflow_id}`
  * `UpdateWorkflowExecution`- `POST /api/v1/namespaces/{namespace}/workflows/{workflow_id}/update/{update_name}`
    * We also support `POST /api/v1/namespaces/{namespace}/workflows/{workflow_id}/updates/{update_id}` which will
      expect an update name in the body but gives a stable URL to do future things like "describe update" or
      "cancel update" one day (note the plural `updates`)
  * `PollWorkflowExecutionUpdate` - Intentionally not exposed
    * Not sure if best to have long HTTP API here. Would prefer non-blocking describe and maybe one day the difference
      between describing an update and polling for an update is a "wait" boolean.
* Activities:
  * `RecordActivityTaskHeartbeat` - `POST /api/v1/namespaces/{namespace}/activities/heartbeat`
    * We consider "heartbeat" a verb for these purposes
  * `RecordActivityTaskHeartbeatById` - `POST /api/v1/namespaces/{namespace}/activities/heartbeat-by-id`
    * We are intentionally not doing `/activities/{activity_id}/heartbeat` or similar due to URL ambiguity and that we
      want to encourage the task token approach
  * `RespondActivityTaskCompleted` - `POST /api/v1/namespaces/{namespace}/activities/complete`
  * `RespondActivityTaskCompletedById` - `POST /api/v1/namespaces/{namespace}/activities/complete-by-id`
  * `RespondActivityTaskFailed` - `POST /api/v1/namespaces/{namespace}/activities/fail`
  * `RespondActivityTaskFailedById` - `POST /api/v1/namespaces/{namespace}/activities/fail-by-id`
  * `RespondActivityTaskCanceled` - `POST /api/v1/namespaces/{namespace}/activities/cancel`
  * `RespondActivityTaskCanceledById` - `POST /api/v1/namespaces/{namespace}/activities/cancel-by-id`
* Search attributes:
  * Intentionally not exposed high-level search attribute calls from workflow service
* Task polling/completing:
  * Intentionally not exposed (except for activity task stuff needed for async activities)
* Task queues:
  * `ResetStickyTaskQueue` - Intentionally not exposed
  * `DescribeTaskQueue` - `GET /api/v1/namespaces/{namespace}/task-queues/{task_queue_name}`
  * `ListTaskQueuePartitions` - Intentionally not exposed
* Schedules:
  * `CreateSchedule` - `POST /api/v1/namespaces/{namespace}/schedules/{schedule_id}`
  * `DescribeSchedule` - `GET /api/v1/namespaces/{namespace}/schedules/{schedule_id}`
  * `UpdateSchedule` - `POST /api/v1/namespaces/{namespace}/schedules/{schedule_id}/update`
    * This is not a `PUT` because update different from create and not `PATCH` to avoid confusion with below
  * `PatchSchedule` - `POST /api/v1/namespaces/{namespace}/schedules/{schedule_id}/patch`
    * This is not a `PATCH` to avoid confusion with update above
  * `ListScheduleMatchingTimes` - `GET /api/v1/namespaces/{namespace}/schedules/{schedule_id}/matching-times`
  * `DeleteSchedule` - `DELETE /api/v1/namespaces/{namespace}/schedules/{schedule_id}`
    * Confirm whether eventually consistent
  * `ListSchedules` - `GET /api/v1/namespaces/{namespace}/schedules`
* Batch operations:
  * `StartBatchOperation` - `POST /api/v1/namespaces/{namespace}/batch-operations/{job_id}`
  * `DescribeBatchOperation` - `GET /api/v1/namespaces/{namespace}/batch-operations/{job_id}`
  * `ListBatchOperations` - `GET /api/v1/namespaces/{namespace}/batch-operations`
  * `StopBatchOperation` - `POST /api/v1/namespaces/{namespace}/batch-operations/{job_id}/stop`
* Worker build IDs:
  * Intentionally not exposed until they settle
* Other calls:
  * `GetClusterInfo` - Intentionally not exposed
  * `GetSystemInfo` - `GET /api/v1/system-info`

### Embedding into Server

Current suggested approach, subject to discussion:

* Generated gRPC gateway code will be auto-generated at the same time as api-go is for gRPC and live alongside it
* Service config has new `httpPort`
  * Only allowed on "frontend" service, presence elsewhere is config failure
  * Default value is `grpcPort` + 10
    * Makes `7243` the default - unassigned in IANA, unused in server
    * Cannot think of case where +10 clashes, e.g. if they use 80 or 443 or 8080 or whatever, 90, 453, and 8090 are fine
* Service config has new `disableHttp`
  * Default enabled, as harmless as exposing gRPC by default, and will encourage use
  * This is separate from `httpPort` because we don't want to support some `false` on an int option
* Full support for same TLS options as frontend
* Since it goes through gRPC, all metadata (i.e. HTTP headers) and interceptors are respected
* Will test all of the above
* Can discuss approach for cloud in separate place

#### Payload Formatting

One of the major drawbacks of payloads is that if we accept them directly in JSON, they look like:

```json
{
  "payloads": [{
    "metadata": {
      "encoding": "anNvbi9wbGFpbg=="
    },
    "data": "IkhlbGxvLCBXb3JsZCEi"
  }]
}
```

This is for the simple JSON message of `"Hello, World"`. With larger JSON objects it gets even more ugly like if we
wanted: `{ "foo": "bar" }`, it becomes `"data": "eyAiZm9vIjogImJhciIgfQ=="`. This is because by default proto byte
arrays are serialized/deserialized as base64.

But we may be able to solve this using a "shorthand" approach. Some research has been done yet, here are the notes:

* grpc-gateway uses `jsonpb` and supports custom marshalling choice (so `gogoproto`'s `jsonpb` could be used instead)
* We can make custom JSON unmarshalling _per proto_ on these older forms of unmarshalling, e.g. see
  [here](https://pkg.go.dev/github.com/gogo/protobuf/jsonpb#JSONPBUnmarshaler)
  * But newer `protojson` does not support this, see [this issue](https://github.com/golang/protobuf/issues/1322) and
    others. So this could harm our ability to upgrade.
* We can make `go.temporal.io/api/common/v1.Payloads` impl JSON marshal/unmarshal to assume if it is given a JSON
  collection, it can assume it's for the "payloads" field
* We can make `go.temporal.io/api/common/v1.Payload` impl JSON marshal/unmarshal to assume if it not an object that can
  deserialize into payload using strict rules (e.g. exact `metadata` and `data` format), then treat it as a `json/plain`
  payload for non `null` or null payload for null value.
  * We could just say "without metadata assume JSON/null" but what if someone has an object with a "metadata" field?
  * The only way it will clash with the raw form is if someone happens to have a `metadata` and/or `data` field with
    proper base64
* Should we assume that a payloads shorthand collection means all payloads within are shorthand?
  * If we do, it reduces clash likelihood, but won't allow raw payloads to come through
  * Answer: probably not
* Sure on unmarshal we can accept either type, but on marshal can we assume the shorthand notation is best?
  * I think for ease of use, the answer is "yes" for JSON/null payloads
* Upon JSON marshal however, how do we know that we are in the HTTP handler and therefore should use shorthand?
  * This is a tough challenge. We don't want to change what this looks like on history dump or something, right?
  * There's no real way to pass contextual I-am-HTTP-handler state to the underlying 
  * The best way is probably to use the [payload visitor](https://pkg.go.dev/go.temporal.io/api/proxy#VisitPayloads) to
    set metadata on every payload saying it should be shorthand on marshal
* What do we do about `json/protobuf` input/output?
  * On the way out we can unmarshal in shorthand mode, no problem
  * On the way in, how can we know that it is possibly proto form? Should we have a new shorthand for proto JSON that is
    a bit different than regular JSON? Probably and should apply to output too.
  * This new proto JSON form needs to have some way to make it clear it's a proto JSON payload. Since protos always have
    to be objects, a `_protoMessageType` key will have to be present that is the qualified "messageName"

So now, with the above shorthand, that same payloads set now looks like:

```json
["Hello, World!"]
```

And that works in either direction. Nice. And if your memo before was:

```json
{
  "fields": {
    "my-key1": {
      "metadata": {
        "encoding": "anNvbi9wbGFpbg=="
      },
      "data": "Im15LXZhbHVlMSI="
    },
    "my-key2": {
      "metadata": {
        "encoding": "anNvbi9wbGFpbg=="
      },
      "data": "Im15LXZhbHVlMiI="
    }
  }
}
```

It is now:

```json
{
  "fields": {
    "my-key1": "my-value1",
    "my-key2": "my-value2"
  }
}
```

Nice.

### Documentation

* Need to simply document its presence at first, OpenAPI spec _can_ come later though Temporal may consider a more
  intentionally-designed API in the future
  * Maybe a snippet or two in docs showing how to use `curl` to start, signal, cancel, and maybe even get history with
    filter type of close event to get workflow result
* https://api-docs.temporal.io/ already exists, may be worth adapting for this use too

## Usage Examples

These are `curl` examples that are based on documentation but are not tested because that would require actually
implementing the proposal. So there may be some mistakes.

Note, responses are shown pretty printed though they would not be by default. But we can make this a header/query
option.

### Start a workflow - no input

Request:

```bash
curl -X POST http://localhost:7243/api/v1/namespaces/my-namespace/workflows/my-workflow-id -d '{
  "workflowType": { "name": "MyWorkflow" },
  "taskQueue": { "name": "my-task-queue" }
}'
```

Response:

```json
{
  "runId": "7124ede7-fef5-4e15-8411-baa23d6beefd"
}
```

### Start a workflow with input

Request:

```bash
curl -X POST http://localhost:7243/api/v1/namespaces/my-namespace/workflows/my-workflow-id -d '{
  "workflowType": { "name": "MyWorkflow" },
  "taskQueue": { "name": "my-task-queue" },
  "input": ["Hello, World!"]
}'
```

This assumes that the approach from "Payload Formatting" above is applied and works.

Response:

```json
{
  "runId": "7124ede7-fef5-4e15-8411-baa23d6beefd"
}
```

### Signal workflow

Request:

```bash
curl -X POST http://localhost:7243/api/v1/namespaces/my-namespace/workflows/my-workflow-id/signal/MySignal
```

Response:

```json
{}
```

### Query workflow

Request:

```bash
curl -X POST http://localhost:7243/api/v1/namespaces/my-namespace/workflows/my-workflow-id/query/MyQuery
```

Response:

```json
{
  "queryResult": ["Hello, World!"]
}
```

We could set `queryResult` to be the implied body, but it is best we stick with the gRPC protocol we've bad for better
or worse. So `queryRejected` comes back as a success. This is just how we chose to implement query rejection (not to be
confused with query failure).

### Update workflow without ID

Request:

```bash
curl -X POST http://localhost:7243/api/v1/namespaces/my-namespace/workflows/my-workflow-id/update/MyUpdate -d '{
  "request": {
    "input": {
      "args": ["Hello, World!"]
    }
  }
}'
```

Response:

```json
{
  "updateRef": {
    "workflowExecution": {
      "workflowId": "my-workflow-id",
      "runId": "7124ede7-fef5-4e15-8411-baa23d6beefd"
    },
    "updateId": "6dad5439-40dd-4b01-9f15-f5723a450776"
  },
  "outcome": {
    "success": ["Hello, World!"]
  }
}
```

### Update workflow with ID

Request:
​
```bash
curl -X POST http://localhost:7243/api/v1/namespaces/my-namespace/workflows/my-workflow-id/updates/my-update-id -d '{
  "request": {
    "input": {
      "name": "MyUpdate",
      "args": ["Hello, World!"]
    }
  }
}'
```
​
Response:
​
```json
{
  "updateRef": {
    "workflowExecution": {
      "workflowId": "my-workflow-id",
      "runId": "7124ede7-fef5-4e15-8411-baa23d6beefd"
    },
    "updateId": "my-update-id"
  },
  "outcome": {
    "success": ["Hello, World!"]
  }
}
```

So `/update/<update-name>` is sending to a name, but `/updates/<update-id>` is also sending to a name but an ID url too.
The reason for this is to support a stable ID-based URL for creating and describing (i.e. non-blocking-result fetch) one
day.

### Cancel workflow

Request:
​
```bash
curl -X POST http://localhost:7243/api/v1/namespaces/my-namespace/workflows/my-workflow-id/cancel -d '{
  "reason": "some reason"
}'
```
​
Response:
​
```json
{ }
```

## Rejected Alternative Approach - Full API Redesign

An alternative to the approach to this proposal is to make a quality Temporal HTTP API from scratch instead of just
exposing our existing API. But it would still call the existing RPC calls.

Pros:

* Can design a higher quality API
  * Arguably not that much higher quality though
* Can be much more consistent
  * We are incredibly inconsistent with how we do similar things today

Cons:

* Every call and field has to be manually reviewed and designed
  * This is hundreds of fields. Schedules alone would take a while.
* Double the effort for many API additions
  * Something as simple as adding a history or schedule field requires HTTP API design
* May require maintaining separate auth/headers/timeouts/etc
  * Just exposing HTTP on existing gRPC leverages existing interceptors, timeouts, etc
* Still at the mercy of the gRPC interface and therefore can't design very well
  * For instance, if gRPC doesn't return the full resource as a result of  a mutate call, we can't do so from HTTP side
    either in a RESTful manner because it would not be atomic
  * Can't use `PUT`, `PATCH`, etc like you might like because our gRPC API
* Easy to get bogged down in detailed design discussions
  * For instance, does the workflow type belong in the URL?

### Usage Examples of a New API Design

These are the same examples as before, just what they might look like if we designed the API from scratch. These can be
compared with the original.

**Start a workflow - no input**

```bash
curl -X POST http://localhost:7243/api/v1/namespaces/my-namespace/workflows/my-workflow-id -d '{
  "workflow": "MyWorkflow",
  "taskQueue": "my-task-queue"
}'
```

Response:

```json
{
  "runId": "7124ede7-fef5-4e15-8411-baa23d6beefd"
}
```

Note, the response does not include the entire workflow like a normal REST API might. This is because we can't
start-then-describe atomically.

Differences:

* Changed `"workflowType": { "name": "MyWorkflow" }` to `"workflow": "MyWorkflow"`
* Changed `"taskQueue": { "name": "my-task-queue" }` to `"taskQueue": "my-task-queue"`

**Start a workflow with input**

Request:

```bash
curl -X POST http://localhost:7243/api/v1/namespaces/my-namespace/workflows/my-workflow-id -d '{
  "workflow": "MyWorkflow",
  "taskQueue": "my-task-queue",
  "args": ["Hello, World!"]
}'
```

Response:

```json
{
  "runId": "7124ede7-fef5-4e15-8411-baa23d6beefd"
}
```

Differences:

* Changed `"workflowType": { "name": "MyWorkflow" }` to `"workflow": "MyWorkflow"`
* Changed `"taskQueue": { "name": "my-task-queue" }` to `"taskQueue": "my-task-queue"`
* Changed the term `input` to `args`

**Signal workflow**

Request:

```bash
curl -X POST http://localhost:7243/api/v1/namespaces/my-namespace/workflows/my-workflow-id/signal/MySignal
```

Response:

```json
{}
```

Differences:

* None

**Query workflow**

Request:

```bash
curl -X POST http://localhost:7243/api/v1/namespaces/my-namespace/workflows/my-workflow-id/query/MyQuery
```

Response:

```json
["Hello, World!"]
```

Differences:

* We were able to lift the response to the top level

**Update workflow without ID**

Request:

```bash
curl -X POST http://localhost:7243/api/v1/namespaces/my-namespace/workflows/my-workflow-id/update/MyUpdate \
     -d '["Hello, World!"]'
```

Response:

```json
{
  "updateId": "6dad5439-40dd-4b01-9f15-f5723a450776",
  "result": ["Hello, World!"]
}
```

Differences:

* We were able to lift the request to the top level
* We were able to lift the response ID and result to the top level

**Update workflow with ID**

Request:
​
```bash
curl -X POST http://localhost:7243/api/v1/namespaces/my-namespace/workflows/my-workflow-id/updates/my-update-id -d '{
  "update": "MyUpdate",
  "args": ["Hello, World!"]
}'
```
​
Response:
​
```json
{
  "updateId": "my-update-id",
  "result": ["Hello, World!"]
}
```

Differences:

* We were able to put `update` and `args` to be consistent with starting workflow
* We were able to lift the response ID and result to the top level

**Cancel workflow**

Request:
​
```bash
curl -X POST http://localhost:7243/api/v1/namespaces/my-namespace/workflows/my-workflow-id/cancel -d '{
  "reason": "some reason"
}'
```
​
Response:
​
```json
{ }
```

Differences:

* None

## Rejected Alternative Approach - Full API Redesign and New Frontend Implementation

An alternative approach to this proposal is, like above, redesign the HTTP API but without calling the existing RPCs.
Instead redevelop those too.

In addition to many of the pros/cons of the redesign approach mentioned, these stand out in particular:

Pros:

* Can build a high-quality API with no boundaries

Cons:

* Have to write your own new Temporal frontend service
* Will likely have to alter persistence abstraction to support some features
  * For example, if server today doesn't support transactional mutate-then-read semantics, would have to add them