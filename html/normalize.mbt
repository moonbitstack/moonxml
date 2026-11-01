/// Document normalization for `loads`.
///
/// The tree builder produces the nodes a tokenizer saw; a browser additionally
/// guarantees one `html` element with a `head` (possibly empty) and a `body`
/// (or a `frameset`), and drops formatting whitespace outside the body. This
/// file performs that shaping after parsing, so the tree matches the shape the
/// html5lib corpus expects without a full set of insertion modes.

fn is_blank_text(n : @moonxml.Node) -> Bool {
  match n {
    @moonxml.Node::TextNode(s) => @text.is_blank(s)
    _ => false
  }
}

fn append_head_child(head : @moonxml.Element, n : @moonxml.Node) -> Unit {
  // Formatting whitespace inside head is not part of the tree.
  if is_blank_text(n) {
    return
  }
  head.append(n)
}

fn append_body_child(body : @moonxml.Element, n : @moonxml.Node) -> Unit {
  body.append(n)
}

fn find_element_child(parent : @moonxml.Element, name : String) -> @moonxml.Element? {
  for c in parent.children {
    match c {
      @moonxml.Node::ElementNode(e) => if local_of(e.name).to_lower() == name {
        return Some(e)
      }
      _ => ()
    }
  }
  None
}

/// Shape `root` into a document: one `html`, a `head`, and a `body` or
/// `frameset`, with head content routed and formatting whitespace dropped.
pub fn normalize_document(root : @moonxml.Element) -> Unit {
  let existing = find_element_child(root, "html")
  // Gather the nodes to redistribute.
  let source : Array[@moonxml.Node] = []
  if existing.is_none() {
    for c in root.children {
      match c {
        @moonxml.Node::DoctypeNode(_) => ()
        _ => source.push(c)
      }
    }
  } else {
    let html = existing.unwrap()
    for c in html.children {
      source.push(c)
    }
    html.set_children([])
  }
  let html = match existing {
    Some(e) => e
    None => @moonxml.Element::new("html")
  }
  let head = @moonxml.Element::new("head")
  let body = @moonxml.Element::new("body")
  let mut frameset : @moonxml.Element? = None
  let pre : Array[@moonxml.Node] = []
  let mut in_body = false
  for n in source {
    match n {
      @moonxml.Node::ElementNode(e) => {
        let l = local_of(e.name).to_lower()
        if l == "head" {
          let kids = e.children.copy()
          e.set_children([])
          for k in kids {
            append_head_child(head, k)
          }
        } else if l == "body" {
          let kids = e.children.copy()
          e.set_children([])
          for k in kids {
            append_body_child(body, k)
          }
          in_body = true
        } else if l == "frameset" {
          frameset = Some(e)
          in_body = true
        } else if is_head_element(n) && not(in_body) {
          append_head_child(head, n)
        } else {
          in_body = true
          append_body_child(body, n)
        }
      }
      @moonxml.Node::TextNode(s) => {
        if @text.is_blank(s) && not(in_body) {
          // formatting whitespace before body is not part of the tree
        } else {
          in_body = true
          body.append(n)
        }
      }
      @moonxml.Node::CommentNode(_) => {
        if in_body {
          body.append(n)
        } else {
          pre.push(n)
        }
      }
      _ => {
        in_body = true
        body.append(n)
      }
    }
  }
  html.set_children([])
  html.append(@moonxml.Node::ElementNode(head))
  match frameset {
    Some(f) => html.append(@moonxml.Node::ElementNode(f))
    None => html.append(@moonxml.Node::ElementNode(body))
  }
  // Keep doctypes at the document level, then the html element.
  let keep : Array[@moonxml.Node] = []
  for c in root.children {
    match c {
      @moonxml.Node::DoctypeNode(_) => keep.push(c)
      _ => ()
    }
  }
  for c in pre {
    keep.push(c)
  }
  keep.push(@moonxml.Node::ElementNode(html))
  root.set_children(keep)
}
