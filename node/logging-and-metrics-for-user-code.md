## Logging and Metrics in user Workflow code

A hard requirement for our logging and metrics solution for user code is that we do not enforce a specific tool or convention and instead let our users use their existing tools.<br/>
For Activities, there is not an issue because users can run anything in an Activity. In Workflows OTOH, only deterministic code can run and metrics and logs should usually be dropped when a Workflow is replaying. Additionally the fact that the Node SDK runs Workflows in v8 isolates, mean that there's no way to do IO or anything that interacts with the world without explicit support from the SDK.

### IO in Workflow code

There are a few options for doing IO inside a Workflow's isolate:

1. Load a binary (c++) module into the isolate, the module is not isolated the way JS code is
2. Inject a function reference from the main NodeJS isolate into a Workflow isolate
3. Accumulate data in the isolate (e.g when collecting commands to complete an activation) and pass it into a function in the main NodeJS isolate

(1) is automatically ruled out because users' existing tools are probably written in JS and depend on the NodeJS environment.<br/>
(2) has some overhead (cross thread communication and possibly blocking the isolate thread) - from the [isolated-vm](https://github.com/laverdet/isolated-vm#api-documentation) documentation:

> Calling the synchronous functions will block your thread while the method runs and eventually returns a value. The asynchronous functions will return a Promise while the work runs in a separate thread pool.<br/>
> ... <br/>
> Additionally, some methods will provide an "ignored" version which runs asynchronously but returns no promise. This can be a good option when the calling isolate would ignore the promise anyway, since the ignored versions can skip an extra thread synchronization. Just be careful because this swallows any thrown exceptions which might make problems hard to track down.

If we go for (2) we will probably recommend using the "ignored" version to reduce the extra overhead and avoid non-deterministic code from interfering with Workflow code.<br/>
(3) has the lowest overhead but also means there's an inherent delay from logs and metrics generation to processing.

### Proposed solution

Allow users to expose their logging and metrics interfaces to Workflow code as external dependencies.
We'll use either technique (2) or (3) stated above after receiving more input and running a benchmark.

#### Definitions

Logging and metrics require Workflow execution context to have any meaning.
We define the `WorkflowInfo` interface which is accessible in Workflow code via `Context.info` and passed into users' "external dependency" functions.

`@temporalio/workflow`

```ts
export interface WorkflowInfo {
  workflowId: string;
  runId: string;
  isReplaying: boolean;
  // TBD - more attributes
}
```

### Logger injection example

#### Variant A - `Context.dependency` + `Worker.inject`

`interfaces/logger.ts`

```ts
export interface Logger {
  info(message: string): void;
  error(message: string): void;
}
```

`workflows/logger-demo.ts`

```ts
import { Context } from "@temporalio/workflow";
import { Logger } from "../interfaces/logger";

const log = Context.dependency<Logger>("logger");

export async function main(): Promise<void> {
  log.info("hey ho");
  log.error("lets go");
}
```

Register a logger for injection into the Worker's isolate context.
Each time a Workflow is initialized it gets a reference to the injected dependencies.

`worker/index.ts`

```ts
import { WorkflowInfo } from "@temporalio/workflow";
import { Logger } from "../interfaces/logger";

// ...

worker.inject<Logger /* optional for type checking */>(
  "logger",
  {
    /* Your logger implementation goes here */
    info(info: WorkflowInfo, message: string) {
      console.log(info, message);
    },
    error(info: WorkflowInfo, message: string) {
      console.error(info, message);
    },
  },
  { ignoreReplay: false /* default is true  */ }
);
```

#### Variant B - Using a single `Dependencies` interface

`interfaces/index.ts`

```ts
import { Logger } from "./logger";

export interface Dependencies {
  logger: Logger;
}
```

`workflows/logger-deps-demo.ts`

```ts
import { Context } from "@temporalio/workflow";
import { Dependencies } from "../interfaces";

const { logger } = Context.deps<Dependencies>();

export function main(): void {
  logger.info("hey ho");
  logger.error("lets go");
}
```

`worker/index.ts`

```ts
import { WorkflowInfo } from "@temporalio/workflow";
import { Dependencies } from "../interfaces";

await worker.create<Dependencies /* optional for type checking */>({
  workDir: __dirname,
  dependencies: {
    logger: {
      implementation: {
        /* Your logger implementation goes here */
        info(info: WorkflowInfo, message: string) {
          console.log(info, message);
        },
        error(info: WorkflowInfo, message: string) {
          console.error(info, message);
        },
      },
      options: { ignoreReplay: false /* default is true  */ },
    },
  },
});
```

#### Comparison

|                      | Variant A                                                        | Variant B                   |
| -------------------- | ---------------------------------------------------------------- | --------------------------- |
| Missing dependencies | ❌ Hard to enforce all dependencies are injected into the worker | ✅ Enforced by type checker |
| Dependency naming    | ❌ Prone to typos                                                | ✅ Enforced by type checker |

I'm strongly leaning towards variant B.

### Other considered solutions

1. Provide our own logger implementation

   - Users cannot use their own tools

1. Expose the Worker's logger to Workflows and Activities

   - Does not cover metrics
   - Users cannot use their own tools

1. Let users build their own logger over the injected `console.log`

   - Requires Workflow `console.log` output to be customizable
   - Separate solution for Activities and Workflows
   - Users cannot use their own tools

### A note on `console.log`

Currently we inject `console.log` into the Workflow isolate for convenience. This has proven to be quite handy but the produced logs are missing important context like the workflowId / runId that generated them.
We should modify `console.log`'s output to include the relevant context by default and allow overriding `console.log` via the external dependencies mechanism.

- `console.log` messages should be dropped during replays (by default).

### Dependencies

In order to implement this solution we need to add an `isReplay` flag to each activation in the core<>lang interface.
