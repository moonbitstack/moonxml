// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Serialization. The format-library verbs: `dumps` writes a tree to text,
/// `dump` answers bytes, `loads` and `load` read one back (those live with
/// their parsers, in `moonxml/xml` and `moonxml/html`).
///
/// Two rule sets, because there are two languages. The XML writer is exact:
/// attribute order, CDATA, comments, processing instructions and the doctype
/// survive, and a well-formed document that is not edited comes back
/// byte-identical — the one deviation is that character references are
/// decoded, as a DOM means them to be. The HTML writer follows WHATWG's
/// serialization rules, and its criterion is the fixpoint: write, read, write
/// again gives the same bytes.

///|
/// The XML serialization of a node.
pub fn dumps(node : Node) -> String {
  let out = StringBuilder()
  write_xml(node, out)
  out.to_string()
}

///|
/// The XML serialization of a node, as bytes.
pub fn dump(node : Node) -> Bytes {
  @utf8.encode(dumps(node))
}

///|
/// The HTML serialization of a node, WHATWG's rules.
pub fn dumps_html(node : Node) -> String {
  let out = StringBuilder()
  write_html(node, out, raw=false, scripting=false)
  out.to_string()
}

///|
/// The HTML serialization of a node, as bytes.
pub fn dump_html(node : Node) -> Bytes {
  @utf8.encode(dumps_html(node))
}

///|
/// A whole document, in the flavour it was read as.
pub fn Document::dumps(self : Document) -> String {
  match self.flavour {
    Xml => {
      let out = StringBuilder()
      for child in self.root.children {
        write_xml(child, out)
      }
      out.to_string()
    }
    Html => self.dumps_html()
  }
}

///|
/// A whole document as bytes, in the flavour it was read as.
pub fn Document::dump(self : Document) -> Bytes {
  @utf8.encode(self.dumps())
}

///|
/// A whole document, HTML rules whatever it was read as.
pub fn Document::dumps_html(self : Document) -> String {
  let out = StringBuilder()
  let scripting = self.scripting()
  for child in self.root.children {
    write_html(child, out, raw=false, scripting~)
  }
  out.to_string()
}

///|
/// A whole document as bytes, by HTML's rules.
pub fn Document::dump_html(self : Document) -> Bytes {
  @utf8.encode(self.dumps_html())
}

// The XML writer.

///|
fn write_xml(node : Node, out : StringBuilder) -> Unit {
  write_xml_in(node, out, [])
}

///|
/// Write one node given the space declarations in force: `{uri}local`
/// becomes a prefixed name again, using the prefix the document declared when
/// there is one and inventing `ns1` when there is not.
fn write_xml_in(
  node : Node,
  out : StringBuilder,
  scope : Array[(String, String)],
) -> Unit {
  match node {
    ElementNode(data) => {
      let local_scope = scope.copy()
      for pair in data.attrs {
        if pair.0 == "xmlns" {
          local_scope.push(("", pair.1))
        } else if pair.0.has_prefix("xmlns:") {
          local_scope.push((pair.0[6:pair.0.length()].to_owned(), pair.1))
        }
      }
      let declared : Array[(String, String)] = []
      let tag = qualify(data.name, local_scope, declared, false)
      out.write_string("<" + tag)
      for pair in declared {
        out.write_string(
          " xmlns:" + pair.0 + "=\"" + escape_xml_attr(pair.1) + "\"",
        )
      }
      for pair in data.attrs {
        out.write_string(
          " " +
          qualify(pair.0, local_scope, declared, true) +
          "=\"" +
          escape_xml_attr(pair.1) +
          "\"",
        )
      }
      if data.children.is_empty() && data.closed {
        out.write_string("/>")
        return
      }
      out.write_string(">")
      for child in data.children {
        write_xml_in(child, out, local_scope)
      }
      out.write_string(
        "</" + qualify(data.name, local_scope, declared, false) + ">",
      )
    }
    TextNode(text) => out.write_string(escape_xml_text(text))
    CDataNode(text) => out.write_string("<![CDATA[" + text + "]]>")
    CommentNode(text) => out.write_string("<!--" + text + "-->")
    ProcessingInstructionNode(pi) =>
      out.write_string("<?" + pi.target + pi.data + "?>")
    DoctypeNode(text) => out.write_string("<!DOCTYPE " + text + ">")
    // Attributes and namespaces are not children of anything, so there is no
    // position in a document for them to be written at.
    AttributeNode(_) | NamespaceNode(_) => ()
  }
}

///|
/// A name as it is written: unchanged when it carries no space, prefixed
/// when it does. A name whose space nothing declares gets a declaration on
/// the element being written, collected in `declared`.
fn qualify(
  name : String,
  scope : Array[(String, String)],
  declared : Array[(String, String)],
  is_attr : Bool,
) -> String {
  let uri = match namespace_of(name) {
    Some(found) => found
    None => return name
  }
  let tail = local_of(name)
  for pair in scope {
    if pair.1 == uri && (!is_attr || !pair.0.is_empty()) {
      if pair.0.is_empty() {
        return tail
      }
      return pair.0 + ":" + tail
    }
  }
  let mut k = 1
  let mut prefix = ""
  let mut chosen = false
  while !chosen {
    prefix = "ns\{k}"
    let mut taken = false
    for pair in scope {
      if pair.0 == prefix {
        taken = true
      }
    }
    chosen = !taken
    if !chosen {
      k = k + 1
    }
  }
  scope.push((prefix, uri))
  declared.push((prefix, uri))
  prefix + ":" + tail
}

// The HTML writer, WHATWG's serialization rules.

///|
fn write_html(
  node : Node,
  out : StringBuilder,
  raw~ : Bool,
  scripting~ : Bool,
) -> Unit {
  match node {
    ElementNode(data) => {
      let foreign = data.name.has_prefix("{")
      let tag = if foreign { local_of(data.name) } else { data.name }
      out.write_string("<" + tag)
      for pair in data.attrs {
        let value = pair.1
        let name = html_attribute_name(pair.0)
        if value.is_empty() {
          out.write_string(" " + name)
        } else {
          out.write_string(" " + name + "=\"" + escape_html_attr(value) + "\"")
        }
      }
      out.write_string(">")
      // A void element never opens; a raw text element's children are written
      // exactly as they are. Foreign elements answer neither rule.
      if !foreign && is_void_element(tag) {
        return
      }
      // The reader drops one newline right after these tags' start tag, so one
      // has to be written for it to drop.
      if !foreign && keeps_leading_newline(tag) {
        match data.children {
          [TextNode(text), ..] =>
            if text.has_prefix("\n") {
              out.write_string("\n")
            }
          _ => ()
        }
      }
      // With scripting on, a `noscript`'s content is raw text, because that is
      // how it was read: escaping it would put the escapes in the text.
      let raw_here = !foreign &&
        (is_raw_text_element(tag) || (tag == "noscript" && scripting))
      for child in data.children {
        write_html(child, out, raw=raw_here || raw, scripting~)
      }
      // A template's children are its contents, and they belong inside the
      // element when it is written.
      match data.content() {
        Some(fragment) =>
          for child in fragment.children {
            write_html(child, out, raw=raw_here || raw, scripting~)
          }
        None => ()
      }
      out.write_string("</" + tag + ">")
    }
    TextNode(text) =>
      if raw {
        out.write_string(text)
      } else {
        out.write_string(escape_html_text(text))
      }
    CDataNode(text) =>
      if raw {
        out.write_string(text)
      } else {
        out.write_string(escape_html_text(text))
      }
    CommentNode(text) => out.write_string("<!--" + text + "-->")
    ProcessingInstructionNode(pi) =>
      out.write_string("<?" + pi.target + pi.data + "?>")
    DoctypeNode(text) => write_doctype(text, out)
    // Attributes and namespaces are not children of anything, so there is no
    // position in a document for them to be written at.
    AttributeNode(_) | NamespaceNode(_) => ()
  }
}

///|
/// The tags whose content the reader starts one newline later: a newline right
/// after the start tag is dropped, the way an author's line break is.
fn keeps_leading_newline(tag : String) -> Bool {
  tag == "pre" || tag == "textarea" || tag == "listing"
}

///|
/// An attribute name as HTML spells it. A foreign attribute is a Clark name in
/// the tree; HTML has prefixes for exactly three namespaces, so those get
/// theirs back and anything else is written by its local name.
fn html_attribute_name(name : String) -> String {
  match namespace_of(name) {
    Some(uri) =>
      match uri {
        "http://www.w3.org/1999/xlink" => "xlink:" + local_of(name)
        "http://www.w3.org/XML/1998/namespace" => "xml:" + local_of(name)
        "http://www.w3.org/2000/xmlns/" => "xmlns:" + local_of(name)
        _ => local_of(name)
      }
    None => name
  }
}

///|
/// A document type declaration as HTML spells it: the name, then `PUBLIC` with
/// both identifiers or `SYSTEM` with the one. The tree keeps the declaration
/// the way the test corpus writes it — `name "public" "system"` — so the
/// keywords have to be put back.
fn write_doctype(text : String, out : StringBuilder) -> Unit {
  let space = match text.find(" ") {
    Some(at) => at
    None => -1
  }
  if space < 0 {
    out.write_string("<!DOCTYPE " + text + ">")
    return
  }
  let name = text[0:space].to_owned()
  let rest = text[space + 1:text.length()].trim().to_owned()
  match quoted_parts(rest) {
    Some(pair) => {
      let (public_id, system_id) = pair
      if public_id.is_empty() {
        out.write_string("<!DOCTYPE " + name + " SYSTEM \"" + system_id + "\">")
      } else {
        out.write_string(
          "<!DOCTYPE " +
          name +
          " PUBLIC \"" +
          public_id +
          "\" \"" +
          system_id +
          "\">",
        )
      }
    }
    None => out.write_string("<!DOCTYPE " + name + ">")
  }
}

///|
/// The two quoted identifiers of a doctype, or nothing when they are not two
/// quoted strings — an identifier that carries a quote of its own cannot be
/// told from the closing one.
fn quoted_parts(text : String) -> (String, String)? {
  let n = text.length()
  if n < 2 || text.at(0) != 0x22 || text.at(n - 1) != 0x22 {
    return None
  }
  // The public identifier ends at the first quote followed by a space, the
  // system one at the last quote.
  let mut i = 1
  while i < n - 1 {
    if text.at(i) == 0x22 && text.at(i + 1) == 0x20 {
      // Past the closing quote, the space and the next opening quote.
      return Some((text[1:i].to_owned(), text[i + 3:n - 1].to_owned()))
    }
    i = i + 1
  }
  None
}

///|
/// The elements HTML leaves open on purpose, the list WHATWG's serialisation
/// gives (§13.3): the end tag is never written for them. SVG's handful rides
/// along as foreign content, which the writer knows by the `{` on the name.
fn is_void_element(tag : String) -> Bool {
  match tag {
    "area"
    | "base"
    | "basefont"
    | "bgsound"
    | "br"
    | "col"
    | "embed"
    | "frame"
    | "hr"
    | "img"
    | "input"
    | "keygen"
    | "link"
    | "meta"
    | "param"
    | "source"
    | "track"
    | "wbr" => true
    _ => false
  }
}

///|
/// The elements whose text is written exactly as it stands.
fn is_raw_text_element(tag : String) -> Bool {
  match tag {
    "script"
    | "style"
    | "xmp"
    | "iframe"
    | "noembed"
    | "noframes"
    | "plaintext" => true
    _ => false
  }
}

///|
/// The local part of a `{uri}local` name.
pub fn local_of(name : String) -> String {
  match rfind(name, '}') {
    Some(at) => name[at + 1:name.length()].to_owned()
    None => name
  }
}

///|
/// The URI of a `{uri}local` name, or `None` when the name carries none.
pub fn namespace_of(name : String) -> String? {
  if name.has_prefix("{") {
    match rfind(name, '}') {
      Some(at) => Some(name[1:at].to_owned())
      None => None
    }
  } else {
    None
  }
}

///|
/// The last place a character occurs, if it does.
fn rfind(text : String, unit : Char) -> Int32? {
  let mut i = text.length() - 1
  while i >= 0 {
    if char_at(text, i) == unit {
      return Some(i)
    }
    i = i - 1
  }
  None
}

///|
fn char_at(text : String, at : Int32) -> Char {
  match text.at(at).to_char() {
    Some(c) => c
    None => '?'
  }
}

///|
/// Text escapes `&` and `<` always; a `>` only when it would close a CDATA
/// section that is not one — the minimal escape that keeps the text legal.
fn escape_xml_text(text : String) -> String {
  if !(text.contains("&") || text.contains("<") || text.contains(">")) {
    return text
  }
  let out = StringBuilder()
  let mut run = 0
  for ch in text {
    if ch == '&' {
      out.write_string("&amp;")
      run = 0
    } else if ch == '<' {
      out.write_string("&lt;")
      run = 0
    } else if ch == '>' && run >= 2 {
      out.write_string("&gt;")
      run = 0
    } else {
      out.write_char(ch)
      run = if ch == ']' { run + 1 } else { 0 }
    }
  }
  out.to_string()
}

///|
/// Attribute values escape the quote they are written in, plus `&` and `<`.
fn escape_xml_attr(text : String) -> String {
  if !(text.contains("&") || text.contains("<") || text.contains("\"")) {
    return text
  }
  let out = StringBuilder()
  for ch in text {
    match ch {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '"' => out.write_string("&quot;")
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// WHATWG's text escaping: `&`, `<`, `>` and a no-break space, which has no
/// business sitting raw in a document that may be re-read as Latin-1.
fn escape_html_text(text : String) -> String {
  if !(text.contains("&") ||
    text.contains("<") ||
    text.contains(">") ||
    text.contains("\r") ||
    text.contains("\u{A0}")) {
    return text
  }
  let out = StringBuilder()
  for ch in text {
    match ch {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      // The reader folds a carriage return into a line feed, so a text that
      // carries one has to write it as a reference.
      '\r' => out.write_string("&#13;")
      _ =>
        if ch == '\u{A0}' {
          out.write_string("&nbsp;")
        } else {
          out.write_char(ch)
        }
    }
  }
  out.to_string()
}

///|
/// WHATWG's attribute-value escaping: `&`, the no-break space and the quote.
fn escape_html_attr(text : String) -> String {
  if !(text.contains("&") ||
    text.contains("\"") ||
    text.contains("\r") ||
    text.contains("\u{A0}")) {
    return text
  }
  let out = StringBuilder()
  for ch in text {
    match ch {
      '&' => out.write_string("&amp;")
      '"' => out.write_string("&quot;")
      '\r' => out.write_string("&#13;")
      _ =>
        if ch == '\u{A0}' {
          out.write_string("&nbsp;")
        } else {
          out.write_char(ch)
        }
    }
  }
  out.to_string()
}
