// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// html5lib's tree-construction corpus, every case answering what it asks for:
/// a document read, or a fragment read in its context, then the tree spelled
/// the way the corpus spells it. A failure is a diff.
///
/// Every case is here, script-on and script-off alike: the flag each one asks
/// for travels with it, and the reader is asked for the same one.
///
/// The documents are the corpus's, in `html_corpus_wbtest.mbt`.
test "the corpus: every case reproduces exactly" {
  let mut passed = 0
  let failed : Array[String] = []
  for entry in corpus {
    let (name, kind, context, source, expected, scripting) = entry
    let got = if kind == "fragment" {
      shape_in(source, context, scripting~)
    } else {
      shape(source, scripting~)
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
