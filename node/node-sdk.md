# NodeJS SDK Proposal

NodeJS is a perfect candidate for authoring Temporal workflows, by leveraging V8 isolates for running workflow code,
we can create a JS runtime that's completely deterministic.

The SDK steers developers to write their workflows and activities in TypeScript but vanilla JS is also supported.
All examples in this proposal are written in TypeScript.

## Table Of Contents
- [Activities](#activities)
    - [Examples](#examples)
    - [Registration](#registration)
    - [Payloads](#payloads)
- [Workflows](#workflows)
    - [Example](#example)
    - [Activity Options](#activity-options)
    - [Activity Type Declarations](#activity-type-declarations)
    - [Registration](#registration-1)
    - [Limitations](#limitations)
    - [Signals](#signals)
    - [Queries](#queries)
    - [Logging](#logging)
    - [Sessions](#sessions)
    - [Deterministic Time](#deterministic-time)
    - [Error Handling](#error-handling)
    - [Cancellation](#cancellation)
    - [Long Histories](#long-histories)


## Activities
Activity implementations are just JS functions, they run on the default NodeJS runtime, along with the Temporal SDK, and can import arbitrary npm packages.

Activities can get their `ActivityContext` by using `ActivityContext.current()`.
This is implemented using [`AsyncLocalStorage`](https://nodejs.org/api/async_hooks.html#async_hooks_class_asynclocalstorage) which was introduced in `nodejs v13.10.0, v12.17.0`.
(We can support earlier node versions by using the building blocks in [`async_hooks`](https://nodejs.org/api/async_hooks.html)).

### Examples
#### Synchronous function
```typescript
import crypto from 'crypto';

export function sha256(txt: string) {
  return crypto.createHash('sha256').update(txt).digest('hex');
}
```

#### Asynchronous function
```typescript
import axios from 'axios';

export async function httpGet(url: string) {
  const response = await axios.get(url);
  return response.data;
}
```

#### With `ActivityContext`
```typescript
import { ActivityContext } from 'temporal-sdk';
import axios from 'axios';

export async function httpGet(url: string) {
  const response = await axios.get(url, {
    onDownloadProgress: (progressEvent) => {
      const total = parseFloat(progressEvent.currentTarget.responseHeaders['Content-Length']);
      const current = progressEvent.currentTarget.response.length;
      const progress = Math.floor(current / total * 100);
      ActivityContext.current().heartbeat(progress);
    },
  });
  return response.data;
}
```

### Registration
Activities should be registered in their corresponding workers.

```typescript
worker.registerActivity('httpGet', httpGet);
```

### Payloads
We support the `DataConverter` interface as in [Java][java-data-converter].

## Workflows
Worflow code looks like vanilla TypeScript.
Workflows run in the same NodeJS process as the Temporal SDK and the activities.
Workflow code must export a `main` function which will be used as the handler method for workflow invocations.

TODO: signal and query handlers.

Each workflow instance runs in a separate [V8 isolate][v8-isolate], which means it has a completely isolated execution context including global variables.
The Temporal SDK injects and removes references from the global object to ensure that code running in the isolate is fully deterministic.

Activities are invoked by calling `activities.$activityName` as a method or with options (see below).

### Example
```typescript
export async function main(x: number, y: number) {
  const msToSleep = await activities.httpGet(`https://calculator.com/add?x=${x}&y={y}`);
  await new Promise((resolve) => setTimeout(resolve, msToSleep * Math.random()));
}
```

### Activity Options
Activity options are passed in using the `withOptions` method.

```typescript
export async function main() {
  const body = await activities.httpGet.withOptions({ retries: 3 }).invoke('http://example.com');
  console.log(body);
}
```

### Activity Type Declarations
To define type declarations for your workflow's activities, add each activity to your `global.d.ts`.
```typescript
/// <reference types="@temporal-sdk/workflow-global" />

import * as declarations from '../../activities';

declare global {
  namespace activities {
    // Use the signature of an activity function
    export var httpGet: Activity<typeof declarations.httpGet>;
    // In case you can't import you function definition (implmented in another language or simply unavailable in this context),
    // define the signature manually
    export var add: Activity<Fn<[number, number], number>>;
  }
}
```

### Registration
```typescript
async function main() {
  const example = 'dist/workflow.js'; // Workflow file generated using the typescript compiler
  await worker.registerWorkflow(example);
}
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

### Signals
TBD

### Queries
TBD

### Logging
Logging from the workflow can be implemented by injecting a custom `console.log` function.

TBD log format and context

### Sessions
Not supported at the moment

### Deterministic Time
In a worflow isolate, all date and time methods, e.g `new Date()` and `Date.now`, are overridden by the SDK and replaced by deterministic versions.

### Error Handling
In workflows, errors are handled by catching exceptions and `Promise.catch` handlers.

### Cancellation
In a workflow, handle activity cancallation by catching a `CancellationError` or cancel activities using a `CancellationScope`.

#### Example
```typescript
export async function main(urls: string[]) {
  const scope = new CancellationScope();

  const promises = urls.map((url) => activities.httpGet.withOptions({ scope }).run(url));

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

#### Or with `CancellationScope.run()`
```typescript
export async function main(urls: string[]) {
  let promises: Array<Promise<string>>;
  const scope = CancellationScope.run(() => {
    promises = urls.map(activities.httpGet);
  });
  // Continue like above
}
```

On the activities side we want to use async functions which means activity authors will have to manually handle cancellation.
The `ActivityContext` exposes 2 ways of subscribing to cancellations.

1. A `cancelled` (Promise) property which can be awaited.
  ```typescript
  async function httpGetJson(url: string) {
    try {
      const request = await Promise.all(ActivityContext.current().cancelled, nonCancellableRequest(url));
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
  ```typescript
  async function httpGetJson(url: string) {
    const request = await fetch(url, { signal: ActivityContext.current().cancellationSignal });
    return request.json();
  }
  ```

### Long Histories
The size of a workflow history is limited, we will workaround this like in the other SDKs by using `ContinueAsNew`.

```typescript
export async function main(x: int) {
  console.log(`Iteration: ${x}`);
  await new Promise((resolve) => setTimeout(resolve, 100));
  return ContinueAsNew(x + 1);
}
```

[mdn-weakmap]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/WeakMap
[mdn-weakset]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/WeakSet
[v8-weakref]: https://v8.dev/blog/v8-release-84#javascript
[nodejs-api]: https://nodejs.org/api/
[typed-arrays]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/TypedArray
[v8-isolate]: https://v8docs.nodesource.com/node-0.8/d5/dda/classv8_1_1_isolate.html
[v8-heap-snaphots]: https://v8.dev/blog/custom-startup-snapshots
[java-data-converter]: https://github.com/temporalio/sdk-java/tree/master/temporal-sdk/src/main/java/io/temporal/common/converter
[abort-controller-signal]: https://developer.mozilla.org/en-US/docs/Web/API/AbortController/signal
