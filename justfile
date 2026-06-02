set dotenv-load
set dotenv-override

protobuf_version := "33.2"

all: setup setup-conformance build generate generate-example run-example test conformance code-quality generate-wkt generate-conformance generate-plugin

build:
    cd protobuf && zig build
    cd protoc-gen-zig && zig build -Dprotobuf_version={{protobuf_version}}

code-quality:
    zig fmt --check protobuf/
    zig fmt --check protoc-gen-zig/
    zig fmt --check conformance/

test:
    cd protobuf && zig build test
    cd protoc-gen-zig && zig build test -Dprotobuf_version={{protobuf_version}}

clean:
    rm -rf protobuf/.zig-cache protobuf/zig-out
    rm -rf protoc-gen-zig/.zig-cache protoc-gen-zig/zig-out

# Run protoc-gen-zig on the test proto file
generate: build
    rm -rf protobuf/src/testgen
    mkdir -p protobuf/src/testgen
    just protoc \
        --plugin=protoc-gen-zig=./protoc-gen-zig/zig-out/bin/protoc-gen-zig \
        --zig_out=./protobuf/src/testgen \
        --proto_path=./protoc-gen-zig/test_protos \
        $(find ./protoc-gen-zig/test_protos -iname "*.proto")

# Generate the well-known types using protoc-gen-zig.
generate-wkt: setup build
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf protobuf/src/wkt
    mkdir -p protobuf/src/wkt
    include_dir="$(PROTOBUF_VERSION={{protobuf_version}} tools/upstream-protobuf.sh paths | grep '^PROTOC_INCLUDE=' | cut -d= -f2-)"
    just protoc \
        --plugin=protoc-gen-zig=./protoc-gen-zig/zig-out/bin/protoc-gen-zig \
        --zig_out=./protobuf/src/wkt \
        --proto_path="$include_dir" \
        "$include_dir"/google/protobuf/*.proto
    mv protobuf/src/wkt/google/protobuf/*.pb.zig protobuf/src/wkt/
    rm -rf protobuf/src/wkt/google

# Generate conformance proto bindings using protoc-gen-zig.
generate-conformance: setup setup-conformance build
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf conformance/src/gen
    mkdir -p conformance/src/gen
    conformance_include="$(PROTOBUF_VERSION={{protobuf_version}} tools/upstream-protobuf.sh paths | grep '^CONFORMANCE_INCLUDE=' | cut -d= -f2-)"
    just protoc \
        --plugin=protoc-gen-zig=./protoc-gen-zig/zig-out/bin/protoc-gen-zig \
        --zig_out=./conformance/src/gen \
        --proto_path="$conformance_include" \
        conformance/conformance.proto \
        "$conformance_include"/google/protobuf/*.proto

# Regenerate plugin bootstrap bindings using our own protoc-gen-zig.
generate-plugin: setup build
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf protoc-gen-zig/src/gen
    mkdir -p protoc-gen-zig/src/gen
    include_dir="$(PROTOBUF_VERSION={{protobuf_version}} tools/upstream-protobuf.sh paths | grep '^PROTOC_INCLUDE=' | cut -d= -f2-)"
    just protoc \
        --plugin=protoc-gen-zig=./protoc-gen-zig/zig-out/bin/protoc-gen-zig \
        --zig_out=./protoc-gen-zig/src/gen \
        --proto_path="$include_dir" \
        google/protobuf/descriptor.proto \
        google/protobuf/compiler/plugin.proto

# Generate the example using buf
generate-example: build
    cd example && buf generate

# Build and run the example
run-example:
    cd example && zig build run

# Download protoc (all platforms)
setup version=protobuf_version:
    PROTOBUF_VERSION={{version}} tools/upstream-protobuf.sh setup {{version}}

# Download the conformance test runner (Linux/macOS only)
setup-conformance version=protobuf_version:
    PROTOBUF_VERSION={{version}} tools/upstream-protobuf.sh setup-conformance {{version}}

# Run protoc (downloads if needed)
protoc *args:
    PROTOBUF_VERSION={{protobuf_version}} tools/upstream-protobuf.sh protoc {{args}}

# Run conformance test runner (downloads if needed)
conformance-runner *args:
    PROTOBUF_VERSION={{protobuf_version}} tools/upstream-protobuf.sh conformance-runner {{args}}

# Build documentation
docs:
    cd protobuf && zig build docs

# Build documentation and serve it locally on port 8080
docs-serve: docs
    python3 -m http.server --directory protobuf/zig-out/docs 8080

# Run protobuf conformance tests (not part of 'test')
conformance:
    cd conformance && zig build -Doptimize=ReleaseFast -Dprotobuf_version={{protobuf_version}}
    just conformance-runner --enforce_recommended --failure_list conformance/known_failures.txt ./conformance/zig-out/bin/conformance
