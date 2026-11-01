# libxml2 XPath corpus (vendored)

Source: <https://github.com/GNOME/libxml2>, the `test/XPath` and `result/XPath`
directories, vendored on 2026-11-01 from `master` (`2034036d2e8d`).

libxml2 runs this suite from `runtest.c`:

- `expr/<name>` is a list of expressions, one per line, evaluated with no
  document. `result-expr/<name>` is what libxml2 printed for each of them.
- `docs/<name>` is a document. Every `tests/<name>…` whose name starts with the
  document's base name holds expressions evaluated against it, and
  `result-tests/<name>` holds the expected results.

A result block is:

```
========================
Expression: /child::*
Object is a Node Set :
Set contains 1 nodes:
1  ELEMENT EXAMPLE
```

so a case has a kind (boolean, number, string, node-set) and a value. For a
node-set the value is its size plus the kind and local name of each top-level
node, which is what a different implementation can be compared on.

`scripts/gen_xpath_cases.py` turns this into `tests/xpath_cases.mbt`, and
`tests/xpath_conformance_test.mbt` measures the engine against it. The
`Copyright` file is libxml2's licence (MIT).
