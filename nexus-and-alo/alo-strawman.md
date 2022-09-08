One of the biggest challenges when designing the holistic user experience for the Nexus project is providing the benefits of Workflow calling conventions without leaking the specifics of Workflows. At our first official Nexus offsite, Sergey (one of the earliest Temporal engineers) discussed the analogy between ALOs and the concept of Promises in asynchronous programming. 

I believe this is a very succinct encapsulation which captures the MVP needs for everything we're trying to accomplish. The notion of Durable Promises (server side promises) also give us some serious guidance on what the surface area of ALOs should be.

> 💡 It’s important to note that in the product requirements we made it clear that the ALO solution needs to support multiple methods of delivering results. We described this as “Get Result” above which would likely be an explicit API in most cases. That being said, Get Result as written above is not an API method but rather a general capability. This capability may be satisfied in the form of asynchronous delivery mechanisms (such as webhooks).

You can imagine the minimal Promise inspired ALO API having the following capabilities:

- Start
- Get Result
- Get Status (ie: Rejected, Resolved, Fulfilled)
- Cancellation

The current belief is that ALO should never become a generic Durable Object and therefore it will never be possible to surface arbitrary methods as part of the ALO itself. Instead you would surface those endpoints as either stateless short lived API methods, or as top level ALOs themselves. That being said, there is significant room for extension in the ALO surface area such a Listing & Filtering, and the ability to Pause and Resume.

### Proposal for initial interface of the ALO

```protobuf
// An ALO is started via the Start method
message AloInfo {
  string id = 1;
  Status status = 2;
  map<string, string> metadata = 3;

  enum Status {
    STATUS_UNSPECIFIED = 0;
    RUNNING = 1;
    COMPLETED = 2;
  }
}

service AloHandler {
  rpc Start(StartRequest) returns (StartResponse);
  rpc GetInfo(GetInfoRequest) returns (GetInfoResponse);
  rpc GetResult(GetResultRequest) (GetResultResponse);
  rpc Cancel(CancelRequest) returns (CancelRepsonse);
}
```

### A bit about Ids

![Lost the client Id](./images/lost-client-id.png)

One of the most common debates around ALOs is whether unique Ids should be a fundamental part of the specification and design. 

Considering ALOs represent the eventual completion of an operation, its impossible to imagine a design where they aren’t identifiable. Note that I did not say “addressable” because technically in the case of asynchronous result delivery it may not be required for the ALO itself to be addressable. That being said, even in the async result delivery case, the result must be delivered with a unique correlation Id. 

![Full client Id flow](./images/full-client-id-flow.png)

Because of this, ALOs will also be required to have a unique Id. Furthermore, because server side generation of unique Ids is inherently lossy, an ALO `StartRequest` **must include a client-side generated unique Id**. To be clear, the id must be unique for that specific ALO endpoint.