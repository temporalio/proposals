# 3rd revision of the Typescript SDK Workflow API

### Current API

```ts
import { Trigger } from '@temporalio/workflow';

export type MyWorkflow = (
  arg1: number,
  arg2: string
) => {
  execute(): Promise<void>;
  signals: {
    unblock(): void;
  };
  queries: {
    isBlocked(): boolean;
  };
};

export const myWorkflow: MyWorkflow = (arg1, arg2) => {
  const unblocked = new Trigger<void>();
  let isBlocked = true;
  return {
    // Main workflow logic
    async execute() {
      await unblocked;
      isBlocked = false;
    },
    signals: {
      unblock() {
        unblocked.resolve();
      },
    },
    queries: {
      isBlocked() {
        return isBlocked;
      },
    },
  };
};
```

#### Issues

- Types must be explicitly declared (To make [eslint happy](https://github.com/typescript-eslint/typescript-eslint/blob/master/packages/eslint-plugin/docs/rules/explicit-module-boundary-types.md))
- Very verbose
- Trigger (ResolvablePromise) is a foreign concept to JS developers
- Trigger doesn't provide all of the functionality for this workflow, an additional `isBlocked` boolean variable is required
- Signals and queries must be defined at the top level in order for types to be inferred.

#### Advantages

- Types for all Workflow handlers can be inferred at Workflow handle creation

### Goals for the redesign

- Maintain type inference capabilities - Mandatory for the Typescript SDK
- Dynamic signals and queries registration first - A single API for Workflow handler registration
- Componentization of related functionality - increase reusability
- Implicit interface declarations - less boilerplate
- No global variables - to support running Workflows in less isolated runtimes

### New proposal

#### Remove the `Trigger` API in favor of `condition`

`condition` is similar to `Workflow.await` in Java, it returns a Promise and accepts a closure which resolve the Promise when it returns `true`.

```ts
import { condition } from '@temporalio/workflow';

let isBlocked = true;
await condition(() => !isBlocked);
```

#### Remove the Workflow factory wrapper and always use dynamic handler registration

`workflows.ts`

```ts
import { Signal, Query, condition } from '@temporalio/workflow';

// Define the signal / query with the type signature at the top level to share the definition for handle creation
export const unblockSignal = new Signal<[] /* args */>('unblock');
export const isBlockedQuery = new Query<boolean /* return type */, [] /* args */>('isBlocked');

// Types are inferred without an additional type definition
export async function myWorkflow(arg1: number, arg2: string): Promise<void> {
  let isBlocked = true;
  unblockSignal.handler = () => (isBlocked = false);
  isBlockedQuery.handler = () => isBlocked;
  await condition(() => !isBlocked);
}
```

- Note how all unblocking related functionality is co-located now, we can use this to split our Workflow into components, for example we could have a reusable "unblock" component.

  ```ts
  export async function unblocked() {
    let isBlocked = true;
    unblockSignal.handler = () => (isBlocked = false);
    isBlockedQuery.handler = () => isBlocked;
    await condition(() => !isBlocked);
  }

  export async function myWorkflow1() {
    await unblocked();
  }

  export async function myWorkflow2() {
    await unblocked();
  }
  ```

#### WorkflowClient usage

`execute-workflow.ts`

```ts
import { WorkflowClient } from '@temporalio/client';
import { myWorkflow, unblockSignal, isBlockedQuery } from './workflows';

const client = new WorkflowClient();
const handle = client.createWorkflowHandle(myWorkflow);
await handle.start();
await handle.query(isBlocked /* no args */); // true
await handle.signal(unblockSignal /* no args */);
await handle.query(isBlocked /* no args */); // false
await handle.query<[number, string], string>('queryWithUnexportedType', 1, 'a'); // should return a string
await handle.result(); // undefined
```

### Alternatives considered

#### Signal as Trigger

```ts
export const unblockWithSignal = async () => {
  let isBlocked = true; // queryable
  await new Signal('unblock');
  isBlocked = false;
};
```

##### Checklist

| Goal                                      |                    |
| ----------------------------------------- | :----------------: |
| Verbosity                                 | :star::star::star: |
| Type inference for client                 |        :x:         |
| Dynamic handler registration              | :white_check_mark: |
| Componentization of related functionality | :white_check_mark: |
| Remove interface declarations             | :white_check_mark: |
| No global variables                       | :white_check_mark: |

##### Additional issues

- Does not support multiple signals of the same type or arguments (can be added with a `Signal(name, handler)` signature).
- Local variables cannot be automatically queryable - a practice which is questionable since it potentially leaks Workflow implementation details

#### Signal/Trigger with types

```ts
type UnblockSignal = {
  // can reuse for type safety when invoking, see below
  name: 'unblock';
  kind: void;
};

export const unblockWithSignal = async () => {
  let isBlocked = true; // queryable
  await new Signal<UnblockSignal>('unblock');
  isBlocked = false;
};
```

Same issues as the previous example with the additional issue that type definition requires the user to type the signal name and type in both the Workflow and client code.

#### QueryVariable / Signal as async iterator

```ts
export const unblockWithSignal = () => ({
  async execute() {
    await this.signals.unblock.next();
    this.queries.isBlocked.value = false;
  },
  signals: {
    unblock: new Signal<void>(), // A channel / async iterator
  },
  queries: {
    isBlocked: new QueryVariable<boolean>(true),
  },
});
```

-- OR --

```ts
export const signalLooper = () => {
  let state = 'idle';
  return {
    async execute() {
      for await (state of this.signals.changeState);
    },
    signals: {
      changeState: new Signal<string>(),
    },
    queries: {
      isRunning() {
        state === 'running';
      },
    },
  };
};
```

##### Checklist

| Goal                                      |                    |
| ----------------------------------------- | :----------------: |
| Verbosity                                 |    :star::star:    |
| Type inference for client                 | :white_check_mark: |
| Dynamic handler registration              |        :x:         |
| Componentization of related functionality |        :x:         |
| Remove interface declarations             |        :x:         |
| No global variables                       | :white_check_mark: |

##### Additional issues

- Using channels complicates writing Workflow code, this model is used in the golang SDK and requires the user to drain all signals from the channel before completing the Workflow to ensure all signals are processed. This is critical for Temporal which aims to support financial use-cases where missing signal delivery could result in $$$ lost.

#### Top level `QueryVariable`

```ts
export const unblockSignal = new Signal<[] /* args */>('unblock');
export const isBlockedQuery = new QueryVariable('isBlocked', true);

// Types are inferred without an additional type definition
export async function myWorkflow(arg1: number, arg2: string): Promise<void> {
  unblockSignal.handler = () => (isBlocked.value = false);
  await condition(() => !isBlocked.value);
}
```

##### Checklist

| Goal                                      |                    |
| ----------------------------------------- | :----------------: |
| Verbosity                                 | :star::star::star: |
| Type inference for client                 | :white_check_mark: |
| Dynamic handler registration              | :white_check_mark: |
| Componentization of related functionality | :white_check_mark: |
| Remove interface declarations             | :white_check_mark: |
| No global variables                       |        :x:         |

#### Handlers as Workflow arguments

1. With factory

```ts
export const myWorkflow: MyWorkflow = ({ signals, queries }) => (arg1, arg2) => {
  let isBlocked = true;
  queries.isBlocked = () => isBlocked;
  signals.unblock = () => (isBlocked = false);
  await condition(() => !isBlocked);
};
```

- :warning: Eslint doesn't like this and the `MyWorkflow` type must be explicitly declared

2. In first argument

```ts
export async function myWorkflow({ signals, queries }, arg1, arg2) {
  // ...
}
```

- :warning: Makes calling the client's execute function a bit weird since the first argument must be omitted

3. In last argument

```ts
export async function myWorkflow(arg1, arg2, { signals, queries }) {
  // ...
}
```

- :warning: Makes calling the client's execute function a bit weird, although not as weird as the avove

4. Args in props

```ts
export async function myWorkflow({ signals, queries: args: [arg1, arg2] }: MyWorkflowProps) {
  // ...
}
```

- :warning: Client execute function is disconnected from workflow definition / implementation

5. React style props

```ts
export async function myWorkflow({ signals, queries: arg1, arg2 }: MyWorkflowProps) {
  // ...
}
```

- :warning: Client execute function is disconnected from workflow definition / implementation.
- :warning: Makes cross SDK work weird since we support positional arguments in other SDKs.

##### Checklist

| Goal                                      |                    |
| ----------------------------------------- | :----------------: |
| Verbosity                                 | :star::star::star: |
| Type inference for client                 | :white_check_mark: |
| Dynamic handler registration              |        :x:         |
| Componentization of related functionality |        :x:         |
| Remove interface declarations             |        :x:         |
| No global variables                       | :white_check_mark: |
