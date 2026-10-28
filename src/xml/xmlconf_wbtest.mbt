// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a document does: `None` when it reads, the refusal when it does not.
fn outcome(source : String) -> String? {
  let doc = loads(source) catch { err => return Some(err.to_string()) }
  ignore(doc)
  None
}

///|
/// The W3C XML conformance suite, every case answering what the suite asks
/// for: a document it calls well-formed reads, and one it calls not well-formed
/// is refused. The documents are the suite's, in `xmlconf_data_wbtest.mbt`.
test "the conformance suite answers every case as the suite expects" {
  let mut passed = 0
  let failed : Array[String] = []
  for entry in conformance {
    let (name, kind, source) = entry
    let answer = outcome(source)
    let wanted = kind == "pass"
    if (answer is None) == wanted {
      passed = passed + 1
    } else {
      let got = match answer {
        None => "read"
        Some(err) => err
      }
      failed.push(name + " | want " + kind + " | got " + got)
    }
  }
  let mut report = ""
  if passed < conformance.length() {
    report = passed.to_string() +
      " of " +
      conformance.length().to_string() +
      " agree; the rest:/n" +
      failed.join("\n")
  }
  assert_eq(report, "")
}
