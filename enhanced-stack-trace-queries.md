# Enhanced stack trace queries

## Backround

The SDKs have a built-in `__stack_trace` query that can be used display where the workflow is blocked at the time of the
query (the last processed workflow task).

The response to a `__stack_trace` query is a single string representing a list of stack individual stack traces
separated by double newlines.

Example from the TS SDK:

```
    at someInternalFunction (/path/to/workflows/my-workflow.ts:18:10)
    at someWorkflowFunction (/path/to/workflows/my-workflow.ts:60:20)

    at someInternalFunction2 (/path/to/workflows/my-workflow.ts:100:30)
    at someWorkflowFunction2 (/path/to/workflows/my-workflow.ts:123:5)
```

While this is valuable for developers to be able to understand how their code correlates to event histories, it is quite
limited since it requires looking up the actual code to get the full picture.

## Proposal

SDKs can optionally implement an `__enhanced_stack_trace` query (name TBD) where instead of returning the stack traces
as a single string, they return a pre-defined structure, that structure will also include file sources.

The web UI can use this response to show the workflow code and highlight locations where it is blocked.

### Proposed structure

```ts
export interface SDKInfo {
  name: string;
  version: string;
}

/**
 * Represents a slice of a file starting at lineOffset
 */
export interface FileSlice {
  content: string;
  lineOffset: number;
}

/**
 * A pointer to a location in a file
 */
export interface FileLocation {
  /**
   * Path to source file (absolute or relative).
   * When using a relative path, make sure all paths are relative to the same root.
   */
  filepath: string;
  line: number;
  column: number;
  /**
   * function/goroutine/thread/greenlet/whatever name, if it exists.
   * (Not sure if this will be used but doesn't hurt to have some more information)
   */
  context?: string;
}

export interface StackTrace {
  locations: FileLocation[];
}

/**
 * Used as the result for the enhanced stack trace query
 */
export interface EnhancedStackTrace {
  sdk: SDKInfo;
  /**
   * Mapping of file name to file contents
   */
  sources: Record<string, FileSlice[]>;
  stacks: StackTrace[];
}
```

## Details

### TS SDK

In the TS SDK, the worker already has access to a single source map where it can look up the sources and fulfill this
query.

### Other SDKs

Other SDKs may not have access to the source in production environments but in certain environments like local
development those sources should be present, the exact solution should be researched per SDK.

## Alternatives considered

### SDK provides source control URLs for the UI to look up the code in

The problem with this approach is that the workflow code is composed from several sources, internal and external.
It would be very difficult to map all of these sources.

Another problem with this approach is that, when developing locally, workflow code would not be checked into the
upstream source control system and it would be difficult to produce a local URL, at that point we'd be better off using
file paths.

## Future work

When we have support for (not yet-planned) worker queries, we could build a more advanced UI that will let you follow
the execution of the workflow over time. This proposal could serve as the basis for that.

The reason why worker queries are required for this is because it would require fetching history, replaying a workflow
from the beginning, and recording the stack traces at every "activation" point (typically the workflow task boundary).
