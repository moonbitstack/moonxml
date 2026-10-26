// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// XML 1.0 with Namespaces 1.0, strictly: a document is either well-formed
/// and read whole, or refused with the offset of the fault. What is read
/// survives the round-trip — attribute order, CDATA, comments, processing
/// instructions (their raw data), the doctype (its raw declaration) and the
/// self-closing syntax.
///
/// Names are resolved to the `{uri}local` spelling the tree carries; a
/// prefix nothing declared is a well-formedness error, and the two reserved
/// ones (`xml`, `xmlns`) are honoured as the spec says.

///|
/// The scanner's state: where it is, and what prefixes are in scope.
priv struct Scan {
  text : String
  mut at : Int32
  sink : &@event.Sink
  scopes : Array[Array[(String, String)]]
  fragment : Bool
  limit : Int32
}

///|
/// How deep elements may nest before a document is refused. Chrome and WebKit
/// stop at 512 nested elements; a document deeper than that is a stack to eat,
/// not a document.
pub let limit : Int32 = 512

///|
/// Read a document and answer its tree. `limit` bounds the element nesting.
pub fn loads(
  text : String,
  limit~ : Int32 = limit,
) -> @moonxml.Document raise @moonxml.Refused {
  let doc = @moonxml.Document::new(flavour=@moonxml.Xml)
  scan(text, doc, fragment=false, limit~)
  doc
}

///|
/// Read a document from bytes; UTF-8, with a leading byte-order mark skipped.
/// `limit` is as for `loads`.
pub fn load(
  bytes : Bytes,
  limit~ : Int32 = limit,
) -> @moonxml.Document raise @moonxml.Refused {
  match @text.decode(bytes) {
    Ok(text) => loads(text, limit~)
    Err(at) =>
      raise @moonxml.Malformed(at~, why="the bytes are not valid UTF-8")
  }
}

///|
/// Read content that has no single root — several elements, or text beside
/// them — into a document whose root holds them. Not a well-formed document,
/// which is the point: it is for a snippet.
pub fn loads_fragment(
  text : String,
  limit~ : Int32 = limit,
) -> @moonxml.Document raise @moonxml.Refused {
  let doc = @moonxml.Document::new(flavour=@moonxml.Xml)
  scan(text, doc, fragment=true, limit~)
  doc
}

///|
/// Stream a document's events into a sink, building nothing. `limit` is as for
/// `loads`.
pub fn scan(
  text : String,
  sink : &@event.Sink,
  fragment~ : Bool = false,
  limit~ : Int32 = limit,
) -> Unit raise @moonxml.Refused {
  let scanner : Scan = {
    text: @text.strip_bom(text),
    at: 0,
    sink,
    scopes: [[]],
    fragment,
    limit,
  }
  scan_document(scanner)
}

///|
fn scan_document(scanner : Scan) -> Unit raise @moonxml.Refused {
  prologue(scanner)
  if scanner.at >= scanner.text.length() {
    if scanner.fragment {
      return
    }
    raise @moonxml.Malformed(
      at=scanner.at,
      why="a document needs a root element",
    )
  }
  if scanner.fragment {
    fragment_body(scanner)
    return
  }
  content(scanner, 1)
  trailing(scanner)
}

///|
/// The prologue: the XML declaration, comments, processing instructions and
/// the doctype, in the order the spec allows.
fn prologue(scanner : Scan) -> Unit raise @moonxml.Refused {
  let mut seen_doctype = false
  let mut decl_seen = false
  while true {
    skip_space(scanner)
    if !starts_with(scanner, "<") {
      return
    }
    if starts_with(scanner, "<?xml") && is_space_at(scanner, scanner.at + 5) {
      if decl_seen {
        raise @moonxml.Malformed(
          at=scanner.at,
          why="one XML declaration is enough",
        )
      }
      decl_seen = true
      instruction(scanner)
      continue
    }
    if starts_with(scanner, "<!--") {
      comment(scanner)
      continue
    }
    if starts_with(scanner, "<?") {
      instruction(scanner)
      continue
    }
    if starts_with(scanner, "<!DOCTYPE") {
      if seen_doctype {
        raise @moonxml.Malformed(at=scanner.at, why="one doctype is enough")
      }
      seen_doctype = true
      doctype(scanner)
      continue
    }
    return
  }
}

///|
/// Everything after the root element: whitespace, comments and processing
/// instructions, and nothing else.
fn trailing(scanner : Scan) -> Unit raise @moonxml.Refused {
  while true {
    skip_space(scanner)
    if scanner.at >= scanner.text.length() {
      return
    }
    if starts_with(scanner, "<!--") {
      comment(scanner)
    } else if starts_with(scanner, "<?") {
      instruction(scanner)
    } else {
      raise @moonxml.Malformed(
        at=scanner.at,
        why="content after the root element",
      )
    }
  }
}

///|
/// A fragment: text, elements, comments and instructions, with no single root
/// required.
fn fragment_body(scanner : Scan) -> Unit raise @moonxml.Refused {
  let text = scanner.text
  while scanner.at < text.length() {
    if starts_with(scanner, "<!--") {
      comment(scanner)
    } else if starts_with(scanner, "<![CDATA[") {
      cdata(scanner)
    } else if starts_with(scanner, "<?") {
      instruction(scanner)
    } else if starts_with(scanner, "</") {
      raise @moonxml.Malformed(
        at=scanner.at,
        why="a close tag with no open one",
      )
    } else if starts_with(scanner, "<") {
      content(scanner, 1)
    } else {
      text_run(scanner)
    }
  }
}

///|
/// An element, its content, and its close: the recursive heart.
fn content(scanner : Scan, depth : Int32) -> Unit raise @moonxml.Refused {
  if depth > scanner.limit {
    raise @moonxml.Exceeded(at=scanner.at, limit=scanner.limit, got=depth)
  }
  let (name, attrs, self_closing) = start_tag(scanner)
  scanner.sink.push(@event.StartTag(name~, attrs~, self_closing~))
  if self_closing {
    return
  }
  let text = scanner.text
  while true {
    if scanner.at >= text.length() {
      raise @moonxml.Malformed(at=scanner.at, why="`<\{name}>` is never closed")
    }
    if starts_with(scanner, "</") {
      let close = end_tag(scanner)
      if close != name {
        raise @moonxml.Malformed(
          at=scanner.at,
          why="`</\{close}>` closes `<\{name}>`",
        )
      }
      scanner.sink.push(@event.EndTag(name~))
      return
    }
    if starts_with(scanner, "<!--") {
      comment(scanner)
    } else if starts_with(scanner, "<![CDATA[") {
      cdata(scanner)
    } else if starts_with(scanner, "<?") {
      instruction(scanner)
    } else if starts_with(scanner, "<!") {
      raise @moonxml.Malformed(
        at=scanner.at,
        why="a declaration inside content",
      )
    } else if starts_with(scanner, "<") {
      content(scanner, depth + 1)
    } else {
      text_run(scanner)
    }
  }
}

///|
/// A start tag: its resolved name, its resolved attributes in document order,
/// and whether it closed itself.
fn start_tag(
  scanner : Scan,
) -> (String, Array[(String, String)], Bool) raise @moonxml.Refused {
  let text = scanner.text
  scanner.at = scanner.at + 1
  let (qname, after) = read_name(scanner, scanner.at)
  scanner.at = after
  if qname.is_empty() {
    raise @moonxml.Malformed(
      at=scanner.at,
      why="an element needs a name after `<`",
    )
  }
  let raw : Array[(String, String)] = []
  let mut self_closing = false
  while true {
    skip_space(scanner)
    if scanner.at >= text.length() {
      raise @moonxml.Malformed(
        at=scanner.at,
        why="the tag `<\{qname}>` is unterminated",
      )
    }
    if text.at(scanner.at) == 0x3E {
      scanner.at = scanner.at + 1
      break
    }
    if starts_with(scanner, "/>") {
      self_closing = true
      scanner.at = scanner.at + 2
      break
    }
    let (attr, next) = read_name(scanner, scanner.at)
    if attr.is_empty() {
      raise @moonxml.Malformed(at=scanner.at, why="an attribute needs a name")
    }
    scanner.at = next
    skip_space(scanner)
    if !(scanner.at < text.length() && text.at(scanner.at) == 0x3D) {
      raise @moonxml.Malformed(
        at=scanner.at,
        why="XML attributes take values: `\{attr}`",
      )
    }
    scanner.at = scanner.at + 1
    skip_space(scanner)
    let value = attribute_value(scanner)
    for pair in raw {
      if pair.0 == attr {
        raise @moonxml.Malformed(
          at=scanner.at,
          why="a duplicate attribute: `\{attr}`",
        )
      }
    }
    raw.push((attr, value))
  }
  // The declarations apply to the element and its content, and the element's
  // own name is resolved against them.
  let scope : Array[(String, String)] = []
  for pair in raw {
    if pair.0 == "xmlns" {
      scope.push(("", pair.1))
    } else if pair.0.has_prefix("xmlns:") {
      scope.push((pair.0[6:pair.0.length()].to_owned(), pair.1))
    }
  }
  scanner.scopes.push(scope)
  let name = resolve(scanner, qname, true)
  // The declarations stay on the element: names are Clark, but the document's
  // own choice of prefix is what writing it back has to reproduce.
  let attrs : Array[(String, String)] = []
  for pair in raw {
    if pair.0 == "xmlns" || pair.0.has_prefix("xmlns:") {
      attrs.push(pair)
    } else {
      attrs.push((resolve(scanner, pair.0, false), pair.1))
    }
  }
  (name, attrs, self_closing)
}

///|
/// Resolve a QName against the scopes in force, answering `{uri}local` or the
/// bare local name.
fn resolve(
  scanner : Scan,
  qname : String,
  is_element : Bool,
) -> String raise @moonxml.Refused {
  match qname.find(":") {
    Some(at) => {
      let prefix = qname[0:at].to_owned()
      let name = qname[at + 1:qname.length()].to_owned()
      if prefix == "xml" {
        return "{http://www.w3.org/XML/1998/namespace}" + name
      }
      if prefix == "xmlns" {
        raise @moonxml.Malformed(
          at=scanner.at,
          why="the xmlns prefix is reserved",
        )
      }
      match lookup_prefix(scanner, prefix) {
        Some(uri) => "{" + uri + "}" + name
        None =>
          raise @moonxml.Malformed(
            at=scanner.at,
            why="the prefix `\{prefix}` was never declared",
          )
      }
    }
    None =>
      if is_element {
        match lookup_prefix(scanner, "") {
          Some(uri) =>
            if uri.is_empty() {
              qname
            } else {
              "{" + uri + "}" + qname
            }
          None => qname
        }
      } else {
        // A default namespace does not apply to attributes.
        qname
      }
  }
}

///|
/// The URI a prefix names in the innermost scope that declares it.
fn lookup_prefix(scanner : Scan, prefix : String) -> String? {
  let mut k = scanner.scopes.length() - 1
  while k >= 0 {
    let scope = scanner.scopes[k]
    let mut j = scope.length() - 1
    while j >= 0 {
      if scope[j].0 == prefix {
        return Some(scope[j].1)
      }
      j = j - 1
    }
    k = k - 1
  }
  None
}

///|
/// The end tag's name, leaving the scanner past it.
fn end_tag(scanner : Scan) -> String raise @moonxml.Refused {
  scanner.at = scanner.at + 2
  skip_space(scanner)
  let (qname, after) = read_name(scanner, scanner.at)
  scanner.at = after
  skip_space(scanner)
  if !(scanner.at < scanner.text.length() && scanner.text.at(scanner.at) == 0x3E) {
    raise @moonxml.Malformed(at=scanner.at, why="a close tag ends at `>`")
  }
  scanner.at = scanner.at + 1
  let name = resolve(scanner, qname, true)
  if scanner.scopes.length() > 1 {
    ignore(scanner.scopes.pop())
  }
  name
}

///|
/// An attribute value: quoted, entity-decoded, with a `<` refused as the spec
/// requires.
fn attribute_value(scanner : Scan) -> String raise @moonxml.Refused {
  let text = scanner.text
  if !(scanner.at < text.length() &&
    (text.at(scanner.at) == 0x22 || text.at(scanner.at) == 0x27)) {
    raise @moonxml.Malformed(
      at=scanner.at,
      why="an attribute value must be quoted",
    )
  }
  let quote = text.at(scanner.at)
  let start = scanner.at + 1
  scanner.at = start
  while scanner.at < text.length() && text.at(scanner.at) != quote {
    if text.at(scanner.at) == 0x3C {
      raise @moonxml.Malformed(at=scanner.at, why="a `<` in an attribute value")
    }
    scanner.at = scanner.at + 1
  }
  if scanner.at >= text.length() {
    raise @moonxml.Malformed(at=start, why="an unterminated attribute value")
  }
  let raw = text[start:scanner.at].to_owned()
  scanner.at = scanner.at + 1
  unescape(scanner, raw, at=start)
}

///|
/// A run of text, decoded; `]]>` in content is refused, as the spec says.
fn text_run(scanner : Scan) -> Unit raise @moonxml.Refused {
  let text = scanner.text
  let start = scanner.at
  while scanner.at < text.length() && text.at(scanner.at) != 0x3C {
    scanner.at = scanner.at + 1
  }
  let raw = text[start:scanner.at].to_owned()
  if raw.contains("]]>") {
    raise @moonxml.Malformed(at=start, why="`]]>` in content")
  }
  let decoded = unescape(scanner, raw, at=start)
  if !decoded.is_empty() {
    scanner.sink.push(@event.TextRun(text=decoded))
  }
}

///|
/// Decode the five predefined entities and numeric character references; a
/// document that names any other entity is not well-formed, because there is
/// no DTD to declare it.
fn unescape(
  scanner : Scan,
  raw : String,
  at~ : Int32,
) -> String raise @moonxml.Refused {
  if !raw.contains("&") {
    return raw
  }
  let out = StringBuilder()
  let n = raw.length()
  let mut i = 0
  while i < n {
    if raw.at(i) != 0x26 {
      out.write_char(unit_char(raw.at(i)))
      i = i + 1
      continue
    }
    let semi = match find_char(raw, i + 1, ';') {
      Some(found) => found
      None =>
        raise @moonxml.Malformed(
          at=at + i,
          why="an entity reference has no `;`",
        )
    }
    let entity = raw[i + 1:semi].to_owned()
    let decoded = match entity {
      "amp" => Some('&')
      "lt" => Some('<')
      "gt" => Some('>')
      "quot" => Some('"')
      "apos" => Some('\'')
      _ => None
    }
    match decoded {
      Some(ch) => out.write_char(ch)
      None =>
        if entity.has_prefix("#x") || entity.has_prefix("#X") {
          out.write_char(
            code_point(
              scanner,
              entity[2:entity.length()].to_owned(),
              16,
              at + i,
            ),
          )
        } else if entity.has_prefix("#") {
          out.write_char(
            code_point(
              scanner,
              entity[1:entity.length()].to_owned(),
              10,
              at + i,
            ),
          )
        } else {
          raise @moonxml.Malformed(
            at=at + i,
            why="the entity `&\{entity};` is not one XML defines",
          )
        }
    }
    i = semi + 1
  }
  out.to_string()
}

///|
/// A numeric character reference read in the given base.
fn code_point(
  scanner : Scan,
  digits : String,
  base : Int32,
  at : Int32,
) -> Char raise @moonxml.Refused {
  ignore(scanner)
  let code = Some(@string.parse_int(digits, base~)) catch { _ => None }
  match code {
    Some(value) =>
      if value <= 0 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF) {
        raise @moonxml.Malformed(at~, why="a character reference out of range")
      } else {
        value.unsafe_to_char()
      }
    None =>
      raise @moonxml.Malformed(
        at~,
        why="a character reference that is not a number",
      )
  }
}

///|
/// A comment: everything between `<!--` and `-->`, refused if it carries `--`
/// the way the spec forbids.
fn comment(scanner : Scan) -> Unit raise @moonxml.Refused {
  let start = scanner.at + 4
  let close = match find_text(scanner.text, "-->", start) {
    Some(found) => found
    None => raise @moonxml.Malformed(at=start, why="a comment is unterminated")
  }
  let body = scanner.text[start:close].to_owned()
  if body.contains("--") || body.has_suffix("-") {
    raise @moonxml.Malformed(at=start, why="`--` inside a comment")
  }
  scanner.at = close + 3
  scanner.sink.push(@event.CommentEvent(text=body))
}

///|
/// A CDATA section: its text, exactly as it stands.
fn cdata(scanner : Scan) -> Unit raise @moonxml.Refused {
  let start = scanner.at + 9
  let close = match find_text(scanner.text, "]]>", start) {
    Some(found) => found
    None =>
      raise @moonxml.Malformed(at=start, why="a CDATA section is unterminated")
  }
  scanner.at = close + 3
  scanner.sink.push(@event.CDataRun(text=scanner.text[start:close].to_owned()))
}

///|
/// A processing instruction: the target, and the raw text between it and the
/// `?>`, so it writes back exactly.
fn instruction(scanner : Scan) -> Unit raise @moonxml.Refused {
  let text = scanner.text
  let began = scanner.at
  let start = scanner.at + 2
  let (target, after) = read_name(scanner, start)
  scanner.at = after
  if target.is_empty() {
    raise @moonxml.Malformed(
      at=start,
      why="a processing instruction needs a target",
    )
  }
  if target.to_lower() == "xml" && began != 0 {
    raise @moonxml.Malformed(
      at=start,
      why="the XML declaration belongs at the start",
    )
  }
  let close = match find_text(text, "?>", scanner.at) {
    Some(found) => found
    None =>
      raise @moonxml.Malformed(
        at=scanner.at,
        why="a processing instruction is unterminated",
      )
  }
  let data = text[scanner.at:close].to_owned()
  if data.contains("?>") {
    raise @moonxml.Malformed(
      at=scanner.at,
      why="`?>` inside a processing instruction",
    )
  }
  scanner.at = close + 2
  scanner.sink.push(@event.ProcessingInstruction(target~, data~))
}

///|
/// The doctype, with its internal subset: what is kept is the raw declaration,
/// so writing it back is exact.
fn doctype(scanner : Scan) -> Unit raise @moonxml.Refused {
  let text = scanner.text
  let start = scanner.at + 9
  scanner.at = start
  let mut depth = 0
  let mut quote : UInt16 = 0
  while scanner.at < text.length() {
    let unit = text.at(scanner.at)
    if quote != 0 {
      if unit == quote {
        quote = 0
      }
    } else if unit == 0x22 || unit == 0x27 {
      quote = unit
    } else if unit == 0x5B {
      depth = depth + 1
    } else if unit == 0x5D {
      depth = depth - 1
    } else if unit == 0x3E && depth == 0 {
      let body = text[start:scanner.at].trim().to_owned()
      scanner.at = scanner.at + 1
      scanner.sink.push(@event.DoctypeEvent(text=body))
      return
    }
    scanner.at = scanner.at + 1
  }
  raise @moonxml.Malformed(at=start, why="the doctype is unterminated")
}

///|
/// A name as XML defines it: a start character, then name characters, with a
/// single colon allowed for a QName.
fn read_name(scanner : Scan, from : Int32) -> (String, Int32) {
  let text = scanner.text
  let n = text.length()
  let mut i = from
  if i < n && !is_name_start(text.at(i)) {
    return ("", from)
  }
  let run = StringBuilder()
  while i < n {
    let unit = text.at(i)
    if is_name_char(unit) {
      run.write_char(unit_char(unit))
      i = i + 1
    } else {
      break
    }
  }
  (run.to_string(), i)
}

///|
fn is_name_start(unit : UInt16) -> Bool {
  (unit >= 0x61 && unit <= 0x7A) ||
  (unit >= 0x41 && unit <= 0x5A) ||
  unit == 0x5F ||
  unit == 0x3A ||
  unit >= 0x80
}

///|
fn is_name_char(unit : UInt16) -> Bool {
  is_name_start(unit) ||
  (unit >= 0x30 && unit <= 0x39) ||
  unit == 0x2D ||
  unit == 0x2E
}

///|
fn skip_space(scanner : Scan) -> Unit {
  let text = scanner.text
  let n = text.length()
  while scanner.at < n {
    let unit = text.at(scanner.at)
    if unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D {
      scanner.at = scanner.at + 1
    } else {
      break
    }
  }
}

///|
fn starts_with(scanner : Scan, needle : String) -> Bool {
  let at = scanner.at
  at + needle.length() <= scanner.text.length() &&
  scanner.text[at:at + needle.length()] == needle
}

///|
fn is_space_at(scanner : Scan, at : Int32) -> Bool {
  if at >= scanner.text.length() {
    return false
  }
  let unit = scanner.text.at(at)
  unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0x3E
}

///|
fn find_text(text : String, needle : String, from : Int32) -> Int32? {
  let n = text.length()
  let m = needle.length()
  let mut i = from
  while i + m <= n {
    if text[i:i + m] == needle {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn find_char(text : String, from : Int32, unit : Char) -> Int32? {
  let n = text.length()
  let mut i = from
  while i < n {
    if unit_char(text.at(i)) == unit {
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
