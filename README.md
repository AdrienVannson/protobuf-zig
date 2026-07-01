# protobuf-zig

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
