// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A property the corpus cannot state: parsing is idempotent once written. If a
// document writes to `s`, then reading `s` must give the same tree, so writing
// it again must give `s` back. Every tree-construction case is a candidate, so
// this is a second look at all of them — the corpus comparison only ever sees
// the first read, and a writer that disagrees with the reader about the tree
// they share passes it.
//
// The test attempts the round trip on every case and only falls back on an
// exclusion when the attempt fails, because a tree the writer cannot express is
// the exception, not the rule. A failed case still has to name the construct
// that makes it unwritable, and each family has a ceiling, so a case that
// starts failing lands on the family that already covers it only if that family
// has room to spare; otherwise the count goes over and the test is red. The
// numbers can go down and never up.
//
// The families, with the clause each one rests on:
//
// - `fragment`, a fragment read in a context whose content is raw text. A
//   fragment is written as the document its nodes make, and the serialisation
//   has no way to record the context it will be read in: text is escaped as
//   WHATWG's serialisation escapes text, and a raw-text context (script, style,
//   xmp, iframe, noembed, noframes, plaintext, noscript) does not decode it,
//   so the escapes come back as characters.
// - `plaintext`: the tokenizer's PLAINTEXT state (WHATWG §13.2.5.5) has no end
//   tag — everything after `<plaintext>` is text, including the `</plaintext>`
//   the writer emits for the element's own end tag, so the element grows a
//   level on every read.
// - `script`: raw text that carries `</` and the element's own name, or a
//   `<!--` the text never closes with `-->`. WHATWG's serialisation appends a
//   raw-text element's text verbatim (§13.3), and the tokenizer leaves the
//   element at either sequence, so the end tag written after it is not the end
//   tag.
// - `doctype`: a doctype whose public or system identifier carries a `"`. The
//   doctype's syntax has no escape for its own delimiters, so two identifiers
//   that each carry one cannot be told from the four quotes the writer emits.
// - `namesake`: an element from the set whose start tag closes, ignores or
//   merges a namesake, nested inside an ancestor of the same name (`a` in `a`,
//   `p` in `p`, `form` in `form`). §13.2.6.4.7 does that on the way in, so the
//   nesting has no source form.
//
// WHATWG's own note on the algorithm says the same thing in one line: the
// output, parsed again, need not give the original tree.
//
// Against the current corpus 1728 of 1792 cases round-trip; the 64 that do not
// are 28 plaintext, 8 namesake, 24 script data, 1 doctype identifier and 3
// raw-text fragment contexts.

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
/// Elements whose content the reader takes as raw text: escaping is not applied
/// to them, so a text that closes them on the way back cannot be written down.
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
/// Whether a script's text ends inside a `<!--` that nothing closes. The
/// tokenizer's escaped states (WHATWG §13.2.5.4.26) are entered by `<!--` and
/// left by `-->`; a text that ends in one leaves the element open, so the end
/// tag the writer appends is text.
fn ends_inside_a_script_comment(text : String) -> Bool {
  let mut i = 0
  let mut escaped = false
  while i < text.length() {
    if !escaped && text[i:text.length()].has_prefix("<!--") {
      escaped = true
      i = i + 4
    } else if escaped && text[i:text.length()].has_prefix("-->") {
      escaped = false
      i = i + 3
    } else {
      i = i + 1
    }
  }
  escaped
}

///|
/// Whether a text inside `name` takes the reader out of the element before the
/// end tag the writer appends: its own end tag, or a script comment the text
/// never closes, which leaves the tokenizer in a state where `</script>` is not
/// the end tag.
fn leaves_raw_text(name : String, text : String) -> Bool {
  let lower = text.to_lower()
  if lower.contains("</" + name) {
    return true
  }
  name == "script" && ends_inside_a_script_comment(lower)
}

///|
fn holds_its_own_end_tag(element : @moonxml.Element) -> Bool {
  let name = @moonxml.local_of(element.name)
  if !is_raw_text(name) {
    return false
  }
  for node in element.children {
    if node is @moonxml.TextNode(text) && leaves_raw_text(name, text) {
      return true
    }
  }
  // A template's content is a subtree of its own.
  match element.content() {
    Some(fragment) => return holds_its_own_end_tag(fragment)
    None => ()
  }
  false
}

///|
/// Whether a doctype's identifiers carry the quote that delimits them.
fn doctype_carries_a_quote(text : String) -> Bool {
  let mut quotes = 0
  for ch in text {
    if ch == '"' {
      quotes = quotes + 1
    }
  }
  quotes > 4
}

///|
/// Which family of unwritable trees `element` belongs to, if any.
fn unwritable_family(element : @moonxml.Element) -> String? {
  for node in element.children {
    match node {
      @moonxml.ElementNode(child) => {
        let name = @moonxml.local_of(child.name)
        if name == "plaintext" {
          return Some("plaintext")
        }
        if holds_its_own_end_tag(child) {
          return Some("script")
        }
        if closes_namesake(name) && has_ancestor_named(child, name) {
          return Some("namesake")
        }
        match unwritable_family(child) {
          Some(family) => return Some(family)
          None => ()
        }
        match child.content() {
          Some(fragment) =>
            match unwritable_family(fragment) {
              Some(family) => return Some(family)
              None => ()
            }
          None => ()
        }
      }
      @moonxml.DoctypeNode(text) =>
        if doctype_carries_a_quote(text) {
          return Some("doctype")
        }
      _ => ()
    }
  }
  None
}

///|
/// Read a case the way the corpus read it, so the comparison is about the tree
/// and not about a different parser configuration.
fn read_case(
  source : String,
  kind : String,
  context : String,
  scripting~ : Bool,
) -> @moonxml.Document {
  if kind == "fragment" {
    loads_fragment(source, context~, scripting~)
  } else {
    loads(source, scripting~)
  }
}

///|
/// A fragment is written as the document its nodes make, so a fragment read in
/// a context that takes its content as raw text has no document form to be
/// written to: the context decides how the text is escaped, and the
/// serialisation has nothing to say it.
fn context_takes_text_raw(kind : String, context : String) -> Bool {
  if kind != "fragment" {
    return false
  }
  match @moonxml.local_of(context) {
    "script"
    | "style"
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
/// The cases each family is allowed to keep. A family that grows past its
/// ceiling is a regression the family's own construct does not explain.
let plaintext_ceiling : Int32 = 28

///|
let namesake_ceiling : Int32 = 8

///|
let script_ceiling : Int32 = 24

///|
let doctype_ceiling : Int32 = 1

///|
let fragment_ceiling : Int32 = 3

///|
let exclusion_ceiling : Int32 = plaintext_ceiling +
  namesake_ceiling +
  script_ceiling +
  doctype_ceiling +
  fragment_ceiling

///|
test "a written document reads back to the same text" {
  let mut written = 0
  let mut plaintext = 0
  let mut namesake = 0
  let mut script = 0
  let mut doctype = 0
  let mut fragment = 0
  let failures : Array[String] = []
  for entry in corpus {
    let (name, kind, context, source, _, scripting) = entry
    let first = read_case(source, kind, context, scripting~)
    let text = first.dumps()
    let second = read_case(text, kind, context, scripting~)
    let again = second.dumps()
    if again == text {
      written = written + 1
      continue
    }
    let family = if context_takes_text_raw(kind, context) {
      "fragment"
    } else {
      match unwritable_family(first.root) {
        Some(family) => family
        // Nothing about the tree says it cannot be written. That is a bug in
        // the writer or in the reader, and it is reported as one.
        None => "unexplained"
      }
    }
    match family {
      "plaintext" => plaintext = plaintext + 1
      "namesake" => namesake = namesake + 1
      "script" => script = script + 1
      "doctype" => doctype = doctype + 1
      "fragment" => fragment = fragment + 1
      _ => failures.push(name + "\n  wrote " + text + "\n  again " + again)
    }
  }
  let mut report = ""
  if failures.length() > 0 {
    report = failures.length().to_string() +
      " cases do not round-trip and no construct explains them:\n" +
      failures.join("\n")
  }
  // Each family is capped at what its construct explains, counted case by case.
  if plaintext > plaintext_ceiling {
    report = report + "\nplaintext: " + plaintext.to_string() + " over"
  }
  if namesake > namesake_ceiling {
    report = report + "\nnamesake: " + namesake.to_string() + " over"
  }
  if script > script_ceiling {
    report = report + "\nscript: " + script.to_string() + " over"
  }
  if doctype > doctype_ceiling {
    report = report + "\ndoctype: " + doctype.to_string() + " over"
  }
  if fragment > fragment_ceiling {
    report = report + "\nfragment: " + fragment.to_string() + " over"
  }
  assert_eq(report, "")
  // Every case was judged, one way or the other; a document that silently
  // stops being tested is the failure mode to watch.
  assert_eq(
    written + plaintext + namesake + script + doctype + fragment,
    corpus.length(),
  )
  // The exclusion is a shrinking set, not a budget to spend.
  assert_eq(
    plaintext + namesake + script + doctype + fragment <= exclusion_ceiling,
    true,
  )
}
