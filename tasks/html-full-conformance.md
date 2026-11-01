# Task: full HTML parsing conformance

Status: in progress. The corpus is vendored and the runner measures a real pass
rate: **1345/1700** cases (79.1%) as of the latest commit. The parser implements
the common insertion behaviours and the real adoption agency algorithm, but is
not yet 100% of the corpus. This file is the incremental plan to get there.

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
reparenting; the canonical cases are covered in `tests/adoption_test.mbt`.
Still to come: markers at the spec boundary points, the `nobr` special case, and
the corpus comparison.

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

## Non-goals

Scripting (`document.write`, scripting-enabled branches), and encoding sniffing
beyond UTF-8, matching the html5lib-tests posture.
