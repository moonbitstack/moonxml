# moonxml

Tag documents in, a tree you can walk, query and change out.

> **Status: planned.** The repository is set up; nothing is
> implemented yet.

HTML, XML and SVG parse into one tree. The tree can be queried — XPath, CSS
selectors, or by hand — and **edited**: a document read is a document you can
write back.

| Decided | Why |
|:--|:--|
| WHATWG's recovery rules | Malformed HTML is the normal case; how to recover is written down, so it is not invented here |
| One mutable tree | Editing a document by rebuilding it is not editing it |
| Two query languages | XPath and CSS selectors answer different questions; both are what people already know |

## Install

```bash
moon add moonbitstack/moonxml
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
