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

HTML is read the way a browser reads it; XML is read strictly, as XML 1.0 requires; both become the same node kinds, so a query written for a page works on a feed.

## Why this shape

| | |
|:--|:--|
| **One tree, two syntaxes** | `Node` is element, text, CDATA, comment, processing instruction or doctype. Nothing about a node says which parser made it. |
| **One chain** | Every query answers a `Selection`, so `css` → `xpath` → `selector` → `custom` → `items[i]` → `children()[j]` → `css` again never changes type. |
| **Two engines, and yours** | CSS Selectors 4's statically decidable subset, all of XPath 1.0, and a `Selector` trait you implement and register by name. |
| **Editing, not re-parsing** | A full set of editing verbs on the same selection the query returned, with parent pointers kept true. |
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
  "moonbitstack/moonxml/htmx",  // @htmx.Hx — htmx's attributes, read and carried out
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
    .children()[1]                       // still going
    .css("span")
    .set_text("done")
```

Results arrive in document order, deduplicated by **identity** — two `<li>coffee</li>` are different nodes and both are kept — and an empty selection stays empty rather than widening to the document.

Where XPath answers something that is not a node-set, `xpath_value` answers it typed: `Nodes`, `Str`, `Num` or `Flag`.

## The interface

Four types, and every method sits on the type it acts on: `Selection` is a
node list, `Element` is one node, `Node` is any node, `Document` is the
container the tree hangs from. Query methods exist on all four, so a chain
never has to stop and re-wrap.

### `Document`

| | |
|:--|:--|
| read | `root` `document_element()` `flavour()` `repairs()` |
| search | `css(q)` `xpath(q)` `xpath_value(q)` `selector(name, q)` `custom(sel)` `by_id(v)` `by_class(v)` `by_tag(v)` `by_name(v)` |
| content | `text()` `html()` `children()` `descendants()` `dumps()` `dump()` `dumps_html()` `dump_html()` `events()` |
| change | `append(node)` `prepend(node)` `clear()` `smooth()` `register(name, sel)` `push(event)` |

A document's `root` is a container, not a node of the document, so the verbs
that act on one node among siblings are deliberately **not** forwarded to
`Document`: `remove`, `replace_with`, `wrap`, `unwrap`, `parent`, `first`,
`last`, `eq`, `length`, `attr`, `set_attr`, `remove_attr`, `add_class`,
`remove_class`, `filter`, `closest`, `set_text`. Each would answer for the
container itself — remove the document from the document, ask what a document
is named — which is not an operation a caller can mean. They stay on
`Selection` and `Element`, where they name something real.

### `Selection`

| | |
|:--|:--|
| search | `css` `xpath` `xpath_value` `selector` `custom` `by_id` `by_class` `by_tag` `by_name` `filter(f)` `closest(q)` |
| narrow | `first()` `last()` `eq(i)` `children()` `parent()` `descendants()` `items[i]` |
| read | `length()` `text()` `html()` `attr(name)` |
| change | `append` `prepend` `remove` `replace_with` `unwrap` `wrap` `clear` `set_text` `set_attr` `remove_attr` `add_class` `remove_class` `smooth` |

### `Element`

| | |
|:--|:--|
| fields | `name` `attrs` `children` `parent` `closed` |
| structure | `append` `prepend` `insert(at, node)` `insert_before` `insert_after` `replace_with` `remove` `unwrap` `wrap` `clear` `smooth` |
| attributes | `attr` `has_attr` `set_attr` `remove_attr` `classes` `has_class` `add_class` `remove_class` |
| content | `text()` `set_text(s)` `html()` `walk(f)` `document()` |

### `Node`

`name()` `is_element()` `is_text()` `text()` `children()`, plus the query
methods above. A node that is not an element answers an empty selection
rather than refusing, so `.items[0].css("a")` never needs a guard.

Selection-level edits apply to every matched element; the verbs that need a
position (`insert`, `insert_before`, `insert_after`) live on `Element`, where
a position means one thing.

## Parsers

**HTML** — WHATWG's tokenizer and tree construction, whole: implied
`html`/`head`/`body`/`tbody`, cells that close themselves, foster parenting in
front of tables, formatting reopened after a block closed it, the adoption
agency for misnested markup, character references with the Windows-1252 repair.
Foreign content is parsed as foreign: `<svg>` and `<math>` carry their
namespaces, their tags and attributes are spelled the way SVG and MathML spell
them, and the integration points (`foreignObject`, `desc`, `title`, `mi`,
`mtext`, `annotation-xml`) are where HTML resumes. A `<template>`'s contents
live in a fragment of their own, on `element.content()`, so what is inside a
template is inert until someone puts it in the document. Framesets are
documents too. What the parser fixed is countable afterwards on
`document.repairs()`.

**XML** — XML 1.0 with Namespaces 1.0, strict: a document reads whole or is
refused with the offset of the fault. Names become `{uri}local`, and writing
back reproduces attribute order, CDATA, comments, processing instructions, the
doctype with its internal subset, and `<a/>` versus `<a></a>`.

The internal subset is read: entity declarations, general and parameter, nested
and with recursion refused; attribute defaults and their types; the content
models that decide whether a declaration is well-formed. Nothing is fetched — a
document whose entities live in a file beside it is read without them, and
`document.unresolved()` names what was skipped, as XML 1.0 asks a
non-validating processor to. `standalone="yes"` turns that gap into a fault,
because the document said it needed nothing from outside. Expansion is bounded
by `entity_limit`, a million characters by default, so a document built to
expand for ever is refused instead of read.

**Fragments** — `@html.loads_fragment(text, context="div")` reads markup the
way `innerHTML` does, inside the element named as the context; `svg desc` and
`math mi` name a foreign context. `@xml.loads_fragment(text)` reads a snippet
that has no single root.

**Streaming** — `@xml.scan(text, sink)` emits `Event`s to any `Sink`;
`document.events()` reads a finished tree back as the same stream.

## Hypermedia

`moonxml/htmx` reads the attributes htmx defines and carries them out: when to
ask, what to ask, and where the answer goes.

```moonbit
let page = @html.loads(
  "<form hx-post='/todos' hx-target='#list' hx-swap='beforeend'>" +
  "<input name='title' value='write it down'><button>Add</button></form>" +
  "<ul id='list'></ul>")

let request = @htmx.Hx::of(page.css("form").items[0]).request("submit").unwrap()

request.address()                    // "/todos"
request.query()                      // "title=write+it+down"
request.headers()                    // [("HX-Request", "true"), ("HX-Target", "list")]

request.answer("<li>a second one</li>")   // and the list has it
```

The verbs (`hx-get`, `hx-post`, `hx-put`, `hx-patch`, `hx-delete`), `hx-trigger`
with `once`, `changed`, `delay:`, `throttle:`, `from:`, `queue:` and `every`;
`hx-target` with `this`, `closest`, `find`, `next`, `previous` and bare
selectors; `hx-swap` with its seven positions and its timing; `hx-vals`,
`hx-headers`, `hx-include`, `hx-params`, `hx-select`, `hx-confirm`,
`hx-indicator`, `hx-push-url`, `hx-boost` and `hx-swap-oob`. Attributes
inherit down the tree, and `hx-disinherit` and `unset` stop them, as htmx does.

What it does not do is the two things a library cannot: send the request, and
wait for the answer. It describes the first and applies the second.

## Examples

| | |
|:--|:--|
| [`src/examples/tour`](src/examples/tour/main.mbt) | the whole surface in one run: `moon run src/examples/tour` |
| [`src/examples/hypermedia`](src/examples/hypermedia/main.mbt) | a page that declares its requests: read it, make one, swap the answer in |
| [`src/examples/scrape`](src/examples/scrape/main.mbt) | a page in, a table out: query, filter, reshape, serialize |
| [`src/examples/rewrite`](src/examples/rewrite/main.mbt) | read a feed, edit every entry, write it back byte-faithfully |

## What is not here

`document.write`, scripting-enabled branches, and the CSS pseudo-classes that
need a live browser (`:hover`, `:visited`) — none of those can be decided from
a document alone, so each is a named answer rather than a silent miss. XSLT,
DTD validation and XPath 2.0 are transformations and languages of their own,
not features of a tree library. The same goes for htmx's `ws:` and `sse:`
extensions, `hx-on` handlers and history cache: they need an event loop and a
connection, so `moonxml/htmx` stops at the request and the swap.

## Licence

Apache-2.0. See [LICENSE](LICENSE). Test fixtures generated from [html5lib-tests](https://github.com/html5lib/html5lib-tests) (MIT).
