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

impl Selector for DeepLinks with select(_self, ctx, query) {
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
| entry | `loads(text)`, `load(bytes)`, `loads_fragment(text)`, `scan(text, sink)` | `loads(text)`, `load(bytes)`, `loads_fragment(text, context="body")`, `tokenize(text, state=, last_start_tag=)` |
| entities | the five predefined, numeric, internal general and parameter entities | the named table documents use, numeric |
| namespaces | `xmlns` resolved to `{uri}local` | foreign content (`svg`, `math`) namespaced |

**XML internal subset.** `<!ENTITY>` general and parameter entities expand with
nested substitution, recursion detection, and a total expansion budget
(`limit`, default 1,000,000 characters) that defeats entity-expansion attacks.
`<!ATTLIST>` attribute defaults (including `#FIXED`) are applied. External
entities are never fetched — there is no I/O — and a reference to one is
reported as `Unsupported`, not dropped. Nesting is bounded by `depth` (default
512, matching Chrome and WebKit).

**HTML.** The tokenizer is the specification's state machine and can be used on
its own: `tokenize(text)` returns the token stream, with `state=` choosing the
content model (`data`, `rcdata`, `rawtext`, `script`, `plaintext`, `cdata`) and
`last_start_tag=` supplying the tag that closes a raw-text run. Void elements,
optional end tags (`p`, `li`, `dt`/`dd`, table rows and cells, `option`),
raw-text `script`/`style`, RCDATA `textarea`/`title`,
`loads_with_scripting(text, on)` sets the scripting flag, which makes `noscript`
content raw text the way an enabled browser does.

comments, doctypes, and foreign content (`svg`, `math`, `foreignObject`) with
SVG's camelCase tag and attribute names restored, plus MathML's `definitionURL`
and the `mglyph`/`malignmark` elements. Character references use the whole
WHATWG table (2,231 names, longest match, the legacy semicolon-less forms and
the attribute-value rule), and `script` text is scanned through the script-data
escaped and double-escaped states. Misnested formatting elements
are repaired by the adoption agency algorithm, with the active formatting
elements list and its reconstruction. Stray content inside a table is
foster-parented before it, and leading head content (`title`, `meta`, `link`,
`style`, `script`) is routed into `head`. Loose content is wrapped in
`html`/`body`.

## Writing back

`dumps()` writes the whole document in the flavour it was read as; `dumps_html()`
forces HTML. `dumps(node)` writes one node.

- **XML round-trip is byte-identical** for a well-formed document that is not
  edited: attribute order, CDATA, comments, processing instructions, the doctype
  and self-closing syntax all survive. Three deliberate deviations: attribute
  quoting is normalised to double quotes, a prefixed name is written as a default
  `xmlns` declaration on the element that needs it, and character references are
  decoded (`&#65;` reads as `A` and writes as `A`).
- **HTML** has no byte-identity promise; its criterion is the fixpoint — parse,
  serialize, parse, serialize gives the same bytes. The writer does its part: a
  doctype with identifiers gets its `PUBLIC`/`SYSTEM` keyword back, a leading
  newline in `pre`/`textarea` is written twice so the parser eats only one, and
  `noscript` that came from a raw-text parse is written unescaped.
  `tests/html_fixpoint_test.mbt` checks the property over the whole corpus; the
  sixty cases it excludes are trees no HTML source can express (a `plaintext`
  element, a `<a>` inside a `<a>`, a fragment parsed in a raw-text context,
  script text in the double-escaped state), and the exclusions are counted per
  category in the test output rather than silently dropped.

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

HTML never raises; it repairs, and counts what it repaired: `Document::repairs()`
is empty for a clean document and reports the number otherwise.

## Not here yet

Stated plainly, because a library is defined as much by what it refuses:

- **The html5lib corpora are not "not here yet" items any more: both pass in
  full.** The tokenizer implements every state of the specification, and tree
  construction is a full insertion-mode state machine:
  every mode in the specification, the five table states included, with an
  explicit mode variable and a reset that walks the open-element stack. Templates
  carry their own mode stack, fragments start from their context element's mode,
  and foreign content follows the integration-point rules. The vendored corpus
  runs in `moon test` and passes 1700 of 1700 cases.
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

`moon test` runs 192 tests and both vendored corpora. The unit tests are
organised by the question they answer, not by the package they touch:

| file | what it pins |
|---|---|
| `tests/xpath_matrix_test.mbt` | every axis, node test, precedence level and core function of XPath 1.0 |
| `tests/css_matrix_test.mbt` | every attribute operator, combinator, structural and functional pseudo-class |
| `tests/serialize_test.mbt` | byte fidelity for XML, the WHATWG rules for HTML, namespace re-declaration |
| `tests/html_fixpoint_test.mbt` | serialise, reparse, serialise returns the same text, over all 1700 corpus cases |
| `tests/xml_wellformed_test.mbt` | what `loads` accepts and what it refuses, case by case |
| `tests/error_paths_test.mbt` | a bad selector or expression raises, and with which `Refused` variant |
| `tests/tree_invariants_test.mbt` | parent pointers, indices and single parentage after each editing verb |
| `tests/events_scan_test.mbt` | the streaming reader and the tree builder emit the same events |
| `tests/html_modes_test.mbt` | one case per insertion mode, named after it |
| `tests/tokenizer_cases_test.mbt` | the `tokenize()` entry point: order, doctype parts, content models |
| `tests/tree_edit_test.mbt`, `tests/chain_test.mbt`, `tests/xpath_css_test.mbt` | the everyday surface: editing verbs, the chain, representative queries |

The corpora run as part of the same `moon test` invocation:

- **Tree construction** — `vendor/html5lib-tests/tree-construction`, 1700 cases,
  fixtures from `scripts/gen_html5lib.py`, runner
  `tests/html5lib_runner_test.mbt`. Current rate: **1700/1700**.
- **Tokenizer** — `vendor/html5lib-tests/tokenizer`, 7017 cases once the initial
  states are expanded, fixtures from `scripts/gen_tokenizer_tests.py`, runner
  `tests/tokenizer_runner_test.mbt`. Current rate: **7017/7017**.
- **XPath** — `vendor/xpath-tests`, libxml2's corpus: 326 expressions, thirteen
  of them against a document, each with libxml2's result (a boolean, a number, a
  string, or a node-set described by its size and the kind and name of each
  top-level node). Fixtures from `scripts/gen_xpath_cases.py`, runner
  `tests/xpath_conformance_test.mbt`. Current rate: **311/326**. The fifteen
  that fail are listed in the runner: the namespace axis, ancestor walks from an
  attribute, six `mixedpat` cases that assume libxml2's context node, and two
  `string()` formats.
- **CSS selectors** — `vendor/css-selectors`, the W3C CSS3 Selectors Test Suite
  from web-platform-tests' `css/selectors/old-tests`: 292 files, of which 99
  carry a machine-readable assertion for a rule that paints lime, giving 116
  cases. Fixtures from `scripts/gen_css_selector_cases.py`, runner
  `tests/css_selector_conformance_test.mbt`. Current rate: **70/116**; sixteen
  of the failures are `prefix|name` selectors, which this engine refuses because
  it keeps no `@namespace` map.

Every runner asserts a ratchet floor, so a regression fails the build rather than
lowering the number quietly.

## Continuous integration

`.github/workflows/ci.yml` runs three jobs:

- **check** — `moon check`, then fails if the committed interface files no longer
  match the source (`moon check` regenerates them, so a diff is drift), and runs
  `scripts/check_hygiene.py`, which checks for tabs, carriage returns, trailing
  whitespace and emoji. `moon fmt --check` cannot serve as that gate: it would
  reflow the generated fixtures into one field per line.
- **test** — the whole suite on Linux, macOS and Windows, and on the `wasm-gc`,
  `js` and `native` backends. The three backends matter here: the parsers index
  into arrays of UTF-16 code units, and a backend that disagrees about string
  length would show up as a corpus failure rather than as a mystery bug.
- **conformance** — verifies all four vendored corpora against their upstreams
  (html5lib from the 1.1 sdist and from its repository, libxml2 from a source
  tarball, web-platform-tests through a sparse checkout of the one directory),
  regenerates the five fixture files and the entity table and fails if they
  differ from the committed copies, then measures the rates and writes them to
  the job summary.

`.github/workflows/upstream.yml` runs weekly against html5lib master: it replaces
the vendored corpora with upstream's, regenerates the fixtures and runs the
suite, so corpus drift shows up on its own schedule instead of at the next
dependency bump. It never commits.

## Roadmap

The increments that take this from "works on ordinary documents" to "passes the
corpora" are written down as task orders:

- `tasks/html-full-conformance.md` — landed: tokenizer token stream, every
  insertion mode, foreign content, fragment parsing, and a committed html5lib
  fixture harness that measures the pass rate. All 1700 cases pass.
- `tasks/dtd-schema-xslt-xpath2.md` — DTD validation, XML Schema, XPath 2.0 and
  XSLT 1.0/2.0, each with its W3C acceptance corpus.

## License

MIT. See `LICENSE`.
