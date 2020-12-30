# NodeJS SDK Proposal

NodeJS is a perfect candidate for authoring Temporal workflows, by leveraging V8 isolates for running workflow code,
we can create a JS runtime that's completely deterministic.

The SDK steers developers to write their workflows and activities in TypeScript but vanilla JS is also supported.
All examples in this proposal are written in TypeScript.

## Minimal Example
#### `activities/greeter.ts`
```ts
export async function greet(name: string) {
  return `Hello, ${name}!`;
}
```

#### `interfaces/workflows.ts`
```ts
import { Workflow } from '@temporal-sdk/interfaces';

export interface Example extends Workflow {
  main(name: string): Promise<void>;
}
```

#### `workflows/example.ts`
```ts
import { Example } from '@interfaces/workflows';
import { greet } from '@activities/greeter';

async function main(name: string): Promise<void> {
  const greeting = await greet(name);
  console.log(greeting);
}
export const workflow: Example = { main };
```

#### `worker/index.ts`
```ts
import { Worker } from '@temporal-sdk/worker';

(async () => {
  const worker = new Worker();
  await worker.run();
})();
```

### Workflow Invocation
#### `test.ts`
```ts
import { Example } from '@interfaces/workflows';
import { WorkflowClient } from '@temporal-sdk/workflow-client';

(async () => {
  const example = new WorkflowClient<Example>();
  await example("Temporal");
})();
```

## Table Of Contents
<!-- vim-markdown-toc GFM -->

* [Activities](#activities)
  * [Example](#example)
  * [activity `Context`](#activity-context)
  * [Registration](#registration)
  * [Payloads](#payloads)
* [Workflows](#workflows)
  * [Interface](#interface)
  * [Implementation](#implementation)
    * [Calling activities](#calling-activities)
    * [Activity Options](#activity-options)
      * [Global Activity Configuration](#global-activity-configuration)
      * [Per activity override](#per-activity-override)
      * [Activites with no type definitions](#activites-with-no-type-definitions)
    * [`ActivityOptions`](#activityoptions)
  * [Signals](#signals)
  * [Queries](#queries)
  * [Limitations](#limitations)
  * [Logging](#logging)
  * [Sessions](#sessions)
  * [Deterministic Time and Random](#deterministic-time-and-random)
  * [Error Handling](#error-handling)
  * [Worker](#worker)
    * [`constructor(queue: string, options?: WorkerOptions)`](#constructorqueue-string-options-workeroptions)
    * [`registerWorkflows(nameToPath: Record<string, string>): Promise<void>`](#registerworkflowsnametopath-recordstring-string-promisevoid)
    * [`registerActivities(importPathToImplementation: Record<string, Record<string, Function>>): Promise<void>`](#registeractivitiesimportpathtoimplementation-recordstring-recordstring-function-promisevoid)
    * [`run(): Promise<never>`](#run-promisenever)
    * [`suspendPolling(): Promise<void>`](#suspendpolling-promisevoid)
    * [`resumePolling(): Promise<void>`](#resumepolling-promisevoid)
    * [`isSuspended(): boolean`](#issuspended-boolean)
    * [`options: Readonly<WorkerOptions>`](#options-readonlyworkeroptions)
  * [WorkflowClient](#workflowclient)
    * [Example](#example-1)
  * [ChildWorkflow](#childworkflow)
  * [Cancellation](#cancellation)
    * [Example](#example-2)
    * [`CancellationScope.run()`](#cancellationscoperun)
  * [Long Histories](#long-histories)
* [Project Structure](#project-structure)
  * [References](#references)

<!-- vim-markdown-toc -->

## Activities

Activity implementations are just JS functions, they run in the default NodeJS runtime, along with the Temporal SDK's worker, and can import arbitrary npm packages.

### Example
```ts
// activities/greeter.ts

export async function greet(name: string) {
  return `Hello, ${name}!`;
}
```

### activity `Context`

Activities can get their `Context` by using `Context.current()`.

This is implemented using [`AsyncLocalStorage`](https://nodejs.org/api/async_hooks.html#async_hooks_class_asynclocalstorage) which was introduced in `nodejs v13.10.0, v12.17.0`.
(We can support earlier node versions by using the building blocks in [`async_hooks`](https://nodejs.org/api/async_hooks.html)).

```ts
// activities/http.ts

import { Context } from '@temporal-sdk/activity';
import axios from 'axios';

export async httpGet(url: string): Promise<string> {
  const response = await axios.get(url, {
    onDownloadProgress: (progressEvent) => {
      const total = parseFloat(progressEvent.currentTarget.responseHeaders['Content-Length']);
      const current = progressEvent.currentTarget.response.length;
      const progress = Math.floor(current / total * 100);
      Context.current().heartbeat(progress);
    },
  });
  return response.data;
}
```

### Registration
Activities are automatically registered by path when using the project initializer.

If for any reason you need custom registration, you may do so using `worker.registerActivities`:

```ts
// worker/index.ts
import * as impl from './implementation/greeter'; // Non-standard path

worker.registerActivities({ '@activities/greeter': impl });
```

### Payloads
We support the `DataConverter` interface as in [Java][java-data-converter].

## Workflows
Workflow code looks like vanilla TypeScript.
Workflow implementation must export a `workflow` object which will be used as handler methods for workflow invocations, signals, and queries.

Workflows run in the same NodeJS process as the worker and the activities.
Each workflow instance runs in a separate [V8 isolate][v8-isolate], a completely isolated execution context including global variables.
The Temporal SDK injects and removes references from the global object to ensure that code running in the isolate is fully deterministic.

### Interface
A workflow's interface is used for validating the implementation and generating a type safe `WorkflowClient` and `ChildWorkflow`.

Workflow interfaces are intended for the implementation and are written in sync or async form
meaning a method could return `number` or it could return `Promise<number>` or their union.
We provide a `WorkflowForClient` type which transforms the interface to an async only interface for `WorkflowClient` and `ChildWorkflow`.

Workflow interface declarations are optional, they're only required for generating type safe clients.
It is considered good practice to declare an interface for each workflow.

```ts
// interfaces/workflows.ts
import { WorkflowForClient } from '@temporal-sdk/interfaces';

// This interface will need to be implemented
export interface Example {
  main(name: string): Promise<void>;
  // more on these later
  signals: {
    abandon(reason: string): void; // or Promise<void>; 
  };
  queries: {
    step(): number;
    state(key: string): unknown;
  };
}

// Optionally export the client interface too
export type GreeterClient = WorkflowClient<Example>;
```

### Implementation
The workflow implementation is limited to using deterministic code only.
A workflow file must export a `workflow` object which can be type checked using a pre-defined inteface.

```ts
// workflows/example.ts
import '@temporal-sdk/workflow'; // inject global type declarations
import { Example } from '@interfaces/workflows';

async function main(name: string) {
  // setTimeout and Math.random are replaced with deterministic versions
  await new Promise((resolve) => setTimeout(resolve, Math.random()));
  console.log(`Hello, ${name}!`);
}

export const workflow: Example = { main, signals, queries }; // signals and queries discussed below
```

#### Calling activities

Activities can be imported into the workflow implementation and called as regular functions.
At runtime, the activities imported are replaced with stubs which schedule activities in the system.

```ts
// workflows/example.ts
import '@temporal-sdk/workflow'; // inject global type declarations
import { Example } from '@interfaces/workflows';
import { greet } from '@activites/greeter';

async function main(name: string) {
  const greeting = await greet(name);
  console.log(greeting);
}

export const workflow: Example = { main };
```

#### Activity Options
Activity options can be provided as global configuration on worker creation and customized per activity function.

##### Global Activity Configuration
```ts
// worker/index.ts

new Worker({
  activityDefaults: { // ActivityOptions
    type: 'local',
    startToCloseTimeout: '5 minutes',
  },
});
```

##### Per activity override
```ts
// workflows/example.ts

import { Context } from '@temporal-sdk/workflow';
import { Example } from '@interfaces/workflows';
import { greet } from '@activites/greeter';

const greetWithCustomTimeout = Context.configure({ greet }, { // ActivityOptions
  type: 'remote', // 'local' is also valid
  taskQueue: 'greeter',
  startToCloseTimeout: '1 hour',
}); // returns a copy, `greet`'s options are unchanged

async function main(name: string) {
  const greeting = await greetWithCustomTimeout(name);
  console.log(greeting);
}

export const workflow: Example = { main };
```

##### Activites with no type definitions
```ts
const Greet = (name: string) => string;

const greet = Context.configure<Greet>('greet', { // ActivityOptions
  type: 'remote', // 'local' is also valid
  taskQueue: 'greeter',
  startToCloseTimeout: '1 hour',
});
```

#### `ActivityOptions`
```ts
// All timeouts and intervals accept ms format strings (see: https://www.npmjs.com/package/ms).

// See: https://www.javadoc.io/doc/io.temporal/temporal-sdk/latest/io/temporal/activity/ActivityOptions.Builder.html
interface CommonActivityOptions {
  scheduleToCloseTimeout?: string,
  startToCloseTimeout?: string,
  scheduleToStartTimeout?: string,
  heartbeatTimeout?: string,
  /**
   * If not defined, will not retry, otherwise retry with given options
   */
  retry?: RetryOptions,
}

interface LocalActivityOptions extends CommonActivityOptions {
  type: 'local',
}

// 
interface RemoteActivityOptions extends CommonActivityOptions {
  type: 'remote',
  taskQueue: string,
}

// See: https://www.javadoc.io/doc/io.temporal/temporal-sdk/latest/io/temporal/common/RetryOptions.Builder.html
interface RetryOptions {
  backoffCoefficient?: number,
  initialInterval?: string,
  maximumAttempts?: number,
  maximumInterval?: string,
}

type ActivityOptions = RemoteActivityOptions | LocalActivityOptions;
```


### Signals
Workflows can register signal hooks by via the exported `workflow`'s `signals` property.

```ts
const scope = new CancellationScope();

export const signals = {
  abandon(reason: string) {
    console.log('Abandon requested, reason:', reason);
    scope.cancel();
  }
}

async function main() {
  // ...
}

export const workflow: Example = { main, signals };
```

### Queries
Workflows can register signal hooks by via the exported `workflow`'s `queries` property.

```ts
let step = 0;
const state = {
  a: 1,
  b: 2,
};

export const queries = {
  step: () => step,
  state: (key) => state[key],
}

async function main() {
  // ...
  ++step;
  state.b = 3;
  // ...
}

export const workflow: Example = { main, signals };
```

### Limitations
* The [NodeJS API][nodejs-api] is not available in workflow code as it breaks determinism.
* Only ES modules can be imported out of the box with V8 isolates while most npm package use the CommonJS module implementation.
    * We can bypass this by implementing `CommonJS` `require` ([reference](https://nodejs.org/api/modules.html#modules_all_together)).
    * 3rd party imported modules may contain async / await keywords - this can be overcome by transpiling each required file at runtime.
* Submitted workflow code must not use async / await syntax.
    Using async / await bypasses the injected Promise object in the workflow context and hinders our ability to gain full control over scheduling.
    To get around this we recommend setting the `tsconfig.json` target to `<=es6` which transforms all async await calls into generators and Promises.
    Other solutions include using babel [transform regenerator](https://babeljs.io/docs/en/babel-plugin-transform-regenerator) for e.g. when using vanilla JS.
* `es2015.collection` library should be excluded from `tsconfig.json` because it exports [`WeakMap`][mdn-weakmap] and [`WeakSet`][mdn-weakset].
    Weak references are non-deterministic since we can't programatically control the V8 garbage collector.
    [`WeakRef`][v8-weakref] (`v8 >= 8.4` -> `nodejs >= 14.6.0`) suffers from the same issue and should be avoided.
    `WeakRef`, `WeakMap` and `WeakSet` are all deleted from the global scope.

### Logging
Logging from the workflow can be implemented by injecting a custom `console.log` function.

TBD log format and context

### Sessions
Not supported at the moment

### Deterministic Time and Random
In a workflow isolate, all date and time methods, e.g `new Date()` and `Date.now`, are overridden by the SDK and replaced by deterministic versions.
This is also true for `Math.random()`.

### Error Handling
In workflows, errors are handled by catching exceptions and `Promise.catch` handlers.

### Worker
A worker is needed in order to register and run activities and workflows with the Temporal server.

See [Java SDK](https://www.javadoc.io/static/io.temporal/temporal-sdk/1.0.4/io/temporal/worker/WorkerOptions.Builder.html) for an explanation of the various options.
```ts
interface WorkerOptions {
  activityDefaults: ActivityOptions,
  activitiesPath?: string, // defaults to '../activities'
  workflowsPath?: string,  // defaults to '../workflows'
  autoRegisterActivities?: boolean, // defaults to true
  autoRegisterWorkflows?: boolean,  // defaults to true

  maxConcurrentActivityExecutionSize?: number, // defaults to 200
  maxConcurrentLocalActivityExecutionSize?: number, // defaults to 200
  getMaxConcurrentWorkflowTaskExecutionSize?: number, // defaults to 200
  getMaxTaskQueueActivitiesPerSecond?: number,
  getMaxWorkerActivitiesPerSecond?: number,
  isLocalActivityWorkerOnly?: boolean, // defaults to false
}

interface WorkflowRegistrationOptions {
  activityDefaults: ActivityOptions,
}
```

#### `constructor(queue: string, options?: WorkerOptions)`
Create a `Worker` and bind it to `queue`, optionally automatically register workflows and activities.

#### `registerWorkflows(nameToPath: Record<string, string>): Promise<void>`
Manually register workflows, e.g. for when using a non-standard directory structure.

#### `registerActivities(importPathToImplementation: Record<string, Record<string, Function>>): Promise<void>`
Manually register activities, e.g. for when using a non-standard directory structure ([example](#registration)).

#### `run(): Promise<never>`
Start polling, throws on unhandled error.

#### `suspendPolling(): Promise<void>`
Do not make new poll requests.

#### `resumePolling(): Promise<void>`
Allow new poll requests.

#### `isSuspended(): boolean`

#### `options: Readonly<WorkerOptions>`
Getter for the worker's options.

### WorkflowClient
A workflow client can be used to invoke workflow methods, signals, and queries.
`WorkflowClient` may not be used from workflows.

```ts
interface WorkflowClientOptions {
  // Host of the temporal service
  host?: string, // defaults to localhost
  // Port of the temporal service
  port?: number // defaults to 7233
  namespace?: string // default TBD
  identity?: string // defaults to `${process.pid}@${os.hostname()}`
}

type Promisify<T> = T extends Promise<any> ? T : Promise<T>;

type Asyncify<F extends (...args: any[]) => any> = (...args: Parameters<F>) => Promisify<ReturnType<F>>;

type WorkflowClient<T extends Workflow> = {
  new (options?: WorkflowClientOptions): WorkflowClient<T>,
  (...args: Parameters<T['main']>): Promisify<ReturnType<T['main']>>,
  signal: T['signals'] extends Record<string, WorkflowSignalType> ? {
      [P in keyof T['signals']]: Asyncify<T['signals'][P]>
  } : undefined,
  query: T['queries'] extends Record<string, WorkflowQueryType> ? {
      [P in keyof T['queries']]: Asyncify<T['queries'][P]>
  } : undefined,
}
```

#### Example
```ts
const example = new WorkflowClient<Example>();
await example(process.env.USER); // Call workflow main
await example.signal.abort();
const state = await example.query.state("a");
```

### ChildWorkflow
`ChildWorkflow` is used for calling workflow from other workflows.
It is similar to `WorkflowClient` but it cannot call queries, only main and signals.

```ts
import { Context } from '@temporal-sdk/workflow';

interface Add {
  main(a: number, b: number): number;
}
const add = Context.child<Add>();

async function main() {
  const res = await add(1, 1);
  console.log(res);
}
```

### Cancellation
In a workflow, handle activity cancallation by catching a `CancellationError` or cancel activities using a `CancellationScope`.

#### Example
```ts
// workflow/example.ts
import { httpGet } from '@activities/http';

async function main(urls: string[]) {
  const scope = new CancellationScope();
  const cancelableHttpGet = Context.configure(httpGet, { scope });

  const promises = urls.map((url) => cancelableHttpGet(url);

  const result = await Promise.race(promises);
  scope.cancel();

  for (const promise of promises) {
    try {
      await promise;
    } catch (err) {
      if (!(err instanceof CancellationError)) {
        throw err;
      }
    }
  }
}
```

#### `CancellationScope.run()`
```ts
// workflow/example.ts
import { httpGet } from '@activities/http';

async function main(urls: string[]) {
  let promises: Array<Promise<string>>;
  const scope = CancellationScope.run(() => {
    promises = urls.map(httpGet);
  });
  // Continue like above
}
```

On the activities side we want to use async functions which means activity authors will have to manually handle cancellation.
The `ActivityContext` exposes 2 ways of subscribing to cancellations.

1. A `cancelled` (Promise) property which can be awaited.
  ```ts
  async function httpGetJson(url: string) {
    try {
      const request = await Promise.all(Context.current().cancelled, nonCancellableRequest(url));
    } catch (err) {
      if (err instanceof CancellationError) {
        // cleanup
      } 
      throw err;
    }
    return request.json();
  }
  ```
1. A `cancellationSignal`([`AbortController signal`][abort-controller-signal]) which can be used i.e with `fetch`.
  ```ts
  async function httpGetJson(url: string) {
    const request = await fetch(url, { signal: Context.current().cancellationSignal });
    return request.json();
  }
  ```

### Long Histories
The size of a workflow execution's history is limited, we workaround this like in the other SDKs by using `continueAsNew`.

```ts
// workflows/tail-recursion.ts
async function main(x: int) {
  console.log(`Iteration: ${x}`);
  await new Promise((resolve) => setTimeout(resolve, 100));
  return Context.continueAsNew(x + 1);
}
```

## Project Structure
A typical project consists of 4 sub-projects with typescript [project references][ts-project-references].

```
worker/ -> worker code
interfaces/ -> interfaces (mostly for workflows)
workflows/ -> workflows implementations
activities/ -> activities implementations
```

This code structure is required for enabling workflows - which run in an [isolated environment](#workflows) - to specify a custom `tsconfig.json` than the rest of the project.

Since the project skeleton is complex we'll provide an initializer package to be used with [npm init][npm-init].

### References
![](./project-structure.svg)

Each of the referenced projects can be imported using [typescript path aliases][tsconfig-paths].

The following aliases are included in the initializer package:
- `@interfaces`
- `@workflows`
- `@activities`

[ts-project-references]: https://www.typescriptlang.org/tsconfig#references
[npm-init]: https://docs.npmjs.com/cli/v6/commands/npm-init
[tsconfig-paths]: https://www.typescriptlang.org/tsconfig#paths
[mdn-weakmap]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/WeakMap
[mdn-weakset]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/WeakSet
[v8-weakref]: https://v8.dev/blog/v8-release-84#javascript
[nodejs-api]: https://nodejs.org/api/
[typed-arrays]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/TypedArray
[v8-isolate]: https://v8docs.nodesource.com/node-0.8/d5/dda/classv8_1_1_isolate.html
[v8-heap-snaphots]: https://v8.dev/blog/custom-startup-snapshots
[java-data-converter]: https://github.com/temporalio/sdk-java/tree/master/temporal-sdk/src/main/java/io/temporal/common/converter
[abort-controller-signal]: https://developer.mozilla.org/en-US/docs/Web/API/AbortController/signal
