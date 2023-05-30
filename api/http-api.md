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
  * `UpdateWorkflowExecution`- `POST /api/v1/namespaces/{namespace}/workflows/{workflow_id}/updates/{update_id}`
    * Decided to make this an identity so we can have "describe update" or "cancel update" or whatever one day
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

### Documentation

* Need to simply document its presence at first, OpenAPI spec _can_ come later though Temporal may consider a more
  intentionally-designed API in the future
  * Maybe a snippet or two in docs showing how to use `curl` to start, signal, cancel, and maybe even get history with
    filter type of close event to get workflow result
* https://api-docs.temporal.io/ already exists, may be worth adapting for this use too