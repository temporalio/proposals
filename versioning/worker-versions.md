# User-specified Worker versions

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
aware of when all workflows on `foo-v1` are complete, allowing them to decomission
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

The `patch` type APIs can't be elimiated completely. There will always be 
situations where a "broken" workflow needs to be fixed to make progress. Such
fixes are typically less common than just making changes to workflow logic, though.

To make the more common case easier, we will provide a set of features that
make the "versioned task queues" approach much easier to use.

At a high level:
* Provide a simple API for versioning entire workers (this proposal)
* Allow clients to point at task queue `foo`, and automatically route new workflow executions
  to the latest version of the `foo` queue.
* Provide good notifications and information about when old workers may be
  decomissioned

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
    string worker_version = 1;
}
```

This message is pre-emptively named pluarally in order to accomodate potential
increases in versioning granularity in the future. For example, we have considered
versioning Workflows, Activities, and Data Converters/Interceptors all separately.
They could be added as new fields to this message if/when that happens.

Each language will expose a way to set the worker version to start, supporting
the possibility other versions later. This will translate into the above message
to be sent to server.

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
