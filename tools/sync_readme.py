#!/usr/bin/env python3
# Regenerates the embedded code blocks in README.md from the real files in
# example/, and the version badges from build.zig.zon and the justfile

import argparse
import pathlib
import re
import sys
import textwrap

ROOT = pathlib.Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
BUILD_ZIG_ZON = ROOT / "build.zig.zon"

LANG_BY_SUFFIX = {".proto": "proto", ".zig": "zig"}

INCLUDE_RE = re.compile(r"<!-- include: (?P<path>[^\n]+) -->.*?<!-- /include -->", re.DOTALL)

ZIG_SECTION_RE = re.compile(
    r"// <!-- include -->\n(?P<body>.*?)\n[ \t]*// <!-- /include -->", re.DOTALL
)


def extract_zig_section(content: str) -> str:
    match = ZIG_SECTION_RE.search(content)
    if not match:
        return content.rstrip("\n")
    body = textwrap.dedent(match.group("body"))
    return body.strip("\n")


def fenced_block(path: pathlib.Path) -> str:
    lang = LANG_BY_SUFFIX.get(path.suffix, "")
    content = path.read_text()
    if path.suffix == ".zig":
        content = extract_zig_section(content)
    else:
        content = content.rstrip("\n")
    return f"```{lang}\n{content}\n```"


def sync_include(match: "re.Match[str]") -> str:
    rel_path = match.group("path").strip()
    path = ROOT / rel_path
    if not path.is_file():
        sys.exit(f"sync_readme: included file not found: {rel_path}")
    return f"<!-- include: {rel_path} -->\n{fenced_block(path)}\n<!-- /include -->"


# Shields.io uses `-` as a separator, so versions stop at the first `-`
VERSION = r"[^-/)\s]+"


def zig_version() -> str:
    regex = re.compile(r'\.minimum_zig_version\s*=\s*"(?P<version>[^"]+)"')
    match = regex.search(BUILD_ZIG_ZON.read_text())
    if not match:
        sys.exit("sync_readme: minimum_zig_version not found in build.zig.zon")
    return match.group("version")


def sync_badges(text: str, zig: str, protobuf: str) -> str:
    replacements = [
        (rf"(img\.shields\.io/badge/zig-){VERSION}(-)", zig),
        (rf"(img\.shields\.io/badge/protobuf-v){VERSION}(-)", protobuf),
        (rf"(protocolbuffers/protobuf/releases/tag/v){VERSION}(\))", protobuf),
    ]
    for pattern, version in replacements:
        text, count = re.subn(pattern, lambda m: f"{m.group(1)}{version}{m.group(2)}", text)
        if count == 0:
            sys.exit(f"sync_readme: badge pattern not found in README.md: {pattern}")
    return text


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--protobuf-version", required=True)
    args = parser.parse_args()

    text = README.read_text()
    text = INCLUDE_RE.sub(sync_include, text)
    text = sync_badges(text, zig_version(), args.protobuf_version)
    README.write_text(text)


if __name__ == "__main__":
    main()
