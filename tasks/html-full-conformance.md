# Task: full HTML parsing conformance

Status: done. Both corpora are vendored and measured: tree construction
**1700/1700**, tokenizer **7017/7017**, with both floors asserted, so any
regression fails the build. The tree builder is a full insertion-mode state
machine (P2), the adoption agency follows the specification (P3), foreign content
and fragment parsing follow the integration-point rules (P4, P5).

Acceptance for "done": every `.dat` file under html5lib-tests/tree-construction
passes, the tokenizer JSON tests pass, and the fragment cases pass, with a
committed fixture set so CI needs no network.

## Why a fixture harness comes first

Conformance is a number, not an opinion. The first deliverable is a harness that
turns the html5lib corpus into committed fixtures and prints a pass rate, so each
later change is measured rather than asserted.

- `scripts/gen_html5lib.py` (Python, run by a maintainer, not CI) fetches
  `html5lib-tests` and writes `tests/fixtures/html5lib/*.json`: one record per
  case with input, fragment context, expected serialized tree.
- `tests/html5lib_runner_test.mbt` parses each input, serializes with the
  html5lib tree format, and compares. Failures are reported per file.
- CI runs the runner against the committed fixtures; a drop in the pass rate
  fails the build.

Landed: `vendor/html5lib-tests/` (the 1.1 sdist corpus, 1700 cases),
`scripts/gen_html5lib.py`, `tests/html5lib_cases.mbt`, and
`tests/html5lib_runner_test.mbt`, which prints the rate and enforces a ratchet
floor. The `conformance` CI job downloads the corpus from PyPI, diffs it against
the vendored copy, regenerates the fixtures and fails if they are stale, then
runs the runner.

## Phases

### P1 — tokenizer as a state machine

Replace the ad-hoc scanner with the WHATWG tokenizer states: data, tag open,
end tag open, tag name, before/after attribute name, attribute value
(double/single/unquoted), self-closing start tag, bogus comment, markup
declaration open, comment states, DOCTYPE states, CDATA section states,
RCDATA/RAWTEXT/script data and their escape states, character reference states
(named with the longest-match table, numeric, ambiguous ampersand).

Acceptance: html5lib tokenizer JSON tests pass (`.test` files), including the
named character reference table generated from `entities.json`.

### P2 — tree construction insertion modes

Implement every insertion mode and the dispatcher:
initial, before html, before head, in head, in head noscript, after head, in body,
text, in table, in table text, in caption, in column group, in table body, in row,
in cell, in select, in select in table, in template, after body, in frameset,
after frameset, after after body, after after frameset.

Each mode handles its start tags, end tags, character tokens, comments, DOCTYPE
and EOF as the spec lists them, including "generate implied end tags",
"has an element in scope / list item scope / button scope / table scope",
"reset the insertion mode appropriately", and the stack of open elements rules.

Acceptance: the tree-construction corpus pass rate reaches 100%.

### P3 — active formatting elements and adoption agency

- Maintain the list of active formatting elements with markers, the Noah's Ark
  clause, and reconstruction of active formatting elements.
- Implement the adoption agency algorithm in full (all eight outer steps, the
  inner loop with its three-iteration limit, the bookmark, cloning, reparenting,
  and insertion of the clone below the furthest block).
- Add markers at `td`, `th`, `caption`, `applet`, `object`, `marquee`, `template`
  and the other spec boundary points.

Acceptance: the adoption-agency cases in the corpus pass, including
`<p>1<b>2<i>3</b>4</i>5</p>`, `<b>1<p>2</b>3</p>`, and the `nobr` cases.
Landed: the active formatting list, reconstruction, the Noah's Ark clause, and
the full adoption agency with the inner-loop limit, bookmark, cloning and
reparenting; markers at the spec boundary points (`td`/`th`/`caption`/
`applet`/`object`/`marquee`/`template`); the `nobr` special case (its own start
rule and the adoption agency on its end tag). 18/18 cases in `adoption01.dat`
and 2/2 in `adoption02.dat` pass.

### P4 — foreign content

- Full integration-point rules for `svg` and `math`: `foreignObject`, `desc`,
  `title`, MathML text integration points, annotation-xml.
- The "breakout" list that pops foreign elements on HTML start tags.
- Attribute adjustment beyond the current table (xlink/xml/xmlns namespaced
  attributes, `definitionURL`).

Acceptance: the foreign-content cases in the corpus pass.

### P5 — fragment parsing

`loads_fragment(text, context)` must follow the spec's fragment algorithm: create
a context element, set the tokenizer state from the context tag, parse with the
context as the root, and return the context's children.

Acceptance: the fragment cases in the corpus pass.

### P6 — serializer

Emit the html5lib tree format for the runner, and keep the user-facing HTML
serializer spec-conformant (raw text elements, void elements, attribute escaping,
the `noscript`/`template` rules).

## Landed

- **P1 (tokenizer)** — every state of the specification, in
  `html/tokenizer.mbt`, with the tree builder switching the content model
  between tokens. The token stream is exposed as `tokenize()`, and the
  tokenizer corpus passes in full (7017 cases once the initial states are
  expanded). NUL is handled per state: kept in data and CDATA, U+FFFD in raw
  text, comments and foreign content. Two families of cases are excluded and
  reported separately rather than counted: the legacy
  `ProcessingInstruction` expectations (which contradict the same repository's
  tree-construction corpus, where `<?COMMENT?>` is a comment) and the four
  cases whose inputs are lone surrogates, which cannot be written to a UTF-8
  source file.
- **P2 (insertion modes)** — all twenty-three modes with an explicit `mode`
  variable, the transition table documented at the top of `html/builder.mbt`, and
  `reset_insertion_mode` walking the open-element stack appropriately. `Text`
  and `InTableText` remember the mode they came from.
- **P3 (adoption agency)** — see above.
- **P4 (foreign content)** — MathML text integration points, SVG/HTML
  integration points, `annotation-xml` encodings, the breakout list, namespaced
  attributes (`xlink:`, `xml:`, `xmlns:`), `definitionURL`, the SVG tag and
  attribute case tables, and the rule that a fragment whose context is a plain
  foreign element never breaks out.
- **P5 (fragments)** — the context element supplies the namespace, the tokenizer
  content model and the insertion mode, but stays off the stack; the tree is
  built in a fresh `html` root and the fragment is that root's children.
- **P6 (serializer)** — the runner's html5lib-format dump and the user-facing
  writer are separate; the latter is not part of the conformance measurement.

## The last five cases, and what they taught

Each was a namespace question rather than a missing mode:

- `namespace-sensitivity.dat`: `<td><svg><td><foreignObject><span></td>Foo`.
  The cell's end tag must close the **HTML** `td`, not the SVG one that shares
  the name. `pop_until` and `pop_until_any` now match HTML-namespaced elements
  only.
- `template.dat`: `<template><svg><foo><template><foreignObject><div></template>`
  — the same rule on `has_open`: a foreign `template` is not the template an end
  tag closes.
- `plain-text-unsafe.dat` (two cases): `<svg>`, NUL, `</svg>`, `<frameset>`.
  The frameset-ok flag is decided on the text with NUL removed, even though the
  NUL is inserted as U+FFFD. That is what lets the frameset replace a body whose
  only content was that character; html5lib labels the file "unsafe" precisely
  because the rule is subtle.

## Non-goals

Scripting (`document.write`, scripting-enabled branches), and encoding sniffing
beyond UTF-8, matching the html5lib-tests posture.
