set dotenv-load
set dotenv-override

protobuf_version := "33.2"

all: setup setup-conformance build generate generate-example run-example test conformance code-quality generate-wkt

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
generate:
    cd protoc-gen-zig && zig build -Dprotobuf_version={{protobuf_version}}
    rm -rf protobuf/src/testgen
    mkdir -p protobuf/src/testgen
    just protoc \
        --plugin=protoc-gen-zig=./protoc-gen-zig/zig-out/bin/protoc-gen-zig \
        --zig_out=./protobuf/src/testgen \
        --proto_path=./protoc-gen-zig/test_protos \
        example.proto

# Generate the well-known types using protoc-gen-zig.
generate-wkt: setup
    #!/usr/bin/env bash
    set -euo pipefail
    (cd protoc-gen-zig && zig build -Dprotobuf_version={{protobuf_version}})
    rm -rf protobuf/src/wkt
    mkdir -p protobuf/src/wkt
    include_dir="$(PROTOBUF_VERSION={{protobuf_version}} tools/upstream-protobuf.sh paths | grep '^PROTOC_INCLUDE=' | cut -d= -f2-)"
    just protoc \
        --plugin=protoc-gen-zig=./protoc-gen-zig/zig-out/bin/protoc-gen-zig \
        --zig_out=./protobuf/src/wkt \
        --proto_path="$include_dir" \
        "$include_dir"/google/protobuf/*.proto

# Generate the example using buf
generate-example:
    cd protoc-gen-zig && zig build -Dprotobuf_version={{protobuf_version}}
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

# Run protobuf conformance tests (not part of 'test')
conformance:
    cd conformance && zig build -Doptimize=ReleaseFast -Dprotobuf_version={{protobuf_version}}
    just conformance-runner --enforce_recommended --failure_list conformance/known_failures.txt ./conformance/zig-out/bin/conformance
