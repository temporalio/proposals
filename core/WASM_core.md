# Summary

This proposal intends to outline the shape of the interfaces and implementation work necessary
to make Core WASM-compilable.

# Motivation

A few problems a WASM Core Can solve, in no particular order:

* Allow Go and Java to be ported to run on top of Core. *Potentially* without the downsides of CGo
  and JNI. More on that later.
* No longer any need to ship compiled Core binaries of various architectures with our existing SDKs.
  This is both a nice plus for us, in terms of reducing CI complexity, but also a substantial size
  reduction in our packages.
* Workers in the browser
* Hosted workers (also possible without, but with, there are some nice benefits)
* A simpler way to manage callbacks into the lang layer, enabling things like user-defined metrics
  exporters, lower-level interceptors, etc. This is certainly doable without WASM, but is probably
  a bit easier (and, necessary) with it.
* Auto-updates to core logic. This isn't detailed in this doc, but is a potentially very compelling
  feature. Imagine a worker that can update core logic without needing to be restarted.
* Allow the use of lang-native gRPC clients (though core can still provide things like retry and 
  backoff logic, etc.)


# Detailed design

The first and largest chunk of work involved in implementation is more or less pure grunt work. 
I need to switch Core to compiling with the wasm32-unknown-unknown target, and then fix all the
compiler errors.

There are a few predictable problems we'll definitely have to deal with:

The largest hiccup is the use of network (gRPC) calls. There is more than one way we could skin this
cat. Luckily (intentionally), all of this is contained to the `temporal-client` crate.

The next major source of side effects come from the tracing and metrics exporting facilities for
OTel and Prometheus.

Additionally, there is the code dealing with downloading and starting the CLI / Java test server.

Finally, there may be some issues with other things that in native world use syscalls like atomics,
locks, random number gen, etc. Luckily my experience so far is that those pretty much all just work
without any, or fairly minor, changes.

Ultimately we have two strategies available to us. We can create interfaces for Core to call back
into lang to perform all these functions, or we can attempt to leverage WASI for this functionality.
WASI is quite immature, but *in theory* it can support these use cases.

## WASM Runtime

Regardless of the strategy, we need to choose a WASM runtime which each Lang SDK will use, so I'll
address that first. The two major players in the space are
[Wasmer](https://github.com/wasmerio/wasmer) and
[Wasmtime](https://github.com/bytecodealliance/wasmtime). It's also not impossible that we might
use one library from Rust for defining things like the host imported functions, but use different
libraries for the runtime in the host langs.

### Wasmer
Wasmer's biggest pro is it's language support. Every language we currently have an SDK for (and
more beyond that) has a Wasmer SDK for embedding and running WASM in that language. It's docs are
decent, but not great.

It has an MIT license.

It's controlled by a startup (but hey, so are we) and has somewhat less active open-source
development than Wasmtime.

### Wasmtime
Wasmtime supports all our languages _except_ Java, which is unfortunate, though it looks like
there's an unofficial repo. It's also not immediately clear how usable JS/Node support is, 
particularly when it comes to using WASI. It does have quite excellent docs, and built-in support
for calling async functions from WASM, which is pretty awesome.

It has an Apache 2.0 license.

It's owned and maintained by the bytecode alliance, which also owns the WASM/WASI spec. It's backed
by Mozilla.

### Oh no CGo (and JNI)
There's a big downside to both Wasmer and Wasmtime. Both of their Go implementations use CGo, and
Wasmer's Java implementation uses JNI. This blows one of the bigger pluses out of the water.
Luckily, [wazero](https://github.com/tetratelabs/wazero) exists, which we can use to get a pure Go
environment. It supports WASI as well, but seemingly [not what we would need for network
calls](https://wazero.io/specs/).

I can't seem to find anything reasonable for Java. Maybe if we're blessed, such a thing
will exist by the time we get around to porting Java, but that's a huge if.

## Implementation Strategy

### How much, if any WASI to use?

The more we can lean on WASI, the less we have to expand the Core<-->Lang interface. That's a good
thing in terms of both immediate work and long-term maintenance. There are some problems though:

* Assuming we need to use `wazero` for non-CGo support, it doesn't appear to be able to handle
  network calls. We'll test this, though. Even if we intend to use native gRPC clients, being able
  to make network calls in Core is still pretty desirable for things like auto-updates, test server
  downloads, etc.
* Calling back into lang gives us opportunities for more user customization, which can be nice.
  Especially when it comes to the metrics and tracing stuff. gRPC interceptors are also a potential
  plus.

My inclination for now is to at least *investigate* how much we can get out of WASI. Particularly
with respect to running from Go.

Unfortunately, my assumption is that we will need to callback into Lang for all the usecases
mentioned at the top of the doc. The only sys interface things it appears we'll be able to reliably
use are clocks (which is good, that does come up) and possibly file I/O, which currently does not
happen in Core (and probably never should) except for in the test server usecase.


### Core API changes
Operating under the assumption that all the major syscalls will need to be handled through callbacks
into lang. In WASM, calling functions in the host is supported via `import`ing those host functions.
Ultimately these functions may be bundled together into a trait or something on the Core side, but
this doc will focus on the individual functions.

Here are the functions I think we'll need to add to the Core<-->Lang interface, beyond the existing
ones that lang already calls. They're defined as they would appear in Rust, after being imported.
This is definitely a rough draft, as it will be influenced by runtime selection and whatever
practical problems we run into along the way.

```rust
// In reality, everything in these functions is going to need to be serialized and shuttled back
// and forth as bytes. That makes for uninteresting signatures, though, so instead I show what
// those signatures would look like if we were using deserialized types directly. The exact details
// of how that serialization happens are intentionally not included here.
//
// WASM has an `ExternRef` type which is a pointer to a host-owned opaque object.

// For all the types which wrap an `ExternRef`, the implementations on those types which take
// `self` will be implemented as calls to a host-defined function which looks like:
fn func_name(receiver: ExternRef, arg: ArgType) -> ResultType;
// There may be a more clever way to manage some of this by using `Table` and `Func` types along with
// `ExternRef` but I need to play around more to determine that.

// -------------- Grpc -----------------

// Would be passed into core along with client config options when creating instantiating a client.
// Core can then augment the client with retry behavior, and the client can then be used when
// instantiating Core workers.
struct GrpcClientRef {
    /// Points to the host's gRPC client
    host_ref: ExternRef,
}

struct GrpcRequest {
    uri: String,
    body: Vec<u8>,
    metadata: Metadata,
}

struct GrpcResponse {
    body: Vec<u8>,
    metadata: Metadata,
}

struct GrpcStatus {
    // Serializable equivalent of https://docs.rs/tonic/latest/tonic/struct.Status.html
}

struct Metadata {
    data: HashMap<String, Vec<u8>>,
}

struct GrpcClientConfig {
    // Details elided. See `ClientConfig` in core. Would *not* include `RetryConfig`, as that will
    // continue to be handled in core.
}

impl GrpcClientRef {
    /// Make a unary grpc call
    async fn grpc_unary(
        &self,
        req: GrpcRequest,
    ) -> Result<GrpcResponse, GrpcStatus> {}

    // Will be called by a `Drop` impl, but must exist and be exported by the WASM host.
    fn close(self) {}
}

// -------------- Metrics --------------

// This is mostly a simplified version of the OTel API, which, ideally we can use to implement on the
// lang side. https://opentelemetry.io/docs/reference/specification/metrics/
// Given this is probably our easiest common denominator, it makes sense to stick close to it.
// At the moment, all metrics are sync rather than async (callback based).

struct MeterProviderRef {
    host_ref: ExternRef,
}

// I anticipate that each worker will live in its own module instance, so there's no need to pass
// some kind of worker reference here. If that doesn't work, we'll need one.
fn get_meter_provider() -> MeterProviderRef {}

impl MeterProviderRef {
    fn new_counter(&self, name: String) -> CounterRef {}
    // We deviate from OTel here by providing a histogram's buckets at instrument instantiation.
    // Adhering to the OTel spec would seem to overcomplicate things substantially here. See
    // https://opentelemetry.io/docs/reference/specification/metrics/sdk/#aggregation
    fn new_histogram(&self, name: String, buckets: Buckets) -> HistogramRef {}
    fn new_gauge(&self, name: String) -> GaugeRef {}
}


struct MetricsAttributesRef {
    host_ref: ExternRef,
}

struct MetricsAttributesOptions {
    attributes: Vec<MetricKeyValue>,
}

struct MetricKeyValue {
    key: String,
    value: MetricValue,
}

enum MetricValue {
    String(String),
    Int(i64),
    Float(f64),
    Bool(bool),
    // Maybe array type, but I don't use that anywhere currently.
}

impl MetricsAttributesRef {
    fn new(options: MetricsAttributesOptions) -> Self {}
    fn with_kvs(&self, kvs: Vec<MetricKeyValue>) -> MetricsAttributesRef {}
}

struct CounterRef {
    host_ref: ExternRef,
}

struct HistogramRef {
    host_ref: ExternRef,
}

struct GaugeRef {
    host_ref: ExternRef,
}

impl CounterRef {
    fn add(&self, value: u64, attributes: MetricsAttributesRef) {}
}

impl HistogramRef {
    // When referring to durations, this value is in millis
    fn record(&self, value: u64, attributes: MetricsAttributesRef) {}
}

impl GaugeRef {
    fn record(&self, value: u64, attributes: MetricsAttributesRef) {}
}

struct Buckets {
    buckets: Vec<f64>,
}

// -------------- Logging --------------

// In Core, all logging is represented as events on trace spans. However, adding a full tracing
// API would be insanely huge, and way, way too much work on both sides. Additionally, OTel simply
// does not seem designed for exporting and importing traces in the same process (I can't find any
// in-memory importers). Even if that worked, just defining the Span struct is significant. All
// that in mind, I propose only adding a logging interface here.

// This is copied straight out of Core today
pub struct CoreLog {
    /// The module within core this message originated from
    pub target: String,
    /// Log message
    pub message: String,
    /// Time log was generated
    pub timestamp: SystemTime,
    /// Message level
    pub level: Level,
    /// Arbitrary k/v pairs (span k/vs are collapsed with event k/vs here).
    pub fields: HashMap<String, serde_json::Value>,
    /// A list of the outermost to the innermost span names
    pub span_contexts: Vec<String>,
}

enum Level {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

// The same assumption about a worker-per-module-instance applies here as with metrics.
fn log(log: CoreLog) {}
```

#### An aside on serialization

We are presented with an opportunity here to get rid of the ser/de overhead currently present
as a result of using protos for everything. Since we are introducing additional overhead b/c of
WASM, we could maybe introduce some savings here. My **completely unsubstantiated** guess is that if
we stopped the unneeded ser/de we might actually get slightly *faster* under WASM which would be
amusing.

The options here are Cap'n'Proto or Flatbuffers. Both appear to have support for all the languages
we care about, except for Flatbuffers not having a Ruby implementation.

Flatbuffer's design is more oriented towards what we're doing, whereas Cap'n'Proto is more concerned
with sending things over the wire, but is perhaps a bit more ergonomic.

In either case, the primary pain point would be figuring out how to deal with the annoyance of
having lifetime annotations in the Rust code. Cap'n'Proto has built-in support for creating owned
versions of the structs which makes that pretty easy, but at that point it's unclear if whatever
speedup we'd get is worth it compared to Protobuf.

Ultimately, it may makes sense to defer this work until we have measured performance and decided
it's worth it. Of course, the rub there is adding this support later is a pretty monster change.

What I do think we should take some time to do is make a toy application with the runtime we land on
(say, with Go as the host), and then just shuffle back and forth some Workflow/Activity tasks using
proto and using Cap'n/Flatbuffer and measure performance. Unless there's a striking difference, we
can stick with proto.

# Drawbacks

* It's a bit difficult to predict exactly what the lift is here, but it's clearly not a small amount
  of work. Not only is there everything that needs to be done in Core, but all our existing Core
  based SDKs will (eventually) need their bridge layer re-written in a nontrivial way - at least any
  of them that wish to use WASM Core.
* Less performant. Core doesn't really do all that much CPU work, though, so this is
  unlikely to be a meaningful concern. If it is, we could possibly still offer fully native
  options, but the only place this feels sustainable is in conjunction with a Rust SDK.
* Increases the surface area of the API between Core and Lang. All side-effecty (namely, GRPC) calls
  now need to go through Lang - this could get simpler over time as WASI matures, though it's still
  pretty limited even to begin with. To the extent that we can/want to use WASI for anything
  initially, that helps reduce this.

# Alternatives

Don't do this. Lol. Use JNI/CGo for those SDKs when we port them. Give up on the idea of a browser
based worker.


# Unresolved questions

Re-summarizing:
* What runtime(s)?
* Serialization format change?
* A variety of API specifics