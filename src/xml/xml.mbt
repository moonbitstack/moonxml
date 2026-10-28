// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
// XML 1.0 with Namespaces 1.0, strictly: a document is either well-formed
// and read whole, or refused with the offset of the fault. What is read
// survives the round-trip — attribute order, CDATA, comments, processing
// instructions (their raw data), the doctype (its raw declaration) and the
// self-closing syntax.
// 
// Names are resolved to the `{uri}local` spelling the tree carries; a
// prefix nothing declared is a well-formedness error, and the two reserved
// ones (`xml`, `xmlns`) are honoured as the spec says.
// 
// The internal subset is read: entity declarations (general and parameter,
// nested, with recursion refused), attribute defaults, and the content models
// that decide whether a declaration is well-formed. Nothing is fetched — a
// document whose entities live in a file is read without them, and
// `Document::unresolved` names what was skipped.

///|
// The scanner's state: where it is, and what prefixes are in scope. `text` is
// mutable because expanding a general entity splices its replacement in where
// the reference stood, which is how the markup an entity carries is parsed.
priv struct Scan {
  mut text : String
  mut at : Int32
  // Added to every offset this scanner reports: a subset read inside the
  // doctype still reports offsets in the document.
  base : Int32
  sink : &@event.Sink
  scopes : Array[Array[(String, String)]]
  fragment : Bool
  depth_limit : Int32
  ctx : Ctx
}

///|
/// How deep elements may nest before a document is refused. Chrome and WebKit
/// stop at 512 nested elements; a document deeper than that is a stack to eat,
/// not a document.
pub let limit : Int32 = 512

///|
/// How many characters of entity expansion one document may spend. A million
/// is well past what a document that means something needs, and well under
/// what one built to expand for ever would ask for.
pub let entity_limit : Int32 = 1048576

///|
/// Read a document and answer its tree. `limit` bounds the element nesting,
/// `entity_limit` the total expansion of entities.
pub fn loads(
  text : String,
  limit~ : Int32 = limit,
  entity_limit~ : Int32 = entity_limit,
) -> @moonxml.Document raise @moonxml.Refused {
  run(text, fragment=false, limit~, entity_limit~)
}

///|
/// Read a document from bytes; UTF-8, with a leading byte-order mark skipped.
/// `limit` and `entity_limit` are as for `loads`.
pub fn load(
  bytes : Bytes,
  limit~ : Int32 = limit,
  entity_limit~ : Int32 = entity_limit,
) -> @moonxml.Document raise @moonxml.Refused {
  match @text.decode(bytes) {
    Ok(text) => loads(text, limit~, entity_limit~)
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
  entity_limit~ : Int32 = entity_limit,
) -> @moonxml.Document raise @moonxml.Refused {
  run(text, fragment=true, limit~, entity_limit~)
}

///|
/// Stream a document's events into a sink, building nothing. `limit` and
/// `entity_limit` are as for `loads`.
pub fn scan(
  text : String,
  sink : &@event.Sink,
  fragment~ : Bool = false,
  limit~ : Int32 = limit,
  entity_limit~ : Int32 = entity_limit,
) -> Unit raise @moonxml.Refused {
  let ctx = Ctx::new(entity_limit)
  let scanner : Scan = {
    text: @text.strip_bom(text),
    at: 0,
    base: 0,
    sink,
    scopes: [[]],
    fragment,
    depth_limit: limit,
    ctx,
  }
  scan_document(scanner)
}

///|
fn run(
  text : String,
  fragment~ : Bool,
  limit~ : Int32,
  entity_limit~ : Int32,
) -> @moonxml.Document raise @moonxml.Refused {
  let doc = @moonxml.Document::new(flavour=@moonxml.Xml)
  let ctx = Ctx::new(entity_limit)
  let scanner : Scan = {
    text: @text.strip_bom(text),
    at: 0,
    base: 0,
    sink: doc,
    scopes: [[]],
    fragment,
    depth_limit: limit,
    ctx,
  }
  scan_document(scanner)
  doc.set_unresolved(ctx.unresolved)
  doc
}

///|
fn scan_document(scanner : Scan) -> Unit raise @moonxml.Refused {
  match first_illegal(scanner.text) {
    Some(at) =>
      fail(scanner, at, "a character XML does not allow in a document")
    None => ()
  }
  prologue(scanner)
  if scanner.fragment {
    fragment_body(scanner)
    return
  }
  if scanner.at >= scanner.text.length() {
    fail(scanner, scanner.at, "a document needs a root element")
  }
  content(scanner, 1)
  trailing(scanner)
}

///|
/// The prologue: the XML declaration, comments, processing instructions and
/// the doctype, in the order the spec allows.
fn prologue(scanner : Scan) -> Unit raise @moonxml.Refused {
  let mut seen_doctype = false
  while true {
    skip_space(scanner)
    if !starts_with(scanner, "<") {
      return
    }
    if scanner.at == 0 &&
      starts_with(scanner, "<?xml") &&
      is_space_at(scanner, 5) {
      xml_declaration(scanner)
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
        fail(scanner, scanner.at, "one doctype is enough")
      }
      seen_doctype = true
      doctype(scanner)
      continue
    }
    return
  }
}

///|
/// `<?xml version="1.0"?>`, with the optional encoding and standalone
/// declarations, and nothing else: the declaration is not a processing
/// instruction, and its pseudo-attributes are not attributes. The order the
/// spec gives them in is the order they have to arrive in.
fn xml_declaration(scanner : Scan) -> Unit raise @moonxml.Refused {
  let began = scanner.at
  scanner.at = scanner.at + 5
  let mut seen = 0
  while true {
    let spaced = is_space_at(scanner, 0)
    skip_space(scanner)
    if starts_with(scanner, "?>") {
      if seen == 0 {
        fail(scanner, began, "the declaration needs a version")
      }
      // The declaration is kept as the instruction it looks like, so a
      // document that is not edited writes back exactly as it was read.
      scanner.sink.push(
        @event.ProcessingInstruction(
          target="xml",
          data=scanner.text[began + 5:scanner.at].to_owned(),
        ),
      )
      scanner.at = scanner.at + 2
      return
    }
    if !spaced {
      fail(scanner, scanner.at, "the declaration takes a space here")
    }
    let (name, after) = read_name(scanner, scanner.at)
    scanner.at = after
    if name.is_empty() {
      fail(scanner, scanner.at, "the declaration takes pseudo-attributes")
    }
    skip_space(scanner)
    expect(scanner, 0x3D, "a pseudo-attribute takes a value")
    skip_space(scanner)
    let value = quoted(scanner)
    // VersionInfo, then EncodingDecl, then SDDecl, each at most once.
    match name {
      "version" => {
        if seen != 0 {
          fail(scanner, began, "the version comes first, and once")
        }
        if value != "1.0" {
          raise @moonxml.Unsupported(
            what="XML \{value}: this reader is XML 1.0",
          )
        }
      }
      "encoding" => {
        if seen != 1 {
          fail(scanner, began, "the encoding comes second")
        }
        if !is_encoding_name(value) {
          fail(scanner, began, "an encoding name is a name, not a phrase")
        }
        let upper = value.to_upper()
        if upper.has_prefix("UTF-16") || upper.has_prefix("UCS") {
          fail(scanner, began, "these bytes are not the encoding they name")
        }
      }
      "standalone" => {
        if seen < 1 || seen > 2 {
          fail(scanner, began, "standalone comes last")
        }
        if value != "yes" && value != "no" {
          fail(scanner, began, "standalone is `yes` or `no`")
        }
        scanner.ctx.standalone = value == "yes"
      }
      _ => fail(scanner, began, "not a pseudo-attribute of the declaration")
    }
    seen = seen + 1
  }
}

///|
/// `EncName ::= [A-Za-z] ([A-Za-z0-9._] | '-')*`
fn is_encoding_name(value : String) -> Bool {
  if value.is_empty() {
    return false
  }
  let n = value.length()
  let first = value.at(0)
  if !((first >= 0x41 && first <= 0x5A) || (first >= 0x61 && first <= 0x7A)) {
    return false
  }
  let mut i = 1
  while i < n {
    let unit = value.at(i)
    let legal = (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      (unit >= 0x30 && unit <= 0x39) ||
      unit == 0x2E ||
      unit == 0x5F ||
      unit == 0x2D
    if !legal {
      return false
    }
    i = i + 1
  }
  true
}

///|
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
      fail(scanner, scanner.at, "content after the root element")
    }
  }
}

///|
/// A fragment: text, elements, comments and instructions, with no single root
/// required.
fn fragment_body(scanner : Scan) -> Unit raise @moonxml.Refused {
  while scanner.at < scanner.text.length() {
    if starts_with(scanner, "<!--") {
      comment(scanner)
    } else if starts_with(scanner, "<![CDATA[") {
      cdata(scanner)
    } else if starts_with(scanner, "<?") {
      instruction(scanner)
    } else if starts_with(scanner, "</") {
      fail(scanner, scanner.at, "a close tag with no open one")
    } else if starts_with(scanner, "<") {
      content(scanner, 1)
    } else if scanner.peek() == 0x26 {
      content_reference(scanner)
    } else {
      text_run(scanner)
    }
  }
}

///|
/// An element, its content, and its close: the recursive heart.
fn content(scanner : Scan, depth : Int32) -> Unit raise @moonxml.Refused {
  if depth > scanner.depth_limit {
    raise @moonxml.Exceeded(
      at=scanner.at + scanner.base,
      limit=scanner.depth_limit,
      got=depth,
    )
  }
  let (name, attrs, self_closing) = start_tag(scanner)
  scanner.sink.push(@event.StartTag(name~, attrs~, self_closing~))
  if self_closing {
    if scanner.scopes.length() > 1 {
      ignore(scanner.scopes.pop())
    }
    return
  }
  while true {
    if scanner.at >= scanner.text.length() {
      fail(scanner, scanner.at, "`<\{name}>` is never closed")
    }
    if starts_with(scanner, "</") {
      let close = end_tag(scanner)
      if close != name {
        fail(scanner, scanner.at, "`</\{close}>` closes `<\{name}>`")
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
      fail(scanner, scanner.at, "a declaration inside content")
    } else if starts_with(scanner, "<") {
      content(scanner, depth + 1)
    } else if scanner.peek() == 0x26 {
      content_reference(scanner)
    } else {
      text_run(scanner)
    }
  }
}

///|
/// A reference in content. A character reference is one character of text; a
/// general entity's replacement text is spliced in where the reference stood,
/// so the markup it carries is read as markup.
fn content_reference(scanner : Scan) -> Unit raise @moonxml.Refused {
  let at = scanner.at
  let text = scanner.text
  if at + 1 < text.length() && text.at(at + 1) == 0x23 {
    let ch = character_reference(scanner)
    scanner.sink.push(@event.Text(text=code_text(ch)))
    return
  }
  scanner.at = at + 1
  let (name, after) = read_name(scanner, scanner.at)
  if name.is_empty() {
    fail(scanner, at, "`&` starts a reference")
  }
  scanner.at = after
  expect(scanner, 0x3B, "an entity reference ends at `;`")
  let value = expand_entity(scanner.ctx, name, at, [], content=true)
  // An entity's replacement text has to be well-formed on its own: a tag it
  // opens and never closes cannot be closed by what follows the reference.
  check_balanced(scanner, value, at)
  // The reference has been read; what it stands for takes its place, so the
  // markup it carries is read as markup. Its own references are resolved by
  // now, and the characters they stood for are written so that reading them
  // again gives the characters, not the references.
  let end = scanner.at
  scanner.at = at
  splice(scanner, end - at, value)
}

///|
/// Replace `length` characters at the scanner's position with `text`, so that
/// what an entity stands for is read exactly as if it had been written there.
fn splice(scanner : Scan, length : Int32, text : String) -> Unit {
  let source = scanner.text
  let n = source.length()
  scanner.text = source[0:scanner.at].to_owned() +
    text +
    source[scanner.at + length:n].to_owned()
}

///|
/// A start tag: its resolved name, its resolved attributes in document order,
/// and whether it closed itself.
fn start_tag(
  scanner : Scan,
) -> (String, Array[(String, String)], Bool) raise @moonxml.Refused {
  scanner.at = scanner.at + 1
  let (qname, after) = read_name(scanner, scanner.at)
  scanner.at = after
  if qname.is_empty() {
    fail(scanner, scanner.at, "an element needs a name after `<`")
  }
  let raw : Array[(String, String)] = []
  let mut self_closing = false
  let mut first = true
  while true {
    let spaced = is_space_at(scanner, 0)
    skip_space(scanner)
    if scanner.at >= scanner.text.length() {
      fail(scanner, scanner.at, "the tag `<\{qname}>` is unterminated")
    }
    if scanner.text.at(scanner.at) == 0x3E {
      scanner.at = scanner.at + 1
      break
    }
    if starts_with(scanner, "/>") {
      self_closing = true
      scanner.at = scanner.at + 2
      break
    }
    if !first && !spaced {
      fail(scanner, scanner.at, "attributes are separated by whitespace")
    }
    first = false
    let (attr, next) = read_name(scanner, scanner.at)
    if attr.is_empty() {
      fail(scanner, scanner.at, "an attribute needs a name")
    }
    scanner.at = next
    skip_space(scanner)
    if !(scanner.at < scanner.text.length() &&
      scanner.text.at(scanner.at) == 0x3D) {
      fail(scanner, scanner.at, "XML attributes take values: `\{attr}`")
    }
    scanner.at = scanner.at + 1
    skip_space(scanner)
    let raw_value = attribute_value(scanner)
    // A declaration that gives the attribute a type other than CDATA is
    // saying its value is a list, so the writer's whitespace is not data.
    let value = if declared_cdata(scanner.ctx, qname, attr) {
      raw_value
    } else {
      normalize(raw_value, false)
    }
    for pair in raw {
      if pair.0 == attr {
        fail(scanner, scanner.at, "a duplicate attribute: `\{attr}`")
      }
    }
    raw.push((attr, value))
  }
  // The defaults the declaration gives this element, for the attributes the
  // tag itself left out.
  let filled = apply_defaults(scanner.ctx, qname, raw, scanner.at)
  // The declarations apply to the element and its content, and the element's
  // own name is resolved against them.
  let scope : Array[(String, String)] = []
  for pair in filled {
    if pair.0 == "xmlns" {
      scope.push(("", pair.1))
    } else if pair.0.has_prefix("xmlns:") {
      let prefix = pair.0[6:pair.0.length()].to_owned()
      check_declaration(scanner, prefix, pair.1)
      scope.push((prefix, pair.1))
    }
  }
  scanner.scopes.push(scope)
  let name = resolve(scanner, qname, true)
  // The declarations stay on the element: names are Clark, but the document's
  // own choice of prefix is what writing it back has to reproduce.
  let attrs : Array[(String, String)] = []
  let seen : Array[String] = []
  for pair in filled {
    let resolved = if pair.0 == "xmlns" || pair.0.has_prefix("xmlns:") {
      pair.0
    } else {
      resolve(scanner, pair.0, false)
    }
    if seen.contains(resolved) {
      fail(scanner, scanner.at, "two attributes with one name: `\{pair.0}`")
    }
    seen.push(resolved)
    attrs.push((resolved, pair.1))
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
        fail(scanner, scanner.at, "the xmlns prefix is reserved")
      }
      match lookup_prefix(scanner, prefix) {
        Some(uri) =>
          if uri.is_empty() {
            fail(
              scanner,
              scanner.at,
              "the prefix `\{prefix}` is bound to no space",
            )
          } else {
            "{" + uri + "}" + name
          }
        None =>
          fail(scanner, scanner.at, "the prefix `\{prefix}` was never declared")
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
        // A default space does not apply to attributes.
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
  let (qname, after) = read_name(scanner, scanner.at)
  scanner.at = after
  if qname.is_empty() {
    fail(scanner, scanner.at, "a close tag needs a name")
  }
  skip_space(scanner)
  if !(scanner.at < scanner.text.length() && scanner.text.at(scanner.at) == 0x3E) {
    fail(scanner, scanner.at, "a close tag ends at `>`")
  }
  scanner.at = scanner.at + 1
  let name = resolve(scanner, qname, true)
  if scanner.scopes.length() > 1 {
    ignore(scanner.scopes.pop())
  }
  name
}

///|
/// An attribute value: quoted, its references expanded, and its whitespace
/// normalized by the attribute's declared type.
fn attribute_value(scanner : Scan) -> String raise @moonxml.Refused {
  let text = scanner.text
  if !(scanner.at < text.length() &&
    (text.at(scanner.at) == 0x22 || text.at(scanner.at) == 0x27)) {
    fail(scanner, scanner.at, "an attribute value must be quoted")
  }
  let quote = text.at(scanner.at)
  let start = scanner.at + 1
  scanner.at = start
  let out = StringBuilder()
  while true {
    if scanner.at >= text.length() {
      fail(scanner, start, "an unterminated attribute value")
    }
    let unit = text.at(scanner.at)
    if unit == quote {
      scanner.at = scanner.at + 1
      return out.to_string()
    }
    if unit == 0x3C {
      fail(scanner, scanner.at, "a `<` in an attribute value")
    }
    if unit == 0x26 {
      if scanner.at + 1 < text.length() && text.at(scanner.at + 1) == 0x23 {
        out.write_char(character_reference(scanner))
      } else {
        let at = scanner.at
        scanner.at = scanner.at + 1
        let (name, after) = read_name(scanner, scanner.at)
        if name.is_empty() {
          fail(scanner, at, "`&` starts a reference")
        }
        scanner.at = after
        expect(scanner, 0x3B, "an entity reference ends at `;`")
        match scanner.ctx.ents.get(name) {
          Some(File) =>
            fail(scanner, at, "an attribute value is not a place for a file")
          Some(Unparsed) =>
            fail(scanner, at, "an unparsed entity stands for no text")
          _ => ()
        }
        let value = expand_entity(scanner.ctx, name, at, [], content=false)
        out.write_string(value)
      }
      continue
    }
    // A literal tab or newline is a space in every attribute value.
    if unit == 0x09 || unit == 0x0A || unit == 0x0D {
      out.write_char(' ')
    } else {
      out.write_char(unit_char(unit))
    }
    scanner.at = scanner.at + 1
  }
  ""
}

///|
/// A run of text, exactly as it stands; `]]>` in content is refused, as the
/// spec says.
fn text_run(scanner : Scan) -> Unit raise @moonxml.Refused {
  let text = scanner.text
  let start = scanner.at
  while scanner.at < text.length() {
    let unit = text.at(scanner.at)
    if unit == 0x3C || unit == 0x26 {
      break
    }
    if unit == 0x5D &&
      scanner.at + 2 < text.length() &&
      text.at(scanner.at + 1) == 0x5D &&
      text.at(scanner.at + 2) == 0x3E {
      fail(scanner, scanner.at, "`]]>` in content")
    }
    scanner.at = scanner.at + 1
  }
  let raw = text[start:scanner.at].to_owned()
  if !raw.is_empty() {
    scanner.sink.push(@event.Text(text=raw))
  }
}

///|
/// A character reference at the scanner's position, answering its character.
fn character_reference(scanner : Scan) -> Char raise @moonxml.Refused {
  let at = scanner.at
  let text = scanner.text
  scanner.at = scanner.at + 2
  let hex = if scanner.at < text.length() && text.at(scanner.at) == 0x78 {
    scanner.at = scanner.at + 1
    true
  } else {
    false
  }
  let start = scanner.at
  while scanner.at < text.length() &&
        (if hex {
          is_hex(text.at(scanner.at))
        } else {
          text.at(scanner.at) >= 0x30 && text.at(scanner.at) <= 0x39
        }) {
    scanner.at = scanner.at + 1
  }
  if scanner.at == start {
    fail(scanner, at, "a character reference needs digits")
  }
  let digits = text[start:scanner.at].to_owned()
  expect(scanner, 0x3B, "a character reference ends at `;`")
  let code = Some(@string.parse_int(digits, base=if hex { 16 } else { 10 })) catch {
    _ => None
  }
  match code {
    Some(value) =>
      if !is_char(value) {
        fail(scanner, at, "a character reference XML does not allow")
      } else {
        value.unsafe_to_char()
      }
    None => fail(scanner, at, "a character reference that is not a number")
  }
}

///|
/// Whether a code point is a character XML allows.
fn is_char(value : Int32) -> Bool {
  value == 0x9 ||
  value == 0xA ||
  value == 0xD ||
  (value >= 0x20 && value <= 0xD7FF) ||
  (value >= 0xE000 && value <= 0xFFFD) ||
  (value >= 0x10000 && value <= 0x10FFFF)
}

///|
/// The offset of the first character in the input that XML does not allow, if
/// there is one. Surrogate halves are checked as pairs, so a document that is
/// UTF-8 but carries half of one is refused rather than read as two characters
/// that are not characters.
fn first_illegal(text : String) -> Int32? {
  let n = text.length()
  let mut i = 0
  while i < n {
    let unit = text.at(i)
    if unit >= 0xD800 && unit <= 0xDBFF {
      if i + 1 >= n {
        return Some(i)
      }
      let low = text.at(i + 1)
      if low < 0xDC00 || low > 0xDFFF {
        return Some(i)
      }
      i = i + 2
      continue
    }
    if unit >= 0xDC00 && unit <= 0xDFFF {
      return Some(i)
    }
    if !is_char(unit.to_int()) {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// A comment: everything between `<!--` and `-->`, refused if it carries `--`
/// the way the spec forbids.
fn comment(scanner : Scan) -> Unit raise @moonxml.Refused {
  let start = scanner.at + 4
  let close = match find_text(scanner.text, "-->", start) {
    Some(found) => found
    None => fail(scanner, start, "a comment is unterminated")
  }
  let body = scanner.text[start:close].to_owned()
  if body.contains("--") || body.has_suffix("-") {
    fail(scanner, start, "`--` inside a comment")
  }
  scanner.at = close + 3
  scanner.sink.push(@event.Comment(text=body))
}

///|
/// A CDATA section: its text, exactly as it stands.
fn cdata(scanner : Scan) -> Unit raise @moonxml.Refused {
  let start = scanner.at + 9
  let close = match find_text(scanner.text, "]]>", start) {
    Some(found) => found
    None => fail(scanner, start, "a CDATA section is unterminated")
  }
  scanner.at = close + 3
  scanner.sink.push(@event.CData(text=scanner.text[start:close].to_owned()))
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
    fail(scanner, start, "a processing instruction needs a target")
  }
  if target.to_lower() == "xml" {
    fail(scanner, began, "`xml` is reserved to the declaration")
  }
  if target.contains(":") {
    fail(scanner, began, "a target is not a qualified name")
  }
  let close = match find_text(text, "?>", scanner.at) {
    Some(found) => found
    None =>
      fail(scanner, scanner.at, "a processing instruction is unterminated")
  }
  let data = text[scanner.at:close].to_owned()
  if data.contains("?>") {
    fail(scanner, scanner.at, "`?>` inside a processing instruction")
  }
  if !data.is_empty() && !is_space(data.at(0)) {
    fail(scanner, scanner.at, "the data follows the target after a space")
  }
  scanner.at = close + 2
  scanner.sink.push(@event.ProcessingInstruction(target~, data~))
}

///|
/// The doctype, with its external identifier and its internal subset: what goes
/// into the tree is the raw declaration, so writing it back is exact, and what
/// stays with the reader is the declarations it made.
fn doctype(scanner : Scan) -> Unit raise @moonxml.Refused {
  let text = scanner.text
  let body = scanner.at + 9
  scanner.at = body
  require_space(scanner, "a doctype")
  skip_space(scanner)
  let (name, after) = read_name(scanner, scanner.at)
  if name.is_empty() {
    fail(scanner, scanner.at, "a doctype needs a name")
  }
  scanner.at = after
  skip_space(scanner)
  if starts_with(scanner, "SYSTEM") || starts_with(scanner, "PUBLIC") {
    scanner.ctx.external = true
    external_id(scanner)
    skip_space(scanner)
  }
  if scanner.peek() == 0x5B {
    scanner.at = scanner.at + 1
    internal_subset(scanner)
    skip_space(scanner)
  }
  let end = scanner.at
  if scanner.peek() != 0x3E {
    fail(scanner, scanner.at, "a doctype ends at `>`")
  }
  scanner.at = scanner.at + 1
  scanner.sink.push(@event.Doctype(text=text[body:end].trim().to_owned()))
}

///|
/// A name as XML defines it: a start character, then name characters. With
/// Namespaces in force a name carries at most one colon, and not at either end.
fn read_name(scanner : Scan, from : Int32) -> (String, Int32) {
  let text = scanner.text
  let n = text.length()
  let mut i = from
  if i >= n {
    return ("", from)
  }
  let first = code_unit_at(text, i)
  if !name_start(first.code) {
    return ("", from)
  }
  let run = StringBuilder()
  let mut colons = 0
  let mut ended_in_colon = false
  while i < n {
    let here = code_unit_at(text, i)
    if !name_char(here.code) {
      break
    }
    if here.code == 0x3A {
      colons = colons + 1
      ended_in_colon = true
    } else {
      ended_in_colon = false
    }
    push_code(run, here.code)
    i = i + here.width
  }
  if colons > 1 || ended_in_colon {
    return ("", from)
  }
  (run.to_string(), i)
}

///|
/// An `Nmtoken`: name characters, without the requirement of a start character.
fn read_nmtoken(scanner : Scan, from : Int32) -> (String, Int32) {
  let text = scanner.text
  let n = text.length()
  let mut i = from
  let run = StringBuilder()
  let mut colons = 0
  while i < n {
    let here = code_unit_at(text, i)
    if !name_char(here.code) {
      break
    }
    if here.code == 0x3A {
      colons = colons + 1
    }
    push_code(run, here.code)
    i = i + here.width
  }
  if colons > 1 {
    return ("", from)
  }
  (run.to_string(), i)
}

///|
// One code point read at an index, with the width it takes in the string.
priv struct CodeUnit {
  code : Int32
  width : Int32
}

///|
fn code_unit_at(text : String, at : Int32) -> CodeUnit {
  let unit = text.at(at)
  if unit >= 0xD800 && unit <= 0xDBFF && at + 1 < text.length() {
    let low = text.at(at + 1)
    if low >= 0xDC00 && low <= 0xDFFF {
      let code = ((unit.to_int() - 0xD800) << 10) +
        (low.to_int() - 0xDC00) +
        0x10000
      return { code, width: 2, }
    }
  }
  { code: unit.to_int(), width: 1, }
}

///|
fn push_code(out : StringBuilder, code : Int32) -> Unit {
  out.write_char(code.unsafe_to_char())
}

///|
/// `NameStartChar`, as XML 1.0 (fifth edition) spells it.
fn name_start(code : Int32) -> Bool {
  code == 0x3A ||
  (code >= 0x41 && code <= 0x5A) ||
  code == 0x5F ||
  (code >= 0x61 && code <= 0x7A) ||
  (code >= 0xC0 && code <= 0xD6) ||
  (code >= 0xD8 && code <= 0xF6) ||
  (code >= 0xF8 && code <= 0x2FF) ||
  (code >= 0x370 && code <= 0x37D) ||
  (code >= 0x37F && code <= 0x1FFF) ||
  (code >= 0x200C && code <= 0x200D) ||
  (code >= 0x2070 && code <= 0x218F) ||
  (code >= 0x2C00 && code <= 0x2FEF) ||
  (code >= 0x3001 && code <= 0xD7FF) ||
  (code >= 0xF900 && code <= 0xFDCF) ||
  (code >= 0xFDF0 && code <= 0xFFFD) ||
  (code >= 0x10000 && code <= 0xEFFFF)
}

///|
/// `NameChar` — every start character, plus digits, `-`, `.`, `#xB7` and two
/// combining ranges.
fn name_char(code : Int32) -> Bool {
  name_start(code) ||
  (code >= 0x30 && code <= 0x39) ||
  code == 0x2D ||
  code == 0x2E ||
  code == 0xB7 ||
  (code >= 0x300 && code <= 0x36F) ||
  (code >= 0x203F && code <= 0x2040)
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
fn is_space_at(scanner : Scan, offset : Int32) -> Bool {
  let at = scanner.at + offset
  if at >= scanner.text.length() {
    return false
  }
  is_space(scanner.text.at(at))
}

///|
/// The code unit at the scanner's position, or 0 at the end of the input.
fn Scan::peek(self : Scan) -> UInt16 {
  if self.at >= self.text.length() {
    0
  } else {
    self.text.at(self.at)
  }
}

///|
/// A quoted literal at the scanner's position: what a pseudo-attribute and a
/// space declaration are written with.
fn quoted(scanner : Scan) -> String raise @moonxml.Refused {
  let text = scanner.text
  let quote = scanner.peek()
  if !(quote == 0x22 || quote == 0x27) {
    fail(scanner, scanner.at, "a value is quoted")
  }
  let start = scanner.at + 1
  let mut at = start
  while at < text.length() && text.at(at) != quote {
    at = at + 1
  }
  if at >= text.length() {
    fail(scanner, start, "a value is unterminated")
  }
  scanner.at = at + 1
  text[start:at].to_owned()
}

///|
fn require_space(scanner : Scan, what : String) -> Unit raise @moonxml.Refused {
  if !is_space_at(scanner, 0) {
    fail(scanner, scanner.at, "\{what} takes a space here")
  }
}

///|
fn expect(
  scanner : Scan,
  unit : UInt16,
  what : String,
) -> Unit raise @moonxml.Refused {
  if scanner.at >= scanner.text.length() || scanner.text.at(scanner.at) != unit {
    fail(scanner, scanner.at, what)
  }
  scanner.at = scanner.at + 1
}

///|
fn[T] fail(
  scanner : Scan,
  at : Int32,
  why : String,
) -> T raise @moonxml.Refused {
  raise @moonxml.Malformed(at=at + scanner.base, why~)
}

///|
fn is_space(unit : UInt16) -> Bool {
  unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
}

///|
fn is_alnum(unit : UInt16) -> Bool {
  (unit >= 0x30 && unit <= 0x39) ||
  (unit >= 0x41 && unit <= 0x5A) ||
  (unit >= 0x61 && unit <= 0x7A)
}

///|
fn is_hex(unit : UInt16) -> Bool {
  (unit >= 0x30 && unit <= 0x39) ||
  (unit >= 0x61 && unit <= 0x66) ||
  (unit >= 0x41 && unit <= 0x46)
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

///|
fn code_text(ch : Char) -> String {
  let out = StringBuilder()
  out.write_char(ch)
  out.to_string()
}

///|
/// The rules the two reserved prefixes and the two reserved namespaces carry:
/// `xml` is bound to the XML space and nothing else, `xmlns` is never
/// declared, and no other prefix may take either space.
fn check_declaration(
  scanner : Scan,
  prefix : String,
  uri : String,
) -> Unit raise @moonxml.Refused {
  let xml_namespace = "http://www.w3.org/XML/1998/namespace"
  let xmlns_namespace = "http://www.w3.org/2000/xmlns/"
  if prefix == "xmlns" {
    fail(scanner, scanner.at, "the xmlns prefix is reserved")
  }
  if prefix == "xml" && uri != xml_namespace {
    fail(scanner, scanner.at, "the xml prefix is bound to its one space")
  }
  if prefix != "xml" && uri == xml_namespace {
    fail(scanner, scanner.at, "only the xml prefix names that space")
  }
  if uri == xmlns_namespace {
    fail(scanner, scanner.at, "that space belongs to xmlns alone")
  }
}

///|
/// Where an entity's replacement text goes when it is read for its shape and
/// nothing else.
priv struct Quiet {
  /// Nothing is recorded here; the field is what makes the literal a struct.
  ignored : Bool
}

///|
fn Quiet::new() -> Quiet {
  { ignored: true, }
}

///|
impl @event.Sink for Quiet with fn push(self, event) -> Unit {
  ignore(self.ignored)
  ignore(event)
}

///|
/// Read an entity's replacement text on its own, so that one that is not
/// well-formed — a tag it opens and never closes, a name that is not a name —
/// is refused where the reference stands rather than where the expansion lands.
fn check_balanced(
  scanner : Scan,
  text : String,
  at : Int32,
) -> Unit raise @moonxml.Refused {
  let inner : Scan = {
    text,
    at: 0,
    base: scanner.base + at,
    sink: Quiet::new(),
    scopes: [[]],
    fragment: true,
    depth_limit: scanner.depth_limit,
    ctx: scanner.ctx,
  }
  scan_document(inner)
}
