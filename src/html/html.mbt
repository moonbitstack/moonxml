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
///
/// `scripting` is whether the reader may run what it reads. It changes one
/// thing: a `noscript`'s content is markup when nothing is going to run it, and
/// raw text when something is, which is what a browser does. Off by default —
/// a library reads documents, and reading them is not running them.
///
/// ```mbt check
/// test {
///   let doc = @html.loads("<ul><li>coffee<li>tea</ul>")
///   assert_eq(doc.css("li").length(), 2)
///   assert_eq(doc.css("li").last().text(), "tea")
/// }
/// ```
pub fn loads(text : String, scripting~ : Bool = false) -> @moonxml.Document {
  let doc = @moonxml.Document::new(flavour=@moonxml.Html, scripting~)
  let builder = Builder::new(doc)
  builder.scripting = scripting
  let lexer = Lexer::new(preprocess(@text.strip_bom(text)), builder)
  tokenize(lexer)
  finish(builder)
  doc
}

///|
/// Read a document from bytes; UTF-8, with a leading byte-order mark skipped.
/// A byte that is not UTF-8 reads as U+FFFD, the way a browser reads it.
pub fn load(bytes : Bytes, scripting~ : Bool = false) -> @moonxml.Document {
  loads(@utf8.decode_lossy(bytes, ignore_bom=true), scripting~)
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
  scripting~ : Bool = false,
) -> @moonxml.Document {
  let doc = @moonxml.Document::new(flavour=@moonxml.Html, scripting~)
  let builder = Builder::new(doc)
  builder.scripting = scripting
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
  // A fragment has no start tag of its own, so no end tag in it is "the
  // appropriate one": raw text runs to the end of the input.
  if space == html_namespace {
    match local_name {
      "title" | "textarea" => lexer.state = Rcdata
      "style" | "xmp" | "iframe" | "noembed" | "noframes" =>
        lexer.state = Rawtext
      "script" => lexer.state = ScriptData
      "plaintext" => lexer.state = Plaintext
      _ => ()
    }
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
/// Read a text as the token stream the tokenizer answers, before any tree is
/// built: the runs of characters, the start tags with their attributes, the end
/// tags, the comments and the doctype, in the order they come.
///
/// This is the tokenizer's own reading, not the tree builder's: an end tag that
/// matches nothing is still an end tag here, a stray table cell is still a cell,
/// and the attributes a tag repeats are still repeated. `Document::events`
/// answers the same shape for a document that has been built.
pub fn scan(
  text : String,
  sink : &@event.Sink,
  scripting~ : Bool = false,
) -> Unit {
  let doc = @moonxml.Document::new(flavour=@moonxml.Html, scripting~)
  let builder = Builder::new(doc)
  builder.scripting = scripting
  let lexer = Lexer::new(preprocess(text), builder, out=fn(_, token) {
    match token {
      StartTag(name~, attrs~, self_closing~) =>
        sink.push(@event.StartTag(name~, attrs~, self_closing~))
      EndTag(name~) => sink.push(@event.EndTag(name~))
      Characters(text~) => sink.push(@event.Text(text~))
      CommentToken(text~) => sink.push(@event.Comment(text~))
      DoctypeToken(name~, public_id~, system_id~, force_quirks~) => {
        ignore(force_quirks)
        sink.push(
          @event.Doctype(
            text=doctype_text(
              name.unwrap_or(""),
              public_id.unwrap_or(""),
              system_id.unwrap_or(""),
            ),
          ),
        )
      }
      Eof => ()
    }
  })
  tokenize(lexer)
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
  fill_selects(builder.doc.root)
}

///|
/// A deep copy of a node. What a `<selectedcontent>` holds is a copy of the
/// chosen option's children, not the children themselves.
fn copy_node(node : @moonxml.Node) -> @moonxml.Node {
  match node {
    @moonxml.ElementNode(data) => {
      let copy = @moonxml.Element::new(data.name, attrs=data.attrs.copy())
      for child in data.children {
        copy.append(copy_node(child))
      }
      match data.content() {
        Some(fragment) => {
          let inner = @moonxml.Element::new("#content")
          for child in fragment.children {
            inner.append(copy_node(child))
          }
          copy.set_content(inner)
        }
        None => ()
      }
      @moonxml.ElementNode(copy)
    }
    @moonxml.TextNode(text) => @moonxml.TextNode(text)
    @moonxml.CDataNode(text) => @moonxml.CDataNode(text)
    @moonxml.CommentNode(text) => @moonxml.CommentNode(text)
    @moonxml.ProcessingInstructionNode(instruction) =>
      @moonxml.ProcessingInstructionNode(instruction)
    @moonxml.DoctypeNode(text) => @moonxml.DoctypeNode(text)
    @moonxml.AttributeNode(attr) => @moonxml.AttributeNode(attr)
    @moonxml.NamespaceNode(space) => @moonxml.NamespaceNode(space)
  }
}

///|
/// The first element named `name` under `element`, in document order.
fn first_named(element : @moonxml.Element, name : String) -> @moonxml.Element? {
  for child in element.children {
    if child is @moonxml.ElementNode(data) {
      if data.name == name {
        return Some(data)
      }
      match first_named(data, name) {
        Some(found) => return Some(found)
        None => ()
      }
    }
  }
  None
}

///|
fn collect_named(
  element : @moonxml.Element,
  name : String,
  into : Array[@moonxml.Element],
) -> Unit {
  for child in element.children {
    if child is @moonxml.ElementNode(data) {
      if data.name == name {
        into.push(data)
      }
      collect_named(data, name, into)
    }
  }
}

///|
/// The option a select chose: the first one that says it is selected, or, when
/// none does, the first one that is not disabled.
fn chosen_option(select : @moonxml.Element) -> @moonxml.Element? {
  let options : Array[@moonxml.Element] = []
  collect_named(select, "option", options)
  for option in options {
    if option.has_attr("selected") {
      return Some(option)
    }
  }
  for option in options {
    if !option.has_attr("disabled") {
      return Some(option)
    }
  }
  None
}

///|
/// A `<select>`'s own algorithm, run over the finished tree: what the chosen
/// option holds is copied into the `<selectedcontent>` the select carries. A
/// browser runs this whenever the choice changes, which is what makes the box
/// show the option's content; a reader runs it once, when the tree is done, so
/// that the tree it answers is the tree a browser would show.
fn fill_select(select : @moonxml.Element) -> Unit {
  let holder = match first_named(select, "selectedcontent") {
    Some(found) => found
    None => return
  }
  let chosen = chosen_option(select)
  holder.clear()
  match chosen {
    Some(option) =>
      for child in option.children {
        holder.append(copy_node(child))
      }
    None => ()
  }
}

///|
fn fill_selects(element : @moonxml.Element) -> Unit {
  for child in element.children.copy() {
    if child is @moonxml.ElementNode(data) {
      if data.name == "select" {
        fill_select(data)
      }
      fill_selects(data)
    }
  }
}
