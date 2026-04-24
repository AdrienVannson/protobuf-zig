# Zig Protobuf Implementation Spec

## Overview

Implement a protobuf code generator and runtime library for Zig. The system has two parts:

1. **Code generator**: Takes `.proto` files and emits Zig source files containing struct definitions and comptime metadata.
2. **Runtime library**: Provides serialization, deserialization, and wire format utilities that work generically over any generated message struct.

---

## Generated Message Representation

Each protobuf message becomes a Zig struct. The struct uses the following conventions:

### Field representation

- **Singular scalar fields** (int32, string, bool, etc.): Use `?T` optional types. `null` means the field is not set (has its default/wire-default value). Examples: `?i32`, `?[]const u8`, `?bool`.
- **Singular message fields**: Use `?*SubMessage` (optional pointer). Pointer indirection is required to allow mutually recursive message types and because the size of the sub-message cannot be inlined. The generated code must handle allocation and deallocation of these pointers.
- **Repeated fields**: Use `std.ArrayListUnmanaged(T)` initialized to `.{}`. For repeated message fields, use `std.ArrayListUnmanaged(SubMessage)` (values, not pointers, since the list itself is heap-backed).
- **Map fields**: Use `std.ArrayHashMapUnmanaged(K, V, ...)` or model as repeated entries of a generated key-value entry struct (the standard protobuf approach). Choose whichever is simpler to start with.
- **Enum fields**: Generate a Zig `enum(i32)` for each protobuf enum. Represent enum fields as `?GeneratedEnum`.
- **Oneof fields**: Generate a Zig tagged union for each oneof group. Represent the oneof as `?TheUnion`.

### Default values

All optional fields default to `null`. Repeated fields default to `.{}`. This means an unmodified, default-initialized struct represents a message with no fields set.

### Field presence

A field is considered "present" / "set" if it is non-null. This applies uniformly. Proto3 implicit-presence fields still use `?T` internally — when reading, treat `null` as the type's default value (0, false, empty string). Proto2 and proto3 explicit-presence (`optional` keyword) fields use `null` to mean "not set on the wire."

### Comptime field descriptor table

Each generated struct contains a `pub const _desc` field: a comptime-known slice of `FieldDescriptor` structs. The descriptors are in the same order as the struct fields (excluding `_desc` and methods). This allows the runtime library to iterate over `@typeInfo(T).@"struct".fields` and index into `_desc` in lockstep.

```zig
pub const FieldDescriptor = struct {
    name: []const u8,       // protobuf field name
    number: u32,            // protobuf field number
    wire_type: WireType,    // varint, fixed32, fixed64, length_delimited
    field_type: FieldType,  // semantic type (int32, string, message, etc.)
    is_repeated: bool = false,
    is_map: bool = false,
    is_packed: bool = false,
    // For proto2: could add a default_value field later
};

pub const WireType = enum(u3) {
    varint = 0,
    fixed64 = 1,
    length_delimited = 2,
    // 3, 4 are deprecated group start/end
    fixed32 = 5,
};

pub const FieldType = enum {
    int32, int64, uint32, uint64, sint32, sint64,
    fixed32, fixed64, sfixed32, sfixed64,
    float, double, bool_,
    string, bytes,
    message, @"enum",
};
```

### Example generated output

For this proto:

```proto
message Person {
  string name = 1;
  int32 id = 2;
  optional string email = 3;
  repeated PhoneNumber phones = 4;
  Address home_address = 5;
}
```

Generate:

```zig
pub const Person = struct {
    name: ?[]const u8 = null,
    id: ?i32 = null,
    email: ?[]const u8 = null,
    phones: std.ArrayListUnmanaged(PhoneNumber) = .{},
    home_address: ?*Address = null,

    pub const _desc = &[_]FieldDescriptor{
        .{ .name = "name",         .number = 1, .wire_type = .length_delimited, .field_type = .string },
        .{ .name = "id",           .number = 2, .wire_type = .varint,           .field_type = .int32 },
        .{ .name = "email",        .number = 3, .wire_type = .length_delimited, .field_type = .string },
        .{ .name = "phones",       .number = 4, .wire_type = .length_delimited, .field_type = .message, .is_repeated = true },
        .{ .name = "home_address", .number = 5, .wire_type = .length_delimited, .field_type = .message },
    };

    pub fn deinit(self: *Person, allocator: std.mem.Allocator) void {
        // Free allocated strings if they were allocated during deserialization.
        // Deinit and free sub-messages (home_address).
        // Deinit repeated fields (phones).
    }
};
```

### Memory management

- The `deinit` method on each message must recursively free all owned memory: sub-message pointers, repeated field backing arrays, and any strings/bytes that were allocated during deserialization.
- Deserialization takes an `Allocator` parameter and uses it for all allocations. The generated `deinit` frees using the same allocator.
- Serialization does not allocate (writes to a `writer: anytype`).

---

## Runtime Library: Serialization

Implement a single generic serialization function:

```zig
pub fn serialize(comptime T: type, msg: *const T, writer: anytype) !void
```

It works as follows:

1. Get the struct fields via `@typeInfo(T).@"struct".fields`.
2. `inline for` over `T._desc` and the struct fields in lockstep.
3. For each field:
   - **Repeated**: iterate over `.items` and write each element with its tag.
   - **Optional scalar** (`?T`): if non-null, write the tag and value.
   - **Optional message pointer** (`?*M`): if non-null, dereference the pointer, compute the serialized size of the sub-message, write the tag + length prefix, then recursively call `serialize` on the sub-message.
   - **Null/not present**: skip entirely (proto wire default behavior).

This uses comptime recursion for sub-messages. Mutually recursive types (A references B, B references A) work because the compiler instantiates `serialize(A, ...)` and `serialize(B, ...)` as two separate runtime functions that call each other — no infinite comptime expansion.

### Wire format helpers needed

- `writeVarint(writer, value)` — encode a varint
- `writeTag(writer, field_number, wire_type)` — encode field tag
- `writeFixed32 / writeFixed64`
- `writeLengthDelimited(writer, bytes)` — write length prefix + bytes
- `encodeZigZag` — for sint32/sint64
- `serializedSize(comptime T: type, msg: *const T) usize` — compute the serialized byte size of a message (needed for length-prefixed sub-messages)

---

## Runtime Library: Deserialization

Implement a single generic deserialization function:

```zig
pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, reader: anytype) !T
```

It works as follows:

1. Initialize a default `T` (all nulls / empty lists).
2. Loop: read a tag (field number + wire type) from the reader.
3. Look up the field number in `T._desc` (can build a comptime lookup from field number → descriptor index).
4. Based on the descriptor's `field_type` and `wire_type`, decode the value.
5. Set the corresponding struct field:
   - Scalars: set the `?T` field to the decoded value.
   - Messages: allocate a `*SubMessage` via the allocator, recursively `deserialize` into it, set the `?*SubMessage` field.
   - Repeated: append to the `ArrayListUnmanaged`.
6. Unknown fields: skip based on wire type (read and discard the correct number of bytes). Optionally store them for round-tripping.
7. Return the populated struct.

### Wire format helpers needed

- `readVarint(reader)` — decode a varint
- `readTag(reader)` — decode into (field_number, wire_type)
- `readFixed32 / readFixed64`
- `readLengthDelimited(reader, allocator)` — read length prefix + bytes
- `decodeZigZag`
- `skipField(reader, wire_type)` — skip an unknown field

---

## Code Generator

The code generator reads `.proto` files and outputs `.zig` files. It needs to handle:

1. **Parsing** `.proto` files (proto2 and proto3 syntax). You can use an existing protobuf parser or write a minimal one.
2. **Resolving** message references (imports, nested messages, packages).
3. **Emitting** Zig structs following the conventions above.
4. **Name mapping**: convert protobuf snake_case field names to snake_case Zig identifiers (they're the same convention). Convert PascalCase message names to PascalCase Zig struct names. Handle reserved Zig keywords by prefixing with `@""` quoting.

---

## Implementation Order

1. Wire format primitives (varint encoding/decoding, tag reading/writing, zigzag).
2. `FieldDescriptor`, `WireType`, `FieldType` type definitions.
3. Generic `serialize` function for a hand-written test message struct.
4. Generic `deserialize` function for the same.
5. Tests: round-trip a hand-crafted message struct through serialize → deserialize and verify equality.
6. Code generator: `.proto` parser → Zig source emitter.
7. End-to-end test: `.proto` → generated Zig → serialize → deserialize → verify.
