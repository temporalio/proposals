Temporal Core SDK Roadmap
===

*Hi!* This is not a proposal in the sense that we are already started on this here at Temporal, but it _is_ a proposal in the sense that the APIs and methodologies described here are by no means final, and very much subject to change as we discover the right way to implement things.

The Temporal Core SDK seeks to provide a faster means for developing temporal SDKs in new languages.

Unlike many clientside sdks/libraries, Temporal requires quite a bit of complex logic to be performed clientside, rather than being a simple wrapper over some network calls. As a result, supporting new languages is very expensive. The Core SDK will make the process substantially simpler by using Rust to create a shared underpinning for future SDK development.

## High level description

The below diagram depicts how future SDKs are split into two parts. The `sdk-core` common code, which is written in Rust, and a `sdk-lang` package specific to the language the user is writing their workflow/activity in. For example a user writing workflows in Rust would be pulling in (at least) two crates - `temporal-sdk-core` and `temporal-sdk-rust`.

![Arch Diagram](https://lucid.app/publicSegments/view/7872bb33-d2b9-4b90-8aa1-bac111136aa5/image.png)

The `core` communicates with the Temporal service in the same way that existing SDKs today do, via gRPC. It's responsible for polling for tasks, processing those tasks according to our state machine logic, and then driving the language-specific code and shuttling events to it and commands back.

The `sdk-lang` side communicates with `sdk-core` via either C bindings, IPC, or (later) bindings to a WASM interface. IPC will exist as a thin layer on top of the C bindings. Care should be taken here to avoid unnecessary copying and [de]serialization. Then `sdk-lang` is responsible for dispatching tasks to the appropriate user code (to whatever extent parts of this can be reasonably put in the core code, we desire that to make lang-specific SDKs as small as possible).

As a general note, the more we can push from `sdk-lang` into `sdk-core`, the easier our ecosystem is to maintain in the long run as we will have less semantically identical code.

### Core SDK Responsibilities

- Communication with Temporal service using a generated gRPC client, which is wrapped with somewhat more ergonomic traits.
- Provide interface for language-specific SDK to drive event loop and handle returned commands. The lang sdk will periodically call/poll the core SDK to receive new `Task`s, which are either represent workflows being started or awoken (`WFActivation`) or activities to execute (`ActivityTask`). It will then call it's workflow/activity functions with the provided information as appropriate, and will then push completed tasks back into the core SDK.
- Advance state machines and report back to the temporal server as appropriate when handling events and commands

### Language Specific SDK Responsibilities

- Periodically poll Core SDK for tasks
- Call workflow and activity functions as appropriate, using information in events it received from Core SDK
- Return results of workflows/activities to Core SDK
- Manage concurrency using language appropriate primitives. For example, it is up to the language side to decide how frequently to poll, and whether or not to execute worklows and activities in separate threads or coroutines, etc.

### Example Sequence Diagrams

Here we consider what the sequence of API calls would look like for a simple workflow executing a happy path. The hello-world workflow & activity in imaginary Rust (don't pay too much attention to the specifics, just an example) is below. It is meant to be like our most basic hello world samples.

```rust
#[workflow]
async fn hello_world_workflow(name: &str) -> Result<String, Error> {
    info!("Hello world workflow started! Name: {}", name);
    // Very much TBD how this would actually work in rust sdk. Many options here.
    activity!(hello_activity(name), timeout: 2s).await
}

#[activity]
async fn hello_activity(name: &str) -> String {
    format!("Hello {}!", name)
}
```

[![](https://mermaid.ink/img/eyJjb2RlIjoic2VxdWVuY2VEaWFncmFtXG4gICAgcGFydGljaXBhbnQgUyBhcyBUZW1wb3JhbCBTZXJ2aWNlXG4gICAgcGFydGljaXBhbnQgQyBhcyBDb3JlIFNES1xuICAgIHBhcnRpY2lwYW50IEwgYXMgTGFuZyBTREtcblxuICAgIEwgLT4-IEM6IEluaXRpYWxpemUgd29ya2VyXG4gICAgTCAtPj4gQzogU3RhcnQgd29yZmtsb3dcbiAgICBDIC0-PiBTOiBncnBjOiBTdGFydFdvcmtmbG93RXhlY3V0aW9uXG5cbiAgICBsb29wIHdvcmtmbG93IHRhc2sgcHJvY2Vzc2luZ1xuICAgIEMgLT4-IFM6IGdycGM6IFBvbGxXb3JrZmxvd1Rhc2tRdWV1ZVxuICAgIFMgLS0-PiBDOiBUYXNrcyAmIGhpc3RvcnkgICBcbiAgICBDIC0-PiBDOiBBcHBseSBoaXN0b3J5IHRvIHN0YXRlIG1hY2hpbmVzXG4gICAgXG4gICAgbG9vcCBldmVudCBsb29wXG4gICAgTCAtPj4gQzogUG9sbCBmb3Igc2RrIGV2ZW50c1xuICAgIEwgLT4-IEw6IFJ1biB3b3JrZmxvdywgcHJvZHVjZXMgY29tbWFuZHNcbiAgICBMIC0tPj4gQzogV29ya2Zsb3cgaXRlcmF0aW9uIGRvbmUgdy8gY29tbWFuZHNcbiAgICBDIC0-PiBDOiBBZHZhbmNlIHN0YXRlIG1hY2hpbmVzXG4gICAgZW5kXG5cbiAgICBDIC0-PiBTOiBncnBjOiBSZXNwb25kV29ya2Zsb3dUYXNrQ29tcGxldGVkXG4gICAgZW5kXG4iLCJtZXJtYWlkIjp7InRoZW1lIjoiZGVmYXVsdCJ9LCJ1cGRhdGVFZGl0b3IiOmZhbHNlfQ)](https://mermaid-js.github.io/mermaid-live-editor/#/edit/eyJjb2RlIjoic2VxdWVuY2VEaWFncmFtXG4gICAgcGFydGljaXBhbnQgUyBhcyBUZW1wb3JhbCBTZXJ2aWNlXG4gICAgcGFydGljaXBhbnQgQyBhcyBDb3JlIFNES1xuICAgIHBhcnRpY2lwYW50IEwgYXMgTGFuZyBTREtcblxuICAgIEwgLT4-IEM6IEluaXRpYWxpemUgd29ya2VyXG4gICAgTCAtPj4gQzogU3RhcnQgd29yZmtsb3dcbiAgICBDIC0-PiBTOiBncnBjOiBTdGFydFdvcmtmbG93RXhlY3V0aW9uXG5cbiAgICBsb29wIHdvcmtmbG93IHRhc2sgcHJvY2Vzc2luZ1xuICAgIEMgLT4-IFM6IGdycGM6IFBvbGxXb3JrZmxvd1Rhc2tRdWV1ZVxuICAgIFMgLS0-PiBDOiBUYXNrcyAmIGhpc3RvcnkgICBcbiAgICBDIC0-PiBDOiBBcHBseSBoaXN0b3J5IHRvIHN0YXRlIG1hY2hpbmVzXG4gICAgXG4gICAgbG9vcCBldmVudCBsb29wXG4gICAgTCAtPj4gQzogUG9sbCBmb3Igc2RrIGV2ZW50c1xuICAgIEwgLT4-IEw6IFJ1biB3b3JrZmxvdywgcHJvZHVjZXMgY29tbWFuZHNcbiAgICBMIC0tPj4gQzogV29ya2Zsb3cgaXRlcmF0aW9uIGRvbmUgdy8gY29tbWFuZHNcbiAgICBDIC0-PiBDOiBBZHZhbmNlIHN0YXRlIG1hY2hpbmVzXG4gICAgZW5kXG5cbiAgICBDIC0-PiBTOiBncnBjOiBSZXNwb25kV29ya2Zsb3dUYXNrQ29tcGxldGVkXG4gICAgZW5kXG4iLCJtZXJtYWlkIjp7InRoZW1lIjoiZGVmYXVsdCJ9LCJ1cGRhdGVFZGl0b3IiOmZhbHNlfQ)

## API Definition

We define the interface between the core and lang SDKs in terms of gRPC service definitions. The actual implementations of this "service" are not generated by gRPC generators, but the messages themselves are, and make it easier to hit the ground running in new languages.

See the latest API definition [here](https://github.com/temporalio/sdk-core/blob/master/protos/local/core_interface.proto)
