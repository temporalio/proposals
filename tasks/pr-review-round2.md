# PR Review Round 2 - cretz Comments

## Q1: Default Parameters - Other SDKs Support Them
**Comment ID:** 2687176966
**File:** kotlin/open-questions.md:35
**Status:** DECIDED

> While I agree with the decision to disallow because it can be easily walked back if we change our minds, it may be worth noting that IIRC, Python, .NET, and Ruby all support default parameters. Here is a Python test confirming it: https://github.com/temporalio/sdk-python/blob/993de6d0e9b42bb01f24edfdb46e0795b00debcf/tests/worker/test_workflow.py#L3502-L3545.

**Decision:** Allow default parameters for the 0-1 argument case, aligning with Python/.NET/Ruby. With the 0-1 parameter model (>1 falls back to untyped), Kotlin's out-of-order named parameter complexity becomes moot.

**Response:** Good point about other SDKs supporting defaults. Given we're moving to 0-1 parameters (with >1 falling back to untyped), supporting a default for a single parameter is straightforward and aligns with Python/.NET/Ruby. Will update the docs to allow defaults for the single-parameter case.

---

## Q2: Interfaceless - Require Matching Annotations on Overrides
**Comment ID:** 2687205136
**File:** kotlin/open-questions.md:162
**Status:** DECIDED

> Note, in order to support this in some newer SDKs and not hit diamond problems or other inheritance confusion for when they _do_ want to have interfaces/abstracts, we _require_ every overridden method to have the same matching annotation/attribute/decorator. This prevents ambiguity, is easy to understand, and clarifies author intent clearly to reader without relying on inheritance (at the small cost of having to write duplicate annotations on overrides).

**Decision:** Keep current Java SDK behavior (annotation only on interface, not required on implementation). Requiring duplicate annotations would break backward compatibility with existing Java activities/workflows and feel unnatural to Java SDK users.

**Response:** While this approach makes sense for newer SDKs starting fresh, requiring duplicate annotations would break backward compatibility with existing Java activities/workflows and feel unnatural to Java SDK users. Since Kotlin SDK builds on Java SDK, we'll maintain the current convention where annotations on the interface are sufficient.

---

## Q3: Type-Safe Args - 0-1 Arguments Pattern
**Comment ID:** 2687220447
**File:** kotlin/open-questions.md:216
**Status:** DECIDED

> Or "0-1 Argument(s)", meaning any > 1 argument, which Temporal discourages, can fall back to untyped. This is what we do in some newer SDKs.

**Our Follow-up:** Why do you prefer the type-unsafe fallback for >1 args instead of the KArgs approach which maintains type safety? Is API simplicity the main driver, or are there other considerations?

**cretz Response (2690497106):**
> API simplicity (and overload count) was my main driver in preferring just falling back to untyped, but in some SDKs (namely Python), we actually do support arbitrary multi-param typed as a different overload. Would be fine if we did that here too. And really, with how .NET is lambda expressions, it supports multi-param typed as well. So overall, yeah, ok w/ a typed multi-param, and having 0 or 1 be even simpler forms of that.

**Decision:** Use KArgs approach (Option C) - type-safe for all arities with `kargs()` wrapper for 2+ arguments. 0-1 args have simpler direct forms.

**Response:** Thanks for confirming. We'll go with the KArgs approach (Option C) - provides full type safety for all arities while keeping 0-1 argument cases simple. The `kargs()` wrapper for 2+ args is a small price for compile-time type checking.

---

## Q4: Data Classes - Binary Breaking Not Considered Breaking
**Comment ID:** 2687231550
**File:** kotlin/open-questions.md:506
**Status:** DEFERRED - Need to think

> Hrmm, not sure we have ever considered binary breaking changes to be breaking changes from our POV (i.e. we expect you to compile against the same JAR you'll run with). Having said that, definitely not against better options patterns. But I don't think we want to discourage e.g. users from using `data` classes for their need-backwards-compatibility models.

**Decision:** Deferred

**Response:**

---

## Q5: Pure Kotlin Worker Options
**Comment ID:** 2687245857
**File:** kotlin/activities/implementation.md:68
**In Reply To:** 2682769025
**Status:** DECIDED

> I saw later there is a concept of a "plugin" that you register with a worker if you're using Java interop. Note, for a pure Kotlin experience, we don't have to be subject to Java worker approaches even if it wraps a Java worker. For instance, activities, workflows, Nexus services, etc can be worker options. But I understand not wanting to deviate too far from Java.

**Decision:** Follow Python/.NET pattern - pass workflows/activities at worker construction time via options rather than separate registration methods.

**Response:** Agreed. Will follow the Python/.NET pattern where workflows and activities are passed at worker construction time via options. This aligns with newer SDKs and provides immutable, all-in-one-place configuration.

---

## Q6: Heartbeat Infallible + Coroutine Cancellation
**Comment ID:** 2687258492
**File:** kotlin/activities/implementation.md:1
**In Reply To:** 2682800514
**Status:** DECIDED

> Not understanding "push" cancellation, but yeah so long as I can have heartbeat infallible and cancellation represented as traditional Kotlin coroutine cancellation, I think that is ideal. Arguably both of those could be the default, but I understand if it is confusing to have `suspend fun` do something completely different than non-suspend `fun` (this is a struggle we run into w/ Python where cancellation is represented quite differently w/ `async def` vs just `def`, but not this differently, heartbeat remained infallible on both).

**Decision:**
- Heartbeat infallible (never throws)
- Suspend activities: Standard coroutine cancellation (CancellationException at suspension points)
- Non-suspend activities: `CompletableFuture<CancellationDetails>` via `KActivity.cancellationFuture()` - supports polling (isDone), blocking (get), or callbacks (thenAccept)

**Response:** Agreed on heartbeat infallible. For cancellation:
- Suspend activities: Standard Kotlin coroutine cancellation
- Non-suspend activities: `KActivity.cancellationFuture()` returns `CompletableFuture<CancellationDetails>` which supports polling (`isDone`), blocking (`get`), or callback notification (`thenAccept`) - similar flexibility to Python's approach.

---

## Q7: Inconsistent Annotation Usage
**Comment ID:** 2687264865
**File:** kotlin/activities/local-activities.md:10
**In Reply To:** 2682894879
**Status:** DECIDED

> Makes sense, was just a bit strange to see it present inconsistently sometimes even w/out name customization in this proposal

**Decision:** Only show annotations in examples when customizing name (minimal approach). Will clean up docs for consistency.

**Response:** Good catch. Will clean up the docs to be consistent - only showing annotations like `@ActivityMethod` when customizing the name.

---

## Q8: Workflow-Specific Alternatives for Sleep
**Comment ID:** 2687272025
**File:** kotlin/api-parity.md:11
**In Reply To:** 2682956017
**Status:** DECIDED

> Using existing async utilities makes sense, but still may need some workflow-specific alternatives for advanced users, such as being able to provide a timer summary for `sleep`.

**Decision:** Provide both overloads:
- `KWorkflow.delay(duration)` - simple alternative to stdlib `delay()`
- `KWorkflow.delay(duration, summary)` - for timer summaries

**Response:** Agreed. Will provide `KWorkflow.delay(duration)` as a simple alternative to stdlib `delay()`, plus `KWorkflow.delay(duration, summary)` for advanced users who need timer summaries.

---

## Q9: KotlinPlugin Naming Confusion
**Comment ID:** 2687294728
**File:** kotlin/worker/setup.md:97
**In Reply To:** 2683181166
**Status:** DECIDED

> Makes sense to implement Kotlin support on Java workers as a plugin, though may get a bit confusing to call it KotlinPlugin, assuming there will _also_ be KPlugin for users to implement plugins in Kotlin (granted I can't think of a much better name, maybe KotlinToJavaWorkerPlugin or something)

**Decision:** Rename to `KotlinJavaWorkerPlugin` - clearly indicates it's for integrating Kotlin with Java workers.

**Response:** Good point about naming confusion. Renamed to `KotlinJavaWorkerPlugin` to make it clear this is for integrating Kotlin coroutine support with Java workers.

---

## Q10: coroutineScope vs supervisorScope
**Comment ID:** 2687311387
**File:** kotlin/workflows/cancellation.md:32
**In Reply To:** 2683186177
**Status:** RESOLVED

> Ah, I see this is the difference between `coroutineScope` and `supervisorScope`

**Decision:** No action needed - cretz's comment is an acknowledgment that he understood the distinction.

**Response:** (No response needed - resolved by acknowledgment)

---

## Q11: Heartbeat Infallible - Slot Eating Concern
**Comment ID:** 2690451590
**File:** kotlin/activities/implementation.md
**In Reply To:** 2682800514 (Q6)
**Status:** DECIDED

> Note, I was a bit on the fence here of whether heartbeat being infallible should be the default. There are pros/cons to the default of heartbeat still throwing. Granted this is one of those defaults people will probably never change via worker options, so maybe deviating from Java is accepted here. But we've found if we don't interrupt these activities by default and require people to opt-in to checking cancellation (i.e. the non-suspend ones), they will eat slots because people will forget.

**Concern:** Non-suspend activities may eat worker slots if developers forget to check cancellation.

**Decision:** Heartbeat throws `CancellationException` on cancellation for both suspend and non-suspend activities. This prevents slot eating and provides consistent behavior. Add TODO for `cancellationFuture()` which will be needed when cancellation can be delivered without heartbeat.

**Response:** Good point about slot eating. Revised approach: heartbeat throws `CancellationException` on cancellation for both suspend and non-suspend activities. This prevents slot eating and aligns with Java behavior. We'll document `cancellationFuture()` as a TODO for future use when cancellation can be delivered without requiring heartbeat calls.

---

## Q12: Unified Client Suggestion
**Comment ID:** 2690483803
**File:** kotlin/client/workflow-client.md
**Status:** DECIDED

> Forgot to mention this, but in newer SDKs, we found just having one big client that is a workflow client + schedule client (w/ features to make an async activity completion handle) is a bit cleaner from an options POV. This will also help when standalone activity client and Nexus operation client come about. No need to change though if we don't want, there is also value in matching what Java does (though you will duplicate a lot of these client options each time).

**Suggestion:** Consider unified `KClient` instead of separate `KWorkflowClient`, `KScheduleClient`, etc.

**Decision:** Use unified `KClient` matching Python/.NET style. Single client with workflow, schedule, async activity completion, and future Nexus support.

**Response:** Agreed. We'll use a unified `KClient` matching the Python/.NET pattern - single client covering workflows, schedules, async activity completion, and ready for future Nexus support. Cleaner options and less duplication.

---

## Previous Pending Questions

### R1-Q5: getVersion API
**Comment ID:** 2682977990
**Status:** DECIDED

**cretz Response (2690460783):**
> I have no strong preference, but as a past Kotlin developer, I always thought in terms of Java, so I think our default stance of "be like Java" is a good one for developer understanding. (I'm not even sure the newer patching approaches for Core-based SDKs can be done in Java user-land today without Java SDK updates)

**Decision:** Use `KWorkflow.version(changeId, minVersion, maxVersion)` method instead of getter-style. Better indicates side-effect nature.

**Response:** Since there's no strong preference, we'll use `KWorkflow.version()` as a method rather than getter-style. This better indicates the side-effecting nature of the call, which feels more idiomatic for Kotlin.

### R1-Q6: WithStartWorkflowOperation Design
**Comment ID:** 2683006111
**Status:** PENDING - Awaiting cretz clarification
