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
  repeated string emails = 3;
  map<string, string> tags = 5;
  Address address = 6;
}

message Address {
  string street = 1;
  string city = 2;
}
```
<!-- /include -->

### `toBinary`

Encoding a message to the binary wire format:

<!-- include: example/examples/to_binary.zig -->
```zig
var emails = [_][]const u8{"alice@example.com"};
const person = example.Person{
    .name = "Alice",
    .age = 30,
    .emails = .fromOwnedSlice(&emails),
};

const encoded = try protobuf.toBinary(allocator, person);
defer allocator.free(encoded);
std.debug.print("encoded ({d} bytes): {x}\n", .{ encoded.len, encoded });
```
<!-- /include -->

### `fromBinary`

Decoding a message (the caller owns the result and must `deinit` it):

<!-- include: example/examples/from_binary.zig -->
```zig
const encoded = "\x0a\x05Alice\x10\x1e\x1a\x11alice@example.com";

var person = try protobuf.fromBinary(example.Person, allocator, encoded);
defer person.deinit(allocator);

// decoded: Alice, 30, alice@example.com
std.debug.print("decoded: {s}, {d}, {s}\n", .{ person.name, person.age, person.emails.items[0] });
```
<!-- /include -->

### `merge`

Merging a message into another, following protobuf merge semantics (the result is the
same as decoding the concatenation of both encodings): singular fields set in the source
overwrite the target, repeated fields are appended, map entries are replaced by key, and
sub-messages are merged recursively. All data is copied, so the target never references
memory owned by the source.

> [!WARNING]
> The destination message must own all its memory, recursively: merging may free or
> extend fields using the allocator passed to `merge`.

<!-- include: example/examples/merge.zig -->
```zig
// The target owns its strings, which merge frees when overwritten
var person = example.Person{ .name = try allocator.dupe(u8, "Alice"), .age = 30 };
defer person.deinit(allocator);

var emails = [_][]const u8{"alice@example.com"};
const update = example.Person{ .age = 31, .emails = .fromOwnedSlice(&emails) };

try protobuf.merge(&person, allocator, update);

// merged: Alice, 31, alice@example.com
std.debug.print("merged: {s}, {d}, {s}\n", .{ person.name, person.age, person.emails.items[0] });
```
<!-- /include -->

### `mergeFromBinary`

Merging binary data into an existing message. This follows the same semantics as
`merge`: the result is the same as decoding the concatenation of the message's encoding
and the input. All data is copied, so the message never references the input buffer.

> [!WARNING]
> The destination message must own all its memory, recursively: merging may free or
> extend fields using the allocator passed to `mergeFromBinary`.

<!-- include: example/examples/merge_from_binary.zig -->
```zig
// The message owns its strings, which are freed by `deinit` or when overwritten
var person = example.Person{ .name = try allocator.dupe(u8, "Alice"), .age = 30 };
defer person.deinit(allocator);

// Person{ .age = 31, .emails = .{"alice@example.com"} }
const encoded = "\x10\x1f\x1a\x11alice@example.com";
try protobuf.mergeFromBinary(&person, allocator, encoded);

// merged: Alice, 31, alice@example.com
std.debug.print("merged: {s}, {d}, {s}\n", .{ person.name, person.age, person.emails.items[0] });
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

var emails = [_][]const u8{"alice@example.com"};
const person = example.Person{
    .name = "Alice",
    .age = 30,
    .emails = .fromOwnedSlice(&emails),
};

// Pack the person into an Any
var payload = try Any.pack(allocator, person);
defer payload.deinit(allocator);
std.debug.print("type_url: {s}\n", .{payload.type_url}); // type.googleapis.com/example.Person

// Check the type held by the Any, and unpack it
if (payload.is(example.Person)) {
    var unpacked = try payload.unpack(example.Person, allocator);
    defer unpacked.deinit(allocator);
    std.debug.print("unpacked: {s}, {d}, {s}\n", .{ unpacked.name, unpacked.age, unpacked.emails.items[0] });
}
```
<!-- /include -->
