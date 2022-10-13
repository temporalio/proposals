# Mass Replay Verification API

Users often manually verify that they have not broken compat with existing
workflow histories when making changes by downloading histories and replaying
them with a replay worker.

We aim to make that simpler and faster with the below changes, which should
be similarly applicable to all SDKs but are laid out here in TS first.

For flexibility and compose-ability reasons, it is desirable to separate the
construction of a set of histories the user might care about from the 
downloading of those histories and the replay of those histories. Hence
the base level APIs proposed are (in order):

## Fetching
See https://github.com/temporalio/proposals/pull/67

Which includes functions for listing workflows according to some query params.
Those functions return something like `AsyncIterable<WorkflowExecutionInformation>`

## Downloading
This is simply a matter of (lazily) mapping the iterable:
`AsyncIterable<WorkflowExecutionInformation> -> AsyncIterable<WorkflowIDAndHistory>`

Preserving the workflow id is important, since history does not include it
by itself.

By itself, this would look something like:
`const historyIterator = client.workflow.downloadLazily(workflowIds, { concurrency: 10 })`

Which would be sugar for creating a returning an async iterator which calls
`getExecutionHistory` on each id. This might include doing so concurrently
(not required for initial implementation).


## Replaying
Pass the lazy iterable of histories into a function which instantiates the
worker and feeds the histories to it:

```typescript
export interface ReplayResults {
  // True if any workflow failed replay
  readonly hadAnyFailure: boolean;
  // Maps run id to information about the replay failure
  readonly failureDetails: Map<string, WorkflowError>;
}

// Critically, ReplayWorkerOptions will get a `failFast` option, which will
// default to true. If set, we throw on the first nondeterminism error. If not
// set, failure information is in the returned results object.

export class Worker {
  // etc etc...
  public static async runReplayHistories(
    options: ReplayWorkerOptions,
    histories: AsyncIterable<History>
  ): Promise<ReplayResults> {}
  // etc etc...
}
```

Under the hood this creates a Rust stream, which is fed the histories
downloaded from the lang side as they become available, and is passed into 
`init_replay_worker`.

## All together now
A user doing this using these base APIs would write something like:
```typescript
const iterator = client.workflow.list({
  // Made up nonsense syntax. See other proposal.
  query: 'task_queue=foo AND status=closed ORDER BY end_time DESC',
  pageSize: 100,
});
const histories = client.workflow.downloadLazily(iterator);
const result = await Worker.runReplayHistories({ whatever: 'options' }, histories);
```

## But wait there's more
Arguably, the above is still a bit too manual. We could, in addition to the
base APIs, provide a more "all-in-one" approach:

```typescript
const result = await Worker.validateCompatabilityWithQueue(
    client, 'task_queue_foo', { sampleStrategy: mostRecent(500) }
);
```

Which wraps up all of the above. Different strategies can be introduced over
time.
