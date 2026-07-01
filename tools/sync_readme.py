#!/usr/bin/env python3
# Regenerates the embedded code blocks in README.md from the real files in
# example/

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
README = ROOT / "README.md"

LANG_BY_SUFFIX = {".proto": "proto", ".zig": "zig"}

INCLUDE_RE = re.compile(r"<!-- include: (?P<path>[^\n]+) -->.*?<!-- /include -->", re.DOTALL)


def fenced_block(path: pathlib.Path) -> str:
    lang = LANG_BY_SUFFIX.get(path.suffix, "")
    content = path.read_text().rstrip("\n")
    return f"```{lang}\n{content}\n```"


def sync_include(match: "re.Match[str]") -> str:
    rel_path = match.group("path").strip()
    path = ROOT / rel_path
    if not path.is_file():
        sys.exit(f"sync_readme: included file not found: {rel_path}")
    return f"<!-- include: {rel_path} -->\n{fenced_block(path)}\n<!-- /include -->"


def main() -> None:
    text = README.read_text()
    text = INCLUDE_RE.sub(sync_include, text)
    README.write_text(text)


if __name__ == "__main__":
    main()
