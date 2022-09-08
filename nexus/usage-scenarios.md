> Note: Some of these scenarios are forward looking and will not be supported for some time. 

**Contents:**

- [Exposing Temporal application to a non-Temporal consumer (Nexus + ALO)](#exposing-temporal-application-to-a-non-temporal-consumer-nexus--alo)
- [Exposing Temporal application to a Temporal consumer (Nexus)](#exposing-temporal-application-to-a-temporal-consumer-nexus)
- [Exposing non-Temporal application with Temporal-esque calling semantics (ALO)](#exposing-non-temporal-application-with-temporal-esque-calling-semantics-alo)
- [Exposing non-Temporal application via Nexus](#exposing-non-temporal-application-via-nexus)

## Exposing Temporal application to a non-Temporal consumer (Nexus + ALO)

**Problem statement:** One of the most common patterns we see from Temporal users is the need to expose a generic API for internal consumers who are not familiar with Temporal. The most common solution for this problem today is to stand up a separate infrastructure dependency in front of Temporal (such as a load balancer, HTTP server, GRPC Gateway) which defines the formal API & contract for consumers.

**Solution:** Temporal users can now define and create a Nexus which represents the desired shape of their GRPC/HTTP API. Because Nexus gives users full control of how to parse/handle incoming requests, they can choose to expose their Temporal logic without anyone knowing that they used Temporal behind the scenes. If the consumer of their API has adopted the ALO standard, they can also “automagically” expose their Nexus APIs as ALOs. The capabilities of Nexus completely and totally obviate the need for a standalone API in these scenarios.

(Inspired by comments by Chad) Our long term vision is to have appropriate abstractions in place such that exposing a Nexus is done entirely through a service definition file. That service definition would be discoverable through a registry or maybe even just automatically via a well-known endpoint provided by all Nexus Services. Consumers would be able to generate strongly typed interfaces from this definition and implementers would be able to generate scaffolding and boilerplate from it as well. This will be leveragable by non-Temporal users but for Temporal users we can even automatically generate binding code in a Temporal specific way.

## Exposing Temporal application to a Temporal consumer (Nexus)

**Problem statement:** Having a strong story for cross team collaboration is one of the most important aspects in the long term success of any technology. Within Temporal, we support the concept of a Namespace, which represents a bucket of isolated Temporal resources. While Namespaces are great for isolating resources, they leave a lot to be desired when it comes to exposing those resources to other teams operating inside or outside of your Temporal Cluster. Today cross Namespace calls only work with ChildWorkflows and even that behavior is unintuitive to most. Furthermore, calling into another Namespace when that Namespace resides on an external Cluster or even when it is replicated across your own Clusters makes things even less straightforward. 

**Solution:** Temporal users can now define and create a Nexus which can be used to surface any Temporal functionality to other Temporal consumers. When calling into another Nexus from a Temporal context (eg: Workflow), every call will surfaced as an ALO, even if the Nexus implementation did not define them as such. This is because Temporal can automatically retry calls to any external endpoint and therefore seamlessly provide the ALO experience even when the endpoint was not implemented as an ALO originally. 

## Exposing non-Temporal application with Temporal-esque calling semantics (ALO)

**Problem statement:** When designing and building APIs, there is often a need to expose operations which are not well suited for traditional request/response semantics. In many cases, developers simply shoehorn the arbitrary length operations into a traditional req/res approach resulting in bad dx at minimum and catastrophic bugs in the worst case. There exists no standardized approach for calling operations of arbitrary length in a reliable and consistent manner. There are schema specifics approaches such as [grpc long running](https://cloud.google.com/spanner/docs/reference/rpc/google.longrunning) and approaches that marry themselves to specific architectures like pub/sub which is the case with [Async API](https://www.asyncapi.com/). 

**Solution:** While there is no open standard for exposing ALOs, there is a very reasonable Temporal-specific approach to this problem today - Workflows. Workflows provide the minimum set of APIs and functionality required to surface ALOs in a reliable and enjoyable fashion. Taking inspiration from Workflows, we are proposing a standard for ALOs which provide a Workflow-esque calling experience for any backend that supports the standard - not just Temporal. ALOs will be a first class citizen in Temporal, but any ALO compliant backend can be interacted with as if you were calling Workflows. 