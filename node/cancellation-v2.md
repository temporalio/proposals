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

## Changes to the current design

### Naming and structure

To solve issue (1), in this proposal the term "scope" goes away and blends in with the concept of Workflow `Context`.

```
cancellationScope -> Context.cancellable
shield -> Context.nonCancellable
cancel -> ContextualPromise.cancel (not related to (1), more on this below)
```

### New concepts

With these new concepts we can address issue (2).

#### `ContextualPromise` (or `CancellablePromise`)

- Implements the `PromiseLike` interface (awaitable via `then()`), exposes the `cancel` method
- Context aware: linked to parent context and propagates cancellation, transferable between different contexts
- Returned by activities, timers, and `Context.cancellable`

#### `ResolvablePromise` (or `Trigger`)

- Extends `ContextualPromise`
- Provides additional public methods to resolve and reject itself
- Useful for e.g waiting for a signal from WF main

  ```ts
  const unblocked = new ResolvablePromise<void>();
  const signals = {
    unblock(): void {
      unblocked.resolve();
    },
  };

  async function main() {
    await unblocked;
  }
  ```

### Open Questions

#### Sharing promises between different contexts

1. What happens when a timer or activity is created in a cancellable context and awaited in a non-cancellable context?

```ts
const p = sleep(3);
await Context.nonCancellable(async () => {
  // p is cancellable in a non cancellable context
  await p;
});
```

If the Workflow is cancelled, the user might be surprised if `await p` throws.

2. What happens when a timer or activity was created in a non-cancellable context and awaited in a cancellable context?

```ts
let p: Promise<void> | undefined = undefined;
await Context.nonCancellable(async () => {
  p = sleep(3);
});
// p is non cancellable in a cancellable context
await p;
```

If the Workflow is cancelled, the user might be surprised if `await p` does not throw.

One approach would be to say that once a `ContextualPromise` is awaited in a non-cancellable context it becomes non-cancellable in all contexts. Another approach is the exact opposite where the promise becomes cancellable once awaited in a cancellable context.

We should be able to support different cancellation policies for a single promise.
With this approach, when a promise is cancelled while it is awaited in a both cancellable and non-cancellable contexts, an exception is thrown immediately in all cancellable contexts (assuming TRY_CANCEL cancellation type) but the activity does not get cancelled.

The first 2 approaches are still surprising although they're predictable if they are well documented.
The latter approach seems preferable to me and the least surprising. Not sure how feasable this is and if there are limitations with different cancellation types.

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
  await ctx.sleep(3); // User mistake, should have been used `childCtx`
  await childCtx.configure(httpGet)("...");
});
```
