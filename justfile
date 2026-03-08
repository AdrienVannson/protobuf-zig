protobuf_version := "33.2"

all: setup build test conformance

build:
    cd protobuf && zig build
    cd protoc-gen-zig && zig build

test:
    cd protobuf && zig build test
    cd protoc-gen-zig && zig build test

clean:
    rm -rf protobuf/.zig-cache protobuf/zig-out
    rm -rf protoc-gen-zig/.zig-cache protoc-gen-zig/zig-out

# Download protoc, conformance runner, and conformance protos
setup version=protobuf_version:
    tools/upstream-protobuf.sh setup {{version}}

# Run protoc (downloads if needed)
protoc *args:
    PROTOBUF_VERSION={{protobuf_version}} tools/upstream-protobuf.sh protoc {{args}}

# Run conformance test runner (downloads if needed)
conformance-runner *args:
    PROTOBUF_VERSION={{protobuf_version}} tools/upstream-protobuf.sh conformance-runner {{args}}

# Run protobuf conformance tests (not part of 'test')
conformance: setup
    cd conformance && zig build -Doptimize=ReleaseFast
    just conformance-runner --failure_list conformance/known_failures.txt ./conformance/zig-out/bin/conformance
