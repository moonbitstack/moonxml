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
  utf8_encode(dumps(node))
}

///|
/// The HTML serialization of a node, WHATWG's rules.
pub fn dumps_html(node : Node) -> String {
  let out = StringBuilder()
  write_html(node, out, raw=false)
  out.to_string()
}

///|
/// The HTML serialization of a node, as bytes.
pub fn dump_html(node : Node) -> Bytes {
  utf8_encode(dumps_html(node))
}

///|
/// A whole document, in the flavour it was read as.
pub fn Document::dumps(self : Document) -> String {
  match self.flavour {
    Xml => {
      let out = StringBuilder()
      for child in self.root.childrens {
        write_xml(child, out)
      }
      out.to_string()
    }
    Html => self.dumps_html()
  }
}

///|
pub fn Document::dump(self : Document) -> Bytes {
  utf8_encode(self.dumps())
}

///|
/// A whole document, HTML rules whatever it was read as.
pub fn Document::dumps_html(self : Document) -> String {
  let out = StringBuilder()
  for child in self.root.childrens {
    write_html(child, out, raw=false)
  }
  out.to_string()
}

///|
pub fn Document::dump_html(self : Document) -> Bytes {
  utf8_encode(self.dumps_html())
}

// The XML writer.

///|
fn write_xml(node : Node, out : StringBuilder) -> Unit {
  write_xml_in(node, out, [])
}

///|
/// Write one node given the namespace declarations in force: `{uri}local`
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
      if data.childrens.is_empty() && data.closed {
        out.write_string("/>")
        return
      }
      out.write_string(">")
      for child in data.childrens {
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
  }
}

///|
/// A name as it is written: unchanged when it carries no namespace, prefixed
/// when it does. A name whose namespace nothing declares gets a declaration on
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
fn write_html(node : Node, out : StringBuilder, raw~ : Bool) -> Unit {
  match node {
    ElementNode(data) => {
      let foreign = data.name.has_prefix("{")
      let tag = if foreign { local_of(data.name) } else { data.name }
      out.write_string("<" + tag)
      for pair in data.attrs {
        let value = pair.1
        if value.is_empty() {
          out.write_string(" " + pair.0)
        } else {
          out.write_string(
            " " + pair.0 + "=\"" + escape_html_attr(value) + "\"",
          )
        }
      }
      out.write_string(">")
      // A void element never opens; a raw text element's children are written
      // exactly as they are. Foreign elements answer neither rule.
      if !foreign && is_void_element(tag) {
        return
      }
      let raw_here = !foreign && is_raw_text_element(tag)
      for child in data.childrens {
        write_html(child, out, raw=raw_here || raw)
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
    DoctypeNode(text) => out.write_string("<!DOCTYPE " + text + ">")
  }
}

///|
/// The elements HTML leaves open on purpose. SVG's handful rides along as
/// foreign content, which the writer knows by the `{` on the name.
fn is_void_element(tag : String) -> Bool {
  match tag {
    "area"
    | "base"
    | "br"
    | "col"
    | "command"
    | "embed"
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
    text.contains("\u{A0}")) {
    return text
  }
  let out = StringBuilder()
  for ch in text {
    match ch {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
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
  if !(text.contains("&") || text.contains("\"") || text.contains("\u{A0}")) {
    return text
  }
  let out = StringBuilder()
  for ch in text {
    match ch {
      '&' => out.write_string("&amp;")
      '"' => out.write_string("&quot;")
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
