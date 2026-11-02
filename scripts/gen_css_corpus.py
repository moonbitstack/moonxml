#!/usr/bin/env python3
"""Generate MoonBit fixtures from the W3C CSS3 selectors test suite.

The suite is vendored from web-platform-tests' `css/selectors/old-tests` (the
CSS3 Selectors Test Suite, kept there as converted XHTML). Each file has a
`<style>` element whose rule under test paints elements lime, and a script that
asserts which element ids end up lime:

    assert_background_color('t1', LIME);          // t1 must match
    assert_not_background_color('u1', LIME);      // u1 must not match
    assert_equals(getComputedStyle(document.getElementById('t1'))
                    .backgroundColor, "rgb(0, 255, 0)");

so a case is (document, selector, ids that must match, ids that must not, the
`@namespace` declarations the selector's prefixes resolve against).

The colour argument decides the expectation, not the function's name: an
assertion that an element is *not* red says nothing about the lime rule, while
one that it is not lime says it must not match. The message argument carries
commas, so the arguments are split rather than matched by one regular
expression.

Files that need a pointer or a timer (`promise_test`, `test_driver`) or that
test a dynamic pseudo-class cannot be decided by a static query and are
skipped; the count is printed.

Usage: python3 scripts/gen_css_corpus.py <corpus-dir> src/conformance/css_cases_test.mbt
"""

from __future__ import annotations

import pathlib
import re
import sys

DYNAMIC = (":hover", ":active", ":focus", ":visited", ":target", ":link")


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


def style_text(text: str) -> str:
    blocks = re.findall(r"<style[^>]*>(.*?)</style>", text, re.S)
    joined = "\n".join(blocks)
    joined = joined.replace("<![CDATA[", "").replace("]]>", "")
    joined = re.sub(r"/\*.*?\*/", " ", joined, flags=re.S)
    return joined


def lime_selectors(css: str) -> list[str]:
    """The preludes of the rules that paint lime, with at-rules dropped."""
    out = []
    i = 0
    n = len(css)
    while i < n:
        j = css.find("{", i)
        if j < 0:
            break
        prelude = " ".join(css[i:j].split())
        depth = 1
        k = j + 1
        while k < n and depth > 0:
            if css[k] == "{":
                depth += 1
            elif css[k] == "}":
                depth -= 1
            k += 1
        body = css[j + 1 : k].lower()
        if prelude and not prelude.startswith("@"):
            paints = "lime" in body or "rgb(0, 255, 0)" in body
            # `background: lime` is the shorthand for `background-color`.
            if paints and ("background" in body or "color" in body):
                out.append(prelude)
        i = k
    return out


def namespace_decls(css: str) -> list[tuple[str, str]]:
    """The `@namespace` declarations: the prefix (`""` for the default) and URI."""
    out = []
    for m in re.finditer(
        r"@namespace\s+([A-Za-z_][\w-]*\s+)?(?:url\(\s*(['\"]?)([^'\")]*)\2\s*\)|(['\"])(.*?)\4)\s*;",
        css,
    ):
        prefix = (m.group(1) or "").strip()
        uri = (m.group(3) if m.group(3) is not None else m.group(5)) or ""
        out.append((prefix, uri))
    return out


def split_args(text: str) -> list[str]:
    """The arguments of a call, split at top-level commas."""
    out = []
    depth = 0
    quote = None
    run = []
    for ch in text:
        if quote:
            run.append(ch)
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
            run.append(ch)
        elif ch in "([{":
            depth += 1
            run.append(ch)
        elif ch in ")]}":
            depth -= 1
            run.append(ch)
        elif ch == "," and depth == 0:
            out.append("".join(run).strip())
            run = []
        else:
            run.append(ch)
    if run:
        out.append("".join(run).strip())
    return out


def call_arguments(script: str, name: str):
    """Every call of `name`, as its list of arguments."""
    out = []
    for m in re.finditer(r"\b" + name + r"\s*\(", script):
        depth = 1
        i = m.end()
        while i < len(script) and depth > 0:
            ch = script[i]
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            elif ch in "'\"":
                quote = ch
                i += 1
                while i < len(script) and script[i] != quote:
                    i += 1
            i += 1
        out.append(split_args(script[m.end() : i - 1]))
    return out


def is_lime(arg: str) -> bool:
    flat = arg.strip().strip("'\"").lower().replace(" ", "")
    return flat in ("lime", "rgb(0,255,0)")


def asserted_ids(script: str):
    """The ids the script expects to match and not to match."""
    env = {}
    for m in re.finditer(
        r"(?:const|let|var)\s+(\w+)\s*=\s*document\.getElementById\(\s*['\"]([^'\"]+)['\"]\s*\)",
        script,
    ):
        env[m.group(1)] = m.group(2)

    def resolve(expr: str):
        expr = expr.strip()
        m = re.match(r"document\.getElementById\(\s*['\"]([^'\"]+)['\"]\s*\)$", expr)
        if m:
            return m.group(1)
        return env.get(expr)

    expect = []
    reject = []

    # The colour argument decides: a lime assertion wants a match, "not lime"
    # wants none, and any other colour says the element must not be lime.
    for name, negated in (
        ("assert_background_color", False),
        ("assert_not_background_color", True),
    ):
        for args in call_arguments(script, name):
            if len(args) < 2:
                continue
            ident = args[0].strip().strip("'\"")
            lime = is_lime(args[1])
            if lime and not negated:
                expect.append(ident)
            elif negated and not lime:
                # "not red" says nothing about whether the lime rule matched.
                pass
            else:
                reject.append(ident)

    # The older spelling: assert_equals on the computed background colour.
    for name, negated in (("assert_equals", False), ("assert_not_equals", True)):
        for args in call_arguments(script, name):
            if len(args) < 2 or not is_lime(args[1]):
                continue
            target = re.match(
                r"getComputedStyle\(\s*(.*?)\s*\)\s*\.backgroundColor$", args[0], re.S
            )
            if target is None:
                continue
            ident = resolve(target.group(1))
            if ident is None:
                continue
            if negated:
                reject.append(ident)
            else:
                expect.append(ident)
    return expect, reject


def main() -> int:
    corpus = pathlib.Path(sys.argv[1])
    out_path = pathlib.Path(sys.argv[2])

    files = sorted(p for p in corpus.glob("*.xml") if p.is_file())
    if not files:
        print("no corpus files under", corpus, file=sys.stderr)
        return 1

    docs = {}
    cases = []
    skipped = {"interaction": 0, "dynamic": 0, "no-lime-rule": 0, "no-ids": 0}

    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        name = path.name
        if "promise_test" in text or "test_driver" in text:
            skipped["interaction"] += 1
            continue
        style = style_text(text)
        selectors = lime_selectors(style)
        if not selectors:
            skipped["no-lime-rule"] += 1
            continue
        scripts = "\n".join(re.findall(r"<script[^>]*>(.*?)</script>", text, re.S))
        scripts = scripts.replace("<![CDATA[", "").replace("]]>", "")
        expect, reject = asserted_ids(scripts)
        if not expect and not reject:
            skipped["no-ids"] += 1
            continue
        usable = [s for s in selectors if not any(p in s.lower() for p in DYNAMIC)]
        if not usable:
            skipped["dynamic"] += 1
            continue
        decls = ";".join("%s=%s" % (prefix, uri) for prefix, uri in namespace_decls(style))
        docs[name] = text
        for sel in usable:
            cases.append((name, sel, sorted(set(expect)), sorted(set(reject)), decls))

    lines = [
        "// Generated by scripts/gen_css_corpus.py. Do not edit: change the corpus or the generator.",
        "",
        "///|",
        "/// One rule from the W3C CSS3 selectors suite: the selector, the ids the",
        "/// test asserts must and must not match it, and the namespaces its",
        "/// prefixes resolve against, written `prefix=uri` and joined with `;`.",
        "struct CssSelectorCase {",
        "  file : String",
        "  selector : String",
        "  expect : String",
        "  reject : String",
        "  namespaces : String",
        "}",
        "",
        "///|",
        "/// The test documents, by file name.",
        "fn css_selector_docs() -> Array[(String, String)] {",
        "  [",
    ]
    for name in sorted(docs):
        lines.append("    (")
        lines.append('      "%s", "%s",' % (esc(name), esc(docs[name])))
        lines.append("    ),")
    lines.append("  ]")
    lines.append("}")
    lines.append("")
    lines.append("///|")
    lines.append("/// Every rule under test, in file order.")
    lines.append("fn css_selector_cases() -> Array[CssSelectorCase] {")
    lines.append("  [")
    for name, sel, expect, reject, decls in cases:
        lines.append("    {")
        lines.append('      file: "%s",' % esc(name))
        lines.append('      selector: "%s",' % esc(sel))
        lines.append('      expect: "%s",' % ",".join(expect))
        lines.append('      reject: "%s",' % ",".join(reject))
        lines.append('      namespaces: "%s",' % esc(decls))
        lines.append("    },")
    lines.append("  ]")
    lines.append("}")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(
        "wrote %s (%d cases from %d documents, skipped %s)"
        % (out_path, len(cases), len(docs), skipped)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
