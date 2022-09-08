# Milestones

## MVP - Phase 0 (Namespace to Namespace)

**Usage scenarios**:
- Exposing Temporal application to a Temporal consumer (Nexus)

**Rationale:** Keeps requirements as minimal as possible and makes the primary focus unblocking X-Namespace calls.

**Requirements:**

* Existing Temporal users
* Only target scenarios where Temporal Namespace is calling to another Temporal Namespace. To be explicit, we will not initially support client-to-Temporal-ALO calls. 
* Minimum additional authentication and authorization requirements
* Relatively latency insensitive use cases
* Works in single and cross cluster scenarios

## Phase 1 (Supporting internal HTTP APIs)

**Usage scenarios**:
- Exposing Temporal application to a Temporal consumer (Nexus)
- Exposing Temporal application to a non-Temporal consumer (Nexus + ALO)

**Rationale:** Internal APIs will offer a low risk entrypoint into the problem space, giving us time and feedback needed to deliver a killer public facing solution.

**Requirements:**

```diff
- Only target scenarios where Temporal Namespace is calling to another Temporal Namespace

+ Support HTTP Nexus gateway
+ Target teams looking to expose Temporal functionality internally, both in Temporal to Temporal cases and non-Temporal to Temporal cases
```

* Existing Temporal users
* Minimum additional authentication and authorization requirements
* Relatively latency insensitive use cases
* Works in single and cross cluster scenarios

## Phase 2 (Supporting external APIs)

**Usage scenarios**:
- Exposing Temporal application to a Temporal consumer (Nexus)
- Exposing Temporal application to a non-Temporal consumer (Nexus + ALO)
- Exposing non-Temporal application with Temporal-esque calling semantics (ALO) // this is technically possible in P1 but will not be encouraged

**Rationale:** Assuming we have learned significant lessons from internal APIs during Phase 1, we are now ready to target services which are leveraged by external consumers and not just internal ones. This will bring in significantly higher security requirements as exposing something publicly is far more risky than exposing something internally.

**Requirements:**

```diff
- Existing Temporal users
- Minimum additional authentication and authorization requirements
- Target teams looking to expose Temporal functionality internally, both in Temporal to Temporal cases and non-Temporal to Temporal cases

+ Target teams looking to expose Temporal functionality internally and externally, both in Temporal to Temporal cases and non-Temporal to Temporal cases
+ Support GRPC Nexus gateway
```

* Support HTTP Nexus gateway
* Relatively latency insensitive use cases
* Works in single and cross cluster scenarios