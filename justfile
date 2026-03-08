protobuf_version := "33.2"

all: setup build generate test conformance code-quality

build:
    cd protobuf && zig build
    cd protoc-gen-zig && zig build -Dprotobuf_version={{protobuf_version}}

code-quality:
    zig fmt --check protobuf/
    zig fmt --check protoc-gen-zig/

test:
    cd protobuf && zig build test
    cd protoc-gen-zig && zig build test -Dprotobuf_version={{protobuf_version}}

clean:
    rm -rf protobuf/.zig-cache protobuf/zig-out
    rm -rf protoc-gen-zig/.zig-cache protoc-gen-zig/zig-out

# Run protoc-gen-zig on the test proto file
generate:
    cd protoc-gen-zig && zig build -Dprotobuf_version={{protobuf_version}}
    just protoc \
        --plugin=protoc-gen-zig=./protoc-gen-zig/zig-out/bin/protoc-gen-zig \
        --zig_out=./protobuf/src/testgen \
        --proto_path=./protoc-gen-zig/testprotos \
        example.proto

# Download protoc, conformance runner, and conformance protos
setup version=protobuf_version:
    PROTOBUF_VERSION={{version}} tools/upstream-protobuf.sh setup {{version}}

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
