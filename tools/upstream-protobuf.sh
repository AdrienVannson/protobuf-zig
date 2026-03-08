#!/usr/bin/env bash

set -eo pipefail

DIR="$(CDPATH= cd "$(dirname "${0}")/.." && pwd)"
cd "${DIR}"

: "${PROTOBUF_VERSION:?PROTOBUF_VERSION must be set}"

CACHE_DIR="${DIR}/.cache/upstream-protobuf"

detect_os() {
    local os
    os="$(uname -s)"
    case "${os}" in
        Darwin)              echo "darwin" ;;
        Linux)               echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)
            echo "unsupported OS: ${os}" >&2
            exit 1
            ;;
    esac
}

detect_arch() {
    local arch
    arch="$(uname -m)"
    case "${arch}" in
        x86_64|amd64)  echo "x86_64" ;;
        arm64|aarch64) echo "arm64" ;;
        *)
            echo "unsupported architecture: ${arch}" >&2
            exit 1
            ;;
    esac
}

detect_protoc_build() {
    local os="${1}"
    local arch="${2}"
    case "${os}" in
        darwin)
            case "${arch}" in
                arm64)  echo "osx-aarch_64" ;;
                x86_64) echo "osx-x86_64" ;;
            esac
            ;;
        linux)
            case "${arch}" in
                x86_64) echo "linux-x86_64" ;;
                arm64)  echo "linux-aarch_64" ;;
            esac
            ;;
        windows)
            case "${arch}" in
                x86_64) echo "win64" ;;
                *)      echo "win32" ;;
            esac
            ;;
    esac
}

detect_conformance_platform() {
    local os="${1}"
    case "${os}" in
        darwin) echo "darwin-x64" ;;
        linux)  echo "linux-x64" ;;
        *)
            echo "conformance runner not available for OS: ${os}" >&2
            exit 1
            ;;
    esac
}

# RC versions: 33.2-rc1 → 33.2-rc-1 (insert hyphen before the number)
asset_version() {
    local version="${1}"
    echo "${version}" | sed 's/-rc/-rc-/'
}

protoc_dir() {
    local version="${1}"
    echo "${CACHE_DIR}/${version}/protoc"
}

conformance_dir() {
    local version="${1}"
    echo "${CACHE_DIR}/${version}/conformance"
}

download_protoc() {
    local version="${1}"
    local dir
    dir="$(protoc_dir "${version}")"

    if [ -d "${dir}" ]; then
        return
    fi

    local os arch build av zip_url
    os="$(detect_os)"
    arch="$(detect_arch)"
    build="$(detect_protoc_build "${os}" "${arch}")"
    av="$(asset_version "${version}")"
    zip_url="https://github.com/protocolbuffers/protobuf/releases/download/v${version}/protoc-${av}-${build}.zip"

    echo "Downloading protoc ${version} (${build})..." >&2

    local tmp_zip
    tmp_zip="$(mktemp)"
    curl -fsSL -o "${tmp_zip}" "${zip_url}"

    mkdir -p "${dir}"
    unzip -q "${tmp_zip}" -d "${dir}"
    chmod +x "${dir}/bin/protoc"
    rm -f "${tmp_zip}"

    echo "protoc installed to ${dir}" >&2
}

download_conformance() {
    local version="${1}"
    local dir
    dir="$(conformance_dir "${version}")"

    if [ -d "${dir}" ]; then
        return
    fi

    local npm_version="${version}.0"
    local tarball_url="https://registry.npmjs.org/protobuf-conformance/-/protobuf-conformance-${npm_version}.tgz"

    echo "Downloading conformance runner ${version}..." >&2

    local tmp_tgz
    tmp_tgz="$(mktemp)"
    curl -fsSL -o "${tmp_tgz}" "${tarball_url}"

    mkdir -p "${dir}"
    tar xz -f "${tmp_tgz}" -C "${dir}"
    rm -f "${tmp_tgz}"

    echo "conformance runner installed to ${dir}" >&2
}


cmd_setup() {
    local version="${1:-${PROTOBUF_VERSION}}"
    download_protoc "${version}"
    download_conformance "${version}"
    echo ""
    echo "Setup complete for protobuf ${version}:"
    cmd_paths "${version}"
}

cmd_protoc() {
    local version="${PROTOBUF_VERSION}"
    download_protoc "${version}"
    exec "$(protoc_dir "${version}")/bin/protoc" "${@}"
}

cmd_conformance_runner() {
    local version="${PROTOBUF_VERSION}"
    download_conformance "${version}"

    local os arch platform runner
    os="$(detect_os)"
    arch="$(detect_arch)"
    platform="$(detect_conformance_platform "${os}")"
    runner="$(conformance_dir "${version}")/package/bin/conformance_test_runner-${platform}"

    if [ ! -f "${runner}" ]; then
        echo "conformance runner not found: ${runner}" >&2
        exit 1
    fi

    chmod +x "${runner}"
    exec "${runner}" "${@}"
}

cmd_paths() {
    local version="${1:-${PROTOBUF_VERSION}}"
    local os arch platform
    os="$(detect_os)"
    arch="$(detect_arch)"
    platform="$(detect_conformance_platform "${os}")"

    local protoc_d conformance_d
    protoc_d="$(protoc_dir "${version}")"
    conformance_d="$(conformance_dir "${version}")"

    echo "PROTOC=${protoc_d}/bin/protoc"
    echo "CONFORMANCE_RUNNER=${conformance_d}/package/bin/conformance_test_runner-${platform}"
    echo "PROTOC_INCLUDE=${protoc_d}/include"
    echo "CONFORMANCE_INCLUDE=${conformance_d}/package/include"
}

CMD="${1:-}"
shift || true

case "${CMD}" in
    setup)              cmd_setup "${@}" ;;
    protoc)             cmd_protoc "${@}" ;;
    conformance-runner) cmd_conformance_runner "${@}" ;;
    paths)              cmd_paths "${@}" ;;
    *)
        echo "Usage: $(basename "${0}") {setup|protoc|conformance-runner|paths} [args...]" >&2
        exit 1
        ;;
esac
