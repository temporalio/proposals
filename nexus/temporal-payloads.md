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
   2. Strip the key prefix and transform header case to camel case. E.g: `Content-Temporal-Foo-Bar` becomes `fooBar`
   3. Read the values as [data URLs](https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/Data_URLs)
2. Set the `encoding` Payload metadata field as follows:
   1. If `Content-Length` is 0 or body is empty → `binary/null`
   2. If `Content-Type` media type is `application/json` →
      1. If the content type parameter contains a `format=protobuf` → `json/protobuf` and set `messageType` to the corresponding parameter value.
         Example: `Content-Type: application/json; format=protobuf; messageType=com.example.Message`
      2. Otherwise → `json/plain`
   3. If `Content-Type` media type is `application/x-protobuf` → `binary/protobuf` and set the `messageType` parameter as given in the header.
      Example: `Content-Type: application/x-protobuf; messageType="com.example.Message"`
   4. Otherwise → `binary/plain`
3. Extract all `Content-Encoding` values into a `codecs` metadata key with a comma separator. Note that the server may
   decompress gzipped content and other popular encoding formats.
4. Read the entire body into `Payload.data` and unset `Content-Length`
5. Extract any other interesting `Content-` prefixed headers (none seem relevant ATM)

To unmarshal from a Nexus request or response to a Temporal payload:

1. Set the `Content-Length` header to the `Payload.data` length
2. Set body to `Payload.data`
3. Set `Content-Type` based on the `Payload.metadata` `encoding` field:
   1. `binary/null` → unset
   2. `json/plain` → `application/json`
   3. `json/protobuf` → `application/json; proto=$Payload.metadata.messageType`
   4. `binary/protobuf` → `application/x-protobuf; messageType=$Payload.metadata.messageType`
   5. `binary/plain` → `application/octet-stream`
   6. Anything else → `application/octet-stream; temporalEncoding=$Payload.metadata.encoding`
4. Set `Content-Encoding` to `Payload.metadata.codecs`
5. Other metadata fields are set as `Content-Temporal-` headers, transforming camel case to header case. Values are encoded as base64 data URLs.

## Custom data converters

Users implementing custom data converters will need to add a codec that converts to and from their non-standard payload format.

## References

- https://stackoverflow.com/a/48051331
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Type#directives
