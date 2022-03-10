# User-specified Worker Versions

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
workflows which break history compatability (but not interface compatability).

At a high level:
* Provide a simple API for versioning entire workers (this proposal)
* Allow clients to point at task queue `foo`, and automatically route new workflow executions
  to the latest version of the `foo` queue.
* Provide good notifications and information about when old workers may be
  decommissioned
* Ensure histories replayed on older versions fail fast with informative errors
* Easy visibility into what versions deployed workers are using

Building on this base set of features, we plan to eventually implement
automatic safe-rollout of changes, and possibly tools like k8s operators
which can automatically manage worker deployments.

## SDK API changes

The meat of this proposal is simple:
**Add a version field to worker options in each SDK**

Because version information will need to be sent to the Temporal Cluster,
we define it as a protobuf message (which will show up in our API somewhere):
```protobuf
message WorkerVersions {
    UserVersion worker_version = 1;
}

message UserVersion {
    // The string the user passed as their version representation
    string original = 1;
    // Parsed from original string
    uint32 major = 2;
    // Parsed from original string
    uint32 minor = 3;
}
```

This message is pre-emptively named plurally in order to accommodate potential
increases in versioning granularity in the future. For example, we have considered
versioning Workflows, Activities, and Data Converters/Interceptors all separately.
They could be added as new fields to this message if/when that happens.

Each language will expose a way to (optionally) set the worker version to 
start, supporting the possibility of other versions later. This will translate 
into the above message to be sent to server.

### TypeScript

```typescript
Worker.create({ workerVersion: '1.0', ...otherOptions })
```

### Go

```go
workerOptions := worker.Options{
  WorkerVersion: "1.0",
  // other options
}
```

### Java

```java
WorkerOptions.newBuilder().setWorkerVersion("1.0").build()
```

## When and how to increment the worker version number

The information here will be added as a documentation page once this feature
has shipped.

--

The worker version number encompasses changes to all workflow code registered
with the worker, as well as changes to any code which might affect the path
of execution within workflow code.

#### Super-Major
Require a new workflow type name (or new task queue name)

- A backwards-incompatible change to the workflow interface
    - Changing a required parameter type
    - Adding or removing a required parameter


#### Major

- A backwards-incompatible change to the workflow implementation. See more [here](https://docs.temporal.io/docs/concepts/what-is-a-workflow-definition/#deterministic-constraints)
    - Anything that would cause the workflow to fail replay due to nondeterminism, given any possible valid history from the unaltered version of the workflow. 
    - Includes changes to data converters or interceptors which would result in such incompatibilities.

#### Minor

- Backwards compatible change to workflow implementation
    - This includes adding properly implemented `getVersion` or `patch` calls, for fixing bugs.
