# Worker Autotuning Proposal

Users often struggle with the appropriate configuration of workers. There are many options to fiddle with, nearly none
of which ought to be something users should be required to think about. This proposal aims to reduce the cognitive load
of configuring workers by automatically setting appropriate values for various worker options at runtime without
(or with much simplified) user intervention.

## Areas of configuration
There are a few different configuration "areas" that we can autotune:

### Concurrent Pollers
Right now, the number of pollers used for polling workflow and activity tasks is dynamic (in varying ways in different
SDKs), but is limited to a maximum defined by the user. In Core: `max_concurrent_wft_polls` and
`max_concurrent_at_polls`. This limit need not be defined by the user, except possibly as hard high ceiling. This work
is largely already designed and implemented in Go: [see the branch
here](https://github.com/temporalio/sdk-go/compare/master...Quinn-With-Two-Ns:sdk-go:poller-autottune-v0.2). Hence this
doc will not focus on this area in detail.

It is important to note that there is a distinction between the active number of poller *routines* and the active number
of *open actual RPC calls*. The number of routines may be scaled independently of the number of open RPC calls at any
time. The former may have a floor, whereas the latter must always be able to go to 0. Users are unlikely to care about
the number of routines as they are relatively cheap. They *do*, however, care about how quickly we will change the
number of active RPCs. The floor on the number of routines effectively determines how quickly we are willing to consume
available slots and thus make actual RPC calls. IE: If the floor on the number of routines is 10, and 10 slots open up
at the same time, we will immediately make 10 RPC calls.


### Slot tuning & Cache Size

Workers have a configurable number of slots for task types. In Core: `max_outstanding_workflow_tasks`,
`max_outstanding_activities`, and `max_outstanding_local_activities`. These are set by the user and can't change at
runtime. Autotuning of these values would seek to allow them to change at runtime according to available resources on
the worker. It is not feasible to choose *optimal* values for these at runtime, because we cannot know a-priori about
how much resources any given workflow or activity task will consume - only the user can (maybe) know this. However, we
can provide a reasonable default autotuning implementation while also allowing users to provide their own.

Additionally, there is a maximum cache size for cached workflows. In Core: `max_cached_workflows`. This is also set by
users at the moment, and autotuning it is subject to the same lack of knowledge we have as with slot tuning.

## Constraints

There are some invariants that must be maintained:

* The current number of active polls for a task type must be <= the number of free slots for that task type at all
  times. Otherwise, we can end up receiving a task that won't have anywhere to go until a slot frees. For example,
  in Core this is expressed by using a permit reservation system.
* Max outstanding workflow tasks must be <= max cached workflows.

## Proposed interface for slot management

To reiterate, we can't possibly know as well as the user what resources a given workflow or activity task will consume.
Thus, we need to provide an interface by which users can tell us whether they think it's reasonable to allow the use
of an additional slot.

The interface definition here is provided in Rust, but need not be copied exactly by other languages. Since users
are implementing it, we want something idiomatic for them. Languages without destructors might eschew the permit struct
since it may not provide much value there. So, don't get too fixated on the specifics - the important thing is the
semantics of being able to ask for a slot, mark when it's in use, and free it when we're done.

There is some mild generic magic going on to represent different types of slots and constrain that only permits of the
appropriate type are provided or consumed, and only with the corresponding info type. These guarantees can't be
compile-time enforced across the language boundary, but are at least useful after runtime validation.

```rust
trait SlotSupplier {
  type SlotKind: TaskSlotKind;

  /// Blocks until a slot is available, then returns a permit for that slot.
  /// May also return an error if the backing user implementation encounters an error.
  async fn reserve_slot(&self) -> Result<SlotPermit<SlotKind>, anyhow::Error>;
  /// Tries to immediately reserve a slot, returning None if no slot is available.
  /// May also return an error if the backing user implementation encounters an error.
  fn try_reserve_slot(&self) -> Result<Option<SlotPermit<SlotKind>>, anyhow::Error>;


  /// Marks a permit as actually now being used. This is separate from reserving one because the pollers need to
  /// reserve a slot before they have actually obtained work from server. Once that task is obtained (and validated)
  /// then the slot can actually be used to work on the task.
  /// 
  /// Users' implementation of this can choose to emit metrics, or otherwise leverage the information provided by the
  /// `info` parameter to be better able to make future decisions about whether a slot should be handed out.
  fn mark_slot_used(&self, permit: &SlotPermit<SlotKind>, info: &Self::SlotKind::Info);

  /// Frees a slot by reclaiming the provided permit.
  fn release_permit(&self, permit: SlotPermit<SlotKind>, info: &Self::SlotKind::Info);
}

// These functions would be provided to the user as top level statics they can access to get information about how
// all outstanding slots are currently being used. Ostensibly they could've stored this in their own implementation
// too, but this is to make it convenient for them to answer questions like "How many slots are being used by 
// activities of type X right now?". 
//
// These could potentially be provided as parameters to the trait methods - but at least in the case of the 
// async/blocking reserve, the information may change over time, so it may be best to have these be explicit calls.
pub fn used_workflow_slots_info() -> WorkflowSlotsInfo { /* ... */ }
pub fn used_activity_slots_info() -> ActivitySlotsInfo { /* ... */ }
pub fn used_local_activity_slots_info() -> LocalActivitySlotsInfo { /* ... */ }

struct SlotPermit<T: SlotKind> {
  supplier: Arc<dyn SlotSupplier>,
  _kind: PhantomData<T>,
  // ... other implementation details of a permit
}

impl Drop for SlotPermit {
  fn drop(&mut self) {
    // When the permit is dropped, the slot is freed.
    // languages without destructors will need to call a method to free the slot.
    // (for the eagle eyed, yes, technically this won't compile since self can't be consumed here
    // but it's a simplification for the sake of the example and doable with some mem::replace)
    self.supplier.release_permit(self);
  }
}

struct WorkflowSlotsInfo {
  used_slots: Vec<WorkflowSlotInfo>,
  /// Current size of the workflow cache.
  num_cached_workflows: usize,
  /// The limit on the size of the cache, if any. This is important for users to know as discussed below in the section
  /// on workflow cache management.
  max_cache_size: Option<usize>,
}
struct ActivitySlotsInfo {
  used_slots: Vec<ActivitySlotInfo>,
}
struct LocalActivitySlotsInfo {
  used_slots: Vec<LocalActivitySlotInfo>,
}

struct WorkflowSlotInfo {
  workflow_type: String,
  // task queue, worker id, etc...
}
struct ActivitySlotInfo {
  activity_type: String,
  // etc...
}
struct LocalActivitySlotInfo {
  activity_type: String,
  // etc...
}

struct WorkflowSlotKind {}
struct ActivitySlotKind {}
struct LocalActivitySlotKind {}
trait SlotKind {
  type Info;
}
impl SlotKind for WorkflowSlotKind {
  type Info = WorkflowSlotInfo;
}
impl SlotKind for ActivitySlotKind {
  type Info = ActivitySlotInfo;
}
impl SlotKind for LocalActivitySlotKind {
  type Info = LocalActivitySlotInfo;
}

trait WorkflowTaskSlotSupplier: SlotSupplier<SlotKind=WorkflowSlotKind> {}
trait ActivityTaskSlotSupplier: SlotSupplier<SlotKind=ActivitySlotKind> {}
trait LocalActivityTaskSlotSupplier: SlotSupplier<SlotKind=LocalActivitySlotKind> {}

/// Users might want to be able to pause the handing-out of slots as an effective way of pausing their workers.
/// We can provide an implementation for this that wraps their implementation, or one of the defaults we provide.
struct PauseableSlotSupplier<T: SlotKind> {
  inner: Arc<dyn SlotSupplier<SlotKind=T>>,
  paused: AtomicBool,
  // ... details
}
impl<T: SlotKind> PauseableSlotSupplier<T> {
  pub fn new(supplier: impl SlotSupplier<SlotKind=T>) -> Self { /* ... */ }
  pub fn pause(&self) { /* ... */ }
  pub fn resume(&self) { /* ... */ }
}
impl<T: SlotKind> SlotSupplier for PauseableSlotSupplier<T> {
  // ... implementation which checks the paused flag before handing out a slot
}
```

## Workflow cache management

The workflow cache is maintained independently of the number of slots in use. There could be 0 slots in use and 100
workflows cached, and that's a totally normal scenario. We might also choose to make this user-configurable, though we
certainly don't need to have that right out of the gate.

Keeping our fixed-size implementation to start is fine, because we won't ask the user's slot provider for a slot unless
there is room in the cache (either additional capacity, or an idle cached workflow that can be evicted). This avoids
a potential problem where we ask for a slot, they provide one, but there's nothing we can evict at the moment.

If and when we do introduce user-configurable caching, it's likely that they would want the same thing to be responsible
for both slots and cache management, since the two are so closely related.

A possible future:

```rust
trait WorkflowCacheSizer {
  /// Return true if it is acceptable to cache a new workflow
  fn can_allow_additional_workflow(&self, slots_info: &WorkflowSlotsInfo) -> bool;
  /// Called when a workflow is evicted from the cache
  fn evicted_workflow(&self, evicted: &WorkflowSlotInfo);
  /// If there is a fixed maximum number of cached workflows, return it.
  fn max_cached_workflows(&self) -> Option<usize>;
}

/// The user would be allowed to provide either just a slot supplier (using the standard fixed-size cache),
/// or one of these to handle both themselves.
/// 
/// I'm a bit at a loss for a good name
trait WorkflowSlotAndCacheManager: WorkflowTaskSlotSupplier + WorkflowCacheSizer {}
```


## Metrics

Users can add their own metrics behind their implementations now, which is great - but we can also provide one out 
of the box that can apply to all implementations. Namely `slots_in_use` by type. Right now we emit the inverse of this,
available slots - we can keep emitting that with a bundled implementation that can act like the old fixed-number based
implementation.

We can also of course keep emitting the current number of cached workflows.


## Where it hooks up and the language barrier

Staying in just Rust for a moment, the slot supplier implementations can be hooked up on a per-worker basis through
`WorkerConfig`, as expected. We would add:

```rust
pub struct WorkerConfig {
  // ... existing fields
  #[builder(default)]
  pub workflow_task_slot_and_cache: Option<Arc<dyn WorkflowSlotAndCacheManager>>,
  #[builder(default)]
  pub activity_task_slot_supplier: Option<Arc<dyn ActivityTaskSlotSupplier>>,
  #[builder(default)]
  pub local_activity_task_slot_supplier: Option<Arc<dyn LocalActivityTaskSlotSupplier>>,
}

impl WorkerConfig {
  /// Set the slot supplier for workflow tasks, using the default fixed-size workflow cache
  pub fn with_workflow_slot_supplier(&mut self, supplier: impl WorkflowTaskSlotSupplier) -> &mut Self { /* ... */ }
}
```

This is analogous to what we'd expect in the worker config for other languages.

The suppliers are kept inside of `Arc`s so that they can be shared across multiple workers, and used with the pauseable
supplier (which the user presumably wants to retain a reference to so they can call pause).


Of course, most users aren't going to be implementing this in Rust, they'll be doing it in their language, and then
we've got to translate that into calls across the language barrier. As such we need a slot provider implementation
that exists in each language's bridge, and calls callbacks into the user's implementation.

Something like:

```rust
pub struct RustToLangBridgeSlotSupplier {
  // ... store callbacks etc
}

impl<T: SlotKind> SlotSupplier<SlotKind=T> for RustToLangBridgeSlotSupplier {
  // ... call appropriate callbacks, convert data types, etc
}
```

## A neat example

For fun, here's a neat example of some of the complex stuff you could get up to with a custom slot supplier.

Say you have some activity workers who all interact with an external service. There are two types of activities that
interact with the service, one of which can have many instances run in parallel, and another that should prevent any
new work from being done until it's finished.

You can implement a slot supplier for these workers that coordinates their efforts! Pseudocode:

```rust
struct MyCoordinatingSlotSupplier {
  // Magic external lock service. Don't think too hard about races :)
  lock_svc_client: LockServiceClient,
  per_worker_allowed: Sempahore,
}

impl ActivityTaskSlotSupplier for MyCoordinatingSlotSupplier {
  async fn reserve_slot(&self) -> Result<SlotPermit<SlotKind>, anyhow::Error> {
    self.lock_svc_client.wait_for_lock_not_held_or_being_acquired().await;
    self.per_worker_allowed.acquire().await;
    Ok(SlotPermit::new(self))
  }
  fn try_reserve_slot(&self) -> Result<Option<SlotPermit<SlotKind>>, anyhow::Error> { /* ... */ }
  fn mark_slot_used(&self, permit: &SlotPermit<SlotKind>, info: &Self::SlotKind::Info) {
    if info.activity_type == "there_can_only_be_one" {
      self.lock_svc_client.eventually_acquire_lock();
    }
  }
  fn release_permit(&self, permit: SlotPermit<SlotKind>, info: &Self::SlotKind::Info) {
    if info.activity_type == "there_can_only_be_one" {
      self.lock_svc_client.release_lock();
    }
    self.per_worker_allowed.release();
  }
}
```


## Drawbacks

* Gives users a bigger footgun. This is mitigated by the fact that most users are probably just going to use one of our
  default implementations. Inevitably though, someone will implement a custom slot supplier with buggy logic and contact
  support about it.
* More complexity in the core/lang bridge, nothing too bad though.

## Alternatives

We could not expose this as a user-implementable interface at all, and only offer a handful of default implementations.
The benefits of user customization are substantial though, and seem to outweigh the mild complexity increase. Users will
always know more about their workload than we can.

Specifically concerning `mark_slot_used`, we could potentially allow an error to be returned here, causing the SDK to
immediately fail the task instead of working on it. This is maybe a nice way to let users reject tasks they don't want
this worker to handle... however there are some obvious potential thrashing issues there (ex: only one worker rejecting
the same task over and over). Allowing this seems like it'd mostly be a way for users to bandaid over something that was
really a mistake in the way their task queues are architected.

## Adoption & Teaching

We should roll out the feature by introducing the interface & reimplementing the existing behavior behind that
interface. There will be no visible default behavior changes. Likely we'll include some other OOTB implementations like
a memory-based one that users can opt-in to.

We might, at some point, decide that the default implementation should change from the fixed-number-of-slots impl to
a more dynamic one, if we find that it substantially outperforms in most scenarios. If and when we do make that change,
we'll want to give users some advance warning, since although the change is not technically breaking, it could have 
knock-on effects in terms of the external load on the systems their workers are interacting with.

Docs & education will both need content about what the interface is for, what default implementations are provided &
what their limitations are, and how to implement a custom one.

## Future considerations

This proposal has focused specifically on worker autotuning and user customization thereof. However, it's worth
considering how this effort will fit in to future work we know we want to do, namely around autoscaling and on-demand
workers.

### Autoscaling

We know we want users to be easily able to spin up, and more importantly know _when_ to spin up, new workers. A good
chunk of this work is already known and has been talked about quite a bit: Having a more accurate task queue backlog
count, creating autoscalers for k8s or other platforms, etc. These autoscalers would more likely than not primarily
rely on these backlog counts, but it makes sense that they (as well as other tooling like alerting facilities, etc)
might want to gather information from workers as well.

For example, there might be a substantial backlog of tasks in the queue while workers are simultaneously not using all
the capacity they could be - this would indicate a problem with the autotuning implementation (or perhaps the need to
turn one on).

As such, we should consider how workers might best expose this information. The obvious answer is probably the best one:
metrics. With this new interface we give users a chance to provide their own metrics around in-worker scaling however
they like. Combined with machine-level metrics like overall cpu/mem usage, scaling tools should be able to get a good
picture of how each worker is behaving.

I do think it's important to state that we don't want to be in the business of generic machine-level health/usage
monitoring. There are bunches of tools that do this already, and any autoscalers we release ought to integrate with the
most common of those tools. Our responsibility it to provide Temporal-specific information needed to make scaling
decisions.