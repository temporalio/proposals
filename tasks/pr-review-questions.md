# PR Review Questions to Address

Unanswered comments from @cretz on PR #104.

---

## API Parity

### 1. Workflow timer/sleep (api-parity.md:11)
> We thought this way too about async helpers when we were developing Python, .NET, and Ruby. But there are two reasons why you may want to have a workflow version: 1) because you have more options (e.g. timer summary), and 2) because internal lang runtime developers don't know it's harmful to add an extra async.

**Status:** [ ] TODO

---

### 2. Async await helpers (api-parity.md:20)
> Technically none of these are needed in Java either and can be written with wait conditions, but we have them anyways in Java (but not usually in other languages)

**Status:** [ ] TODO

---

### 3. Default activity options (api-parity.md:21)
> Technically we could have made everyone define a shared default options in Java too, but we chose not to (for other languages we don't have this usually)

**Status:** [ ] TODO

---

### 4. Rename typedSearchAttributes (api-parity.md:70)
> I would not call this `typedSearchAttributes`, just `searchAttributes` is fine, we only used the `typed` prefix to disambiguate from the existing, deprecated form in Java.

**Status:** [ ] TODO

---

### 5. getVersion side-effecting (api-parity.md:94)
> Arguably this should have never been a getter since it is side-effecting. But I understand if we don't want to change to full-blown patching API.

**Status:** [ ] TODO

---

## Client

### 6. WithStartWorkflowOperation design (advanced.md:21)
> Why do I need a client to create a with start workflow operation? And why does that return a "handle"? I think after lots of time spent designing this for update with start in Java, we concluded that the with-start-workflow-operation "promise" was just something passed in to `updateWithStart` (and `signalWithStart` if/when modernized).

**Status:** [ ] TODO

---

### 7. Handle naming (workflow-client.md:77)
> Would totally be ok calling these `newWorkflowHandle` or just `workflowHandle`

**Status:** [ ] TODO

---

### 8. Reified R for optional approach (workflow-client.md:77)
> Arguably one should be able to provide reified `R` too if such an optional approach is allowed, but meh

**Status:** [ ] TODO

---

### 9. Options after args (workflow-client.md:31)
> Same comments as activity concerning options after args, 0 or 1 arg overload only (maybe), etc

**Status:** [ ] TODO

---

### 10. Client connect static call (workflow-client.md:12)
> In newer SDKs, we found _requiring_ these separate steps unnecessary. Would recommend a static call on `KWorkflowClient` called `connect` that accepts options with target, namespace, etc.

**Status:** [ ] TODO

---

### 11. Handle type hierarchy (workflow-handle.md:45)
> Mentioned before, but it is confusing to have:
> * `KWorkflowHandle` - half-typed (just not result)
> * `KTypedWorkflowHandle` - typed with result
> * `WorkflowHandle` - untyped, named as if it'll be used from Java
>
> I recommend:
> * `KWorkflowHandle<T> : KWorkflowHandleUntyped` (extends only needed if reasonable)
> * `KWorkflowHandleWithResult<T, R> : KWorkflowHandle<T>` (extends only needed if reasonable)
> * `KWorkflowHandleUntyped`

**Status:** [ ] TODO

---

### 12. Options class for handle methods (workflow-handle.md:87)
> These should be in an options class if we want to be consistent (we can sugar out to these if needed)

**Status:** [ ] TODO

---

### 13. List super class (workflow-handle.md:178)
> I assume there's a super class for this that list returns?

**Status:** [ ] TODO

---

### 14. Wait for stage required (workflow-handle.md:86)
> We very intentionally decided to _require_ wait for stage at this time because we expect to support "admitted" as a wait for stage one day and we're not sure if that will become the default or if we'll ever have a default.

**Status:** [ ] TODO

---

## Configuration

### 15. Data converter design (README.md:52)
> Kotlin has an opportunity to improve on Java here if we want to do what newer SDKs do and make data converter a class that just accepts payload converter, failure converter, and codec instead of having it be something users implement as a whole. But ok if we don't want to have that design here.

**Status:** [ ] TODO

---

### 16. Client interceptors (interceptors.md:1)
> No client interceptors?

**Status:** [ ] TODO

---

## Workflows

### 17. Remove required interfaces (kotlin-idioms.md:21)
> Same as activity, I think we can discuss removing the _required_ interfaces altogether (but still supporting them)

**Status:** [ ] TODO

---

### 18. Cancellation statement unclear (cancellation.md:32)
> I don't understand this statement exactly. Does it mean "if either activity fails, the workflow fails which implicitly cancels any activities" or is there something more explicit here?

**Status:** [ ] TODO

---

## Worker

### 19. Discourage start pattern (README.md:32)
> We should discourage the `start` pattern IMO in favor of a `run` one. We have learned that `start`+`shutdown` can swallow fatal worker-runtime errors that we'd rather propagate.

**Status:** [ ] TODO

---

## Activities - Additional

### 20. Context data type (implementation.md)
**Comment ID:** 2682791531
> What is the data type of this context? Arguably for OO languages where the context is a type one can pass around and reference, obtaining the current context is a static method on the type itself, but if it is the Java SDK context, makes sense (static extension methods are not a thing). EDIT: I see later this is a Kotlin context class, I would recommend moving this call to that class, though it can be here too, meh.

**Status:** [ ] TODO

---

### 21. Logger on context (implementation.md)
**Comment ID:** 2682832357
> Can I get more detail on why a logger would be on the context. Is there an expected Kotlin logging solution that expects situationally stateful loggers instead of existing MDC/NDC thread/coroutine-local types of approaches?

**Status:** [ ] TODO

---

### 22. Heartbeat details collection (implementation.md)
**Comment ID:** 2682834623
> Heartbeat details is a collection, this will either have to accept an index and have a total-count method, or maybe accept some kind of reified tuple type or something. I guess there can be a helper for just the first detail item. Same for the actual `heartbeat` call.
>
> Also, will there be a `lastHeartbeatDetails`?

**Status:** [ ] TODO

---

### 23. Priority for local activities (local-activities.md)
**Comment ID:** 2682941947
> Priority doesn't make sense here

**Status:** [ ] TODO

---

## Workflows - Additional

### 24. Event loop control (kotlin-idioms.md:58)
**Comment ID:** 2683150870
> Do we have full control over the event loop including running the `awaitCondition` stuff when/how we want in that loop, or is this somehow just sugar on top of the Java one (sorry, could dig into the PoC, but being lazy)

**Status:** [ ] TODO

---
