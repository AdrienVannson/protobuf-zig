# protobuf-zig

[![CI](https://github.com/AdrienVannson/protobuf-zig/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AdrienVannson/protobuf-zig/actions/workflows/ci.yml)
[![Zig](https://img.shields.io/badge/zig-0.17.0-f7a41d?logo=zig&logoColor=white)](https://ziglang.org/download/)
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

<!-- include: example/examples/to_binary.zig -->
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

Decoding a message (the caller owns the result and must `deinit` it):

<!-- include: example/examples/from_binary.zig -->
```zig
const encoded = "\x0a\x05Alice\x10\x1e\x1a\x11alice@example.com";

var person = try protobuf.fromBinary(example.Person, allocator, encoded);
defer person.deinit(allocator);

// decoded: Alice, 30, alice@example.com
std.debug.print("decoded: {s}, {d}, {s}\n", .{ person.name, person.age, person.email });
```
<!-- /include -->

Merging binary data into an existing message (singular fields are overwritten,
repeated fields are appended):

<!-- include: example/examples/merge_from_binary.zig -->
```zig
// The message owns its strings, which are freed by `deinit` or when overwritten
var person = example.Person{ .name = try allocator.dupe(u8, "Alice"), .age = 30 };
defer person.deinit(allocator);

// Person{ .age = 31, .email = "alice@example.com" }
const encoded = "\x10\x1f\x1a\x11alice@example.com";
try protobuf.mergeFromBinary(&person, allocator, encoded);

// merged: Alice, 31, alice@example.com
std.debug.print("merged: {s}, {d}, {s}\n", .{ person.name, person.age, person.email });
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
    var unpacked = try payload.unpack(example.Person, allocator);
    defer unpacked.deinit(allocator);
    std.debug.print("unpacked: {s}, {d}, {s}\n", .{ unpacked.name, unpacked.age, unpacked.email });
}
```
<!-- /include -->
