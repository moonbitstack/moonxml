<div align="center">

# <code>&lt;moonxml/&gt;</code>

**HTML, XML and SVG for MoonBit — one mutable tree: parse it, query it by CSS selector or XPath 1.0, edit it in place, write it back.**

[![CI](https://github.com/moonbitstack/moonxml/actions/workflows/ci.yml/badge.svg)](https://github.com/moonbitstack/moonxml/actions/workflows/ci.yml)
[![pages](https://github.com/moonbitstack/moonxml/actions/workflows/pages.yml/badge.svg)](https://moonbitstack.github.io/moonxml/)
[![license](https://img.shields.io/badge/license-Apache--2.0-b23a1f.svg)](LICENSE)

[Documentation](https://moonbitstack.github.io/moonxml/) ·
[Quick start](https://moonbitstack.github.io/moonxml/start.html) ·
[API](https://moonbitstack.github.io/moonxml/api.html) ·
[How it works](https://moonbitstack.github.io/moonxml/inside.html)

</div>

---

```moonbit
let page = @html.loads("<ul id=list><li>coffee<li>tea</ul>")

page.css("li").length()                     // 2 — the document closed neither
page.xpath("//li[2]").text()                // "tea"
page.css("li").last().add_class("done")
page.dumps()
```

HTML is read the way a browser reads it; XML is read the way a validator reads it; both become the same node kinds, so a query written for a page works on a feed.

## Why this shape

| | |
|:--|:--|
| **One tree, two syntaxes** | `Node` is element, text, CDATA, comment, processing instruction or doctype. Nothing about a node says which parser made it. |
| **One chain** | Every query answers a `Selection`, so `css` → `xpath` → `selector` → `custom` → `items[i]` → `childrens()[j]` → `css` again never changes type. |
| **Two engines, and yours** | CSS Selectors 4's statically decidable subset, all of XPath 1.0, and a `Selector` trait you implement and register by name. |
| **Editing, not re-parsing** | bs4's verb set on the same selection the query returned, with parent pointers kept true. |
| **Two ways to read** | Build the tree, or stream `Event`s into your own `Sink` and build nothing. The tree builder is itself a sink: one parser, no drift. |
| **One error family** | `Refused`: malformed input names its offset, a bad selector names its fault. HTML never refuses — it repairs, and tells you what it repaired. |

## Install

```shell
moon add moonbitstack/moonxml
```

```moonbit
import {
  "moonbitstack/moonxml",       // tree, chain, engines, writer
  "moonbitstack/moonxml/html",  // @html.loads
  "moonbitstack/moonxml/xml",   // @xml.loads
  "moonbitstack/moonxml/event", // Event, Sink
}
```

Two dependencies: `moonbitlang/core`, and nothing else.

## The chain

```moonbit
page.xpath("//table")                      // any engine
    .css("tr:nth-child(2)")               // any other
    .selector("mine", "")                 // one you registered
    .custom(@moonxml.SelectorFn::new(f))  // one you did not
    .items[0]                             // a Node
    .childrens()[1]                       // still going
    .css("span")
    .set_text("done")
```

Results arrive in document order, deduplicated by **identity** — two `<li>coffee</li>` are different nodes and both are kept — and an empty selection stays empty rather than widening to the document.

Where XPath answers something that is not a node-set, `xpath_value` answers it typed: `Nodes`, `Str`, `Num` or `Flag`.

## The verbs

| Group | |
|:--|:--|
| Structure | `append` `prepend` `insert` `insert_before` `insert_after` `replace_with` `remove` `unwrap` `wrap` `clear` `smooth` |
| Attributes | `attr` `has_attr` `set_attr` `remove_attr` `classes` `has_class` `add_class` `remove_class` |
| Content | `text` `set_text` `html` `dumps` `dumps_html` |
| Navigation | `childrens` `parent` `descendants` `closest` `first` `last` `eq` `filter` |

Selection-level verbs (`append`, `set_text`, …) apply to every matched node; the ones that need a position (`insert`, `insert_before`, `insert_after`) live on `Element`, where a position means one thing.

## Parsers

**HTML** — WHATWG's tokenizer and tree construction: implied `html`/`head`/`body`/`tbody`, cells that close themselves, foster parenting in front of tables, formatting reopened after a block closed it, the adoption agency for misnested markup, character references with the Windows-1252 repair. What it fixed is countable afterwards on `document.repairs()`.

**XML** — XML 1.0 with Namespaces 1.0, strict: a document reads whole or is refused with the offset of the fault. Names become James Clark's `{uri}local`, and writing back reproduces attribute order, CDATA, comments, processing instructions, the doctype with its internal subset, and `<a/>` versus `<a></a>`.

**Streaming** — `@xml.scan(text, sink)` emits `Event`s to any `Sink`; `document.events()` reads a finished tree back as the same stream.

## Examples

| | |
|:--|:--|
| [`examples/tour`](examples/tour/main.mbt) | the whole surface in one run: `moon run examples/tour` |
| [`examples/scrape`](examples/scrape/main.mbt) | a page in, a table out: query, filter, reshape, serialise |
| [`examples/rewrite`](examples/rewrite/main.mbt) | read a feed, edit every entry, write it back byte-faithfully |

## What is not here yet

- **HTML foreign content.** `<svg>` and `<math>` subtrees are parsed as ordinary elements rather than switching into the SVG/MathML integration points. Querying them works (`page.css("svg rect")`); giving their namespaces meaning does not, and the html5lib files that test it are left out of the fixture.
- **Framesets and template contents.** A `<frameset>` document gets a body; `<template>` has no separate content fragment.
- **`:hover`, `:visited` as behaviour.** The state pseudo-classes are answered from attributes; the ones that need a live browser are a parse error rather than a silent miss.

The HTML tests assert a floor against html5lib's corpus — **817 of 1105 documents** in the fixture reproduce exactly — and the fixture is generated, so the number can only be raised.

## Development

```shell
moon check --target all --deny-warn
moon build --target all
moon test  --target all
moon fmt  && git diff --exit-code
moon info --target all && git diff --exit-code

python3 scripts/make_html5lib_fixtures.py ../.ref/html5lib-tests/tree-construction html/html_corpus_wbtest.mbt
python3 scripts/make_api_docs.py .
```

`DESIGN.md` records the interfaces and why they are shaped that way; it was written before the first line of implementation.

## Licence

Apache-2.0. See [LICENSE](LICENSE). Test fixtures generated from [html5lib-tests](https://github.com/html5lib/html5lib-tests) (MIT).
