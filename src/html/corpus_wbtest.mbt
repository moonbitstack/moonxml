// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// html5lib's tree-construction corpus, every case answering what it asks for:
/// a document read, or a fragment read in its context, then the tree spelled
/// the way the corpus spells it. A failure is a diff.
///
/// Every case that speaks for scripting off is here; the eight marked
/// `#script-on` are not, and each of them has a `#script-off` twin that is.
///
/// The documents are the corpus's, in `html_corpus_wbtest.mbt`.
test "the corpus: every case reproduces exactly" {
  let mut passed = 0
  let failed : Array[String] = []
  for entry in corpus {
    let (name, kind, context, source, expected) = entry
    let got = if kind == "fragment" {
      shape_in(source, context)
    } else {
      shape(source)
    }
    if got == expected {
      passed = passed + 1
    } else if failed.length() < 4000 {
      failed.push(name)
    }
  }
  let mut report = ""
  if passed < corpus.length() {
    report = passed.to_string() +
      " of " +
      corpus.length().to_string() +
      " reproduce; the rest:/n" +
      failed.join("\n")
  }
  assert_eq(report, "")
}
