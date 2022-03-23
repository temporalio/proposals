# Worker Build ID Based Versioning

Temporal workflow authors experience a number of difficulties when it comes to
changing workflow code. The current techniques for versioning workflows are:

**GetVersion & patch APIs**
These APIs allow branching within the same workflow code to handle the presence
or absence of a certain change. See them for [TS](https://docs.temporal.io/docs/typescript/patching#typescript-sdk-patching-api), [Java](https://docs.temporal.io/docs/java/versioning/), and [Go](https://docs.temporal.io/docs/go/versioning/).

These APIs are confusing and challenging to use correctly, and clutter up code.
We advise users to generally use them only to fix bugs that would otherwise prevent
the workflow from completing.

**Versioned task queues**
Conceptually simpler, but operationally more effort, is to version task queues.
IE: A worker operating on task queue `foo-v1` is changed, and when redeployed
points at `foo-v2`.

This avoids complicating the workflow code itself, but means users need to be
aware of when all workflows on `foo-v1` are complete, allowing them to decommission
the old workers. It also means potentially deploying larger numbers of workers.

It also requires updating clients who are starting workflows to point at the
newer task queue name.

**Versioned workflow names**
This approach is much like versioning task queue names, but trades off some of
the operational complexity for some code maintenance complexity.

Rather than needing to keep old workers around, users now need to keep the
old code around until no more workflows using the old type are open.

They still have the same problem with needing to tell clients to use the new
workflow name.

## Improving the situation

The `patch` type APIs can't be eliminated completely. There will always be 
situations where a "broken" workflow needs to be fixed to make progress. Such
fixes are typically less common than just making changes to workflow logic, though.

To make the more common case easier, we will provide a set of features that
make the "versioned task queues" approach much easier to use for changes to
workflows which break history compatability (but not interface compatability),
or would like to safely roll out expected-to-be-compatible changes.

At a high level:
* Provide a simple methodology for versioning entire workers (this proposal)
* Allow clients to point at task queue `foo`, and automatically route new workflow executions
  to the latest version of the `foo` queue.
* Provide good notifications and information about when old workers may be
  decommissioned
* Ensure histories replayed on older versions fail fast with informative errors
* Easy visibility into what versions deployed workers are using

Building on this base set of features, we plan to eventually implement
automatic safe-rollout of changes, and possibly tools like k8s operators
which can automatically manage worker deployments.

## Safe-rollout

Intentionally avoiding deep into details here, the foundation laid here should enable
us, as well as users, to more easily implement automated and safe rollout
of changes to workers. A process like this one can become the de-facto experience:

* If deploying a known-breaking change, new workflows are only processed by
  the new version, existing open workflows are processed by old workers.
* If deploying an expected-to-be-compatible change, new workflow _tasks_ are
  attempted by new workers, and if they succeed, that workflow will subsequently
  only be processed by new workers. If they fail, execution goes back to old
  workers.

# Using opaque whole-worker-identifiers as worker versions

Thanks to @jlegrone for his great feedback encouraging us to revive this approach.

We already have a field called `binaryChecksum` (or similar) in `WorkerOptions`
today in SDKs. This field's intent is to uniquely identify a specific worker
build. Since we believe versioning entire workers is the easiest solution, we
can lean on this existing field.

Deprecating the name `binaryChecksum`and replacing it with something more 
accurate like `workerBuildId` would be appropriate, since most of our SDKs
don't even produce a binary.

With this approach, users who wish to make use of the improved versioning 
features should set the `workerBuildId` during their CI process to a value that
is unique for that worker's implementation. _Implementation_ rather than 
_build_ is an important distinction here, since rebuilds of identical
code should (ideally) produce workers wit the same ID. It is not necessary to
do this, and it is varyingly difficult depending on the language, but when
done it enables users to produce workers with the same ID from their CI builds
if they didn't touch worker code, but something else (ex: The CI definition itself).
This involves some work on the part of the user, but is more reliable than expecting
worker authors to increment a version number.

Unfortunately it is infeasible to automatically set an appropriate ID for many languages.

## How is versioning accomplished with the `workerBuildId`?

Every new worker ID will be assumed to be incompatible with the existing id(s)
unless explicitly specified otherwise. New workers will not process *anything* 
until explicitly enabled if they opt into build-id based versioning. Users who 
wish to always have new workers begin processing new workflows can make an API 
call immediately establishing the new worker as latest as part of their 
deployment process (see below).

In order to either (safely or not) migrate *open* workflows to a new version,
users will explicitly indicate that an ID is compatible with some already-extant
ID.

Because this behavior is a breaking change, SDKs will need to add a
`enableBuildIdBasedVersioning` boolean flag to their `WorkerOptions`.

## Server-side APIs for `workerBuildId`-based versioning

Importantly, we _already_ send the id (checksum, today) on every poll request.
It's TBD if the worker will be changed to poll a unique queue per ID, or if
that will happen on the frontend, or matching.

These APIs could very well end up in a different service, but are shown
as part of `WorkflowService` here for simplicity.
```protobuf
syntax = "proto3";

service WorkflowService {
    rpc SetWorkerBuildIdOrdering (SetWorkerBuildIdOrderingRequest) returns (SetWorkerBuildIdOrderingResponse) {}
    // This could / maybe should just be part of `DescribeTaskQueue`, but is broken out here to show easily.
    rpc GetWorkerBuildIdOrdering (GetWorkerBuildIdOrderingRequest) returns (GetWorkerBuildIdOrderingResponse) {}
}

message SetWorkerBuildIdOrderingRequest {
    string namespace = 1;
    // Must be set, the task queue to apply changes to.
    string task_queue = 2;
    // The version id we are targeting.
    VersionId version_id = 3;
    // When set, indicates that the `version_id` in this message is compatible
    // with the one specified in this field. Because compatability should form
    // a DAG, any build id can only be the "next compatible" version for one
    // other ID of a certain type at a time, and any setting which would create a cycle is invalid.
    VersionId is_compatible_with = 4;
    // When set, establishes the specified `version_id` as the default of it's type
    // for the queue. Workers matching it will begin processing new workflow executions.
    // The existing default will be marked as a previous incompatible version
    // to this one, assuming it is not also in `is_compatible_with`.
    bool default = 5;
}
message SetWorkerBuildIdOrderingResponse {}

message GetWorkerBuildIdOrderingRequest {
    string namespace = 1;
    // Must be set, the task queue to interrogate about worker id ordering
    string task_queue = 2;
    // Limits how deep the returned DAG will go. 1 will return only the
    // default build id.
    uint32 max_depth = 3;
}
message GetWorkerBuildIdOrderingResponse {
    // The currently established default ids. There will be one per version type as defined in
    // the `VersionId` message.
    repeated VersionIdNode current_defaults = 1;
    // Other current latest-compatible versions who are not the overall default. These are the
    // versions that will be used when generating new tasks by following the graph from the
    // version of the last task out to a leaf.
    repeated VersionIdNode compatible_leaves = 2;
}

message VersionIdNode {
    VersionId version = 1;
    VersionIdNode compatible_with = 2;
    VersionIdNode previous_incompatible = 3;
}

message VersionId {
    oneof version {
        // An opaque whole-worker identifier
        string worker_build_id = 1;
        // Exists to support possible future dynamic bundle downloading. Versions a bundle of
        // workflows.
        string workflow_bundle_id = 2;
    }
}

// Additionally, some way to limit version DAG depth is necessary - likely
// something settable via the Operator service.

```

---
This proposal is a second take / alternative to the one [here](https://github.com/temporalio/proposals/pull/52)
