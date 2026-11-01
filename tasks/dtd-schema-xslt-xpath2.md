# Task: DTD validation, XML Schema, XSLT, XPath 2.0

Status: planned. These are increments on top of the current tree, chain, XPath
1.0 and parsers. Each has its own acceptance corpus, so progress is a number.

## Shared groundwork

- A typed XPath data model: sequences, atomic values (string, boolean, decimal,
  double, float, date/time, duration, QName, anyURI), and typed nodes. XPath 1.0
  answers `XPathValue`; 2.0 needs a `Sequence` and atomization.
- Namespace-aware name resolution with a prefix map per element (the tree keeps
  Clark names and drops prefixes, so a query prefix map is needed).
- A shared static context (variables, functions, base URI, default collation).

## Increment 1 — DTD validation

Build on the internal-subset parser already present.

- Parse the full DTD: `<!ELEMENT>` content models (EMPTY, ANY, mixed, children
  with `?`, `*`, `+`, choice, sequence), `<!ATTLIST>` attribute types (CDATA,
  ID, IDREF, IDREFS, ENTITY, ENTITIES, NMTOKEN, NMTOKENS, enumerations,
  NOTATION) and defaults (`#REQUIRED`, `#IMPLIED`, `#FIXED`), `<!ENTITY>` and
  `<!NOTATION>`.
- Validate a tree: element content against its content model (a small NFA),
  required/fixed attributes, ID uniqueness, IDREF/IDREFS resolution, ENTITY
  references, NOTATION declarations.
- Distinguish well-formedness from validity; report `Refused::Invalid(at, why)`
  as a new variant.
- Entry: `@xml.validate_dtd(text) -> Report` or `@xml.loads_validated(text)`.

Acceptance: the W3C XML conformance suite's valid and invalid documents under
validation produce the expected verdicts, run from committed fixtures.

## Increment 2 — XML Schema (XSD 1.0)

- Structures: `schema`, `element`, `attribute`, `complexType`, `simpleType`,
  `sequence`, `choice`, `all`, `group`, `attributeGroup`, `any`, `anyAttribute`,
  `import`/`include`, substitution groups.
- Simple types: all built-ins, `restriction`/`list`/`union`, facets
  (`minLength`, `maxLength`, `pattern`, `enumeration`, `minInclusive`, ...).
- Complex types: content models (the same NFA as DTD), derivation by extension
  and restriction, mixed content, `nillable`, `use="required|prohibited"`.
- Identity constraints: `key`, `keyref`, `unique` via XPath.
- Validation produces a PSVI-lite report (typed values, validity).

Acceptance: the W3C XML Schema test suite's valid/invalid cases pass, from
committed fixtures.

## Increment 3 — XPath 2.0

- Data model and sequences; atomization; the type system (ItemType, SequenceType,
  occurrence indicators).
- Grammar: `for`, `some`, `every`, `if/then/else`, `instance of`, `treat as`,
  `cast as`, `castable as`, range `to`, sequence `,`, the full axis set including
  `namespace`.
- Operators and comparisons (value, general, node), arithmetic on typed values.
- Function library: the F&O 2.0 core (string, numeric, date/time, duration,
  QName, node, sequence, aggregate functions), plus constructor functions.
- Static and dynamic context, variables, `fn:doc`/`fn:collection` are out (no I/O)
  unless a resolver is supplied by the caller.

Acceptance: the W3C XPath 2.0 test suite's core cases pass, from committed
fixtures. XPath 1.0 remains available and unchanged.

## Increment 4 — XSLT

XSLT 1.0 first, because it is defined over XPath 1.0 which already exists.

- Stylesheet parsing, template rules with priorities and modes, `apply-templates`,
  `for-each`, `if`, `choose`, `value-of`, `copy-of`, `copy`, `text`,
  `attribute`, `element`, `variable`/`param`, `sort`, `number`, `key`,
  `output` (method, omit-xml-declaration, indent), whitespace stripping.
- Result tree construction and serialization (xml, html, text methods).

Then XSLT 2.0 over the XPath 2.0 engine: `for-each-group`, `sequence`,
`analyze-string`, `xsl:function`, tunnel parameters, multiple output documents
(unless the caller supplies a sink).

Acceptance: the W3C XSLT 1.0 and 2.0 test suites' core cases pass, from committed
fixtures.

## Ordering and dependencies

```
DTD validation        independent
XSD                   needs DTD-style content-model NFA
XPath 2.0             needs the typed data model
XSLT 1.0              needs XPath 1.0 (done)
XSLT 2.0              needs XPath 2.0
```

## Non-goals

XQuery, XSL-FO, external entity resolution, and network document loading. All I/O
stays with the caller, as in the rest of the library.
