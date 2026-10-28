#!/usr/bin/env python3
"""Generate docs/selectors.html from a real run of the library.

`moon run src/examples/selectors` prints the demonstration document, then one
line per query: the group it belongs to, the engine, the query as it is
written, how many nodes it answered, and those nodes. This script turns that
output into the page, so nothing on the page is written by hand and every
answer on it is one the engine gave.

    python3 scripts/gen_selectors.py
"""

import html
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

GROUPS = [
    (
        "simple",
        "02",
        "The simple selectors",
        "Type, the universal, class, id, and every attribute form: present, "
        "equal, a word, a prefix, a suffix, a substring, a language, and the "
        "case-sensitivity flag. A selector list answers the union, in document "
        "order.",
    ),
    (
        "combinators",
        "03",
        "Combinators",
        "Descendant, child, the adjacent sibling and the general one. A "
        "compound on either side works the same way, so the last row here is a "
        "chain of three.",
    ),
    (
        "pseudo",
        "04",
        "Pseudo-classes",
        "The ones a document can settle: position among siblings, the "
        "functionals — <code>:not</code>, <code>:is</code>, <code>:where</code>, "
        "<code>:has</code> — and the form states. <code>:hover</code> and "
        "<code>:visited</code> are not here because they need a browser, and "
        "the engine refuses them by name rather than answering wrongly.",
    ),
    (
        "chain",
        "05",
        "The chain",
        "Every query answers a <code>Selection</code>, so queries compose: "
        "narrow a selection again, switch engine mid-flight, take the first or "
        "the last, step to the parent, to the children, to the nearest "
        "ancestor. <code>pricey</code> in one of these rows is a selector "
        "registered at run time.",
    ),
    (
        "values",
        "06",
        "Values and attributes",
        "A selection answers the text it holds, the attribute it was asked "
        "for, and the markup inside it; <code>xpath_value</code> answers a "
        "count, a string, a node-set or a boolean, typed. Note that "
        "<code>text()</code> on a group concatenates — the library does not "
        "guess where one node's text ends.",
    ),
    (
        "same",
        "07",
        "One node, seven ways",
        "Seven queries, two engines, one element. This is the point of a "
        "single tree: the node does not know or care which query found it.",
    ),
]


def run():
    done = subprocess.run(
        ["moon", "run", "src/examples/selectors"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if done.returncode != 0:
        sys.stderr.write(done.stdout)
        sys.stderr.write(done.stderr)
        raise SystemExit("the demonstration program did not run")
    source = ""
    rows = []
    for line in done.stdout.splitlines():
        parts = line.split("\t")
        if parts[0] == "document" and len(parts) == 2:
            source = parts[1].replace("\\n", "\n").replace("\\t", "\t")
        elif parts[0] == "row" and len(parts) >= 6:
            # value rows carry no hits, so the seventh field may be missing
            parts += [""] * (7 - len(parts))
            rows.append(tuple(parts[1:7]))
    if not source or not rows:
        raise SystemExit("the demonstration program printed nothing usable")
    return source, rows


def article_of(source):
    """The part of the document a reader can see: the article, and only it."""
    start = source.find("<article")
    end = source.rfind("</article>")
    if start < 0 or end < 0:
        return source
    return source[start : end + len("</article>")]


def table(rows):
    out = []
    out.append('<table class="demos">')
    out.append(
        "<thead><tr><th>Query</th><th>Nodes</th><th>Answer</th></tr></thead>"
    )
    out.append("<tbody>")
    for engine, query, count, answer, hits in rows:
        tag = ""
        if engine != "css":
            tag = '<span class="eng">%s</span>' % html.escape(engine)
        cell = '<code>%s</code>' % html.escape(query)
        klass = ' class="none"' if answer == "nothing" else ""
        number = count if count else "—"
        # the routes the engine answered with, for the page to point at
        marker = (
            ' data-hit="%s" tabindex="0"' % html.escape(hits) if hits else ""
        )
        out.append(
            "<tr%s><td>%s%s</td><td class=\"n\">%s</td><td%s>%s</td></tr>"
            % (marker, tag, cell, number, klass, html.escape(answer))
        )
    out.append("</tbody></table>")
    return "\n".join(out)


def page(source, rows):
    by_group = {}
    for row in rows:
        by_group.setdefault(row[0], []).append(row[1:])
    elements = 0
    for _group, _engine, query, count, _answer, _hits in rows:
        if query == "*" and count:
            elements = int(count)
    parts = []
    parts.append(
        """<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Selectors — moonxml</title>
<meta name="description" content="Every selector moonxml implements, run against one document: CSS, XPath, the chain, and the values and attributes they answer with.">
<link rel="stylesheet" href="assets/site.css">
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><text y='13' font-size='14' font-family='monospace' fill='%%237d2f22'>&lt;/&gt;</text></svg>">
</head>
<body>

<header class="top">
  <div class="wrap">
    <a class="brand" href="index.html"><span class="lt">&lt;</span><b>moonxml</b><span class="gt">/&gt;</span></a>
    <nav class="top-nav">
      <a href="start.html">Start</a>
      <a href="selectors.html" aria-current="page">Selectors</a>
      <a href="api.html">API</a>
      <a href="inside.html">Inside</a>
      <a class="hide-sm" href="https://github.com/moonbitstack/moonxml">GitHub</a>
      <button class="theme-toggle" id="theme" title="Switch theme" aria-label="Switch theme">◐</button>
    </nav>
  </div>
</header>

<main class="wrap">
  <div class="hero" style="padding-bottom:20px">
    <p class="eyebrow">the selector board</p>
    <h1>Every selector, run<br>against one <em>document</em>.</h1>
    <p class="lede">These tables are not examples of what the engines should answer — they are what they answered. Each row is a query, the number of nodes it returned, and those nodes, printed by a program that ran against the document in the box below.</p>
    <div class="colophon-line">
      <span><b>%d rows</b></span><span class="sep">·</span>
      <span>CSS Selectors</span><span class="sep">·</span>
      <span>XPath 1.0</span><span class="sep">·</span>
      <span>the chain</span>
    </div>
  </div>

  <section style="border-top:1px solid var(--rule)">
    <div class="sec-head"><span class="sec-num">01</span><h2>The document</h2></div>
    <div class="demo-brief">
      <div>
        <span class="lab">the specimen</span>
        <p>A page, not a form. The fields take typing, the boxes tick, the list opens — the controls work, and they submit nothing. They are here to be selected.</p>
      </div>
      <div>
        <span class="lab">the source</span>
        <p>Under the box, the document in full: the bytes the engine read to make these tables. Parse it with <code>@html.parse</code> and every answer below falls out again.</p>
      </div>
      <div>
        <span class="lab">the answers</span>
        <p>Sections 02 to 07 give the selectors, the query as written, the nodes it answered, and those nodes. Section 06 adds what a node yields when read from — its text, its attribute, its markup, its typed XPath value.</p>
      </div>
    </div>
    <div class="demo-box">
      <div class="demo-cap"><span>the article, rendered</span><span>%s elements · %d queries below</span></div>
%s
    </div>
    <p class="filename">the document, in full</p>
<pre>%s</pre>
    <p class="sub demo-hint">Hover a query — or click to pin it, <kbd>Esc</kbd> to let go — and the nodes it answered light up in the document above. The page does not run the query again: it follows the routes the engine answered with.</p>
    <p class="sub">A node is labelled <code>tag#id.class "text"</code> when it is an element, and <code>#text "…"</code> when it is not — <code>#text (blank)</code> is the whitespace between two tags, which is a node like any other. The <code>head</code>, <code>title</code> and <code>html</code> rows select from the whole document, not from the article shown.</p>
  </section>
"""
        % (
            len(rows),
            elements,
            len(rows),
            "\n".join("      " + line for line in article_of(source).splitlines()),
            html.escape(source),
        )
    )
    for key, number, title, blurb in GROUPS:
        if key not in by_group:
            continue
        parts.append(
            """  <section>
    <div class="sec-head"><span class="sec-num">%s</span><h2>%s</h2></div>
    <p class="sub">%s</p>
%s
  </section>
"""
            % (number, title, blurb, table(by_group[key]))
        )
    parts.append(
        """  <section>
    <div class="sec-head"><span class="sec-num">08</span><h2>What is not on this board</h2></div>
    <p class="sub"><code>:hover</code>, <code>:active</code>, <code>:focus</code>, <code>:visited</code> and <code>:target</code> describe a browser's state, not a document's, so the engine refuses them by name — <code>@moonxml.Refused.BadQuery</code> with the offset — instead of answering a question it cannot see. Everything a tree can settle is above; <code>page.css("a:hover")</code> is a sentence the library will not pretend to understand.</p>
  </section>

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
    var box = document.querySelector(".demo-box article");
    if (!box) return;
    var lit = [];
    var pinned = null;
    function clear() {
      for (var i = 0; i < lit.length; i++) lit[i].classList.remove("hit");
      lit = [];
    }
    function resolve(route) {
      if (route === ".") return box;
      var node = box;
      var steps = route.split("/");
      for (var i = 0; i < steps.length; i++) {
        if (!node) return null;
        node = node.children[parseInt(steps[i], 10)];
      }
      return node || null;
    }
    function show(row) {
      clear();
      var routes = (row.getAttribute("data-hit") || "").split(" ");
      for (var i = 0; i < routes.length; i++) {
        if (!routes[i]) continue;
        var node = resolve(routes[i]);
        if (node) { node.classList.add("hit"); lit.push(node); }
      }
    }
    box.addEventListener("click", function (event) {
      var link = event.target.closest ? event.target.closest("a") : null;
      if (link) event.preventDefault();
    });
    var rows = document.querySelectorAll("tr[data-hit]");
    for (var i = 0; i < rows.length; i++) {
      (function (row) {
        row.addEventListener("mouseenter", function () { if (!pinned) show(row); });
        row.addEventListener("focus", function () { if (!pinned) show(row); });
        row.addEventListener("click", function () {
          if (pinned === row) {
            pinned = null;
            row.classList.remove("pinned");
            clear();
          } else {
            if (pinned) pinned.classList.remove("pinned");
            pinned = row;
            row.classList.add("pinned");
            show(row);
          }
        });
      })(rows[i]);
    }
    var tables = document.querySelectorAll(".demos");
    for (var t = 0; t < tables.length; t++) {
      tables[t].addEventListener("mouseleave", function () {
        if (pinned) { show(pinned); } else { clear(); }
      });
    }
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && pinned) {
        pinned.classList.remove("pinned");
        pinned = null;
        clear();
      }
    });
  })();

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
  })();
</script>
</body>
</html>
"""
    )
    return "".join(parts)


def main():
    source, rows = run()
    out = page(source, rows)
    path = os.path.join(ROOT, "docs", "selectors.html")
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(out)
    print("%d rows written to %s" % (len(rows), path))


if __name__ == "__main__":
    main()
