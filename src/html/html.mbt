// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// HTML, the WHATWG way: the tokenizer's states and the tree construction
/// algorithm, so malformed input repairs the way a browser repairs it. What
/// the parser fixed is on `document.repairs()`; the document is never
/// refused.
///
/// One algorithm, one tree builder: the tokenizer hands tokens to the builder,
/// which is the only thing that touches the tree.

///|
/// Read a document.
pub fn loads(text : String) -> @moonxml.Document {
  let doc = @moonxml.Document::new(flavour=@moonxml.Html)
  let builder = Builder::new(doc)
  let lexer = Lexer::new(preprocess(@text.strip_bom(text)), builder)
  tokenize(lexer)
  finish(builder)
  doc
}

///|
/// Read a document from bytes; UTF-8, with a leading byte-order mark skipped.
/// A byte that is not UTF-8 reads as U+FFFD, the way a browser reads it.
pub fn load(bytes : Bytes) -> @moonxml.Document {
  loads(@utf8.decode_lossy(bytes, ignore_bom=true))
}

///|
/// Read a fragment the way `innerHTML` does: the markup is read inside
/// `context`, an element named as one would write it, and the fragment's nodes
/// come back under the document's root.
///
/// The name may be a foreign one — `svg desc`, `math mi` — in the spelling the
/// standard's test corpus uses, since an SVG `<title>` is not an HTML one.
pub fn loads_fragment(
  text : String,
  context~ : String = "body",
) -> @moonxml.Document {
  let doc = @moonxml.Document::new(flavour=@moonxml.Html)
  let builder = Builder::new(doc)
  let (space, local_name) = read_context(context)
  let element_name = if space.is_empty() {
    local_name
  } else {
    "{" + space + "}" + local_name
  }
  let element = @moonxml.Element::new(element_name)
  builder.context = Some(element)
  // The document gets an html root to hold the fragment while it is read; the
  // nodes are lifted out of it afterwards.
  let root = @moonxml.Element::new("html")
  doc.root.append(@moonxml.ElementNode(root))
  builder.stack.push(root)
  if local_name == "template" {
    builder.templates.push(InTemplate)
  }
  builder.mode = mode_for_context(element)
  let lexer = Lexer::new(preprocess(text), builder)
  lexer.raw_name = local_name
  match local_name {
    "title" | "textarea" => lexer.state = Rcdata
    "style" | "xmp" | "iframe" | "noembed" | "noframes" => lexer.state = Rawtext
    "script" => lexer.state = ScriptData
    "plaintext" => lexer.state = Plaintext
    _ => ()
  }
  tokenize(lexer)
  finish(builder)
  if root.name == "template" {
    return doc
  }
  let kids = root.children.copy()
  root.clear()
  ignore(root.remove())
  for kid in kids {
    doc.root.append(kid)
  }
  doc
}

///|
/// The input preprocessing the standard asks for: a carriage return that ends
/// a line is a line feed, and nothing else about the text changes.
fn preprocess(text : String) -> String {
  if !text.contains("\r") {
    return text
  }
  let out = StringBuilder()
  let n = text.length()
  let mut i = 0
  while i < n {
    let unit = text.at(i)
    if unit == 0x0D {
      out.write_char('\n')
      if i + 1 < n && text.at(i + 1) == 0x0A {
        i = i + 1
      }
    } else {
      out.write_char(unit.unsafe_to_char())
    }
    i = i + 1
  }
  out.to_string()
}

///|
/// The space and local name a context string names: `svg desc` is a `desc`
/// in the SVG space, `math mi` one in MathML, anything else HTML.
fn read_context(context : String) -> (String, String) {
  if context.has_prefix("svg ") {
    (svg_namespace, context[4:context.length()].to_owned())
  } else if context.has_prefix("math ") {
    (mathml_namespace, context[5:context.length()].to_owned())
  } else {
    (html_namespace, context)
  }
}

///|
/// The mode a fragment starts in: the one the context element would put the
/// parser in, worked out the way the stack would.
fn mode_for_context(element : @moonxml.Element) -> Mode {
  match @moonxml.local_of(element.name) {
    "select" => InSelect
    "td" | "th" => InCell
    "tr" => InRow
    "tbody" | "tfoot" | "thead" => InTableBody
    "caption" => InBody
    "colgroup" => InColumnGroup
    "table" => InTable
    "template" => InTemplate
    "frameset" => InFrameset
    "html" => BeforeHead
    _ => InBody
  }
}

///|
fn finish(builder : Builder) -> Unit {
  builder.doc.set_repairs(builder.repairs)
}
