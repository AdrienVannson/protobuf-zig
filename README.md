# protobuf-zig

[![CI](https://github.com/AdrienVannson/protobuf-zig/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AdrienVannson/protobuf-zig/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-API%20reference-blue)](https://adrienvannson.github.io/protobuf-zig/)
[![Zig](https://img.shields.io/badge/zig-0.16.0-f7a41d?logo=zig&logoColor=white)](https://ziglang.org/download/)
[![protobuf](https://img.shields.io/badge/protobuf-v36.2-4285f4)](https://github.com/protocolbuffers/protobuf/releases/tag/v36.2)
<!-- TODO: add once a LICENSE file exists:
[![License](https://img.shields.io/github/license/AdrienVannson/protobuf-zig)](LICENSE)
-->
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

const encoded = try protobuf.to_binary(allocator, person);
defer allocator.free(encoded);
std.debug.print("encoded ({d} bytes): {x}\n", .{ encoded.len, encoded });
```
<!-- /include -->
