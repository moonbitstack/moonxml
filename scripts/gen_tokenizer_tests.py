#!/usr/bin/env python3
"""Generate MoonBit fixtures from the vendored html5lib tokenizer corpus.

The corpus format is documented in vendor/html5lib-tests/tokenizer/README.md.
Run from the repository root:

    python scripts/gen_tokenizer_tests.py

It writes tests/tokenizer_cases.mbt. Every token is flattened to one string so
the MoonBit side compares lists of strings instead of a nested JSON shape:

    c<data>                          character data
    s<name> <attr> <attr>            start tag, attributes as name=value
    e<name>                          end tag
    m<data>                          comment
    d<name> <public> <system> <ok>   doctype; nulls are marked with a leading ~

Fields are separated by U+001F, which cannot appear in a token in practice and
is escaped anyway.

Excluded: xmlViolationTests (they describe the XML infoset tweaks, not
tokenization), and the legacy ProcessingInstruction cases, which contradict the
same repository's tree-construction corpus: `<?COMMENT?>` is a processing
instruction in tokenizer/test2.test but a comment in tree-construction. The
specification has no processing instruction token, so the comment reading wins
and those cases are reported separately instead of counted.
"""

from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORPUS = ROOT / "vendor" / "html5lib-tests" / "tokenizer"
OUT = ROOT / "tests" / "tokenizer_cases.mbt"

US = "\x1f"
STATES = {
    "Data state": "data",
    "PLAINTEXT state": "plaintext",
    "RCDATA state": "rcdata",
    "RAWTEXT state": "rawtext",
    "Script data state": "script",
    "CDATA section state": "cdata",
}


def unescape_double(s: str) -> str:
    """Undo the extra level of `\\uHHHH` escaping the corpus asks for."""
    out = []
    i = 0
    n = len(s)
    while i < n:
        if s[i] == "\\" and i + 5 < n and s[i + 1] == "u":
            hexpart = s[i + 2 : i + 6]
            try:
                out.append(chr(int(hexpart, 16)))
                i += 6
                continue
            except ValueError:
                pass
        out.append(s[i])
        i += 1
    return "".join(out)


def has_surrogate(s: str) -> bool:
    return any(0xD800 <= ord(ch) <= 0xDFFF for ch in s)


def esc(s: str) -> str:
    out = []
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif ch == US:
            out.append("\\u{1F}")
        elif ord(ch) < 0x20:
            out.append("\\u{%X}" % ord(ch))
        else:
            out.append(ch)
    return "".join(out)


def enc_opt(v) -> str:
    if v is None:
        return "~"
    return "=" + esc(v)


def enc_token(tok) -> str:
    kind = tok[0]
    if kind == "Character":
        return "c" + esc(tok[1])
    if kind == "Comment":
        return "m" + esc(tok[1])
    if kind == "EndTag":
        return "e" + esc(tok[1])
    if kind == "StartTag":
        parts = ["s" + esc(tok[1])]
        for k, v in tok[2].items():
            parts.append(esc(k) + "=" + esc(v))
        if len(tok) > 3 and tok[3]:
            parts.append("/")
        return US.join(parts)
    if kind == "DOCTYPE":
        name, pub, sys, ok = tok[1], tok[2], tok[3], tok[4]
        return US.join(["d" + enc_opt(name), enc_opt(pub), enc_opt(sys), "1" if ok else "0"])
    raise SystemExit(f"unknown token kind {kind}")


def parse_file(path: pathlib.Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    if "xmlViolationTests" in data:
        return [], 0
    cases = []
    excluded = 0
    for test in data["tests"]:
        out = test["output"]
        # Legacy processing instructions: see the module docstring.
        if any(tok[0] == "ProcessingInstruction" for tok in out):
            excluded += 1
            continue
        inp = test["input"]
        if test.get("doubleEscaped"):
            inp = unescape_double(inp)
            out = [
                [unescape_double(v) if isinstance(v, str) else v for v in tok]
                for tok in out
            ]
        # A lone surrogate cannot be written to a UTF-8 source file; the case
        # exists to pin JavaScript string handling, not HTML tokenization.
        if has_surrogate(inp) or any(
            has_surrogate(v) for tok in out for v in tok if isinstance(v, str)
        ):
            excluded += 1
            continue
        states = [STATES[s] for s in test.get("initialStates", ["Data state"])]
        last = test.get("lastStartTag", "").lower()
        expected = [enc_token(tok) for tok in out]
        for st in states:
            cases.append(
                {
                    "file": path.name,
                    "desc": test.get("description", ""),
                    "input": inp,
                    "state": st,
                    "last": last,
                    "expected": expected,
                }
            )
    return cases, excluded


def main() -> int:
    cases = []
    excluded = 0
    per_file = {}
    for path in sorted(CORPUS.glob("*.test")):
        got, ex = parse_file(path)
        excluded += ex
        if got:
            per_file[path.name] = len(got)
        cases.extend(got)
    if not cases:
        print("no cases parsed", file=sys.stderr)
        return 1

    lines = [
        "/// Generated by scripts/gen_tokenizer_tests.py from the vendored",
        "/// html5lib tokenizer corpus. Do not edit by hand.",
        "",
        "pub struct TokCase {",
        "  file : String",
        "  desc : String",
        "  input : String",
        "  state : String",
        "  last : String",
        "  expected : Array[String]",
        "}",
        "",
        "pub fn tok_cases() -> Array[TokCase] {",
        "  [",
    ]
    for c in cases:
        exp = ", ".join('"' + esc_one(t) + '"' for t in c["expected"])
        lines.append(
            "    { file: %s, desc: %s, input: %s, state: %s, last: %s, expected: [%s] },"
            % (
                mb(c["file"]),
                mb(c["desc"]),
                mb(c["input"]),
                mb(c["state"]),
                mb(c["last"]),
                exp,
            )
        )
    lines.append("  ]")
    lines.append("}")
    lines.append("")
    OUT.write_text("\n".join(lines), encoding="utf-8")
    total = sum(per_file.values())
    print(f"wrote {total} tokenizer cases to {OUT} ({OUT.stat().st_size} bytes)")
    print(f"excluded {excluded} legacy processing-instruction cases")
    for name in sorted(per_file):
        print(f"  {name}: {per_file[name]}")
    return 0


def esc_one(s: str) -> str:
    """Escape a pre-encoded token string for a MoonBit string literal."""
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
        elif o < 0x20 or o == 0x1F:
            out.append("\\u{%X}" % o)
        else:
            out.append(ch)
    return "".join(out)


def mb(s: str) -> str:
    return '"' + esc_one(s) + '"'


if __name__ == "__main__":
    raise SystemExit(main())
