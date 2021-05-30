## Logging and Metrics in user Workflow code

A hard requirement for our logging and metrics solution for user code is that we do not enforce a specific tool or convention and instead let our users use their existing tools.<br/>
For Activities, there is not an issue because users can run anything in an Activity. In Workflows OTOH, only deterministic code can run and metrics and logs should usually be dropped when a Workflow is replaying. Additionally the fact that the Node SDK runs Workflows in v8 isolates, means that there's no way to do IO or anything that interacts with the world without explicit support from the SDK.

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

(2) is limited to either synchronous and ignored functions as async functions conflict with the way we run isolated Workflow code since we assume that there are never any outstanding promises at the end of Workflow activation.

(3) raises the following reliablility concerns:

- When isolate runs out of memory but in that case logs will probably not work anyways.
- When WF code gets stuck e.g goes into an infinite loop but we can mitigate this problem by enforcing a time limit of execution in the isolate, in case execution times out we will be able to extract the logs.

(3) has the lowest overhead but also means there's an inherent delay from logs and metrics generation to processing - should be relatively minimal assuming Workflow code is not CPU bound - activations are typically short.<br/>
(3) is limited to either ignored and asynchronous functions since because it does **not** block the isolate.

### Proposed solution

Allow users to expose their logging and metrics interfaces to Workflow code as external dependencies.
We'll support techniques (2) and (3) stated above depending on the type of injected function.

**Extra care should be taken when using values returned from external dependencies because it can easily break deterministic Workflow execution.**

#### Definitions

#### `WorkflowInfo`

Logging and metrics require the Workflow's execution context information to have any meaning.
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

#### `ApplyMode`

We define an `ApplyMode` enum for specifying how a dependency function is executed

`@temporalio/workflow`

```ts
/**
 * Controls how an external dependency function is executed.
 * - `ASYNC*` variants run at the end of an activation and do **not** block the isolate.
 * - `SYNC*` variants run during Workflow activation and block the isolate,
 *   they're passed into the isolate using an {@link https://github.com/laverdet/isolated-vm#referenceapplyreceiver-arguments-options-promise | isolated-vm Reference}
 * The Worker will log if an error occurs in one of ignored variants.
 */
export enum ApplyMode {
  /**
   * Injected function will be called at the end of an activation.
   * Isolate enqueues function to be called during activation and registers a callback to await its completion.
   * Use if exposing an async function to the isolate for which the result should be returned to the isolate.
   */
  ASYNC = 'async',
  /**
   * Injected function will be called at the end of an activation.
   * Isolate enqueues function to be called during activation and does not register a callback to await its completion.
   * This is the safest async `ApplyMode` because it can not break Workflow core determinism.
   * Can only be used when the injected function returns void and the implementation returns void or Promise<void>.
   */
  ASYNC_IGNORED = 'asyncIgnored',
  /**
   * Injected function is called synchronously, implementation must be a synchronous function.
   * Injection is done using an `isolated-vm` reference, function called with `applySync`.
   */
  SYNC = 'applySync',
  /**
   * Injected function is called synchronously, implementation must return a promise.
   * Injection is done using an `isolated-vm` reference, function called with `applySyncPromise`.
   * This is the safest sync `ApplyMode` because it can not break Workflow core determinism.
   */
  SYNC_PROMISE = 'applySyncPromise',
  /**
   * Injected function is called in the background not blocking the isolate.
   * Implementation can be either synchronous or asynchronous.
   * Injection is done using an `isolated-vm` reference, function called with `applyIgnored`.
   */
  SYNC_IGNORED = 'applyIgnored',
}
```

#### `InjectedDependencyFunction<F>`

We define an `InjectedDependencyFunction<F>` interface that takes a `DependencyFunction` (any function) and turns it
into a type safe specification consisting of the function implementation type and configuration.

> NOTE: The actual definition of this interface is much more complex because it constraints which apply modes can be used depdending on the interface and implementation.

```ts
/** Any function can be a dependency function (as long as it uses transferrable arguments and return type) */
export type DependencyFunction = (...args: any[]) => any;

export interface InjectedDependencyFunction<F extends DependencyFunction> {
  /**
   * Type of the implementation function for dependency `F`.
   */
  fn(info: WorkflowInfo, ...args: Parameters<F>): ReturnType<F>;
  /**
   * Whether or not a dependency's functions will be called during Workflow replay
   * @default false
   */
  callDuringReplay?: boolean;
  /**
   * Defines how a dependency's functions are called from the Workflow isolate
   * @default IGNORED
   */
  applyMode: ApplyMode;
  /**
   * By default function arguments and result are copied on invocation.
   * That can be customized per isolated-vm docs with these options.
   * Only applicable to `SYNC_*` apply modes.
   */
  transferOptions?: isolatedVM.TransferOptionsBidirectional;
}
```

### Logger injection example

`interfaces/logger.ts`

```ts
/** Simplest logger interface for the sake of this example */
export interface Logger {
  info(message: string): void;
  error(message: string): void;
}
```

`interfaces/index.ts`

```ts
import { Dependencies } from '@temporalio/workflow';
import { Logger } from './logger';

export interface MyDependencies extends Dependencies {
  logger: Logger;
}
```

Use dependencies from a Workflow.

`workflows/logger-deps-demo.ts`

```ts
import { Context } from '@temporalio/workflow';
import { MyDependencies } from '../interfaces';

const { logger } = Context.dependencies<MyDependencies>();
// NOTE: dependencies may not be called at the top level because they require the Workflow to be initialized.
// You may reference them as demonstrated above.
// If called here an `IllegalStateError` will be thrown.

export function main(): void {
  logger.info('hey ho');
  logger.error('lets go');
}
```

Register dependencies for injection into the Worker's isolate context.
Each time a Workflow is initialized it gets a reference to the injected dependencies.

`worker/index.ts`

```ts
import { WorkflowInfo, ApplyMode } from '@temporalio/workflow';
import { MyDependencies } from '../interfaces';

await worker.create<{ dependencies: MyDependencies /* optional for type checking */ }>({
  workDir: __dirname,
  dependencies: {
    logger: {
        // Your logger implementation goes here.
        // NOTE: your implementation methods receive WorkflowInfo as an extra first argument.
        info: {
          fn(info: WorkflowInfo, message: string) {
            console.log(info, message);
          },
          applyMode: ApplyMode.SYNC,
        },
        error: {
          fn(info: WorkflowInfo, message: string) {
            console.error(info, message);
          },
          applyMode: ApplyMode.SYNC_IGNORED,
          // Not really practical to have only error called during replay.
          // We put it here just for the sake of the example.
          callDuringReplay: true,
        },
      },
    },
  },
});
```

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

In order to implement this solution we need to add an `isReplay` flag to each activation in the core⇔lang interface.

### Alternative interface - NOT chosen

#### `Context.dependency` + `Worker.inject`

`workflows/logger-demo.ts`

```ts
import { Context } from '@temporalio/workflow';
import { Logger } from '../interfaces/logger';

const log = Context.dependency<Logger>('logger');

export async function main(): Promise<void> {
  log.info('hey ho');
  log.error('lets go');
}
```

`worker/index.ts`

```ts
import { WorkflowInfo } from '@temporalio/workflow';
import { Logger } from '../interfaces/logger';

// ...

worker.inject<Logger /* optional for type checking */>(
  'logger',
  {
    /* Your logger implementation goes here */
    info(info: WorkflowInfo, message: string) {
      console.log(info, message);
    },
    error(info: WorkflowInfo, message: string) {
      console.error(info, message);
    },
  },
  { callDuringReplay: true /* default is false  */ }
);
```

#### Comparison

|                      | Alternative                                                      | Single `Dependencies` interface |
| -------------------- | ---------------------------------------------------------------- | ------------------------------- |
| Missing dependencies | ❌ Hard to enforce all dependencies are injected into the worker | ✅ Enforced by type checker     |
| Dependency naming    | ❌ Prone to typos                                                | ✅ Enforced by type checker     |

Single `Dependencies` interface was chosen for improved type safety.
