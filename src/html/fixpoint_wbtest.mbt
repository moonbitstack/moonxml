// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A property the corpus cannot state: parsing is idempotent once written. If a
// document writes to `s`, then reading `s` must give the same tree, so writing
// it again must give `s` back. Every tree-construction case is a candidate, so
// this is a second look at all of them — the corpus comparison only ever sees
// the first read, and a writer that disagrees with the reader about the tree
// they share passes it.
//
// Some families of trees are left out, because HTML has no syntax for them:
// a `plaintext` element swallows everything after its start tag, its own end
// tag included; a tree that nests an element inside a namesake whose start tag
// closes or ignores a namesake (an `<a>` inside an `<a>`, a `<p>` inside a
// `<p>`) cannot have come from text; a script whose content carries `<!--` or
// its own end tag leaves script data, so the end tag written after it is not
// the end tag; a doctype identifier carrying a quote has no escaping; and a
// fragment read in a context that takes its content as raw text or RCDATA has
// no document form. Of the corpus's 1784 cases, 1575 round-trip today and 209
// are excluded: 28 plaintext, 29 namesake, 143 script data, 3 doctype
// identifiers, 6 text-only fragment contexts. The exclusions are counted, not
// dropped quietly.

///|
/// Elements whose start tag closes, ignores or merges a namesake, so a tree
/// that nests one inside the other has no source form.
fn closes_namesake(name : String) -> Bool {
  match name {
    "p"
    | "a"
    | "form"
    | "nobr"
    | "button"
    | "select"
    | "option"
    | "li"
    | "dd"
    | "dt"
    | "html"
    | "head"
    | "body"
    | "frameset"
    | "plaintext" => true
    _ => false
  }
}

///|
fn has_ancestor_named(element : @moonxml.Element, name : String) -> Bool {
  let mut current = element.parent
  while current is Some(above) {
    if @moonxml.local_of(above.name) == name {
      return true
    }
    current = above.parent
  }
  false
}

///|
/// Elements whose content the reader takes as raw text: `</script` inside one
/// ends it on the way back, so a text that carries the sequence cannot be
/// written down and read back.
fn is_raw_text(name : String) -> Bool {
  match name {
    "script"
    | "style"
    | "xmp"
    | "iframe"
    | "noembed"
    | "noframes"
    | "noscript" => true
    _ => false
  }
}

///|
fn holds_its_own_end_tag(element : @moonxml.Element) -> Bool {
  let name = @moonxml.local_of(element.name)
  if !is_raw_text(name) {
    return false
  }
  for node in element.children {
    if node is @moonxml.TextNode(text) {
      let lower = text.to_lower()
      // A script's content can also leave script data by writing `<!--`: from
      // there the end tag is not the end tag, and the text written after it
      // comes back as content.
      if lower.contains("</" + name) ||
        (name == "script" && lower.contains("<!--")) {
        return true
      }
    }
  }
  false
}

///|
/// Whether the tree under `element` holds something HTML has no syntax for: a
/// `plaintext`, a namesake nested in a namesake whose start tag closes it, a
/// raw-text element carrying its own end tag, or a doctype whose identifiers
/// carry a quote.
fn cannot_be_written(element : @moonxml.Element) -> Bool {
  for node in element.children {
    if node is @moonxml.ElementNode(child) {
      let name = @moonxml.local_of(child.name)
      if name == "plaintext" {
        return true
      }
      if closes_namesake(name) && has_ancestor_named(child, name) {
        return true
      }
      if holds_its_own_end_tag(child) {
        return true
      }
      if cannot_be_written(child) {
        return true
      }
      match child.content() {
        Some(fragment) => if cannot_be_written(fragment) { return true }
        None => ()
      }
    } else if node is @moonxml.DoctypeNode(text) {
      let mut quotes = 0
      for ch in text {
        if ch == '"' {
          quotes = quotes + 1
        }
      }
      if quotes > 4 {
        return true
      }
    }
  }
  false
}

///|
/// Read a case the way the corpus read it, so the comparison is about the tree
/// and not about a different parser configuration.
fn read_case(
  source : String,
  kind : String,
  context : String,
) -> @moonxml.Document {
  if kind == "fragment" {
    loads_fragment(source, context~)
  } else {
    loads(source)
  }
}

///|
/// A fragment is written as the document its nodes make, so a fragment read in
/// a context that takes its content as raw text or RCDATA has no document form
/// to be written to: the context decides how the text is escaped, and the
/// serialisation has nothing to say it.
fn context_is_text_only(kind : String, context : String) -> Bool {
  if kind != "fragment" {
    return false
  }
  match @moonxml.local_of(context) {
    "script"
    | "style"
    | "textarea"
    | "title"
    | "xmp"
    | "iframe"
    | "noembed"
    | "noframes"
    | "plaintext"
    | "noscript" => true
    _ => false
  }
}

///|
test "a written document reads back to the same text" {
  let mut written = 0
  let mut excluded = 0
  let failed : Array[String] = []
  for entry in corpus {
    let (name, kind, context, source, _) = entry
    if context_is_text_only(kind, context) {
      excluded = excluded + 1
      continue
    }
    let first = read_case(source, kind, context)
    if cannot_be_written(first.root) {
      excluded = excluded + 1
      continue
    }
    let text = first.dumps()
    let second = read_case(text, kind, context)
    written = written + 1
    if second.dumps() != text {
      if failed.length() < 40 {
        failed.push(name + "\n  wrote " + text + "\n  again " + second.dumps())
      }
    }
  }
  let mut report = ""
  if failed.length() > 0 {
    report = failed.length().to_string() +
      " of " +
      written.to_string() +
      " do not round-trip://n" +
      failed.join("\n")
  }
  assert_eq(report, "")
  // Every case either round-trips or is excluded for a stated reason; a
  // document that silently stops being tested is the failure mode to watch.
  assert_eq(excluded > 0, true)
}
