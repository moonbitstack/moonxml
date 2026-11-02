#!/usr/bin/env python3
"""Generate MoonBit fixtures from the vendored libxml2 XPath corpus.

The corpus is libxml2's own conformance set: `test/XPath/expr/<name>` is a list
of expressions evaluated with no document, `test/XPath/tests/<name>` is a list
of expressions evaluated against `test/XPath/docs/<doc>`, and the matching file
under `result/XPath/` records what libxml2 produced. A result block looks like:

    ========================
    Expression: /child::*
    Object is a Node Set :
    Set contains 1 nodes:
    1  ELEMENT EXAMPLE
    ...

so a case has a kind (boolean, number, string, node-set) and a value; a
node-set's value is its size plus the kind and name of each top-level node,
which is what a different implementation can be compared on.

Usage: python3 scripts/gen_xpath_corpus.py <corpus-dir> src/conformance/xpath_cases_test.mbt
"""

from __future__ import annotations

import pathlib
import sys

CORPUS = pathlib.Path(sys.argv[1])
OUT = pathlib.Path(sys.argv[2])

SEPARATOR = "========================\n"


def esc(s: str) -> str:
    out = []
    for ch in s:
        o = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif o < 0x20:
            out.append("\\u{%X}" % o)
        else:
            out.append(ch)
    return "".join(out)


def expressions(path: pathlib.Path) -> list[str]:
    """The expression list: one per line, with blanks and comments removed."""
    lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
    return [l for l in lines if l.strip() and not l.lstrip().startswith("#")]


def blocks(path: pathlib.Path) -> list[list[str]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    parts = [b for b in text.split(SEPARATOR) if b.strip()]
    return [b.split("\n") for b in parts]


def parse_value(body: list[str]):
    """Return (kind, value, nodes) for one result block."""
    kind = ""
    value = ""
    nodes = []
    for line in body:
        if line.startswith("Expression:"):
            continue
        if line.startswith("Object is a Boolean"):
            kind = "bool"
            value = line.split(":", 1)[1].strip().lower()
            break
        if line.startswith("Object is a number"):
            kind = "num"
            value = line.split(":", 1)[1].strip()
            break
        if line.startswith("Object is a string"):
            kind = "str"
            value = line.split(":", 1)[1].strip()
            break
        if line.startswith("Object is a Node Set"):
            kind = "nodes"
            in_set = False
            for inner in body[body.index(line) + 1 :]:
                if inner.startswith("Set contains "):
                    value = inner.split()[2]
                    in_set = True
                    continue
                if not in_set:
                    continue
                # A top-level node: "<index>  KIND [name]". Indented lines
                # describe children, attributes and text of the node above.
                if inner[:1].strip() == "" and inner.strip():
                    continue
                stripped = inner.strip()
                if not stripped:
                    continue
                parts = stripped.split()
                if len(parts) < 2 or not parts[0].isdigit():
                    continue
                nkind = parts[1]
                name = parts[2] if len(parts) > 2 else ""
                if nkind == "ELEMENT":
                    nodes.append("ELEMENT " + unescape_name(name))
                elif nkind == "TEXT":
                    nodes.append("TEXT")
                elif nkind == "COMMENT":
                    nodes.append("COMMENT")
                elif nkind == "CDATA_SECTION":
                    nodes.append("CDATA")
                elif nkind == "PI":
                    nodes.append("PI " + unescape_name(name))
                elif nkind == "ATTRIBUTE":
                    nodes.append("ATTRIBUTE " + unescape_name(name))
                elif nkind == "namespace":
                    nodes.append("NAMESPACE")
                elif nkind == "/":
                    # The root node is printed as `1   /`: the label is `/`.
                    nodes.append("/")
                else:
                    nodes.append(nkind + " " + name)
            break
    return kind, value, nodes


def unescape_name(name: str) -> str:
    """libxml2 writes a non-ASCII name as its UTF-8 bytes in `#HH` form."""
    out = []
    raw = bytearray()
    i = 0
    while i < len(name):
        if name[i] == "#" and i + 2 < len(name) + 1 and len(name[i + 1 : i + 3]) == 2:
            try:
                raw.append(int(name[i + 1 : i + 3], 16))
                i += 3
                continue
            except ValueError:
                pass
        if raw:
            out.append(raw.decode("utf-8", errors="replace"))
            raw = bytearray()
        out.append(name[i])
        i += 1
    if raw:
        out.append(raw.decode("utf-8", errors="replace"))
    return "".join(out)


def doc_for(test_name: str, docs: list[str]) -> str:
    """The document a test file is evaluated against: the longest name prefix."""
    best = ""
    for d in docs:
        if test_name.startswith(d) and len(d) > len(best):
            best = d
    return best


def main() -> int:
    docs = sorted(p.name for p in (CORPUS / "docs").iterdir() if p.is_file())
    doc_text = {d: (CORPUS / "docs" / d).read_text(encoding="utf-8", errors="replace") for d in docs}

    cases = []
    skipped = 0

    for path in sorted((CORPUS / "expr").iterdir()):
        if not path.is_file():
            continue
        result = CORPUS / "result-expr" / path.name
        exprs = expressions(path)
        for expr, body in zip(exprs, blocks(result)):
            kind, value, nodes = parse_value(body)
            if kind == "":
                skipped += 1
                continue
            cases.append(("expr/" + path.name, "", expr, kind, value, nodes))

    for path in sorted((CORPUS / "tests").iterdir()):
        if not path.is_file():
            continue
        result = CORPUS / "result-tests" / path.name
        doc = doc_for(path.name, docs)
        if doc == "":
            print("no document for", path.name, file=sys.stderr)
            return 1
        exprs = expressions(path)
        for expr, body in zip(exprs, blocks(result)):
            kind, value, nodes = parse_value(body)
            if kind == "":
                skipped += 1
                continue
            cases.append(("tests/" + path.name, doc, expr, kind, value, nodes))

    lines = [
        "// Generated by scripts/gen_xpath_corpus.py. Do not edit: change the corpus or the generator.",
        "",
        "///|",
        "/// One expression from the libxml2 XPath corpus, with what libxml2",
        "/// produced for it. `kind` is `bool`, `num`, `str` or `nodes`; for a",
        "/// node-set `value` is the size and `nodes` the kind and name of each",
        "/// top-level node, joined with `|`.",
        "struct XPathCase {",
        "  file : String",
        "  doc : String",
        "  expr : String",
        "  kind : String",
        "  value : String",
        "  nodes : String",
        "}",
        "",
        "///|",
        "/// The documents the cases are evaluated against, by name.",
        "fn xpath_docs() -> Array[(String, String)] {",
        "  [",
    ]
    for name in docs:
        lines.append("    (")
        lines.append('      "%s", "%s",' % (esc(name), esc(doc_text[name])))
        lines.append("    ),")
    lines.append("  ]")
    lines.append("}")
    lines.append("")
    lines.append("///|")
    lines.append("fn xpath_cases() -> Array[XPathCase] {")
    lines.append("  [")
    for file, doc, expr, kind, value, nodes in cases:
        lines.append("    {")
        lines.append('      file: "%s",' % esc(file))
        lines.append('      doc: "%s",' % esc(doc))
        lines.append('      expr: "%s",' % esc(expr))
        lines.append('      kind: "%s",' % kind)
        lines.append('      value: "%s",' % esc(value))
        lines.append('      nodes: "%s",' % esc("|".join(nodes)))
        lines.append("    },")
    lines.append("  ]")
    lines.append("}")
    body = "\n".join(lines) + "\n"
    OUT.write_text(body, encoding="utf-8", newline="\n")
    print("wrote %s (%d cases, %d skipped)" % (OUT, len(cases), skipped))
    return 0


if __name__ == "__main__":
    sys.exit(main())
