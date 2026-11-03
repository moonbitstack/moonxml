#!/usr/bin/env python3
"""Check that the README's caller-side snippets compile.

Most snippets in the README use only this library, so they would compile in a
project that installed nothing else. The ones that pull in another package are
marked with `<!-- check: caller -->` above the fence: they are written for a
caller, whose own project depends on both packages, and this script builds
exactly that project — a workspace holding this checkout plus a throwaway
module — and runs `moon check` on it.

    python3 scripts/check_caller_snippet.py

The module is built in the system temporary directory and removed afterwards,
so nothing is left in the repository.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MARK = "<!-- check: caller -->"

# Pinned the way the documentation requires; only the snippet's own project
# needs it, so the library keeps its single dependency.
REGEX_VERSION = "0.1.3"


def module_version() -> str:
    with open(os.path.join(ROOT, "moon.mod"), encoding="utf-8") as handle:
        found = re.search(r'^version\s*=\s*"([^"]+)"', handle.read(), re.M)
    return found.group(1) if found else "0.1.0"


def caller_snippets(text: str) -> list[str]:
    """Every MoonBit block the README marks as a caller-side one."""
    out = []
    for match in re.finditer(re.escape(MARK), text):
        start = text.find("```moonbit\n", match.end())
        if start < 0:
            continue
        start += len("```moonbit\n")
        end = text.find("```", start)
        if end < 0:
            continue
        out.append(text[start:end])
    return out


def write(path: str, body: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(body)


def main() -> int:
    with open(os.path.join(ROOT, "README.md"), encoding="utf-8") as handle:
        snippets = caller_snippets(handle.read())
    if not snippets:
        print("no caller-side snippet to check")
        return 0

    version = module_version()
    failed = 0
    for index, snippet in enumerate(snippets):
        work = tempfile.mkdtemp(prefix="moonxml-caller-")
        try:
            snippet_dir = os.path.join(work, "snippet")
            write(
                os.path.join(work, "moon.work"),
                "members = [\n"
                f'  "{ROOT.replace(os.sep, "/")}",\n'
                '  "snippet",\n'
                "]\n",
            )
            write(
                os.path.join(snippet_dir, "moon.mod"),
                f'name = "moonbitstack/moonxml-caller-check"\n'
                'version = "0.1.0"\n'
                'source = "src"\n'
                "\n"
                "import {\n"
                f'  "moonbitstack/moonxml@{version}",\n'
                f'  "moonbitstack/moonregex@{REGEX_VERSION}",\n'
                "}\n",
            )
            packages = {
                "@moonxml": "moonbitstack/moonxml",
                "@html": "moonbitstack/moonxml/html",
                "@xml": "moonbitstack/moonxml/xml",
                "@event": "moonbitstack/moonxml/event",
                "@htmx": "moonbitstack/moonxml/htmx",
                "@moonregex": "moonbitstack/moonregex",
            }
            # Only what the snippet names, so the check has no unused import.
            used = [
                (alias, path)
                for alias, path in packages.items()
                if f"{alias}." in snippet
            ]
            imports = "".join(
                f'  "{path}" {alias},\n' for alias, path in sorted(used)
            )
            write(
                os.path.join(snippet_dir, "src", "moon.pkg"),
                "import {\n" + imports + "}\n" "\n" "options(\n  is_main: true,\n)\n",
            )
            # The README writes statements, the way a reader would type them.
            # A caller's entry point is where they go.
            body = snippet.rstrip("\n")
            indented = "\n".join(
                ("  " + line) if line.strip() else "" for line in body.split("\n")
            )
            write(
                os.path.join(snippet_dir, "src", "main.mbt"),
                "fn main raise {\n" + indented + "\n}\n",
            )
            result = subprocess.run(
                ["moon", "check"], cwd=snippet_dir, capture_output=True, text=True
            )
            if result.returncode != 0:
                failed += 1
                print(f"snippet {index + 1} does not compile:")
                print(result.stdout + result.stderr)
            else:
                print(f"snippet {index + 1} compiles")
        finally:
            shutil.rmtree(work, ignore_errors=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
