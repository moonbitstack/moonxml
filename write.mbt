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
      sb.write_string(s)
      sb.write_char('>')
    }
    AttributeNode(_, v) => escape_text_html(sb, v)
  }
}

fn write_html_element(e : Element, sb : StringBuilder) -> Unit {
  let local = html_local(e.name)
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
  if is_void(local) {
    return
  }
  if is_rawtext(local) {
    for c in e.children {
      match c {
        TextNode(s) => sb.write_string(s)
        CDataNode(s) => sb.write_string(s)
        _ => write_html_node(c, sb)
      }
    }
  } else {
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
