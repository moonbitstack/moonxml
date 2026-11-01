#!/usr/bin/env python3
"""Check the source tree for text problems a compiler will not notice.

`moon fmt --check` cannot be a gate here: the formatter rewrites the generated
fixtures into one field per line, which is not what this repository wants. These
checks cover what review actually trips over — trailing whitespace, tabs,
carriage returns, a missing final newline — and the one style rule the project
states outright: no emoji anywhere.
"""

import io
import os
import sys

SOURCES = (".mbt", ".moon", ".yml", ".yaml", ".md", ".py", ".toml")
SKIP_DIRS = {".git", "_build", ".repos", "__pycache__"}
# The vendored corpus is third-party data, checked against upstream instead.
SKIP_PATHS = ("vendor/",)

# Ranges that hold the pictographic characters an editor inserts by accident.
# The corpus fixtures are excluded below: they carry stars, cards and check marks
# as test data, and those are not a style choice.
EMOJI_RANGES = (
    (0x1F300, 0x1FAFF),
    (0x1F000, 0x1F0FF),
    (0x1F1E6, 0x1F1FF),
    (0xFE0F, 0xFE0F),
)

GENERATED = (
    "tests/html5lib_cases.mbt",
    "tests/tokenizer_cases.mbt",
    "html/entities.mbt",
)


def is_emoji(ch):
    code = ord(ch)
    return any(lo <= code <= hi for lo, hi in EMOJI_RANGES)


def files():
    for base, dirs, names in os.walk("."):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in names:
            if not name.endswith(SOURCES):
                continue
            path = os.path.join(base, name)[2:].replace(os.sep, "/")
            if path.startswith(SKIP_PATHS):
                continue
            yield path


def main():
    problems = []
    for path in sorted(files()):
        with io.open(path, "rb") as f:
            raw = f.read()
        if raw.startswith(b"\xef\xbb\xbf"):
            problems.append((path, 1, "byte order mark"))
        if b"\r" in raw:
            problems.append((path, 0, "carriage return (the tree is LF)"))
        if raw and not raw.endswith(b"\n"):
            problems.append((path, 0, "no final newline"))
        text = raw.decode("utf-8").replace("\r\n", "\n")
        for number, line in enumerate(text.split("\n"), start=1):
            if line != line.rstrip():
                problems.append((path, number, "trailing whitespace"))
            if "\t" in line:
                problems.append((path, number, "tab"))
            for ch in line if path not in GENERATED else "":
                if is_emoji(ch):
                    problems.append((path, number, "emoji"))
                    break
    for path, line, why in problems:
        print("%s:%d: %s" % (path, line, why))
    if problems:
        print("%d problem(s)" % len(problems))
        return 1
    print("clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
