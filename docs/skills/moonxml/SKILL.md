---
name: moonxml
description: "Parse, query, edit and write back HTML, XML and SVG in MoonBit — CSS Selectors 4 and XPath 1.0 over one mutable tree, with a streaming reader underneath. Use it to read a page, scrape a table, rewrite a feed, or build markup out of parts."
---

# moonxml

HTML arrives repaired the way a browser repairs it; XML arrives whole or is refused with the offset of the fault. Both land as the same node kinds, so a query written for a page runs on a feed.

```bash
moon add moonbitstack/moonxml
```

```moonbit
import {
  "moonbitstack/moonxml",
  "moonbitstack/moonxml/html",
  "moonbitstack/moonxml/xml",
  "moonbitstack/moonxml/event",
  "moonbitstack/moonxml/htmx",
}
```

## Read a page, and query it

```moonbit
let page = @html.loads("<ul id=list><li>coffee<li>tea<li>beans 12</ul>")

assert_eq(page.css("li").length(), 3)
assert_eq(page.css("#list li:first-child").text(), "coffee")
assert_eq(page.xpath("//li[last()]").text(), "beans 12")
```

`css` and `xpath` answer a `Selection`. `items[i]` is the way to a bare `Node`, and a `Node` answers `css` and `xpath` too, so a query never has to stop:

```moonbit
let page = @html.loads(
  "<table><tr><td>one</td></tr><tr><td><span>two</span></td></tr></table>")

page
  .xpath("//table")
  .css("tr:nth-child(2)")
  .items[0]
  .css("span")
  .set_text("done")

assert_eq(page.css("td span").text(), "done")
```

A selector of your own is one more link: give it a name on this document, and it answers a `Selection` like the built-in engines do.

```moonbit
page.register("cells", @moonxml.SelectorFn::new(fn(ctx, _query) {
  ctx.by_tag("td")
}))
assert_eq(page.selector("cells", "").length(), 2)
```

## Edit in place, and write it back

```moonbit
let page = @html.loads("<ul id=list><li>tea</ul>")
page.css("li").first().add_class("done")
page
  .css("ul")
  .append(
    @moonxml.ElementNode(
      @moonxml.Element::new("li", children=[@moonxml.TextNode("coffee")]),
    ),
  )
assert_eq(
  page.dumps(),
  "<html><head></head><body><ul id=\"list\"><li class=\"done\">tea</li><li>coffee</li></ul></body></html>",
)
```

`dumps` writes HTML with the tree's repairs resolved; `dump` answers `Bytes`. A document read from XML and not edited writes back byte for byte, including attribute order, CDATA and processing instructions.

## XML is strict, and names carry their namespace

```moonbit
let feed = @xml.loads("<feed xmlns:a='urn:a'><a:entry id='1'>first</a:entry></feed>")
assert_eq(feed.css("entry").items[0].name(), "{urn:a}entry")
assert_eq(
  feed.dumps(),
  "<feed xmlns:a=\"urn:a\"><a:entry id=\"1\">first</a:entry></feed>",
)
```

A CSS prefix is not read off the document; you pass the map a stylesheet's `@namespace` would declare:

```moonbit
let page = @html.loads("<svg viewBox='0 0 1 1'><rect/></svg><rect/>")
let ns : @moonxml.NamespaceMap = {
  default: "",
  prefixes: [("svg", "http://www.w3.org/2000/svg")],
}
assert_eq(page.css("svg|rect", namespaces=ns).length(), 1)
assert_eq(page.css("|rect", namespaces=ns).length(), 1)
```

## Stream the events, and build no tree

`@xml.scan` and `@html.scan` push `Event` values into any `Sink` before a tree exists — for input too large to keep, or for a pass that only counts.

```moonbit
priv struct Counter {
  mut starts : Int
}

impl @event.Sink for Counter with fn push(self, event) {
  if event is StartTag(..) {
    self.starts = self.starts + 1
  }
}
```

```moonbit
let sink : Counter = { starts: 0 }
@xml.scan("<a><b/></a>", sink)
assert_eq(sink.starts, 2)
```

## Rules that catch people out

- A `Node` has no editing verbs and no position among siblings. Narrow first: `match node { ElementNode(element) => ... }`.
- `Document` deliberately lacks `remove`, `attr`, `first`, `parent` and the rest — they would act on the container, not on a node of the document. Start from `document.root` or from a selection.
- `insert`, `insert_before` and `insert_after` live on `Element`, because they need a position; every other edit is also on `Selection` and applies to each match.
- HTML never refuses: it repairs and counts what it repaired on `document.repairs()`. XML and the selectors raise `Refused` — `Malformed(at~, why~)`, `BadQuery`, `UnknownSelector`, `Exceeded`.
- `:hover`, `:visited` and other pseudo-classes a browser decides at runtime are a `Refused` parse error, not a silent miss.
- There is no I/O here: fetch the bytes yourself and hand them to `@html.load` / `@xml.load`.
- The tree is mutable and every node knows its parent. Two selections holding the same node hold one node; `clone_deep` is what makes a copy that belongs to no tree.
