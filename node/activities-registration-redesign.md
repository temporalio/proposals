# Node.js Activities Registration

## Problems with the current design

- [#109](https://github.com/temporalio/sdk-node/issues/109) Activity identifier should not include the activity module name
- `@activities` import hack

  Currently we use the following to import Activity functions as stubs in a Workflow.

  ```ts
  import { myActivity } from '@activities/something';
  ```

  Issues:

  - `@` makes it look like a namespaced package
  - Too much _magic_
  - Only way to register activities is by passing a directory for the Worker to scan

## Proposal

Another approach would be to reuse the concept from [`ExternalDependencies`](https://docs.temporal.io/docs/node/external-dependencies#example)

`workflows/example.ts`

```ts
export interface ActivityInterface {
  deposit(account: string, amount: number): Promise<void>;
  withdraw(account: string, amount: number): Promise<void>;
}

// deposit and withdraw are typesafe stubs
const { deposit, withdraw } = Context.activities<ActivityInterface>(activityOptions);

// -- OR --

// We only use the type here, the import gets dropped by the typescript compiler
import * as activities from '../activities';
const { deposit, withdraw } = Context.activities<typeof activities>(activityOptions);
```

Activity Registration

`worker/index.ts`

```ts
import * as activities from '../activities';
const worker = await Worker.create<{ activities: ActivityInterface }>({ activities });
```

Here we rely on an optional interface definition for type safety but it allows more flexibility in registration and it seems like there's less "magic" going on.

This form of registration eliminates the activity identifier issue.

## Alternatives considered

- Single `@activities` file (e.g. `src/activities/index.ts`), disallow imports from `@activities/something`, this way we'd have unique activity registration without worrying about duplicates.
