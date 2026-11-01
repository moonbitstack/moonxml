# moonxml

HTML, XML and SVG for MoonBit. A document goes in, one mutable tree comes out,
queries run against it by CSS selector or XPath (and by any selector a caller
registers), edits happen in place, and the tree writes itself back.

Zero dependencies beyond `moonbitlang/core`, zero I/O. It pairs with
[moonfetch](https://github.com/moonbitstack/moonfetch) — fetch a page, understand
a page — without depending on it.

```moonbit
let doc = @html.loads("<ul><li class=\"a\">one</li><li>two</li></ul>")

let text = doc.css("li.a").text()          // "one"
let href = doc.xpath("//li/@class").text() // "a"  (attribute axis)
let html = doc.css("ul").html()            // "<li class=\"a\">one</li><li>two</li>"
```

## Install

```sh
moon add moonbitstack/moonxml
```

Then import the entry point you need in your `moon.pkg`:

```text
import {
  "moonbitstack/moonxml",       // the tree, the chain, the engines, the writers
  "moonbitstack/moonxml/xml",   // strict XML parser
  "moonbitstack/moonxml/html",  // tolerant HTML parser
  "moonbitstack/moonxml/event", // Event and Sink, for streaming reads
}
```

## The tree

```moonbit
pub(all) enum Node {
  ElementNode(Element)
  TextNode(String)
  CDataNode(String)
  CommentNode(String)
  ProcessingInstructionNode(ProcessingInstruction)
  DoctypeNode(String)
  AttributeNode(String, String)   // synthetic: produced by XPath's @axis
}

pub struct Element {
  name : String                    // {uri}local, or a bare local name
  attrs : Array[(String, String)]  // document order is information
  mut children : Array[Node]
  mut parent : Element?
  mut closed : Bool                // <a/> versus <a></a>
}
```

Decisions, each with its reason:

- **Mutable, with parent pointers.** `Json` in `moonjson` is a value; a DOM is
  an object graph with identity. MoonBit's mutable structs are references, so a
  child and the copy in its parent's `children` are the same object. Every
  editing verb repairs the pointers it breaks.
- **Namespaced names are `{uri}local`** (James Clark's spelling), so a node
  reads the same whatever prefixes the source declared. Prefixes in queries
  match by local part.
- **Attributes are an ordered array of pairs**, not a map, because a hash map
  would shuffle attribute order on the way to the serializer and byte fidelity
  of the round-trip is a criterion.
- **CDATA is its own node kind**, so it round-trips exactly; `text()` still
  includes it, as XPath says.
- **One virtual root per document**, named `#document`, holding the doctype,
  comments, processing instructions and the document element.

## The chain

One `Selection` carries the nodes a query returned and the document they belong
to; every query narrows it and returns a new one. An empty result is an empty
list, never a special value, so a chain never branches.

```moonbit
doc.xpath("//ul")          // XPath narrows ...
   .css("li.external")     // ... then CSS narrows the result
   .xpath("@href")         // ... and back
   .selector("tag", "a")   // a registered selector
   .first()
   .text()
```

Every method exists on `Selection`, on `Element` and on `Document`. Query
methods search descendants (like `querySelectorAll`); XPath can also match the
context node itself (`.`), because XPath's semantics say so. Results are in
document order and deduplicated by identity.

Read with `text()`, `html()`, `attr(name)`, `items`, `length()`. Narrow with
`first()`, `last()`, `eq(i)`, `children()`, `parent()`, `descendants()`,
`filter(f)`, `closest(q)`.

### XPath 1.0

`xpath(q)` returns a `Selection`; when the expression evaluates to a string,
number or boolean, the answer is its XPath string value wrapped as one text
node, so `doc.xpath("string(//h1)").text()` reads naturally. `xpath_value(q)`
returns the typed `XPathValue` (`Nodes`, `Str`, `Num`, `Flag`).

Implemented: all thirteen axes, node tests (`name`, `*`, `text()`,
`comment()`, `node()`, `processing-instruction()`), predicates (including
`position()` and `last()`), the union operator, arithmetic and comparison
operators, and the core function library (`last`, `position`, `count`, `id`,
`local-name`, `namespace-uri`, `name`, `string`, `concat`, `starts-with`,
`contains`, `substring-before`, `substring-after`, `substring`,
`string-length`, `normalize-space`, `translate`, `boolean`, `not`, `true`,
`false`, `number`, `sum`, `floor`, `ceiling`, `round`).

### CSS selectors

Selectors Level 4's statically decidable part: type and universal selectors,
`#id`, `.class`, attribute selectors (`[a]`, `[a=v]`, `[a~=v]`, `[a|=v]`,
`[a^=v]`, `[a$=v]`, `[a*=v]`), the four combinators, structural pseudo-classes
(`:first-child`, `:last-child`, `:only-child`, the `-of-type` family,
`:nth-*` with an optional `of S`), `:root`, `:empty`, and the functional
`:not()`, `:is()`, `:where()`, `:has()`. Dynamic pseudo-classes (`:hover`,
`:focus`) are a parse error naming the pseudo-class, not a silent miss.

### Registering selectors

```moonbit
pub struct DeepLinks {}

impl Selector for DeepLinks with select(self, ctx, query) {
  ignore(query)
  ctx.css("a").filter(fn(n) { n.is_element() })
}

doc.register("deep", DeepLinks::{})
doc.selector("deep", "").length()
```

Re-registering a name replaces it, including a built-in's; `css(q)` still calls
the CSS engine directly, so shadowing `"css"` cannot break it. `custom(sel)` runs
an unregistered selector.

## Editing

The bs4 verb set, as methods on `Element` (they move nodes and repair parent
pointers) and, applied to every selected element, on `Selection` (structural
verbs clone the node per target):

`append`, `prepend`, `insert`, `insert_before`, `insert_after`, `replace_with`,
`remove`, `unwrap`, `wrap`, `clear`, `smooth`, `set_attr`, `remove_attr`,
`add_class`, `remove_class`, `set_text`.

```moonbit
doc.css("li").add_class("row").set_attr("data-x", "1")
doc.css("h1").wrap("div").set_text("title")
```

## Parsing

| | `moonxml/xml` | `moonxml/html` |
|:--|:--|:--|
| dialect | XML 1.0 + Namespaces 1.0, with the internal subset | WHATWG HTML, tolerant |
| malformed | raises `Refused::Malformed(at, why)` | repairs silently |
| entry | `loads(text)`, `load(bytes)`, `loads_fragment(text)`, `scan(text, sink)` | `loads(text)`, `load(bytes)`, `loads_fragment(text, context="body")` |
| entities | the five predefined, numeric, internal general and parameter entities | the named table documents use, numeric |
| namespaces | `xmlns` resolved to `{uri}local` | foreign content (`svg`, `math`) namespaced |

**XML internal subset.** `<!ENTITY>` general and parameter entities expand with
nested substitution, recursion detection, and a total expansion budget
(`limit`, default 1,000,000 characters) that defeats entity-expansion attacks.
`<!ATTLIST>` attribute defaults (including `#FIXED`) are applied. External
entities are never fetched — there is no I/O — and a reference to one is
reported as `Unsupported`, not dropped. Nesting is bounded by `depth` (default
512, matching Chrome and WebKit).

**HTML.** Void elements, optional end tags (`p`, `li`, `dt`/`dd`, table rows and
cells, `option`), raw-text `script`/`style`, RCDATA `textarea`/`title`,
comments, doctypes, and foreign content (`svg`, `math`, `foreignObject`) with
SVG's camelCase tag and attribute names restored. Misnested formatting elements
are repaired by the adoption agency algorithm, with the active formatting
elements list and its reconstruction. Stray content inside a table is
foster-parented before it, and leading head content (`title`, `meta`, `link`,
`style`, `script`) is routed into `head`. Loose content is wrapped in
`html`/`body`.

## Writing back

`dumps()` writes the whole document in the flavour it was read as; `dumps_html()`
forces HTML. `dumps(node)` writes one node.

- **XML round-trip is byte-identical** for a well-formed document that is not
  edited: attribute order and quoting, CDATA, comments, processing instructions,
  the doctype and self-closing syntax all survive. One deliberate deviation:
  character references are decoded (`&#65;` reads as `A` and writes as `A`).
- **HTML** has no byte-identity promise; its criterion is the fixpoint — parse,
  serialize, parse, serialize gives the same bytes.

## Reading a tree as events

```moonbit
pub(open) trait Sink {
  push(Self, event : Event) -> Unit
}
```

`Document::events(sink)` emits a finished tree's events; `@xml.scan(text, sink)`
streams a document straight from its tokenizer, without building a tree, so a
caller counting tags or writing rows to a database consumes a large document
incrementally. Names are resolved and entities expanded identically to the tree
parser, so the two reads agree.

## Errors

One error family for the whole library:

```moonbit
pub(all) suberror Refused {
  Malformed(at~ : Int, why~ : String)   // XML well-formedness; at = UTF-16 offset
  BadQuery(at~ : Int, why~ : String)    // a selector or XPath that does not parse
  UnknownSelector(name~ : String)
  Unsupported(what~ : String)
}
```

HTML never raises; it repairs.

## Not here yet

Stated plainly, because a library is defined as much by what it refuses:

- **Full html5lib conformance.** The adoption agency and active formatting
  elements are implemented, and the common insertion behaviours listed above are
  present. The vendored corpus is run by `moon test`; it currently passes 937 of
  1700 cases (55.1%). The remaining gaps are the full insertion-mode set (table,
  caption, column group, select, template), the tokenizer state machine, foreign
  attribute namespaces and context-sensitive fragment parsing. The work, with an
  acceptance criterion per phase, is in `tasks/html-full-conformance.md`.
- **Complete W3C XPath/XSLT corpora.** XPath 1.0's core is implemented; XSLT,
  XPath 2.0+ and XQuery are out of scope.
- **DTD validation and Schema.** The internal subset is read for entities and
  attribute defaults, not validated.
- **External entities.** Never fetched, by design.
- **Pretty-printing.** Indenting mixed content changes meaning; the writer
  preserves the tree exactly.
- **Encoding detection.** UTF-8 in, UTF-8 out; a leading BOM is stripped.
- **Scripting.** `document.write` and scripting-enabled branches are out; this
  is the testable posture.

## Tests

```sh
moon check
moon test
```

The suite covers the tree and its editing verbs, the chain interleaving XPath
and CSS, XPath axes and the core function library, CSS selectors and combinators,
XML round-trip byte fidelity, the internal subset (general and parameter
entities, attribute defaults, depth and expansion limits), HTML tolerance and
foreign content, and the event stream.

`moon test` also runs the vendored html5lib tree-construction corpus (1700
cases) and prints the pass rate; the test asserts a ratchet floor, so a
regression fails the build. The corpus lives in
`vendor/html5lib-tests/tree-construction`, the fixtures are generated by
`scripts/gen_html5lib.py`, and the runner is
`tests/html5lib_runner_test.mbt`. Current rate: **937/1700** cases. CI runs this in a separate `conformance` job, fetches the corpus directly and checks it against the vendored copy before running.

## Roadmap

The increments that take this from "works on ordinary documents" to "passes the
corpora" are written down as task orders:

- `tasks/html-full-conformance.md` — tokenizer state machine, every insertion
  mode, foreign content, fragment parsing, and a committed html5lib fixture
  harness that measures the pass rate.
- `tasks/dtd-schema-xslt-xpath2.md` — DTD validation, XML Schema, XPath 2.0 and
  XSLT 1.0/2.0, each with its W3C acceptance corpus.

## License

MIT. See `LICENSE`.
