// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The W3C CSS3 selectors suite. A file holds several rules and one list of ids that
// end up lime, so the file is judged whole: what its rules match between them has to
// be every id it wants and none it refuses. The documents are XHTML, read as XML where
// they are well formed and as HTML where they are not, as a browser would.

///|
fn css_case_ids(s : String) -> Array[String] {
  let out : Array[String] = []
  if s == "" {
    return out
  }
  let sb = StringBuilder()
  for c in s {
    if c == ',' {
      out.push(sb.to_string())
      sb.reset()
    } else {
      sb.write_char(c)
    }
  }
  if sb.to_string().length() > 0 {
    out.push(sb.to_string())
  }
  out
}

///|
fn css_matched_ids(sel : @moonxml.Selection) -> Array[String] {
  let out : Array[String] = []
  for item in sel.items {
    match item {
      @moonxml.ElementNode(e) =>
        match e.attr("id") {
          Some(id) => out.push(id)
          None => ()
        }
      _ => ()
    }
  }
  out
}

///|
/// Files that do not pass yet, each a gap in the engine. A file leaving this list
/// has to be taken off it, so the list can only shrink.
let known_files : Array[String] = [
  "css3-modsel-22.xml", "css3-modsel-47.xml", "css3-modsel-57.xml", "css3-modsel-70.xml",
  "css3-modsel-94.xml", "css3-modsel-95.xml", "css3-modsel-96.xml", "css3-modsel-97.xml",
  "css3-modsel-98.xml", "css3-modsel-100.xml", "css3-modsel-104.xml", "css3-modsel-107.xml",
  "css3-modsel-111.xml", "css3-modsel-113.xml", "css3-modsel-114.xml", "css3-modsel-118.xml",
  "css3-modsel-120.xml", "css3-modsel-124.xml", "css3-modsel-130.xml", "css3-modsel-131.xml",
  "css3-modsel-132.xml", "css3-modsel-133.xml", "css3-modsel-137.xml", "css3-modsel-138.xml",
  "css3-modsel-139.xml", "css3-modsel-140.xml", "css3-modsel-144.xml", "css3-modsel-45c.xml",
  "css3-modsel-46b.xml", "css3-modsel-72b.xml", "css3-modsel-94b.xml",
]

///|
test "w3c selectors: every file passes but the known gaps" {
  let docs : Map[String, @moonxml.Document] = Map([])
  for pair in css_selector_docs() {
    let (name, text) = pair
    docs[name] = @xml.loads(text) catch { _ => @html.loads(text) }
  }
  let files : Map[String, Array[CssSelectorCase]] = Map([])
  for c in css_selector_cases() {
    match files.get(c.file) {
      Some(rules) => rules.push(c)
      None => files[c.file] = [c]
    }
  }
  let surprises = []
  for file, rules in files {
    let doc = docs.get(file).unwrap()
    let matched = []
    let mut refused = false
    for rule in rules {
      try doc.css(rule.selector) catch {
        _ => refused = true
      } noraise {
        sel => matched.push_iter(css_matched_ids(sel).iter())
      }
    }
    let ok = !refused &&
      css_case_ids(rules[0].expect).iter().all(id => matched.contains(id)) &&
      !css_case_ids(rules[0].reject).iter().any(id => matched.contains(id))
    if ok == known_files.contains(file) {
      surprises.push(if ok { "passes now: " + file } else { "fails: " + file })
    }
  }
  surprises.sort()
  assert_eq(surprises.join("\n"), "")
}
