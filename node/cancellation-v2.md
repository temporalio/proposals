## [Current design](https://docs.temporal.io/docs/node/workflow-scopes-and-cancellation)

## Issues with the current design

1. The concept of scopes is an additional term users need to learn which is foreign to JS developers

2. With the current design there's no way to share or transfer promises between scopes

   1. In this example the Workflow cannot be cancelled and will be stuck forever:

      ```ts
      // Resolvable promise (should be resolved elsewhere in the code, e.g from signal)
      let resolve: ((val: any) => void) | undefined = undefined;
      const p = new Promise((resolve_, reject) => {
        resolve = resolve_;
      });

      export async function main(): Promise<void> {
        await p;
      }
      ```

   1. When trying to cancel the promise below we get an error from WF internals: `Expected to find child scope mapping, got undefined`

      ```ts
      import { cancel, cancellationScope, sleep } from '@temporalio/workflow';

      export async function main(): Promise<void> {
        const timer = sleep(10);
        const promise = cancellationScope(async () => {
          await timer;
        });
        cancel(promise);
        await promise;
      }
      ```

Issue (1) seems to be a non-issue as cancellation scopes are a wide-spead concept

- [Java SDK](https://github.com/temporalio/samples-java/blob/master/src/main/java/io/temporal/samples/hello/HelloCancellationScope.java)
- [Python trio](https://vorpus.org/blog/timeouts-and-cancellation-for-humans/#cancel-scopes-trio-s-human-friendly-solution-for-timeouts-and-cancellation)
- [dotnet](https://docs.microsoft.com/en-us/dotnet/framework/windows-workflow-foundation/modeling-cancellation-behavior-in-workflows)

To solve issue (2.1), we introduce the [`Trigger`](#trigger) class.<br/>
Issue (2.2) is a bug but it raises the point that the docs should clarify which scope each Activity and timer are attached to and how they are cancelled.

## Proposed changes

### Naming and structure

```
shield -> CancellationScope.shield
cancel -> CancellationScope.cancel
```

### Behavior

- `cancellationScope` no longer throws `CancellationError`, it simply cancels timers and activities which in turn should throw `CancellationError`
- Activities and timers started in a `cancellationScope` after it's been cancelled will not start and instead will throw `CancellationError`
- `Context.cancelled` changes to return a promise to assist writing Workflows which are driven solely by signals

  ```ts
  async function main() {
    await Context.cancelled;
  }

  let counter = 0;

  const signals = {
    increment() {
      ++counter;
    },
  };
  // ...
  ```

## Concepts

In the Node SDK, Workflows are represented internally by a tree of scopes where the `main` function runs in the root scope.
Cancellation propagates from outer scopes to inner ones and is handled by catching `CancellationError`s when `await`ing on promises.

Scopes are created using the `cancellationScope` function.

When a cancellation scope is cancelled, it will cancel any cancellables that reside within the scope and nested inner scopes, cancellables consist of:

- Activities
- Timers
- [`Trigger`](#trigger)s

### Constructs

#### `cancellationScope`

- Creates a new `CancellationScope` and links it as a child of the active `CancellationScope`
- Signatures
  - `cancellationScope<T>(fn: (scope: CancellationScope) => Promise<T>): Promise<T>`
  - `cancellationScope<T>(opts: CancellationScopeOptions, fn: (scope: CancellationScope) => Promise<T>): Promise<T>`

#### `withTimeout<T>(timeout: number, fn: (scope: CancellationScope) => Promise<T>): Promise<T>`

- Alias to `cancellationScope({ deadline: Date.now() + timeout }, fn)`

#### `CancellationScopeOptions`

- `deadline` - absolute (Workflow) time before the scope is cancelled
- `shield` - start the scope in `shield` mode preventing cancellation from propagating to inner scopes, Activities, timers, and Triggers.
- `parent` - an **optional** `CancellationScope` (useful for running background tasks)

#### `CancellationScope`

- Passed into the function argument of `cancellationScope`

  ```ts
  await cancellationScope(async (scope /* CancellationScope */) => {
    scope.deadline = Date.now() + 1000;
    await httpPost('...');
  });
  ```

- Exposes the following methods and attributes
  - `cancelled` - a promise that rejects once the scope is cancelled
  - `cancel()` - manually cancel the scope
  - `deadline` - dynamic deadline for the scope
  - `shield` - boolean controlling whether to shield scope from outer cancellation<br/>
    (Scope may still be cancelled from within if it calls a function that throw `CancellationError`)

#### `Trigger`

- Implements the `PromiseLike` interface (awaitable via `then()`)
- Scope aware: linked to parent scope and propagates cancellation
- Provides public methods to `resolve` and `reject` itself
- Useful for e.g waiting for a signal from WF main

  ```ts
  const unblocked = new Trigger<void>();
  const signals = {
    unblock(): void {
      unblocked.resolve();
    },
  };

  async function main() {
    await unblocked;
  }
  ```

## Examples

#### Cancel a timer from Workflow code

```ts
import { CancellationError, cancellationScope, sleep } from '@temporalio/workflow';

export async function main() {
  // Timers and Activities are automatically cancelled when their containing scope is cancelled.
  // Awaiting on a cancelled scope with throw the original CancellationError.
  try {
    await cancellationScope(async (scope) => {
      sleep(1); // <-- Will be cancelled because it is attached to `scope`
      scope.cancel();
    });
  } catch (e) {
    if (e instanceof CancellationError) {
      console.log('Exception was propagated 👍');
    }
    throw e; // <-- Fail the workflow
  }
}
```

#### Run multiple activities with a single deadline

```ts
import { withTimeout } from '@temporalio/workflow';
import { httpGetJSON } from '@activities';

export async function main(urls: string[], timeoutMs: number) {
  // If timeout triggers before all activities complete
  // the Workflow will fail with a CancellationError.
  const results = await withTimeout(timeout, () => Promise.all(urls.map(httpGetJSON)));
  // Do something with the results
}
```

#### `CancellationScope`s can be shielded, preventing cancellation from propagating to created cancellables

```ts
import { cancellationScope } from '@temporalio/workflow';
import { httpGetJSON } from '@activities';

export async function main(url: string) {
  // Prevent Activity from being cancelled and await completion.
  // Note that the Workflow is completely oblivious to cancellation in this example.
  const result = await cancellationScope(async (scope) => {
    scope.shield = true;
    return httpGetJSON(url);
  });
  return result;
}
```

#### `Context.cancelled` may be awaited upon in order to make Workflow aware of cancellation while waiting on shielded scopes

```ts
import { CancellationError, cancellationScope } from '@temporalio/workflow';
import { httpGetJSON } from '@activities';

export async function main(url: string) {
  let result: any = undefined;
  try {
    const promise = cancellationScope({ shield: true }, () => httpGetJSON(url));
    result = await Promise.race([Context.cancelled, promise]);
  } catch (err) {
    if (!(e instanceof CancellationError)) {
      throw err;
    }
    // Prevent Workflow from completing so Activity can complete
    result = await promise;
  }
  return result;
}
```

#### Handle Workflow cancellation by an external client while an Activity is running

```ts
import { CancellationError, cancellationScope } from '@temporalio/workflow';
import { httpPostJSON, cleanup } from '@activities';

export async function main(url: string, data: any): Promise<void> {
  try {
    await httpPostJSON(url, data);
  } catch (e) {
    if (e instanceof CancellationError) {
      console.log('Workflow cancelled');
      // Cleanup logic goes in a shielded scope here
      // If we'd run cleanup outside of a shielded scope it would've been cancelled
      // before being started because the Workflow's root scope is cancelled.
      await cancellationScope({ shield: true }, () => cleanup(url));
    }
    throw e; // <-- Fail the Workflow
  }
}
```

#### Complex flows may be achieved by nesting cancellation scopes

```ts
import { CancellationError, cancellationScope } from '@temporalio/workflow';
import { setup, httpPostJSON, cleanup } from '@activities';

export async function main(url: string) {
  try {
    return await cancellationScope(async (scope) => {
      await cancellationScope({ shield: true }, () => setup());
      scope.deadline = Date.now() + 1000; // 1 second after setup is complete
      await httpPostJSON(url);
    });
  } catch (err) {
    if (!(err instanceof CancellationError)) {
      throw err;
    }
    await cancellationScope({ shield: true }, () => cleanup(url));
  }
}
```

#### Sharing promises between scopes

```ts
import { cancellationScope } from '@temporalio/workflow';
import { activity1, activity2 } from '@activities';

export async function main(): Promise<void> {
  const p1 = activity1(); // <-- Start activity1 in root scope
  const p2 = activity2(); // <-- Start activity2 in root scope

  const scopePromise = cancellationScope(async (scope) => {
    const first = await Promise.race([p1, p2]);
    scope.cancel(); // Does not cancel activity1 or activity2 as they're tied to the root scope
    return first;
  });
  return await scopePromise;
  // The Activity that did not complete will effectivly be cancelled when
  // Workflow completes unless explicitly awaited upon:
  // await Promise.all([p1, p2]);
}
```

```ts
import { cancellationScope } from '@temporalio/workflow';
import { activity1 } from '@activities';

export async function main(): Promise<void> {
  const p = await cancellationScope(async (scope) => {
    scope.shield = true;
    return activity1(); // <-- Start activity1 in shielded scope without awaiting completion
  });
  // Activity is shielded from cancellation even though it is awaited in the unshielded root scope
  return await p;
}
```

#### Callbacks and cancellation scopes

Callbacks are not particularly useful in the Workflows because all meaningful asynchronous operations return a Promise.

In the odd case that user code utilizes callbacks, `CancellationScope.cancelled` can be used to subscribe to cancellation.

```js
function doSomehing(callback) {
  setTimeout(callback, 10);
}

export async function main() {
  await new Promise((resolve, reject) => {
    cancellationScope(async (scope) => {
      doSomehing(resolve);
      scope.cancelled.catch(reject);
    });
  });
}
```

### Alternatives considered

#### Explicit context

One caveat of the current (implicit) cancellation API is that it relies on [v8's `PromiseHook` API](https://v8.github.io/api/head/namespacev8.html#a3f6381f74a2bcfbdc65fc0df7780f16e) which is only accessible from native bindings.
The extra native binding ([Workflow isolate extention](https://github.com/temporalio/sdk-node/blob/a25c0feca791a195eb5e50cf8c0fd9e0b5a1db83/packages/worker/native/workflow-isolate-extension.cc)) compicates the SDK installation and is currently broken on Windows and the brew NodeJS installation.

An alternative is to pass context around explicitly, but this is ruled out since it is error prone when nesting contexts:

```ts
await ctx.cancellable(async (childCtx) => {
  await ctx.sleep(3); // User mistake, should have used `childCtx`
  await childCtx.configure(httpGet)('...');
});
```

#### Cancellable promises

https://github.com/temporalio/proposals/blob/455f61961773d4364d93ee0c9b58ec221e913401/node/cancellation-v2.md
