**Problems:**

- [Long term solution for cross namespace calls](#long-term-solution-for-cross-namespace-calls)
- [Expose generic APIs natively from Temporal](#expose-generic-apis-natively-from-temporal)
- [Arbitrary length operations](#arbitrary-length-operations)

# Long term solution for cross namespace calls

**TL;DR;** *Cross Namespace (X-Namespace) calls are critical for the adoption of Temporal and today they provide a limited and confusing experience. We want to make X-Namespace calls straightforward and powerful.*

The most fundamental problem is that calling Temporal resources (Child Workflows) in an external Namespace (AKA cross-Namespace/X-Namespace) is an unintuitive and incomplete experience. We strongly believe that the ability for developers to compose applications across multiple Namespaces is key to the long term success of the technology.

In our current system, ChildWorkflows are the only means of creating resources in an external Namespace. Outside of how limiting this model is, the DX for it is also incredibly unintuitive. For example:

- Which Namespace does the event history show up in?
- Who runs the Workers?
- What are the consistency expectations?
- What about Searchable Attributes?

Even if none of these are confusing questions for you, the current solution leaks a ton of low level client details to the caller ie:

- Timeouts
- Task Queues
- Retries

Every day we see more and more companies holistically embracing Temporal. After a certain critical mass is reached within these companies, the need for X-Namespace functionality becomes a given. In addition to wanting a better version of the existing experience, there are often requests for fundamentally new capabilities such as running X-Namespace Activities. If you thought the DX for X-Namespace Child Workflows is complicated, Activities would make that look like 1st grade math.

As a cherry on top, today X-Namespace calls become even more complicated when calling a Namespace in a different cluster and they are completely broken in the Global Namespace scenario. Considering that our Cloud abstracts the concept of clusters and pushes the concept of “Namespace as a Service” this problem is a fundamental blocker for any practical X-Namespace Cloud usage.

# Expose application-specific APIs natively from Temporal

**TL;DR;** *Developers should be able to natively surface Temporal backends using standard protocols (gRPC, HTTP) and IDLs (OpenAPI, Proto, GraphQL) without requiring an external proxy, load balancer, or API server in front.*

The second issue we are trying to tackle, are the deficits around integrating a Temporal backend into a broader application architecture. 

After talking to hundreds of users and companies about how Temporal fits into their broader technology story, a very clear pattern emerged. Almost any company with significant Temporal usage eventually ended up putting their Temporal applications behind a “dumb” proxy layer, load balancer, transformer, etc. To be clear, this is not about providing a REST (or other specification) version of the already well established Temporal API (StartWorkflow, CreateNamespace, ListOpenWorkflows etc) but rather enabling users to expose their application specific APIs directly via Temporal (ProcessOrder, UpdatePrice, etc).

At first the working assumption was that this is due to a lack of perceived security or resiliency from Temporal itself. Instead what became clear is that while Temporal developers within these companies were happy to think in Temporal terms, non-Temporal developers were not. So in order to surface the work they had done with Temporal, developers at these companies would design the external API as a traditional GRPC Service or REST (OpenAPI) Application. This approach meant that non-Temporal developers did not even know they were calling a Temporal application at all. 

We believe that developers should be able to natively surface Temporal backends using standard procotols (GRPC, HTTP) and IDLS (OpenAPI, Proto) without requiring an external proxy, loadbalancer or API server in front.

**What about separation of concerns?**

An immediate question you might have is why Temporal should be responsible for any of this. Isn’t it exactly in the spirit of separation of concerns that Temporal provides a durable execution experience and another component provides the API expressivity?

My current belief is that the separation is artificial and that as a Temporal user you already pay the cost of an expressive API server without getting any of its benefits. To understand why this is true, let’s look at Temporal from a very fundamental perspective. 

For any Temporal application:

- Temporal server provides a single logical endpoint for any and all traffic going to your application.
- Temporal server is required to be the first point of contract (ie: entry point) for any work that is started or messages that are delivered.
- Temporal server autonomously handles the process of distributing messages and work to your application servers.
- Temporal model inherently abstracts language specific constructs implicitly requiring a language-agnostic IDL.
- Temporal handles retries, timeouts, health checks, security and much more.

Just due to these existing and fundamental aspects of the system, I argue that Temporal is already and unavoidably a:

- Service mesh
- API Gateway
- Reverse proxy
- Load balancer
- RPC

Regardless of whether you want Temporal to be used as an API Gateway, you’re already paying the price for it to be one. 

# Arbitrary length operations

**TL;DR;** *There is a missing generic standard for RPCs which are resilient to client failures.*

In the previous section we discussed the need for Temporal developers to expose their Temporal applications using well known formats and approaches. One of the biggest benefits of using something like gRPC is that it abstracts away the implementation details and leaves you only with the contract. In most cases, the underlying implementation is no more expressive than gRPC and even though the semantics may change no fundamental expressivity is lost. In fact, in many cases gRPC is more expressive than the underlying implementation itself. 

However, gRPC does not make it clear how to invoke stateful operations of an arbitrary length—that is, calls that are:

- Arbitrary length - the potential duration is completely unbounded (aka any call over a network)
- Identifiable - if you can’t get back to it, why are we even talking about it?

Assuming we align on what an ALO (Arbitrary length operation) is, it should be immediately clear that todays Workflow primitive is already a perfect vehicle for ALOs. Workflows can durably and reliably run for an unbounded period of time without worrying about faults, old age disease etc. They persist even outside of the RPC that initially led to their creation and can be accessed even if the client which started the RPC fails. 

It is absolutely possible to model an API with these semantics using existing standards like protobuf but any such solution would be an informal representation at best. There have been attempts to formally represent something similar, such as Google's Long-Running Operation (LRO) extension to proto ([Google's long-running operations](https://cloud.google.com/service-infrastructure/docs/service-management/reference/rpc/google.longrunning)) and Microsoft's [Windows Communication Foundation](https://docs.microsoft.com/en-us/dotnet/framework/wcf/whats-wcf). 

Specifically in the case of Googles LRO, we believe it is only addressing a small slice of the broader problem. Even its namesake (Long running…) indicates that the duration of the operation is key to the abstractions applicability. I would argue that the problems Workflows solve in this regard have little do with the length of the actual operation and far more with the uncertainty in how long it will run. In other words, Workflows could run for milliseconds, seconds or years. It’s the uncertainty that’s interesting, not the duration itself. 

We believe there is a potential need for a net new abstraction that imparts the unique and beneficial aspects of the Workflow invocation experience, but in a Temporal agnostic way.

I personally believe that this abstraction may not be wholly independent from the other problems we are trying to solve in this group but we should try to approach it that way initially.
