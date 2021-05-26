## NodeJS SDK interceptors

### What are interceptors?

Interceptors are a concept introduced in the [Java SDK](https://github.com/temporalio/sdk-java/tree/master/temporal-sdk/src/main/java/io/temporal/common/interceptors), they provide a mechanism for users to override behavior of different components of the SDK.

Main uses for interceptors is for extending inbound and outbound calls with auth[NZ] and tracing.

Some server API requests and responses, such as [StartWorkflowExecutionRequest](https://github.com/temporalio/api/blob/15ca7a345e006ad8fa47765ea9026df614241a79/temporal/api/workflowservice/v1/request_response.proto#L152) and [WorkflowExecutionStartedEventAttributes](https://github.com/temporalio/api/blob/15ca7a345e006ad8fa47765ea9026df614241a79/temporal/api/history/v1/message.proto#L79) WF history event, support inection of custom user headers (a mapping of string to `Payload`), which are opaque to the server, headers can be read and written to by interceptors.

> NOTE: Java is the only SDK that supports interceptors at the time of this writing.

### What kind of interceptors are there? (in the Java SDK)

#### [WorkerInterceptor](https://github.com/temporalio/sdk-java/blob/master/temporal-sdk/src/main/java/io/temporal/common/interceptors/WorkerInterceptor.java)

Responsible for registering `WorkflowInboundCallsInterceptor`s and `ActivityInboundCallsInterceptor`s.

#### [ActivityInboundCallsInterceptor](https://github.com/temporalio/sdk-java/blob/master/temporal-sdk/src/main/java/io/temporal/common/interceptors/ActivityInboundCallsInterceptor.java)

Intercepts activity instantiation and execution.

#### [WorkflowInboundCallsInterceptor](https://github.com/temporalio/sdk-java/blob/master/temporal-sdk/src/main/java/io/temporal/common/interceptors/WorkflowInboundCallsInterceptor.java)

Intercepts workflow instantiation, execution, and signal and query handling.

#### [WorkflowOutboundCallsInterceptor](https://github.com/temporalio/sdk-java/blob/master/temporal-sdk/src/main/java/io/temporal/common/interceptors/WorkflowOutboundCallsInterceptor.java)

Intercepts workflow code calls to the Temporal APIs, like scheduling an activity, starting a timer, getting a random value and even thread creation.

#### [WorkflowClientInterceptor](https://github.com/temporalio/sdk-java/blob/master/temporal-sdk/src/main/java/io/temporal/common/interceptors/WorkflowClientInterceptor.java)

Responsible for registering `WorkflowClientCallsInterceptor`s each time a `WorkflowClient` is created and intercepts the creation of `ActivityCompletionClient`s.

#### [WorkflowClientCallsInterceptor](https://github.com/temporalio/sdk-java/blob/master/temporal-sdk/src/main/java/io/temporal/common/interceptors/WorkflowClientCallsInterceptor.java)

Intercepts `WorkflowClient` method calls like `start`, `signal`, `query`, `cancel`, and `terminate`.

### NodeJS SDK limitations

Workflow interceptors should run in the Workflow isolate because they need to be replayed for reconstruction of their state.
This limitation makes writing interceptors tricky because they should be split between isolated and non-isolated code (dependening on the interceptor type).
Another complication that arises from running interceptors in isolation is that if node APIs or IO is a requirement users must rely on [external dependencies](https://github.com/temporalio/proposals/blob/a8d5371595ac96ebab62aaaea6f72a5e45bda344/node/logging-and-metrics-for-user-code.md#proposed-solution) for breaking isolation.

### Which interceptors do we want to port to Node?

We can probably avoid using the `WorkerInterceptor` and simply pass `ActivityInboundCallsInterceptor`, `WorkflowInboundCallsInterceptor` and `WorkflowOutboundCallsInterceptor` directly to the Worker.

```ts
await Worker.create({
  interceptors: {
    activityInbound: [
      {
        /* Implementation goes here */
      },
    ],
    // Note the use of paths here, the SDK expects these paths to be valid JS files
    // which export an interceptor variable.
    // These paths will be included in the bundled Workflow code and loaded into the isolate.
    workflowInboundPaths: ['../workflows/interceptors/inbound2', '../workflows/interceptors/inbound2'],
    workflowOutboundPaths: ['../workflows/interceptors/outbound1', '../workflows/interceptors/outbound2'],
  },
});
```

Same goes for `WorkflowClientInterceptor`, we can pass `WorkflowClientCallsInterceptor` directly to the `Connection` constructor.

```ts
new Connection({
  interceptors: {
    workflowClient: [
      {
        /* Implementation goes here */
      },
    ],
  },
});
```

### `ActivityInboundCallsInterceptor`

Runs in the main NodeJS isolate.

#### Methods

- `execute` intercept activity execution

### `WorkflowInboundCallsInterceptor`

Runs in the Workflow isolate.

#### Methods

- `execute` intercept workflow execution
- `handleSignal` intercept workflow signals
- `handleQuery` intercept workflow queries

### `WorkflowOutboundCallsInterceptor`

Runs in the Workflow isolate.

#### Methods

- `scheduleActivity` intercept scheduling of activities
- `startTimer` intercept starting timers
- More methods TBD

### `WorkflowClientCallsInterceptor`

Runs in the main NodeJS isolate.

#### Methods

- `start`
- `signal`
- `query`
- `cancel`
- `terminate`

## Structure of a Node interceptor

- Interceptor methods are all optional, implementors can choose which methods to intercept.
- Interceptor methods receive the `next` interceptor method which they can call in order to continue the interception chain and eventually call the original SDK method

  ```ts
  export const interceptor: WorkflowOutboundCallsInterceptor = {
    async startTimer(input, next): Promise<void> {
      console.log('Timer started', input);
      let success = false;
      try {
        // next has the same signature as startTimer without the next argument
        await next(input);
        success = true;
      } finally {
        console.log('Timer completed', input, { success });
      }
    },
  };
  ```
