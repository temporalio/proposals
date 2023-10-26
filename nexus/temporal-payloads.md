# Temporal Payloads over Nexus+HTTP

## Motivation

For ideal integration of Temporal applications with Nexus, Temporal users should be able to leverage Temporal Payloads
and not have to concern themselves with Nexus implementation details.

When a workflow completes, we'd like Temporal server to be able to deliver the completion result to any registered Nexus
callbacks and the callback receiver (a Temporal server) to translate the completion to a Temporal Payload.

Inherently, we need a fixed set of translation rules from Payloads to Nexus+HTTP and back. These rules should be
executed server-side.

## Background

Nexus reserves the entire HTTP request and response bodies (for input and successful results) for data and uses HTTP
headers (a mapping of string to an array of strings) for transmitting metadata.

> The main motivation for this design was to support streaming and avoid requiring HTTP proxies to inspect request
> bodies.

A Temporal Payload is defined as:

```proto3
message Payload {
    map<string,bytes> metadata = 1;
    bytes data = 2;
}
```

## Translation rules

To unmarshal a Temporal Payload from a Nexus request or response:

1. Extract all `Content-Temporal-` prefixed headers into the payload metadata using the following rules:
   1. Ignore multiple values (not supported)
   1. Strip the key prefix and transform header case to camel case. E.g: `Content-Temporal-Foo-Bar` becomes `fooBar`
   1. Read the values as [data URLs](https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/Data_URLs)
1. Set the `Payload.metadata.encoding` field as follows:
   1. If `Content-Length` is 0 or body is empty → `binary/null`
   1. If `Content-Type` media type is `application/json` →
      1. If the content type parameter contains a `format=protobuf` → `json/protobuf` and set `messageType` to the corresponding parameter value.
         Example: `Content-Type: application/json; format=protobuf; messageType=com.example.Message`
      2. Otherwise → `json/plain`
   1. If `Content-Type` media type is `application/x-protobuf` → `binary/protobuf` and set the `messageType` parameter as given in the header.
      Example: `Content-Type: application/x-protobuf; messageType="com.example.Message"`
   1. `Content-Type: application/octet-stream; temporalEncoding=X` → `X`
   1. Otherwise → `binary/plain`
1. Read the entire body into `Payload.data`

To unmarshal from a Nexus request or response to a Temporal payload:

1. Set the `Content-Length` header to the `Payload.data` length
1. Set body to `Payload.data`
1. Set `Content-Type` based on the `Payload.metadata.encoding` field:
   1. `binary/null` → unset
   1. `json/plain` → `application/json`
   1. `json/protobuf` → `application/json; format=protobuf; messageType=$Payload.metadata.messageType`
   1. `binary/protobuf` → `application/x-protobuf; messageType=$Payload.metadata.messageType`
   1. `binary/plain` → `application/octet-stream`
   1. Anything else → `application/octet-stream; temporalEncoding=$Payload.metadata.encoding`
1. Other metadata fields are set as `Content-Temporal-` headers, transforming camel case to header case. Values are encoded as base64 data URLs.

## Note on `Content-Encoding`

`Content-Encoding` is handled at the Nexus transport layer - typically handled by Temporal server. Temporal applications
should not concern themselves with that detail.

At a later stage we may want to formalize practices around `Accept` headers and `Content-Encoding` as well as letting a
client request that a result is encrypted using a given key.

## Custom data converters

Users implementing custom data converters will need to add a codec that converts to and from their non-standard payload format.

## References

- https://stackoverflow.com/a/48051331
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Type#directives
