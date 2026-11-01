/// Editing verbs: the bs4 set, applied to the type they edit.
///
/// On `Element` the verbs move nodes: `append` claims the node's parentage and
/// detaches it from wherever it was. On `Selection` a structural verb
/// (`append`, `prepend`, `replace_with`) deep-clones the node for every selected
/// element, so one chain step can add many copies; in-place verbs (`remove`,
/// `unwrap`, `wrap`, `clear`, attributes, `set_text`, `smooth`) act directly.

/// A deep copy of a node. Element copies are detached (no parent) and keep their
/// attribute order, children and self-closing flag.
pub fn Node::clone_deep(self : Node) -> Node {
  match self {
    ElementNode(e) => ElementNode(clone_element(e))
    TextNode(s) => TextNode(s)
    CDataNode(s) => CDataNode(s)
    CommentNode(s) => CommentNode(s)
    ProcessingInstructionNode(p) => ProcessingInstructionNode({ target: p.target, data: p.data })
    DoctypeNode(s) => DoctypeNode(s)
    AttributeNode(n, v) => AttributeNode(n, v)
  }
}

fn clone_element(e : Element) -> Element {
  let c = Element::with_attrs(e.name, e.attrs.copy())
  c.closed = e.closed
  c.parent = None
  for ch in e.children {
    let cc = ch.clone_deep()
    attach(c, cc)
    c.children.push(cc)
  }
  c
}

fn attach(parent : Element, node : Node) -> Unit {
  match node {
    ElementNode(e) => e.parent = Some(parent)
    _ => ()
  }
}

fn detach_from_parent(el : Element) -> Unit {
  match el.parent {
    Some(p) => {
      let mut i = 0
      let mut found = false
      while i < p.children.length() && found == false {
        match p.children[i] {
          ElementNode(x) => if physical_equal(x, el) {
            found = true
          }
          _ => ()
        }
        if found {
          let _ = p.children.remove(i)
        } else {
          i = i + 1
        }
      }
      el.parent = None
    }
    None => ()
  }
}

/// Append `node` as the last child, claiming its parentage.
pub fn Element::append(self : Element, node : Node) -> Unit {
  match node {
    ElementNode(e) => detach_from_parent(e)
    _ => ()
  }
  attach(self, node)
  self.children.push(node)
}

/// Insert `node` as the first child, claiming its parentage.
pub fn Element::prepend(self : Element, node : Node) -> Unit {
  match node {
    ElementNode(e) => detach_from_parent(e)
    _ => ()
  }
  attach(self, node)
  self.children.insert(0, node)
}

/// Insert `node` at index `at`, clamping out-of-range indices.
pub fn Element::insert(self : Element, at : Int, node : Node) -> Unit {
  match node {
    ElementNode(e) => detach_from_parent(e)
    _ => ()
  }
  let n = self.children.length()
  let idx = if at < 0 { 0 } else if at > n { n } else { at }
  attach(self, node)
  self.children.insert(idx, node)
}

/// Place `node` immediately before `self` among its siblings.
pub fn Element::insert_before(self : Element, node : Node) -> Unit {
  match self.parent {
    None => ()
    Some(p) => {
      match node {
        ElementNode(e) => detach_from_parent(e)
        _ => ()
      }
      let idx = self.index_in_parent()
      attach(p, node)
      p.children.insert(idx, node)
    }
  }
}

/// Place `node` immediately after `self` among its siblings.
pub fn Element::insert_after(self : Element, node : Node) -> Unit {
  match self.parent {
    None => ()
    Some(p) => {
      match node {
        ElementNode(e) => detach_from_parent(e)
        _ => ()
      }
      let idx = self.index_in_parent()
      attach(p, node)
      p.children.insert(idx + 1, node)
    }
  }
}

/// Take `self`'s place in its parent.
pub fn Element::replace_with(self : Element, node : Node) -> Unit {
  match self.parent {
    None => ()
    Some(p) => {
      match node {
        ElementNode(e) => detach_from_parent(e)
        _ => ()
      }
      let idx = self.index_in_parent()
      p.children[idx] = node
      attach(p, node)
      self.parent = None
    }
  }
}

/// Detach `self` (and its subtree) from its parent and return it.
pub fn Element::remove(self : Element) -> Node {
  detach_from_parent(self)
  ElementNode(self)
}

/// Replace `self` with its children.
pub fn Element::unwrap(self : Element) -> Unit {
  match self.parent {
    None => ()
    Some(p) => {
      let idx = self.index_in_parent()
      let _ = p.children.remove(idx)
      let mut i = 0
      for c in self.children {
        attach(p, c)
        p.children.insert(idx + i, c)
        i = i + 1
      }
      self.children = []
      self.parent = None
    }
  }
}

/// Wrap `self` in a fresh element named `name`, returning the wrapper.
pub fn Element::wrap(self : Element, name : String) -> Element {
  let wrapper = Element::new(name)
  match self.parent {
    None => {
      wrapper.children.push(ElementNode(self))
      self.parent = Some(wrapper)
    }
    Some(p) => {
      let idx = self.index_in_parent()
      p.children[idx] = ElementNode(wrapper)
      wrapper.parent = Some(p)
      wrapper.children.push(ElementNode(self))
      self.parent = Some(wrapper)
    }
  }
  wrapper
}

/// Drop all children.
pub fn Element::clear(self : Element) -> Unit {
  for c in self.children {
    match c {
      ElementNode(e) => e.parent = None
      _ => ()
    }
  }
  self.children = []
}

/// Replace all children with one text node.
pub fn Element::set_text(self : Element, s : String) -> Unit {
  self.clear()
  self.children.push(TextNode(s))
}

/// Fuse adjacent text nodes. Serialization wants one text run per run; edits
/// that split text leave neighbours that this rejoins.
pub fn Element::smooth(self : Element) -> Unit {
  let out : Array[Node] = []
  let mut pending : String? = None
  for c in self.children {
    match c {
      TextNode(s) => {
        pending = match pending {
          None => Some(s)
          Some(prev) => Some(prev + s)
        }
      }
      _ => {
        match pending {
          Some(prev) => {
            out.push(TextNode(prev))
            pending = None
          }
          None => ()
        }
        out.push(c)
      }
    }
  }
  match pending {
    Some(prev) => out.push(TextNode(prev))
    None => ()
  }
  self.children = out
}

// ---------------------------------------------------------------------------
// Selection-level verbs
// ---------------------------------------------------------------------------

fn selection_elements(sel : Selection) -> Array[Element] {
  let out : Array[Element] = []
  for item in sel.items {
    match item {
      ElementNode(e) => out.push(e)
      _ => ()
    }
  }
  out
}

/// Append a deep copy of `node` to every selected element.
pub fn Selection::append(self : Selection, node : Node) -> Unit {
  for e in selection_elements(self) {
    e.append(node.clone_deep())
  }
}

/// Prepend a deep copy of `node` to every selected element.
pub fn Selection::prepend(self : Selection, node : Node) -> Unit {
  for e in selection_elements(self) {
    e.prepend(node.clone_deep())
  }
}

/// Replace every selected element with a deep copy of `node`.
pub fn Selection::replace_with(self : Selection, node : Node) -> Unit {
  for e in selection_elements(self) {
    e.replace_with(node.clone_deep())
  }
}

/// Detach every selected element and return them as a new selection.
pub fn Selection::remove(self : Selection) -> Selection {
  let out : Array[Node] = []
  for e in selection_elements(self) {
    out.push(e.remove())
  }
  Selection::with_doc(self.doc, out)
}

/// Replace every selected element with its children.
pub fn Selection::unwrap(self : Selection) -> Unit {
  for e in selection_elements(self) {
    e.unwrap()
  }
}

/// Wrap every selected element in a fresh element named `name`.
pub fn Selection::wrap(self : Selection, name : String) -> Unit {
  for e in selection_elements(self) {
    let _ = e.wrap(name)
  }
}

/// Drop the children of every selected element.
pub fn Selection::clear(self : Selection) -> Unit {
  for e in selection_elements(self) {
    e.clear()
  }
}

/// Set attribute `n` to `v` on every selected element.
pub fn Selection::set_attr(self : Selection, n : String, v : String) -> Unit {
  for e in selection_elements(self) {
    e.set_attr(n, v)
  }
}

/// Remove attribute `n` from every selected element.
pub fn Selection::remove_attr(self : Selection, n : String) -> Unit {
  for e in selection_elements(self) {
    e.remove_attr(n)
  }
}

/// Add class `c` to every selected element.
pub fn Selection::add_class(self : Selection, c : String) -> Unit {
  for e in selection_elements(self) {
    e.add_class(c)
  }
}

/// Remove class `c` from every selected element.
pub fn Selection::remove_class(self : Selection, c : String) -> Unit {
  for e in selection_elements(self) {
    e.remove_class(c)
  }
}

/// Replace every selected element's children with one text node.
pub fn Selection::set_text(self : Selection, s : String) -> Unit {
  for e in selection_elements(self) {
    e.set_text(s)
  }
}

/// Fuse adjacent text nodes in every selected element.
pub fn Selection::smooth(self : Selection) -> Unit {
  for e in selection_elements(self) {
    e.smooth()
  }
}
