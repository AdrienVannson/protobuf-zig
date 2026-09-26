# protobuf-zig

[![CI](https://github.com/AdrienVannson/protobuf-zig/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AdrienVannson/protobuf-zig/actions/workflows/ci.yml)
[![Zig](https://img.shields.io/badge/zig-0.16.0-f7a41d?logo=zig&logoColor=white)](https://ziglang.org/download/)
[![protobuf](https://img.shields.io/badge/protobuf-v36.2-4285f4)](https://github.com/protocolbuffers/protobuf/releases/tag/v36.2)
<!-- TODO: add once releases are tagged:
[![Release](https://img.shields.io/github/v/tag/AdrienVannson/protobuf-zig?sort=semver)](https://github.com/AdrienVannson/protobuf-zig/tags)
-->

## Why a new implementation?

TODO

## Examples

All examples share the same schema:

<!-- include: example/proto/example.proto -->
```proto
syntax = "proto3";

package example;

message Person {
  string name = 1;
  int32 age = 2;
  string email = 3;
}
```
<!-- /include -->

Encoding a message to the binary wire format:

<!-- include: example/examples/basic.zig -->
```zig
const person = example.Person{
    .name = "Alice",
    .age = 30,
    .email = "alice@example.com",
};

const encoded = try protobuf.toBinary(allocator, person);
defer allocator.free(encoded);
std.debug.print("encoded ({d} bytes): {x}\n", .{ encoded.len, encoded });
```
<!-- /include -->

## Well-known types

### `google.protobuf.Any`

`Any.pack` wraps a message in a `google.protobuf.Any`. `Any.is` checks which message
type an `Any` holds, and `Any.unpack` decodes it back (returning `error.AnyTypeMismatch`
if the type does not match).

<!-- include: example/examples/any.zig -->
```zig
const Any = protobuf.wkt.any.Any;

const person = example.Person{
    .name = "Alice",
    .age = 30,
    .email = "alice@example.com",
};

// Pack the person into an Any
var payload = try Any.pack(allocator, person);
defer payload.deinit(allocator);
std.debug.print("type_url: {s}\n", .{payload.type_url}); // type.googleapis.com/example.Person

// Check the type held by the Any, and unpack it
if (payload.is(example.Person)) {
    var unpacked = try payload.unpack(allocator, example.Person);
    defer unpacked.deinit(allocator);
    std.debug.print("unpacked: {s}, {d}, {s}\n", .{ unpacked.name, unpacked.age, unpacked.email });
}
```
<!-- /include -->
