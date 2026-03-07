all: build test

build:
    cd protobuf && zig build
    cd protoc-gen-zig && zig build

test:
    cd protobuf && zig build test
    cd protoc-gen-zig && zig build test

clean:
    rm -rf protobuf/.zig-cache protobuf/zig-out
    rm -rf protoc-gen-zig/.zig-cache protoc-gen-zig/zig-out
