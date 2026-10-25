#!/usr/bin/env python3
"""Generate site/api.html from the packages' generated interfaces.

`moon info` writes one `pkg.generated.mbti` per package; that file *is* the
public API, so the reference page is generated from it rather than written by
hand and left to drift. Run after `moon info`:

    moon info --target all
    python3 scripts/make_api_docs.py
"""

import html
import os
import re
import sys

PACKAGES = [
    ("moonxml", "pkg.generated.mbti",
     "The tree, the chain, and the two engines. Everything you need unless you are reading a document."),
    ("moonxml/html", "html/pkg.generated.mbti",
     "The WHATWG parser: tolerant, repairing, and never refusing."),
    ("moonxml/xml", "xml/pkg.generated.mbti",
     "The XML 1.0 parser: strict, with namespaces, and with the offset of the fault."),
    ("moonxml/event", "event/pkg.generated.mbti",
     "The streaming vocabulary — what a parser emits and what a sink receives."),
]

KEYWORDS = (
    "pub", "fn", "struct", "enum", "trait", "impl", "let", "mut", "priv", "all", "open",
    "extend", "with", "suberror", "type", "typealias", "async", "const",
)

GROUPS = {
    "Values": "values",
    "Errors": "errors",
    "Types and methods": "types",
    "Type aliases": "aliases",
    "Traits": "traits",
}


def parse(path):
    """Yield (section, signature) pairs, one per top-level item."""
    out = []
    section = None
    current = []
    depth = 0
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            stripped = line.strip()
            if line.startswith("// ") and not line.startswith("///"):
                if depth == 0:
                    section = GROUPS.get(line[3:].strip())
                continue
            if depth == 0 and (
                line.startswith("// Generated")
                or line.startswith("package ")
                or line.startswith("import {")
                or line == "}"
                or stripped == ""
            ):
                if line == "}" and current:
                    out.append((section, current))
                    current = []
                continue
            if depth == 0 and current and not line.startswith(" "):
                out.append((section, current))
                current = []
            current.append(line)
            depth += line.count("{") + line.count("(") - line.count("}") - line.count(")")
            if depth < 0:
                depth = 0
    if current:
        out.append((section, current))
    return [(s, "\n".join(body)) for s, body in out if s]


def highlight(sig):
    text = html.escape(sig)
    for word in KEYWORDS:
        text = re.sub(r"\b%s\b" % word, '<span class="kw">%s</span>' % word, text, count=1)
    text = re.sub(r"\b([A-Z][A-Za-z0-9_]*)\b", r'<span class="ty">\1</span>', text)
    return text


def item_title(sig):
    match = re.match(r"(?:pub\S*\s+)?(?:fn|struct|enum|trait|suberror|type)\s+([A-Za-z0-9_:]+)", sig)
    if match:
        return match.group(1)
    return sig.split("(")[0]


def render(pkg, path, intro, out):
    items = parse(path)
    out.append('<section id="%s">' % pkg.replace("/", "-"))
    out.append('<div class="sec-head"><h2>%s</h2></div>' % html.escape(pkg))
    out.append('<p class="sub">%s</p>' % html.escape(intro))

    by_group = {}
    for section, sig in items:
        by_group.setdefault(section, []).append(sig)

    for section in ("traits", "errors", "types", "aliases", "values"):
        group = by_group.get(section)
        if not group:
            continue
        out.append('<h3 class="group" data-group="%s">%s</h3>' % (section, section.capitalize()))
        for sig in group:
            title = item_title(sig)
            anchor = "%s-%s" % (pkg.replace("/", "-"), re.sub(r"[^A-Za-z0-9]+", "-", title).lower())
            kind = "type" if "{" in sig else "fn"
            out.append('<div class="api-item" id="%s" data-kind="%s">' % (anchor, kind))
            out.append('<span class="kind">%s</span>' % ("type" if kind == "type" else "fn"))
            out.append('<pre><span class="sig">%s</span></pre>' % highlight(sig))
            out.append("</div>")
    out.append("</section>")

    return [
        (pkg.replace("/", "-"), pkg.split("/")[-1], g, [item_title(s) for s in group])
        for g, group in by_group.items()
    ]


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    out_path = os.path.join(root, "site", "api.html")

    body = []
    nav = []
    total = 0
    for pkg, rel, intro in PACKAGES:
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            print("missing %s — run `moon info --target all` first" % rel, file=sys.stderr)
            continue
        groups = render(pkg, path, intro, body)
        for anchor, short, group, names in groups:
            nav.append((anchor, short, group, names))
            total += len(names)

    # one nav entry per package, with its groups beneath
    seen = []
    for anchor, short, group, names in nav:
        if not seen or seen[-1][0] != anchor:
            seen.append((anchor, short, []))
        seen[-1][2].append((group, names))

    nav_html = []
    for anchor, short, groups in seen:
        nav_html.append('<h4><a href="#%s">%s</a></h4>' % (anchor, html.escape(short)))
        for group, names in groups:
            for name in names:
                target = "%s-%s" % (anchor, re.sub(r"[^A-Za-z0-9]+", "-", name).lower())
                nav_html.append('<a href="#%s">%s</a>' % (target, html.escape(name)))

    page = (
        TEMPLATE.replace("__NAV__", "\n".join(nav_html))
        .replace("__BODY__", "\n".join(body))
        .replace("__TOTAL__", str(total))
    )
    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write(page)
    print("%d items written to %s" % (total, out_path))


TEMPLATE = """<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>API — moonxml</title>
<meta name="description" content="Every public type, trait and function in moonxml, generated from the packages' interfaces.">
<link rel="stylesheet" href="assets/site.css">
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><text y='13' font-size='14' font-family='monospace' fill='%237d2f22'>&lt;/&gt;</text></svg>">
</head>
<body>

<header class="top">
  <div class="wrap">
    <a class="brand" href="index.html"><span class="lt">&lt;</span><b>moonxml</b><span class="gt">/&gt;</span></a>
    <nav class="top-nav">
      <a href="start.html">Start</a>
      <a href="api.html" aria-current="page">API</a>
      <a href="inside.html">Inside</a>
      <a class="hide-sm" href="https://github.com/moonbitstack/moonxml">GitHub</a>
      <button class="theme-toggle" id="theme" title="Switch theme" aria-label="Switch theme">◐</button>
    </nav>
  </div>
</header>

<main class="wrap" style="padding-top:44px">
  <p class="eyebrow">__TOTAL__ public items</p>
  <h1 style="font-size:clamp(32px,4vw,44px);margin-bottom:10px">The API</h1>
  <p class="sub">Generated from each package's interface file, so it cannot describe something the code does not have — or miss something it does.</p>
  <div class="colophon-line">
    <span><b>four packages</b></span><span class="sep">·</span>
    <span>every public item</span><span class="sep">·</span>
    <span>generated, not typed</span>
  </div>

  <div class="api-layout" style="margin-top:34px">
    <aside class="api-nav">
      <input class="api-search" id="q" type="search" placeholder="filter…" aria-label="Filter the API">
      <div id="nav-list">
__NAV__
      </div>
    </aside>
    <div id="items">
__BODY__
    </div>
  </div>
  <p class="fleuron">❦</p>
</main>

<footer class="site">
  <div class="wrap">
    <span>Apache-2.0 · moonbitstack</span>
    <span><a href="https://github.com/moonbitstack/moonxml">github.com/moonbitstack/moonxml</a></span>
    <span class="spacer"><a href="index.html">top ↑</a></span>
    <span class="colophon">Set in Iowan Old Style and Hoefler Text, labels in typewriter capitals · printed to the web on kraft</span>
  </div>
</footer>

<script>
(function () {
  var root = document.documentElement;
  var saved = null;
  try { saved = localStorage.getItem("moonxml-theme"); } catch (e) {}
  var system = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  root.setAttribute("data-theme", saved || system);
  document.getElementById("theme").addEventListener("click", function () {
    var next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);
    try { localStorage.setItem("moonxml-theme", next); } catch (e) {}
  });

  var box = document.getElementById("q");
  var items = Array.prototype.slice.call(document.querySelectorAll(".api-item"));
  var groups = Array.prototype.slice.call(document.querySelectorAll(".group"));
  box.addEventListener("input", function () {
    var needle = box.value.trim().toLowerCase();
    items.forEach(function (el) {
      var hit = !needle || el.textContent.toLowerCase().indexOf(needle) !== -1;
      el.classList.toggle("api-hidden", !hit);
    });
    groups.forEach(function (el) {
      var next = el.nextElementSibling;
      var any = false;
      while (next && next.classList.contains("api-item")) {
        if (!next.classList.contains("api-hidden")) { any = true; break; }
        next = next.nextElementSibling;
      }
      el.classList.toggle("api-hidden", !any);
    });
  });
})();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    main()
