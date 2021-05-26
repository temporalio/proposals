## Tracing, Logging, and Metrics in the NodeJS SDK and Core

### What's already implemented in the Alpha release?

Core [uses opentelemetry](https://github.com/temporalio/sdk-core#debugging) for generating logs and traces, it does not emit any metrics.

The Node SDK uses `WorkerOptions.logger` directly for logging and the opentelemetry API for tracing with no output by default, it does not emit any metrics either.

There's an example of how to export the traces to jaeger in [`bench.ts`](https://github.com/temporalio/sdk-node/blob/a25c0feca791a195eb5e50cf8c0fd9e0b5a1db83/packages/test/src/bench.ts#L105).

See the [documentation](https://docs.temporal.io/docs/node/logging/) on how to customize the Worker logger.

There's currently not a way to log from Workflow internals (inside the isolate).

### Requirements

- Link traces between Node and Core for a more complete picture
- Core traces should be propagated through NodeJS
- Core metrics should be propagated through NodeJS
- Core logs should integrate with the Worker logger
- Support logging from Workflow internals
- Support logging in Worker either within an otel span or without context (e.g. Worker state changed)
- Tracing is often preferrable to plain metrics and should be used wherever possible ([this example](https://github.com/temporalio/samples-go/blob/master/metrics/metrics.go) shows an example of use of metrics that could have been implemented with tracing)

#### Metrics

- Gauge of cached WFs - exported from both Core and Lang to find discrepencies
- Gauge of cached WF memory stats - Lang
- Counter of WF cache insertions - Lang
- Counter of WF cache evictions - Lang
- Gauge of in-flight Activities - Lang
- Gauge of in-flight WF activations - Lang
- GRPC call latency and count per status for each route - Core only - using otel spans (can be exported as metrics if needed)

> PS: More metrics should be considered here, this is just a list off the top of my head.

#### Tracing

- Starting from Lang
  - Poll start to completion (WFs and Activities)
    - Lang passes span context to Core
  - Connect to Server?
- Starting from Core
  - TODO

#### Logging

- Worker logger supports 4 log levels: `DEBUG | INFO | WARN | ERROR`.
- Logging in trace context can be done with otel span events or by extracting the span context into a log event, it's unclear to me if otel spans are a good fit here, see [this discussion](https://github.com/open-telemetry/opentelemetry-specification/issues/67) for info on the subject.

| Level              | Component | Trace context | Event                                                 |
| ------------------ | --------- | ------------- | ----------------------------------------------------- |
| `INFO`             | Worker    | None          | Worker state change                                   |
| `DEBUG`            | Worker    | Activation    | Activation received with list of jobs and WF context  |
| `ERROR`            | Worker    | Activation    | WF activation failed                                  |
| `DEBUG`            | Workflow  | Activation    | WF activation concluded with list of commands         |
| `DEBUG`            | Worker    | Activity Task | Activity task received (start or cancel) with context |
| `DEBUG` or `ERROR` | Worker    | Activity Task | Activity task resolved                                |
| `ERROR`            | Worker    | Any           | Unexpected error occurred                             |
| `ERROR`            | Workflow  | Activation    | Unexpected error occurred                             |
| `DEBUG`            | Worker    | None          | Got activity heartbeat                                |

> TODO: Fill in this table with required Core logs

### Solution

- Add context to logs emitted from Worker where applicable
- Pass span context as from Lang to Core in the `poll_activity_task` and `poll_workflow_activation` APIs
- Write a custom exporter or propagator that runs in the Bridge (Rust) to push everything to Lang
  - Spans created in Core should respect [sampling flags](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/sdk.md#sampling) passed in by Lang to reduce the amount of traces the bridge has to export.
- Inject the Worker logger interface into the isolate for internal use - make sure activation context is baked into the WF logger
- Worker logger should add a `component` attribute (e.g. `worker | core | workflow`) in the log context so we know each log's origin. (`workflow` refers to the WF isolate runtime library, for which logs should collected by the worker).
- Worker is now responsible for propagating 3 async log streams, events will be out-of-order
  - In production this does not matter because the user's logging solution can sort based on timestamps
  - In development, we will stall log output in order to merge and chronologically sort the different logs sources

### Issues

Propagating traces, logs and metrics from Core and WF isolates to Lang implies buffering since they run in different threads and communicate using a queue which could lead to event loss.
For the WF isolate there's no way around it, we should use one of the more reliable approaches discussed in [#22](https://github.com/temporalio/proposals/pull/22).
For Core the only way around it is to emit directly from Rust but in practice we'd have to propagate events via opentelemetry regardless so the extra step to push to Lang is the only extra risk taken.

### Alternatives

- Trace and log directly from Core (using a format similar to the one the Worker uses)
  - Pros:
    - No buffering
    - No overhead
    - Lang is typically slower than Core and could be a bottleneck
  - Cons:
    - Hard to customize and integrate with user's existing instrumentation stack
    - Creates another log stream / tracer for the user to consider
