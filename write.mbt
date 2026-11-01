/// Writing a tree back out.
///
/// XML follows §8's rules: attribute order and quoting are preserved, text is
/// escaped minimally (a `>` only where it would close `]]>`), CDATA, comments,
/// PIs, the doctype and self-closing syntax all survive. A namespaced name
/// (`{uri}local`) is written with a reconstructed `xmlns` declaration, so the
/// output is valid XML even though prefixes may differ from the source.
///
/// HTML follows WHATWG §13: void elements carry no end tag, `script`/`style`
/// carry raw text, and empty attribute values are written bare.

struct SerCtx {
  mut n : Int
}

fn split_clark(name : String) -> (String, String) {
  if name.length() > 0 && char_at(name, 0) == '{' {
    let mut close = -1
    let mut i = 0
    for c in name {
      if c == '}' {
        close = i
        break
      }
      i = i + 1
    }
    if close > 0 {
      (name.substring(start=1, end=close), name.substring(start=close + 1, end=name.length()))
    } else {
      ("", name)
    }
  } else {
    ("", name)
  }
}

fn escape_text_xml(sb : StringBuilder, s : String) -> Unit {
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = char_at(s, i)
    if c == '&' {
      sb.write_string("&amp;")
    } else if c == '<' {
      sb.write_string("&lt;")
    } else if c == '>' {
      // A `>` is safe unless it closes a `]]>`; escape only then.
      if i >= 2 && char_at(s, i - 1) == ']' && char_at(s, i - 2) == ']' {
        sb.write_string("&gt;")
      } else {
        sb.write_char('>')
      }
    } else {
      sb.write_char(c)
    }
    i = i + 1
  }
}

fn escape_attr_xml(sb : StringBuilder, s : String) -> Unit {
  for c in s {
    if c == '&' {
      sb.write_string("&amp;")
    } else if c == '<' {
      sb.write_string("&lt;")
    } else if c == '"' {
      sb.write_string("&quot;")
    } else if c == '\t' {
      sb.write_string("&#9;")
    } else if c == '\n' {
      sb.write_string("&#10;")
    } else if c == '\r' {
      sb.write_string("&#13;")
    } else {
      sb.write_char(c)
    }
  }
}

fn write_xml_node(node : Node, sb : StringBuilder, cur_default : String, ctx : SerCtx) -> Unit {
  match node {
    ElementNode(e) => write_xml_element(e, sb, cur_default, ctx)
    TextNode(s) => escape_text_xml(sb, s)
    CDataNode(s) => {
      sb.write_string("<![CDATA[")
      sb.write_string(s)
      sb.write_string("]]>")
    }
    CommentNode(s) => {
      sb.write_string("<!--")
      sb.write_string(s)
      sb.write_string("-->")
    }
    ProcessingInstructionNode(p) => {
      sb.write_string("<?")
      sb.write_string(p.target)
      if p.data.length() > 0 {
        sb.write_string(" ")
        sb.write_string(p.data)
      }
      sb.write_string("?>")
    }
    DoctypeNode(s) => {
      sb.write_string("<!DOCTYPE ")
      sb.write_string(s)
      sb.write_char('>')
    }
    AttributeNode(_, v) => escape_text_xml(sb, v)
  }
}

fn write_xml_element(e : Element, sb : StringBuilder, cur_default : String, ctx : SerCtx) -> Unit {
  let (uri, local) = split_clark(e.name)
  sb.write_char('<')
  sb.write_string(local)
  let mut child_default = cur_default
  if uri != cur_default {
    sb.write_string(" xmlns=\"")
    escape_attr_xml(sb, uri)
    sb.write_char('"')
  }
  child_default = uri
  for pair in e.attrs {
    let (an, av) = pair
    let (auri, alocal) = split_clark(an)
    if auri == "" {
      sb.write_char(' ')
      sb.write_string(alocal)
      sb.write_string("=\"")
      escape_attr_xml(sb, av)
      sb.write_char('"')
    } else {
      let pfx = "ns" + ctx.n.to_string()
      ctx.n = ctx.n + 1
      sb.write_string(" xmlns:")
      sb.write_string(pfx)
      sb.write_string("=\"")
      escape_attr_xml(sb, auri)
      sb.write_char('"')
      sb.write_char(' ')
      sb.write_string(pfx)
      sb.write_char(':')
      sb.write_string(alocal)
      sb.write_string("=\"")
      escape_attr_xml(sb, av)
      sb.write_char('"')
    }
  }
  if e.closed && e.children.length() == 0 {
    sb.write_string("/>")
  } else {
    sb.write_char('>')
    for c in e.children {
      write_xml_node(c, sb, child_default, ctx)
    }
    sb.write_string("</")
    sb.write_string(local)
    sb.write_char('>')
  }
}

fn is_void(el : String) -> Bool {
  if el == "area" || el == "base" || el == "br" || el == "col" {
    return true
  }
  if el == "embed" || el == "hr" || el == "img" || el == "input" {
    return true
  }
  if el == "link" || el == "meta" || el == "param" || el == "source" {
    return true
  }
  if el == "track" || el == "wbr" {
    return true
  }
  false
}

/// Whether every child of `e` is character data.
fn text_only(e : Element) -> Bool {
  for c in e.children {
    match c {
      TextNode(_) | CDataNode(_) => ()
      _ => return false
    }
  }
  true
}

fn is_rawtext(el : String) -> Bool {
  if el == "script" || el == "style" || el == "xmp" {
    return true
  }
  if el == "iframe" || el == "noembed" || el == "noframes" {
    return true
  }
  el == "plaintext"
}

fn html_local(name : String) -> String {
  let (_, local) = split_clark(name)
  local
}

fn escape_text_html(sb : StringBuilder, s : String) -> Unit {
  for c in s {
    if c == '&' {
      sb.write_string("&amp;")
    } else if c == '<' {
      sb.write_string("&lt;")
    } else if c == '>' {
      sb.write_string("&gt;")
    } else if c == '\u{A0}' {
      sb.write_string("&nbsp;")
    } else {
      sb.write_char(c)
    }
  }
}

fn escape_attr_html(sb : StringBuilder, s : String) -> Unit {
  for c in s {
    if c == '&' {
      sb.write_string("&amp;")
    } else if c == '"' {
      sb.write_string("&quot;")
    } else if c == '\u{A0}' {
      sb.write_string("&nbsp;")
    } else {
      sb.write_char(c)
    }
  }
}

/// Split a flattened doctype (`name "pub" "sys"`) into its name and the quoted
/// identifiers that follow it. A quote inside an identifier makes the flattened
/// form ambiguous; the first two quoted runs are taken as the identifiers, which
/// is the best a string can do.
fn split_doctype(info : String) -> (String, Array[String]) {
  let cs = info.to_array()
  let n = cs.length()
  let mut i = 0
  while i < n && cs[i] != ' ' && cs[i] != '\t' {
    i = i + 1
  }
  let nb = StringBuilder()
  let mut k = 0
  while k < i {
    nb.write_char(cs[k])
    k = k + 1
  }
  let ids : Array[String] = []
  while i < n {
    if cs[i] == '"' {
      let start = i
      i = i + 1
      while i < n && cs[i] != '"' {
        i = i + 1
      }
      if i < n {
        i = i + 1
      }
      let sb = StringBuilder()
      let mut j = start
      while j < i {
        sb.write_char(cs[j])
        j = j + 1
      }
      ids.push(sb.to_string())
    } else {
      i = i + 1
    }
  }
  (nb.to_string(), ids)
}

/// The text of a doctype in a HTML document.
///
/// The tree keeps the flattened form the html5lib corpus prints: the name, then
/// the public and system identifiers when either is present, each quoted, with
/// no `PUBLIC` or `SYSTEM` keyword. A parser needs the keyword, so the writer
/// puts it back — a doctype with an empty public identifier is a `SYSTEM` one,
/// and any other pair is a `PUBLIC` one. That is what makes a written document
/// read back as the same doctype.
fn html_doctype_text(info : String) -> String {
  let (name, ids) = split_doctype(info)
  if ids.length() == 0 {
    info
  } else if ids.length() == 1 {
    name + " SYSTEM " + ids[0]
  } else if ids[0] == "\"\"" {
    name + " SYSTEM " + ids[1]
  } else {
    name + " PUBLIC " + ids[0] + " " + ids[1]
  }
}

fn write_html_node(node : Node, sb : StringBuilder) -> Unit {
  match node {
    ElementNode(e) => write_html_element(e, sb)
    TextNode(s) => escape_text_html(sb, s)
    CDataNode(s) => escape_text_html(sb, s)
    CommentNode(s) => {
      sb.write_string("<!--")
      sb.write_string(s)
      sb.write_string("-->")
    }
    ProcessingInstructionNode(p) => {
      sb.write_string("<?")
      sb.write_string(p.target)
      if p.data.length() > 0 {
        sb.write_string(" ")
        sb.write_string(p.data)
      }
      sb.write_string("?>")
    }
    DoctypeNode(s) => {
      sb.write_string("<!DOCTYPE ")
      sb.write_string(html_doctype_text(s))
      sb.write_char('>')
    }
    AttributeNode(_, v) => escape_text_html(sb, v)
  }
}

/// Whether the element's first child is character data beginning with a
/// newline, which is the case the parser's leading-newline rule eats.
fn starts_with_newline(e : Element) -> Bool {
  if e.children.length() == 0 {
    return false
  }
  match e.children[0] {
    TextNode(s) | CDataNode(s) => s.length() > 0 && char_at(s, 0) == '\n'
    _ => false
  }
}

fn write_html_element(e : Element, sb : StringBuilder) -> Unit {
  let (uri, local) = split_clark(e.name)
  // The HTML rules (void elements, raw text) are about elements in the HTML
  // namespace; an `svg plaintext` is an ordinary element that happens to share
  // the name.
  let html_ns = uri == ""
  sb.write_char('<')
  sb.write_string(local)
  for pair in e.attrs {
    let (an, av) = pair
    let alocal = html_local(an)
    sb.write_char(' ')
    sb.write_string(alocal)
    if av.length() > 0 {
      sb.write_string("=\"")
      escape_attr_html(sb, av)
      sb.write_char('"')
    }
  }
  sb.write_char('>')
  if html_ns && is_void(local) {
    return
  }
  // `noscript` holds raw text when the tree was parsed with scripting enabled
  // and normal content when it was not; a text-only child list can only be the
  // former, and writing it raw is what makes the document read back as itself.
  if html_ns && (is_rawtext(local) || (local == "noscript" && text_only(e))) {
    for c in e.children {
      match c {
        TextNode(s) => sb.write_string(s)
        CDataNode(s) => sb.write_string(s)
        _ => write_html_node(c, sb)
      }
    }
  } else {
    // The parser drops one newline directly after `pre`, `textarea` and
    // `listing`; writing content that starts with a newline therefore needs an
    // extra one, or reading the document back loses it.
    if html_ns && (local == "pre" || local == "textarea" || local == "listing") &&
      starts_with_newline(e) {
      sb.write_char('\n')
    }
    for c in e.children {
      write_html_node(c, sb)
    }
  }
  sb.write_string("</")
  sb.write_string(local)
  sb.write_char('>')
}

/// Serialize `node` as XML.
pub fn dumps(node : Node) -> String {
  let sb = StringBuilder()
  let ctx = SerCtx::{ n: 0 }
  write_xml_node(node, sb, "", ctx)
  sb.to_string()
}

/// Serialize `node` as XML and print it.
pub fn dump(node : Node) -> Unit {
  println(dumps(node))
}

/// Serialize `node` as HTML.
pub fn dumps_html(node : Node) -> String {
  let sb = StringBuilder()
  write_html_node(node, sb)
  sb.to_string()
}

/// Serialize `node` as HTML and print it.
pub fn dump_html(node : Node) -> Unit {
  println(dumps_html(node))
}

/// Serialize the element's children as XML.
pub fn Element::inner_html(self : Element) -> String {
  inner_html_flavoured(self, Flavour::Xml)
}

fn inner_html_flavoured(el : Element, flavour : Flavour) -> String {
  let sb = StringBuilder()
  let ctx = SerCtx::{ n: 0 }
  match flavour {
    Xml => {
      let (uri, _) = split_clark(el.name)
      for c in el.children {
        write_xml_node(c, sb, uri, ctx)
      }
    }
    Html => {
      let local = html_local(el.name)
      if is_rawtext(local) {
        for c in el.children {
          match c {
            TextNode(s) => sb.write_string(s)
            _ => write_html_node(c, sb)
          }
        }
      } else {
        for c in el.children {
          write_html_node(c, sb)
        }
      }
    }
  }
  sb.to_string()
}

/// The whole document, written in the flavour it was read as.
pub fn Document::dumps(self : Document) -> String {
  let sb = StringBuilder()
  let ctx = SerCtx::{ n: 0 }
  match self.flavour {
    Xml => {
      for c in self.root.children {
        write_xml_node(c, sb, "", ctx)
      }
    }
    Html => {
      for c in self.root.children {
        write_html_node(c, sb)
      }
    }
  }
  sb.to_string()
}

/// The whole document, written as HTML.
pub fn Document::dumps_html(self : Document) -> String {
  let sb = StringBuilder()
  for c in self.root.children {
    write_html_node(c, sb)
  }
  sb.to_string()
}

/// Print the whole document in its own flavour.
pub fn Document::dump(self : Document) -> Unit {
  println(self.dumps())
}

/// Print the whole document as HTML.
pub fn Document::dump_html(self : Document) -> Unit {
  println(self.dumps_html())
}
