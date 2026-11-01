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
///
/// Comments are placed by where the tokenizer met them: before the `html`
/// element they stay at the document level, between `html` and `body` they sit
/// inside `html` before `head`, and after body content they are body children.
pub fn normalize_document(root : @moonxml.Element) -> Unit {
  let existing = find_element_child(root, "html")
  let html = match existing {
    Some(e) => e
    None => @moonxml.Element::new("html")
  }
  // Nodes to redistribute, in source order.
  let source : Array[@moonxml.Node] = []
  if existing.is_none() {
    for c in root.children {
      match c {
        @moonxml.Node::DoctypeNode(_) => ()
        _ => source.push(c)
      }
    }
  } else {
    for c in html.children {
      source.push(c)
    }
    html.set_children([])
  }
  let head = @moonxml.Element::new("head")
  let body = @moonxml.Element::new("body")
  let mut frameset : @moonxml.Element? = None
  // Comments before `head`, kept as `html` children when `html` already existed.
  let before_head : Array[@moonxml.Node] = []
  // Document-level comments, only possible when `html` had to be synthesized.
  let doc_level : Array[@moonxml.Node] = []
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
        } else if existing.is_some() {
          before_head.push(n)
        } else {
          doc_level.push(n)
        }
      }
      _ => {
        in_body = true
        body.append(n)
      }
    }
  }
  let shaped : Array[@moonxml.Node] = []
  for c in before_head {
    shaped.push(c)
  }
  shaped.push(@moonxml.Node::ElementNode(head))
  match frameset {
    Some(f) => shaped.push(@moonxml.Node::ElementNode(f))
    None => shaped.push(@moonxml.Node::ElementNode(body))
  }
  html.set_children(shaped)
  if existing.is_none() {
    let keep : Array[@moonxml.Node] = []
    for c in root.children {
      match c {
        @moonxml.Node::DoctypeNode(_) => keep.push(c)
        _ => ()
      }
    }
    for c in doc_level {
      keep.push(c)
    }
    keep.push(@moonxml.Node::ElementNode(html))
    root.set_children(keep)
  }
}
