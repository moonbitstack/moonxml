/// Document normalization for `loads`.
///
/// The tree builder produces the nodes a tokenizer saw; a browser additionally
/// guarantees one `html` element with a `head` (possibly empty) and a `body`
/// (or a `frameset`), and drops formatting whitespace outside the body. This
/// file performs that shaping after parsing, so the tree matches the shape the
/// html5lib corpus expects without a full set of insertion modes.

fn is_fostered(e : @moonxml.Element, fostered : Array[@moonxml.Element]) -> Bool {
  for f in fostered {
    if physical_equal(f, e) {
      return true
    }
  }
  false
}

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
  normalize_document_with_fostered(root, 0, [])
}

/// `fostered` lists elements moved out of a table; they count as body content.
pub fn normalize_document_with_fostered(
  root : @moonxml.Element,
  trailing : Int,
  fostered : Array[@moonxml.Element]
) -> Unit {
  normalize_document_impl(root, trailing, fostered)
}

/// `trailing` is how many comments the parser appended after `</body>`; they
/// stay between `body` and the end of `html`.
pub fn normalize_document_with(root : @moonxml.Element, trailing : Int) -> Unit {
  normalize_document_impl(root, trailing, [])
}

fn normalize_document_impl(
  root : @moonxml.Element,
  trailing : Int,
  fostered : Array[@moonxml.Element]
) -> Unit {
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
  // A `head`/`body` that was already in the input keeps its attributes.
  let mut head_out : @moonxml.Element? = None
  let mut body_out : @moonxml.Element? = None
  // Comments before `head`, kept as `html` children when `html` already existed.
  let before_head : Array[@moonxml.Node] = []
  // Comments met after `head` but before `body`.
  let after_head : Array[@moonxml.Node] = []
  // Comments that follow the body element.
  let after_body : Array[@moonxml.Node] = []
  // Content met after a frameset: it stays at html level.
  let after_frameset : Array[@moonxml.Node] = []
  // Document-level comments, only possible when `html` had to be synthesized.
  let doc_level : Array[@moonxml.Node] = []
  let mut seen_element = existing.is_some()
  let mut seen_head = false
  let mut seen_body = false
  let mut in_body = false
  let mut comment_index = 0
  let mut comment_total = 0
  for c in source {
    match c {
      @moonxml.Node::CommentNode(_) => comment_total = comment_total + 1
      _ => ()
    }
  }
  for n in source {
    match n {
      @moonxml.Node::ElementNode(e) => {
        seen_element = true
        let l = local_of(e.name).to_lower()
        if l == "head" {
          seen_head = true
          head_out = Some(e)
          let kids = e.children.copy()
          e.set_children([])
          for k in kids {
            append_head_child(head, k)
          }
        } else if l == "body" {
          seen_body = true
          body_out = Some(e)
          let kids = e.children.copy()
          e.set_children([])
          for k in kids {
            append_body_child(body, k)
          }
          in_body = true
        } else if l == "frameset" {
          frameset = Some(e)
          in_body = true
        } else if is_head_element(n) && not(in_body) && not(is_fostered(e, fostered)) {
          append_head_child(head, n)
        } else {
          in_body = true
          append_body_child(body, n)
        }
      }
      @moonxml.Node::TextNode(s) => {
        if frameset.is_some() && in_body {
          after_frameset.push(n)
        } else if @text.is_blank(s) && not(in_body) && seen_head {
          after_head.push(n)
        } else if @text.is_blank(s) && not(in_body) {
          // formatting whitespace before head is not part of the tree
        } else {
          in_body = true
          body.append(n)
        }
      }
      @moonxml.Node::CommentNode(_) => {
        comment_index = comment_index + 1
        if frameset.is_some() && in_body {
          after_frameset.push(n)
        } else if comment_index > comment_total - trailing {
          after_body.push(n)
        } else if in_body {
          body.append(n)
        } else if seen_head {
          after_head.push(n)
        } else if head.children.length() > 0 {
          head.append(n)
        } else if seen_element {
          before_head.push(n)
        } else if in_body {
          body.append(n)
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
  match head_out {
    Some(h) => {
      h.set_children(head.children.copy())
      shaped.push(@moonxml.Node::ElementNode(h))
    }
    None => shaped.push(@moonxml.Node::ElementNode(head))
  }
  for c in after_head {
    shaped.push(c)
  }
  match frameset {
    Some(f) => shaped.push(@moonxml.Node::ElementNode(f))
    None => match body_out {
      Some(b) => {
        b.set_children(body.children.copy())
        shaped.push(@moonxml.Node::ElementNode(b))
      }
      None => shaped.push(@moonxml.Node::ElementNode(body))
    }
  }
  for c in after_frameset {
    shaped.push(c)
  }
  for c in after_body {
    shaped.push(c)
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
