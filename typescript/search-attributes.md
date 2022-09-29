## Search attributes V2

### Why do we need this?

In the current version of the SDK, search attributes are always arrays. In order for the server to support visibility
on top of standard persistence, we need to redo the search attributes API to enforce single values for all search
attributes except for keywords. The server will eventually drop support for multiple search attribute values for
non-keywords.

### Minimal proposal

Make the E2E experience consistent, including query construction for listing workflows and search attribute
registration.

`workflows.ts`

```ts
import { searchAttributes } from '@temporalio/common';

export const customerAttribute = searchAttributes.defineAttribute(searchAttributes.Text, 'customer');
export const dateOfPurchaseAttribute = searchAttributes.defineAttribute(Date, 'dateOfPurchase');

export async function myWorkflow() {
  // Get the value of a search attribute - returns string | undefined here
  const customer = customerAttribute.value();
  // ... random workflow logic ...

  // Set the value of a search attribute, all set and unset calls are buffered and flushed out as a single command at
  // the end of an activation
  dateOfPurchaseAttribute.set(new Date());
  // Explicit unset API
  dateOfPurchaseAttribute.unset();
  // ...
}
```

`client.ts`

```ts
import { searchAttributes } from '@temporalio/common';
import { Client, Q } from '@temporalio/client';
import { customerAttribute, dateOfPurchaseAttribute, myWorkflow } from './workflows';

const client = new Client(/* options */);

// Only available in OSS for now
await client.operator.registerSearchAttributes(customerAttribute, dateOfPurchaseAttribute);
// Other methods will be exposed too

const iterator = client.workflow.list({
  query: Q.filter(
    // WorkflowType is a pre-defined search attribute
    Q.and(searchAttributes.WorkflowType.eq(myWorkflow.name), customerAttribute.eq('customer-id-1234')).orderBy(
      dateOfPurchaseAttribute,
      'ASC' // Optionally specify DESC | ASC
    )
  ),
  pageSize: 100, // optional
});

// Returns something like the TS wrapper returned by Describe - the API returns
// temporal.api.workflow.v1.WorkflowExecutionInfo
for await (const { workflowId, ...rest } of iterator) {
  const handle = client.workflow.getHandle(workflowId);
  await handle.cancel();
}

const handle = client.getHandle(someWorkflowId);
const info = await handle.describe();
const customer = info.getAttribute(customerAttribute); // includes runtime validation - returns string | undefined
// -- OR --
const customer = info.getAttribute<string>(customer); // no runtime validation - returns string | undefined
```

### What about the current APIs?

Search attributes are exposed in the SDK today in 3 places:

1. In the client - `WorkflowClient.describe()` return value (`WorkflowExecutionDescription.searchAttributes`)
2. In the workflow - `workflowInfo()` return value (`WorkflowInfo.searchAttributes`)
3. `upsertSearchAttributes` call from the workflow

We'll deprecate all of these APIs and point to the alternatives presented above.

If `upsertSearchAttributes` is called in the same activation after as the new `set|unset` APIs are used, it will trigger
flushing the buffered changes.
