# SDK Connection Configuration

## Problem statement

The current API for connecting a Worker to the server is via a `Core` singleton.
This singleton can only connect to one namespace per process and, by looking at our basic samples,
it not immediately obvious how to configure the server address for a given Worker.

```ts
// worker.ts
await Core.install({ serverOptions: { address, namespace } });
// Worker uses a connection created by the Core singleton
const worker = await Worker.create({ taskQueue });
```

## Proposal

### Explicit `Connection` objects

- `Connection` in `@temporalio/client` for client only
- `NativeConnection` in `@temporalio/worker` for sharing connections between different workers

```ts
// worker.ts
import { NativeConnection, Worker } from '@temporalio/worker';

const connection = await NativeConnection.create({ address });
const worker = await Worker.create({ connection, namespace, taskQueue });

// starter.ts

// same as today but Connection becomes async to make the `getSystemInfo` call
import { Connection, WorkflowClient } from '@temporalio/client';

const connection = await Connection.create({ address });
const client = new WorkflowClient(connection.service, { namespace });
```

#### Pros

- Explicit connection reuse
- Guides developers to reuse connections

#### Cons

- Verbose
- Confusing when to use each connection type

#### Summary

After weighing the pros and cons of the alternatives below this approach was selected for the following reasons:

- Connection sharing is explicit
- Connection sharing is the default and not opt-in
- Future proof for supporting different connection types for both Worker and WorkflowClient
- Flexible - e.g. the [Mix of options and clients](#mix-of-options-and-explicit-clients) alternative could be added later (though unlikely)

## Alternatives considered

### Implicit connection reuse with similar options

```ts
// worker.ts
import { Worker } from '@temporalio/worker';

// worker1 and worker2 share the same underlying connection based on given options
const worker1 = await Worker.create({ connectionOptions: { address }, namespace, taskQueue: 'tq1' });
const worker2 = await Worker.create({ connectionOptions: { address }, namespace, taskQueue: 'tq2' });

// starter.ts
import { WorkflowClient } from '@temporalio/client';

const client = await WorkflowClient.create({ connectionOptions: { address }, namespace });
```

#### Pros

- Short
- Easy path from sample with local server to real world use case

#### Cons

- Implicit connection sharing is non-obvious
- No way to opt out of connection sharing (can be addressed if needed)

### Mix of options and explicit clients

Support a variant of both approaches listed above with no implicit connection reuse

```ts
// worker.ts
import { NativeConnection, Worker } from '@temporalio/worker';

// worker1 and worker2 do not share the same connection
const worker1 = await Worker.create({ connectionOptions: { address }, namespace, taskQueue: 'tq1' });
const worker2 = await Worker.create({ connectionOptions: { address }, namespace, taskQueue: 'tq2' });

// worker3 and worker4 share the same connection
const connection = await NativeConnection.create({ address });
const worker3 = await Worker.create({ connection, namespace, taskQueue });
const worker4 = await Worker.create({ connection, namespace, taskQueue });

// starter.ts
import { Connection, WorkflowClient } from '@temporalio/client';

const client = await WorkflowClient.create({ connectionOptions: { address }, namespace });

const connection = await Connection.create({ address });
const client = new WorkflowClient({ connection, namespace });
```

#### Pros

- Explicit sharing model
- Only verbose when sharing is required

#### Cons

- 2 connection types are confusing

### Typed connection options

Here we'll assume that `WorkflowClient` and `AsyncCompletionClient` have been merged into a single `Client` type.

```ts
// worker.ts
import { Worker } from '@temporalio/worker';
import { Client } from '@temporalio/client';

const client = await Client.create({ connection: { type: 'native', address }, namespace });
const worker = await Worker.create({ client, namespace, taskQueue });

// starter.ts
import { Client } from '@temporalio/client';

const client = await Client.create({ connection: { type: 'native', address }, namespace });
// - OR -
const client = await Client.create({ connection: { type: 'grpc-js', address, interceptors }, namespace });
```

### Python SDK approach

```ts
// worker.ts
import { Worker, WorkflowClient } from '@temporalio/worker';
// WorkflowClient is re-exported from the worker package

const client = await WorkflowClient.create({ connectionOptions: { address }, namespace });
const worker = await Worker.create({ client, taskQueue: 'tq1' });

// starter.ts
import { WorkflowClient } from '@temporalio/client';

const client = await WorkflowClient.create({ connectionOptions: { address }, namespace });
```

#### Pros

- One way to create clients
- Explicit sharing model

#### Cons

- Connnection isn't really reused (not possible)
- Not all options are apply to worker connection (e.g. grpc interceptors and channel args)

### Python SDK approach with different client types

Here we'll assume that `WorkflowClient` and `AsyncCompletionClient` have been merged into a single `Client` type.

```ts
// worker.ts
import { Worker } from '@temporalio/worker';
import { Client } from '@temporalio/client';

const client = await Client.create({ connection: { type: 'native', address }, namespace });
const worker = await Worker.create({ client, taskQueue });

// starter.ts
import { Client } from '@temporalio/client';

const client = await Client.create({ connection: { type: 'native', address }, namespace });
// - OR -
const client = await Client.create({ connection: { type: 'grpc-js', address, interceptors }, namespace });
```

- In the current state of the SDK, `grpc-js` connection cannot be passed to `Worker`s.
- If / when Core supports external client implementations, the `grpc-js` connection could be used for `Worker`s.
- If / when we reach the point above, we could decide to get rid of the `native` connection type.
- The cons mentioned above are _not_ relevant with this approach, connections can be shared between clients and workers and connection options would apply when passing a `Client` to a `Worker`.

#### Pros

- All of the above pros
- Future proof

## Notes

### `WorkflowClient` and `AsyncCompletionClient`

There's no benefit in having 2 client classes except for shorter method names on
each of them (e.g. `WorkflowClient.execute` would need to be named `Client.executeWorkflow`).

Some of the proposed alternatives above would make more sense if the SDK exposed a single `Client` class.

### Why do we need both native and JS clients?

- Rust Core does not support pluggable clients and must use a native client.
- We do not want native extensions as a (strict) dependency for "starters" because those might be deployed on environments where
  native modules blow up the bundle size causing slow cold starts and are hard to package.

### Future of connections

Eventually we'd want the SDK to support different connection types:

- `grpc-js` - pure JS client
- `grpc-web` - browser supported client
- `core` - native Rust client (`NativeConnection` in this proposal)

One day Rust Core might even support pluggable clients in which case JS could be used to power it.
If we get there we could enable connection reuse between "starters" and "workers".
