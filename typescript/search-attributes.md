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
import { defineAttribute, Keyword, Text } from '@temporalio/common/search-attributes';

export const tagsAttribute = defineAttribute(Keyword, 'tags');
export const customerAttribute = defineAttribute(Text, 'customer');
export const dateOfPurchaseAttribute = defineAttribute(Date, 'dateOfPurchase');

export async function myWorkflow() {
  // Get the value of a search attribute - returns string | undefined here
  const customer = customerAttribute.value();
  // Get the value of a search attribute - returns string[] (which will be empty if unset)
  const tags = tagsAttribute.value();
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
import { WorkflowType } from '@temporalio/common/search-attributes';
import { Client, Q } from '@temporalio/client';
import { customerAttribute, dateOfPurchaseAttribute, myWorkflow, tagsAttribute } from './workflows';

const client = new Client(/* options */);

// Only available in OSS for now
await client.operator.registerSearchAttributes(customerAttribute, dateOfPurchaseAttribute);
// Other methods will be exposed too

const iterator = client.workflow.list({
  query: Q.filter(
    // WorkflowType is a pre-defined search attribute
    Q.and(WorkflowType.eq(myWorkflow.name), customerAttribute.eq('customer-id-1234')).orderBy(
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
const customer = info.getSearchAttribute(customerAttribute); // includes runtime validation - returns string | undefined
const tags = info.getSearchAttribute(tagsAttribute);
// ^ includes runtime validation - returns string[] (empty if not set)

// TODO: should we have a string based API? Will it return single or multiple values?
// It could look like this:

const customer = info.getSearchAttribute<string>('customer'); // no runtime validation - may return undefined
const tag = info.getSearchAttribute<string>('tags'); // no runtime validation - returns first tag or undefined

// -- OR --
const [customer] = info.getSearchAttribute<string>('customer'); // returns an array that may be empty
const tags = info.getSearchAttribute<string>('tags');
```

### What about the current APIs?

Search attributes are exposed in the SDK today in 3 places:

1. In the client - `WorkflowClient.describe()` return value (`WorkflowExecutionDescription.searchAttributes`)
2. In the workflow - `workflowInfo()` return value (`WorkflowInfo.searchAttributes`)
3. `upsertSearchAttributes` call from the workflow

We'll deprecate all of these APIs and point to the alternatives presented above.

If `upsertSearchAttributes` is called in the same activation after as the new `set|unset` APIs are used, it will trigger
flushing the buffered changes.
