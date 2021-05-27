## [Current design](https://docs.temporal.io/docs/node/workflow-scopes-and-cancellation)

## Issues with the current design

1. The concept of scopes is an additional term users need to learn which is foreign to JS developers
2. With the current design there's no way to share or transfer promises between scopes.

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

## Proposed changes

### Naming and structure

To solve issue (1), in this proposal the term "scope" goes away and blends in with the concept of Workflow `Context`.

```
cancellationScope -> Context.cancellable
shield -> Context.nonCancellable
cancel -> CancellablePromise.cancel (not related to (1), more on this below)
```

### Behavior

In the current design Activities, timers, `cancellationScope`s and `shield`s were associated with the scope that created them.
To solve issue (2), in the new design, [`CancellablePromise`](#cancellablepromise-or-contextualpromise) can be associated with multiple ~~scopes~~ contexts, association is done when awaited upon.

### New concepts

#### Recap from the documentation site (updated for this proposal)

Temporal Workflows have different types that can be cancelled:

- A `CancellablePromise`
- A timer or an Activity (by cancelling their returned `CancellablePromise`)
- An entire Workflow

Workflows are represented internally by a tree of contexts where the `main` function runs in the root context.
Cancellation propagates from outer contexts to inner ones and is handled by catching `CancellationError`s when `await`ing on `CancellablePromise`s.
Activities and timers return a `CancellablePromise`.

#### `CancellablePromise` (or `ContextualPromise`)

- Implements the `PromiseLike` interface (awaitable via `then()`), exposes the `cancel` method
- Context aware: linked to parent context and propagates cancellation, transferable between different contexts
- Returned by activities, timers, `Context.cancellable`, and `Context.nonCancellable`
- Gets associated with a context once awaited

#### `Trigger` (or `ResolvablePromise`)

- Extends `CancellablePromise`
- Provides additional public methods to resolve and reject itself
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

### Examples

#### Handle Workflow cancellation by an external client while an Activity is running

```ts
import { CancellationError } from '@temporalio/workflow';
import { httpGetJSON } from '@activities';

export async function main(url: string) {
  let result: any = undefined;
  try {
    result = await httpGetJSON(url);
  } catch (e) {
    if (e instanceof CancellationError) {
      console.log('Workflow cancelled');
      // Cleanup logic goes here
    } else {
      throw e;
    }
  }
  return result; // Will be undefined in case the Workflow was cancelled
}
```

#### Cancel a timer from Workflow code

```ts
import { CancellationError, sleep } from '@temporalio/workflow';

export async function main() {
  // Timers and Activities are automatically cancelled when their promise is cancelled.
  // Awaiting on a cancelled promise with throw the original CancellationError.
  const promise = sleep(1);
  promise.cancel(); // promise is a CancellablePromise
  try {
    await promise;
  } catch (e) {
    if (e instanceof CancellationError) {
      console.log('Exception was propagated 👍');
    } else {
      throw e;
    }
  }
}
```

#### `Context.cancellable` and `Context.nonCancellable`

In order to have fine-grained control over cancellation, the Workflow library exports 2 methods for explicitly creating `CancellablePromise`s.

The first is `Context.cancellable` which when cancelled will propagate cancellation to all child `CancellablePromise`s including timers and Activities.

```ts
import { CancellationError, Context, sleep } from '@temporalio/workflow';
import { httpGetJSON } from '@activities';

export async function main(urls: string[], timeoutMs: number) {
  const promise = Context.cancellable(async () => {
    return Promise.all(urls.map(httpGetJSON));
  });
  try {
    const results = await Promise.race([
      promise,
      sleep(timeoutMs).then(() => {
        promise.cancel();
        // CancellationError rejects the race via promise
        // Any code below this line may still run
      }),
    ]);
    // Do something with the results
  } catch (e) {
    if (e instanceof CancellationError) {
      console.log('Exception was propagated 👍');
    } else {
      throw e;
    }
  }
}
```

The second is `Context.nonCancellable` which prevents cancellation from propagating to child promises and does not throw `CancellationError` when awaited.

```ts
import { CancellationError, Context } from '@temporalio/workflow';
import { httpGetJSON } from '@activities';

export async function main(url: string) {
  // Prevent activity from being cancelled and await completion
  // Note that the Workflow is completely unaware of cancellation in this example.
  const result = await Context.nonCancellable(httpGetJSON(url));
  return result;
}
```

`Context.cancellable` and `Context.nonCancellable` take a single argument which can either be an async function or a `CancellablePromise`, they also return a `CancellablePromise`.

Contexts can be nested e.g. for handling Workflow cancellation without disrupting Activity execution.

```ts
import { CancellationError, Context } from '@temporalio/workflow';
import { httpGetJSON } from '@activities';

export async function main(url: string) {
  let result: any = undefined;
  try {
    const promise = Context.nonCancellable(httpGetJSON(url));
    // Even though we wrap our non-cancellable promise in a cancellable context
    // it will not be cancelled when the Workflow is cancelled
    result = await Context.cancellable(promise);
  } catch (err) {
    if (e instanceof CancellationError) {
      console.log('Exception was propagated 👍');
      // Prevent Workflow from completing so activity can complete
      result = await promise;
    } else {
      throw err;
    }
  }
  return result;
}
```

More complex flows may be achieved by combining `cancellable`s and `nonCancellable`s.

### Open Questions

#### Sharing promises between different contexts

1. What happens when a timer or activity is awaited in both cancellable and non-cancellable contexts?

```ts
async function logWhenDone(p: PromiseLike<void>): Promise<void> {
  await p;
  console.log('done');
}

export async function main() {
  const p = sleep(3);
  await Promise.all([logWhenDone(p), Context.nonCancellable(() => logWhenDone(p))]);
}
```

If the Workflow is cancelled, the user might be surprised if `p` throws in a non-cancellable context or does not throw in cancellable context.

One approach would be to say that once a `CancellablePromise` is awaited in a non-cancellable context it becomes non-cancellable in all contexts. Another approach is the exact opposite where the promise becomes cancellable once awaited in a cancellable context.

Another approach would be to throw if a promise is simultaneously awaited in multiple contexts but this is might be too strict of a limitation.

We should be able to support different cancellation policies for a single promise.
With this approach, when a promise is cancelled while it is awaited in a both cancellable and non-cancellable contexts, an exception is thrown immediately in all cancellable contexts (assuming TRY_CANCEL cancellation type) but the activity does not get cancelled.

The first 2 approaches are still surprising although they're predictable if they are well documented.
The latter approach is complex and surprising in the worst way, there's no way for a Workflow to know if the activity was really cancelled or just the promise was cancelled.

The first approach seems like the way to go, because users rely on cancellation being propagated to Workflow code in order to perform cleanup.

> NOTE: This is an edge case and will probably not be encountered by most users.

#### Callbacks do not play well with cancellation

Since cancellation requires context awareness and context is implemented via PromiseHooks, users using callbacks will encounter undefined (and possibly surprising) behavior.

```js
function doSomehing(callback) {
  setTimeout(callback, 10);
}

export async function main() {
  function onDone() {}
  await Context.cancellable(async () => {
    doSomehing(onDone);
  });
}
```

Should we take this into consideration? Is documenting this limitation good enough?

### Alternatives considered

One caveat of the current (implicit) cancellation API is that it relies on [v8's `PromiseHook` API](https://v8.github.io/api/head/namespacev8.html#a3f6381f74a2bcfbdc65fc0df7780f16e) which is only accessible from native bindings.
The extra native binding ([Workflow isolate extention](https://github.com/temporalio/sdk-node/blob/a25c0feca791a195eb5e50cf8c0fd9e0b5a1db83/packages/worker/native/workflow-isolate-extension.cc)) compicates the SDK installation and is currently broken on Windows and the brew NodeJS installation.

An alternative is to pass context around explicitly, but this is ruled out since it is error prone when nesting contexts:

```ts
await ctx.cancellable(async (childCtx) => {
  await ctx.sleep(3); // User mistake, should have used `childCtx`
  await childCtx.configure(httpGet)('...');
});
```
