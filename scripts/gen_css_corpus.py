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

so a case is (document, selector, ids that must match, ids that must not).

Files that need a pointer or a timer (`promise_test`, `test_driver`) or that
test a dynamic pseudo-class cannot be decided by a static query and are
skipped; the count is printed.

Usage: python3 scripts/gen_css_corpus.py <corpus-dir> src/conformance/css_cases_test.mbt
"""

from __future__ import annotations

import pathlib
import re
import sys

CORPUS = pathlib.Path(sys.argv[1])
OUT = pathlib.Path(sys.argv[2])

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

    def is_lime(arg: str) -> bool:
        a = arg.strip().strip("'\"").lower().replace(" ", "")
        return a in ("lime", "rgb(0,255,0)")

    # The colour argument decides the expectation: `assert_background_color('t4',
    # 'rgba(0, 0, 0, 0)')` asserts that t4 is *not* painted lime.
    for m in re.finditer(
        r"assert_(not_)?background_color\(\s*['\"]([^'\"]+)['\"]\s*,\s*([^)]*)\)", script
    ):
        negated = m.group(1) is not None
        ident = m.group(2)
        lime = is_lime(m.group(3))
        if lime and not negated:
            # The element is painted lime, so it must match the rule.
            expect.append(ident)
        elif negated and not lime:
            # "not red" says nothing about whether the lime rule matched.
            pass
        else:
            # Painted some other colour, or explicitly not lime: it must not
            # match the rule under test.
            reject.append(ident)
    for m in re.finditer(
        r"assert_(not_)?equals\(\s*getComputedStyle\(\s*"
        r"(document\.getElementById\(\s*['\"][^'\"]+['\"]\s*\)|\w+)\s*\)\.backgroundColor\s*,\s*"
        r"[\"'](?:rgb\(0, 255, 0\)|lime)[\"']",
        script,
    ):
        name = m.group(1)
        ident = resolve(m.group(2))
        if ident is None:
            continue
        if name:
            reject.append(ident)
        else:
            expect.append(ident)
    return expect, reject


def main() -> int:
    files = sorted(p for p in CORPUS.glob("*.xml") if p.is_file())
    if not files:
        print("no corpus files under", CORPUS, file=sys.stderr)
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
        selectors = lime_selectors(style_text(text))
        if not selectors:
            skipped["no-lime-rule"] += 1
            continue
        scripts = "\n".join(re.findall(r"<script[^>]*>(.*?)</script>", text, re.S))
        scripts = scripts.replace("<![CDATA[", "").replace("]]>", "")
        expect, reject = asserted_ids(scripts)
        if not expect and not reject:
            skipped["no-ids"] += 1
            continue
        usable = []
        for sel in selectors:
            low = sel.lower()
            if any(p in low for p in DYNAMIC):
                continue
            usable.append(sel)
        if not usable:
            skipped["dynamic"] += 1
            continue
        docs[name] = text
        for sel in usable:
            cases.append((name, sel, sorted(set(expect)), sorted(set(reject))))

    lines = [
        "// Generated by scripts/gen_css_selector_cases.py from css-selectors.",
        "// Do not edit: change the corpus or the generator and run it again.",
        "",
        "/// One rule from the W3C CSS3 selectors suite: the selector, and the ids",
        "/// the test asserts must and must not match it.",
        "pub struct CssSelectorCase {",
        "  file : String",
        "  selector : String",
        "  expect : String",
        "  reject : String",
        "}",
        "",
        "/// The test documents, by file name.",
        "pub fn css_selector_docs() -> Array[(String, String)] {",
        "  [",
    ]
    for name in sorted(docs):
        lines.append('    ("%s", "%s"),' % (esc(name), esc(docs[name])))
    lines.append("  ]")
    lines.append("}")
    lines.append("")
    lines.append("pub fn css_selector_cases() -> Array[CssSelectorCase] {")
    lines.append("  [")
    for name, sel, expect, reject in cases:
        lines.append(
            '    { file: "%s", selector: "%s", expect: "%s", reject: "%s" },'
            % (esc(name), esc(sel), ",".join(expect), ",".join(reject))
        )
    lines.append("  ]")
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(
        "wrote %s (%d cases from %d documents, skipped %s)"
        % (OUT.relative_to(ROOT), len(cases), len(docs), skipped)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
