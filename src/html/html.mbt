// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// HTML, the WHATWG way: the tokenizer's states and the tree construction
/// algorithm, so malformed input repairs the way a browser repairs it. What
/// the parser fixed is on `document.repairs()`; the document is never
/// refused.
///
/// One algorithm, one tree builder: the tokenizer hands tokens to the
/// builder, which is the only thing that touches the tree.

///|
/// The tokenizer, a state machine over the source.
priv struct Lexer {
  text : String
  /// The element whose content runs raw, if one does: `script`, `style`,
  /// `title`, `textarea`, … — RAWTEXT and RCDATA folded into one because they
  /// share their shape. `rcdata` says whether references decode inside.
  mut raw : String
  mut rcdata : Bool
  builder : Builder
}

///|
/// The builder: the tree, the open-element stack, the formatting elements and
/// the insertion mode.
priv struct Builder {
  doc : @moonxml.Document
  stack : Array[@moonxml.Element]
  /// The active formatting elements; `None` is a marker.
  afe : Array[@moonxml.Element?]
  mut mode : Mode
  mut head : @moonxml.Element?
  mut form : @moonxml.Element?
  repairs : @moonxml.Repairs
  mut quirks : Bool
  /// Set while a table's stray content is being put before the table.
  mut foster : Bool
  /// The characters "in table text" is holding.
  mut pending : String
  /// Set while a raw-text element is open: everything up to its end tag is its
  /// text, and nothing else can happen.
  mut text_only : Bool
}

///|
/// The insertion modes of the spec, in its order.
priv enum Mode {
  Initial
  BeforeHtml
  BeforeHead
  InHead
  AfterHead
  InBody
  InTable
  InTableText
  InCaption
  InColumnGroup
  InTableBody
  InRow
  InCell
  InSelect
  InSelectInTable
  AfterBody
  AfterAfterBody
}

///|
/// Which elements end a scope: the spec's five families.
priv enum Scope {
  Default
  ListItem
  Button
  Table
  Select
}

///|
/// Read a document.
pub fn loads(text : String) -> @moonxml.Document {
  parse(text)
}

///|
/// Read a document from bytes; UTF-8, with a leading byte-order mark skipped.
pub fn load(bytes : Bytes) -> @moonxml.Document {
  let text = @utf8.decode_lossy(bytes, ignore_bom=true)
  parse(text)
}

///|
/// Read a fragment in the body context, the way `innerHTML` does.
pub fn loads_fragment(text : String) -> @moonxml.Document {
  let doc = @moonxml.Document::new(flavour=@moonxml.Html)
  let builder : Builder = {
    doc,
    stack: [doc.root],
    afe: [],
    mode: InBody,
    head: None,
    form: None,
    repairs: @moonxml.Repairs::new(),
    quirks: false,
    foster: false,
    pending: "",
    text_only: false,
  }
  let lexer : Lexer = {
    text: @text.strip_bom(text),
    raw: "",
    rcdata: false,
    builder,
  }
  tokenize(lexer)
  finish(builder)
  doc
}

///|
fn parse(text : String) -> @moonxml.Document {
  let doc = @moonxml.Document::new(flavour=@moonxml.Html)
  let builder : Builder = {
    doc,
    stack: [doc.root],
    afe: [],
    mode: Initial,
    head: None,
    form: None,
    repairs: @moonxml.Repairs::new(),
    quirks: false,
    foster: false,
    pending: "",
    text_only: false,
  }
  let lexer : Lexer = {
    text: @text.strip_bom(text),
    raw: "",
    rcdata: false,
    builder,
  }
  tokenize(lexer)
  finish(builder)
  doc
}

///|
fn finish(builder : Builder) -> Unit {
  builder.doc.set_repairs(builder.repairs)
}

// ---------------------------------------------------------------- tokenizer

///|
/// Run the tokenizer over the source, handing each token to the builder.
fn tokenize(lexer : Lexer) -> Unit {
  let text = lexer.text
  let n = text.length()
  let mut at = 0
  while at < n {
    if !lexer.raw.is_empty() {
      at = raw_run(lexer, at)
      continue
    }
    let unit = text.at(at)
    if unit == 0x3C {
      at = markup(lexer, at)
    } else {
      let start = at
      while at < n && text.at(at) != 0x3C {
        at = at + 1
      }
      let body = decode(text[start:at].to_owned(), at=start)
      if !body.is_empty() {
        builder_chars(lexer.builder, body)
      }
    }
  }
  builder_eof(lexer.builder)
}

///|
/// The raw text states: everything up to the matching end tag is one run of
/// characters (entity-decoded for RCDATA, exactly as it stands otherwise).
fn raw_run(lexer : Lexer, from : Int32) -> Int32 {
  let text = lexer.text
  let n = text.length()
  if lexer.raw == "plaintext" {
    let body = text[from:n].to_owned()
    if !body.is_empty() {
      builder_chars(lexer.builder, body)
    }
    return n
  }
  let name = lexer.raw
  let rcdata = lexer.rcdata
  let mut at = from
  while at < n {
    if text.at(at) == 0x3C && at + 1 < n && text.at(at + 1) == 0x2F {
      // is this the end tag that closes the raw text?
      let (closing, after) = read_tag_name(text, at + 2)
      if closing == name {
        let end = match skip_to_gt(text, after) {
          Some(found) => found
          None => n
        }
        let body = text[from:at].to_owned()
        if !body.is_empty() {
          builder_chars(
            lexer.builder,
            if rcdata {
              decode(body, at=from)
            } else {
              body
            },
          )
        }
        lexer.rcdata = false
        lexer.raw = ""
        lexer.builder.text_only = false
        builder_end(lexer.builder, name)
        return end
      }
    }
    at = at + 1
  }
  let body = text[from:n].to_owned()
  if !body.is_empty() {
    builder_chars(
      lexer.builder,
      if rcdata {
        decode(body, at=from)
      } else {
        body
      },
    )
  }
  n
}

///|
/// Markup at an angle bracket: a start tag, an end tag, a comment, a doctype,
/// or — when none of those — a bogus comment, which is what the spec says to
/// do with it.
fn markup(lexer : Lexer, from : Int32) -> Int32 {
  let text = lexer.text
  let n = text.length()
  if from + 1 >= n {
    builder_chars(lexer.builder, "<")
    return n
  }
  let unit = text.at(from + 1)
  if unit == 0x21 {
    // '<!'
    if starts(text, from, "<!-->") {
      builder_comment(lexer.builder, "")
      return from + 5
    }
    if starts(text, from, "<!--- >") {
      builder_comment(lexer.builder, " ")
      return from + 8
    }
    if starts(text, from, "<!--") {
      let start = from + 4
      let close = match find_text(text, "-->", start) {
        Some(found) => found
        None => n
      }
      let body = text[start:close].to_owned()
      builder_comment(lexer.builder, body)
      return close + 3
    }
    if starts(text, from, "<![CDATA[") {
      // CDATA is a comment outside foreign content, as the spec says
      let start = from + 9
      let close = match find_text(text, "]]>", start) {
        Some(found) => found
        None => n
      }
      builder_comment(
        lexer.builder,
        "[CDATA[" + text[start:close].to_owned() + "]]",
      )
      return close + 3
    }
    if starts_ci(text, from, "<!doctype") {
      return doctype(lexer, from)
    }
    return bogus_comment(lexer, from + 2)
  }
  if unit == 0x3F {
    // A question mark opens a bogus comment whose data starts with it.
    return bogus_comment(lexer, from + 1)
  }
  if unit == 0x2F {
    // '</'
    if from + 2 >= n {
      builder_chars(lexer.builder, "</")
      return n
    }
    let next = text.at(from + 2)
    if !is_alpha(next) {
      return bogus_comment(lexer, from + 2)
    }
    let (name, after) = read_tag_name(text, from + 2)
    return tag(lexer, after, name, is_end=true)
  }
  if !is_alpha(unit) {
    builder_chars(lexer.builder, "<")
    return from + 1
  }
  let (name, after) = read_tag_name(text, from + 1)
  tag(lexer, after, name, is_end=false)
}

///|
/// A start or end tag: its attributes, its self-closing solidus, and then the
/// content the tag dictates.
fn tag(lexer : Lexer, from : Int32, name : String, is_end~ : Bool) -> Int32 {
  let text = lexer.text
  let n = text.length()
  let attrs : Array[(String, String)] = []
  let mut at = from
  let mut self_closing = false
  while true {
    while at < n && is_space(text.at(at)) {
      at = at + 1
    }
    if at >= n {
      break
    }
    if text.at(at) == 0x3E {
      at = at + 1
      break
    }
    if text.at(at) == 0x2F && at + 1 < n && text.at(at + 1) == 0x3E {
      self_closing = true
      at = at + 2
      break
    }
    // an attribute name
    let start = at
    while at < n {
      let unit = text.at(at)
      if is_space(unit) || unit == 0x3D || unit == 0x3E || unit == 0x2F {
        break
      }
      at = at + 1
    }
    let attr = lower(text[start:at].to_owned())
    let mut value = ""
    while at < n && is_space(text.at(at)) {
      at = at + 1
    }
    if at < n && text.at(at) == 0x3D {
      at = at + 1
      while at < n && is_space(text.at(at)) {
        at = at + 1
      }
      if at < n && (text.at(at) == 0x22 || text.at(at) == 0x27) {
        let quote = text.at(at)
        at = at + 1
        let start = at
        while at < n && text.at(at) != quote {
          at = at + 1
        }
        value = decode(text[start:at].to_owned(), at=start)
        if at < n {
          at = at + 1
        }
      } else {
        let start = at
        while at < n && !is_space(text.at(at)) && text.at(at) != 0x3E {
          at = at + 1
        }
        value = decode(text[start:at].to_owned(), at=start)
      }
    }
    if attr.is_empty() {
      // A character that cannot start or end a name: skip it rather than
      // read the same position again.
      at = at + 1
      continue
    }
    let mut seen = false
    for pair in attrs {
      if pair.0 == attr {
        seen = true
      }
    }
    if !seen {
      attrs.push((attr, value))
    } else {
      lexer.builder.repairs.dropped = lexer.builder.repairs.dropped + 1
    }
  }
  if is_end {
    builder_end(lexer.builder, name)
    return at
  }
  builder_start(lexer.builder, name, attrs, self_closing~)
  // A start tag may put the tokenizer into a raw text state.
  match name {
    "script" | "style" | "xmp" | "iframe" | "noembed" | "noframes" =>
      if !self_closing {
        lexer.raw = name
        lexer.rcdata = false
        lexer.builder.text_only = true
      }
    "title" | "textarea" =>
      if !self_closing {
        lexer.raw = name
        lexer.rcdata = true
        lexer.builder.text_only = true
      }
    "plaintext" =>
      if !self_closing {
        lexer.raw = "plaintext"
        lexer.rcdata = false
        lexer.builder.text_only = true
      }
    _ => ()
  }
  at
}

///|
fn read_tag_name(text : String, from : Int32) -> (String, Int32) {
  let n = text.length()
  let mut at = from
  while at < n {
    let unit = text.at(at)
    if is_space(unit) || unit == 0x3E || unit == 0x2F {
      break
    }
    at = at + 1
  }
  (lower(text[from:at].to_owned()), at)
}

///|
fn skip_to_gt(text : String, from : Int32) -> Int32? {
  let n = text.length()
  let mut at = from
  while at < n {
    if text.at(at) == 0x3E {
      return Some(at + 1)
    }
    at = at + 1
  }
  None
}

///|
fn bogus_comment(lexer : Lexer, from : Int32) -> Int32 {
  let text = lexer.text
  let n = text.length()
  let start = from
  let mut at = from
  while at < n && text.at(at) != 0x3E {
    at = at + 1
  }
  builder_comment(lexer.builder, text[start:at].to_owned())
  at + 1
}

///|
fn doctype(lexer : Lexer, from : Int32) -> Int32 {
  let text = lexer.text
  let n = text.length()
  let start = from + 9
  let mut at = start
  while at < n && is_space(text.at(at)) {
    at = at + 1
  }
  let name_start = at
  while at < n && !is_space(text.at(at)) && text.at(at) != 0x3E {
    at = at + 1
  }
  let name = lower(text[name_start:at].to_owned())
  let quirks = name != "html"
  let after = match skip_to_gt(text, at) {
    Some(found) => found
    None => n
  }
  builder_doctype(lexer.builder, name, quirks~)
  after
}

// ------------------------------------------------------------ small helpers

///|
fn is_space(unit : UInt16) -> Bool {
  unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0C || unit == 0x0D
}

///|
fn is_alpha(unit : UInt16) -> Bool {
  (unit >= 0x61 && unit <= 0x7A) || (unit >= 0x41 && unit <= 0x5A)
}

///|
fn lower(text : String) -> String {
  let out = StringBuilder()
  for ch in text {
    if ch >= 'A' && ch <= 'Z' {
      out.write_char((ch.to_int() + 0x20).unsafe_to_char())
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
fn starts(text : String, at : Int32, probe : String) -> Bool {
  at + probe.length() <= text.length() && text[at:at + probe.length()] == probe
}

///|
fn starts_ci(text : String, at : Int32, probe : String) -> Bool {
  at + probe.length() <= text.length() &&
  lower(text[at:at + probe.length()].to_owned()) == lower(probe)
}

///|
fn find_text(text : String, probe : String, from : Int32) -> Int32? {
  let n = text.length()
  let m = probe.length()
  let mut i = from
  while i + m <= n {
    if text[i:i + m] == probe {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn unit_char(unit : UInt16) -> Char {
  match unit.to_char() {
    Some(ch) => ch
    None => '?'
  }
}

///|
/// Decode the character references in a run of text: numeric always, named
/// when the name is one the table carries and the reference ends properly —
/// which is the spec's rule for attributes too, so the same function serves
/// both.
fn decode(text : String, at~ : Int32) -> String {
  if !text.contains("&") {
    return text
  }
  let out = StringBuilder()
  let n = text.length()
  let mut i = 0
  while i < n {
    if text.at(i) != 0x26 {
      out.write_char(unit_char(text.at(i)))
      i = i + 1
      continue
    }
    let (decoded, next) = reference(text, i)
    ignore(at)
    out.write_string(decoded)
    i = next
  }
  out.to_string()
}

///|
/// One character reference at `from`, answering what it decodes to and where
/// the text continues.
fn reference(text : String, from : Int32) -> (String, Int32) {
  let n = text.length()
  let mut i = from + 1
  if i >= n {
    return ("&", from + 1)
  }
  if text.at(i) == 0x23 {
    // numeric
    i = i + 1
    let mut hex = false
    if i < n && (text.at(i) == 0x78 || text.at(i) == 0x58) {
      hex = true
      i = i + 1
    }
    let start = i
    while i < n &&
          (if hex {
            is_hex(text.at(i))
          } else {
            text.at(i) >= 0x30 && text.at(i) <= 0x39
          }) {
      i = i + 1
    }
    if i == start {
      return ("&", from + 1)
    }
    let digits = text[start:i].to_owned()
    if i < n && text.at(i) == 0x3B {
      i = i + 1
    }
    let code = parse_reference(digits, hex)
    match code {
      Some(value) =>
        if value <= 0 ||
          value > 0x10FFFF ||
          (value >= 0xD800 && value <= 0xDFFF) {
          ("\u{FFFD}", i)
        } else {
          (code_text(remap_c1(value)), i)
        }
      None => ("&", from + 1)
    }
  } else {
    // named: the longest name the table carries
    let start = i
    while i < n && i - start < 32 && is_alnum(text.at(i)) {
      i = i + 1
    }
    if i == start {
      return ("&", from + 1)
    }
    let mut probe = text[start:i].to_owned()
    let mut end = i
    let mut answer : (String, Int32)? = None
    while answer is None && probe.length() >= 1 {
      match named_reference(probe) {
        Some(value) =>
          if end < n && text.at(end) == 0x3B {
            answer = Some((value, end + 1))
          } else {
            // a name without its semicolon still resolves, as the spec allows
            answer = Some((value, end))
          }
        None =>
          if probe.length() == 1 {
            answer = Some(("&", from + 1))
          } else {
            probe = probe[0:probe.length() - 1].to_owned()
            end = end - 1
          }
      }
    }
    match answer {
      Some(pair) => pair
      None => ("&", from + 1)
    }
  }
}

///|
/// The number a character reference spells, or `None` when it does not spell
/// one.
fn parse_reference(digits : String, hex : Bool) -> Int32? {
  let parsed = Some(@string.parse_int(digits, base=if hex { 16 } else { 10 })) catch {
    _ => None
  }
  parsed
}

///|
fn is_hex(unit : UInt16) -> Bool {
  (unit >= 0x30 && unit <= 0x39) ||
  (unit >= 0x61 && unit <= 0x66) ||
  (unit >= 0x41 && unit <= 0x46)
}

///|
fn is_alnum(unit : UInt16) -> Bool {
  is_alpha(unit) || (unit >= 0x30 && unit <= 0x39)
}

///|
/// The spec's Windows-1252 repair: a reference in the C1 range means what the
/// byte meant on a page written in 1997, so `&#x80;` is a euro sign.
fn remap_c1(value : Int32) -> Int32 {
  match value {
    0x80 => 0x20AC
    0x82 => 0x201A
    0x83 => 0x0192
    0x84 => 0x201E
    0x85 => 0x2026
    0x86 => 0x2020
    0x87 => 0x2021
    0x88 => 0x02C6
    0x89 => 0x2030
    0x8A => 0x0160
    0x8B => 0x2039
    0x8C => 0x0152
    0x8E => 0x017D
    0x91 => 0x2018
    0x92 => 0x2019
    0x93 => 0x201C
    0x94 => 0x201D
    0x95 => 0x2022
    0x96 => 0x2013
    0x97 => 0x2014
    0x98 => 0x02DC
    0x99 => 0x2122
    0x9A => 0x0161
    0x9B => 0x203A
    0x9C => 0x0153
    0x9E => 0x017E
    0x9F => 0x0178
    _ => value
  }
}

///|
fn code_text(value : Int32) -> String {
  let out = StringBuilder()
  out.write_char(value.unsafe_to_char())
  out.to_string()
}
