// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A selection: the nodes a query returned, and the document they belong to.
/// The empty result is an empty list, never a special value, so a chain never
/// branches — and every query method exists on `Selection`, on `Element` and
/// on `Document`, so a chain never has to stop at a node.
///
///     doc.xpath("//ul").css("li.external").xpath("@href")
///        .selector("tag", "a").custom(DeepLinks::new())
///        .items[2].children[0].css("span").text()
pub struct Selection {
  priv doc : Document?
  items : Array[Node]
}

///|
/// An empty selection, belonging to no document.
pub fn Selection::new() -> Selection {
  { doc: None, items: [], }
}

///|
/// Wrap one node, answering a selection that carries the document the node
/// belongs to when it has one.
fn selection_of(node : Node) -> Selection {
  match node {
    ElementNode(data) => { doc: data.document(), items: [node], }
    _ => { doc: None, items: [node], }
  }
}

///|
/// A selection of these nodes, belonging to this document.
fn Document::selection(self : Document, nodes : Array[Node]) -> Selection {
  { doc: Some(self), items: nodes, }
}

///|
/// The nodes a query found, deduplicated by identity: overlapping contexts
/// must not answer the same node twice. The scan is skipped when there is one
/// context, whose walk cannot repeat a node.
fn collect(nodes : Array[Node], doc : Document?, unique~ : Bool) -> Selection {
  if !unique {
    return { doc, items: nodes, }
  }
  let kept : Array[Node] = []
  for node in nodes {
    let mut seen = false
    for have in kept {
      if node is ElementNode(a) &&
        have is ElementNode(b) &&
        physical_equal(a, b) {
        seen = true
        break
      }
    }
    if !seen {
      kept.push(node)
    }
  }
  { doc, items: kept, }
}

///|
/// The engine every descendant search shares: walk each context's subtree,
/// keep what `keep` accepts, answer in document order.
fn gather(ctx : Selection, keep : (Element) -> Bool) -> Selection {
  if ctx.items.is_empty() {
    return ctx
  }
  let out : Array[Node] = []
  for node in ctx.items {
    if node is ElementNode(data) {
      data.walk(fn(found) {
        if found is ElementNode(element) && keep(element) {
          out.push(found)
        }
      })
    }
  }
  collect(out, ctx.doc, unique=ctx.items.length() > 1)
}

// Query. Each narrows the selection and answers a new one; the empty result
// is an empty selection.

///|
/// Narrow with a CSS selector, Selectors Level 4's statically decidable
/// subset. Searches the descendants of the selected nodes — the context
/// itself is never a candidate, `querySelectorAll`'s rule.
pub fn Selection::css(
  self : Selection,
  query : String,
) -> Selection raise Refused {
  let complexes = css_parse(query)
  gather(self, fn(element) { complex_list_matches(complexes, element) })
}

///|
/// The elements among the descendants whose `id` attribute is `id`.
pub fn Selection::by_id(self : Selection, id : String) -> Selection {
  gather(self, fn(element) { element.attr("id") == Some(id) })
}

///|
/// The elements among the descendants that carry the class `name`.
pub fn Selection::by_class(self : Selection, name : String) -> Selection {
  gather(self, fn(element) { element.has_class(name) })
}

///|
/// The elements among the descendants whose name is `name`; `*` answers them
/// all.
pub fn Selection::by_tag(self : Selection, name : String) -> Selection {
  gather(self, fn(element) { element.name == name || name == "*" })
}

///|
/// The elements among the descendants whose `name` attribute is `name`.
pub fn Selection::by_name(self : Selection, name : String) -> Selection {
  gather(self, fn(element) { element.attr("name") == Some(name) })
}

///|
/// Keep the selected nodes a closure accepts.
pub fn Selection::filter(self : Selection, keep : (Node) -> Bool) -> Selection {
  collect(self.items.filter(keep), self.doc, unique=false)
}

///|
/// The nearest ancestor — self included — matching a CSS selector.
pub fn Selection::closest(
  self : Selection,
  query : String,
) -> Selection raise Refused {
  let complexes = css_parse(query)
  let out : Array[Node] = []
  for node in self.items {
    if node is ElementNode(start) {
      let mut current : Element? = Some(start)
      let mut climbing = true
      while climbing {
        match current {
          Some(element) =>
            if complex_list_matches(complexes, element) {
              out.push(ElementNode(element))
              climbing = false
            } else {
              current = element.parent
            }
          None => climbing = false
        }
      }
    }
  }
  collect(out, self.doc, unique=self.items.length() > 1)
}

///|
/// Run a selector by the name it was registered under, built-in or the
/// caller's own. An unregistered name raises.
pub fn Selection::selector(
  self : Selection,
  name : String,
  query : String,
) -> Selection raise Refused {
  match self.doc {
    Some(doc) =>
      match doc.selectors.get(name) {
        Some(sel) => sel.select(self, query)
        None => raise UnknownSelector(name~)
      }
    None => raise UnknownSelector(name~)
  }
}

///|
/// Run a selector that was never registered: no name, no state.
pub fn Selection::custom(
  self : Selection,
  sel : &Selector,
) -> Selection raise Refused {
  sel.select(self, "")
}

// Narrowing.

///|
/// `selection[i]` in the chain: the node at that position, so a chain can step
/// down into one node and carry on. Out of range answers a detached empty
/// element rather than panicking.
#alias("_[_]")
pub fn Selection::at(self : Selection, index : Int32) -> Node {
  if index >= 0 && index < self.items.length() {
    self.items[index]
  } else {
    ElementNode(Element::new(""))
  }
}

///|
/// The first selected node; empty stays empty.
pub fn Selection::first(self : Selection) -> Selection {
  if self.items.is_empty() {
    self
  } else {
    { doc: self.doc, items: [self.items[0]], }
  }
}

///|
/// The last selected node; empty stays empty.
pub fn Selection::last(self : Selection) -> Selection {
  let n = self.items.length()
  if n == 0 {
    self
  } else {
    { doc: self.doc, items: [self.items[n - 1]], }
  }
}

///|
/// The selected node at `i`; a negative index counts from the end, the way
/// jQuery's `eq` does. Out of range answers empty.
pub fn Selection::eq(self : Selection, i : Int32) -> Selection {
  let n = self.items.length()
  let at = if i < 0 { n + i } else { i }
  if at < 0 || at >= n {
    { doc: self.doc, items: [], }
  } else {
    { doc: self.doc, items: [self.items[at]], }
  }
}

///|
/// The children of every selected node.
pub fn Selection::children(self : Selection) -> Selection {
  let out : Array[Node] = []
  for node in self.items {
    if node is ElementNode(data) {
      for child in data.children {
        out.push(child)
      }
    }
  }
  collect(out, self.doc, unique=self.items.length() > 1)
}

///|
/// The parent of every selected node that has one.
pub fn Selection::parent(self : Selection) -> Selection {
  let out : Array[Node] = []
  for node in self.items {
    if node is ElementNode(data) {
      match data.parent {
        Some(above) => out.push(ElementNode(above))
        None => ()
      }
    }
  }
  collect(out, self.doc, unique=self.items.length() > 1)
}

///|
/// Every node below the selected nodes, in document order.
pub fn Selection::descendants(self : Selection) -> Selection {
  let out : Array[Node] = []
  for node in self.items {
    if node is ElementNode(data) {
      data.walk(fn(found) { out.push(found) })
    }
  }
  collect(out, self.doc, unique=self.items.length() > 1)
}

// Reading.

///|
/// How many nodes the selection holds.
pub fn Selection::length(self : Selection) -> Int32 {
  self.items.length()
}

///|
/// The text content of every selected node, concatenated.
pub fn Selection::text(self : Selection) -> String {
  let out = StringBuilder()
  for node in self.items {
    out.write_string(node.text())
  }
  out.to_string()
}

///|
/// The inner HTML of the first selected element, written in the flavour its
/// document was read as; `""` when the selection holds no element.
pub fn Selection::html(self : Selection) -> String {
  for node in self.items {
    if node is ElementNode(data) {
      return inner_html(data)
    }
  }
  ""
}

///|
/// The element's inner markup, written in the flavour its document was read as.
pub fn Element::html(self : Element) -> String {
  inner_html(self)
}

///|
fn inner_html(element : Element) -> String {
  let out = StringBuilder()
  let html = match element.document() {
    Some(doc) => doc.flavour is Html
    None => false
  }
  for child in element.children {
    if html {
      write_html(child, out, raw=false)
    } else {
      write_xml(child, out)
    }
  }
  out.to_string()
}

///|
/// The named attribute of the first selected element that carries it.
pub fn Selection::attr(self : Selection, name : String) -> String? {
  for node in self.items {
    if node is ElementNode(data) {
      match data.attr(name) {
        Some(value) => return Some(value)
        None => ()
      }
    }
  }
  None
}

// Editing. Each verb applies to every selected element.

///|
/// Append a node to every selected element.
pub fn Selection::append(self : Selection, node : Node) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      data.append(node)
    }
  }
}

///|
/// Insert a node as the first child of every selected element.
pub fn Selection::prepend(self : Selection, node : Node) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      data.prepend(node)
    }
  }
}

///|
/// Detach every selected element from its parent.
pub fn Selection::remove(self : Selection) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      ignore(data.remove())
    }
  }
}

///|
/// Put a node in the place of every selected element.
pub fn Selection::replace_with(self : Selection, node : Node) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      ignore(data.replace_with(node))
    }
  }
}

///|
/// Replace every selected element with its children.
pub fn Selection::unwrap(self : Selection) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      ignore(data.unwrap())
    }
  }
}

///|
/// Wrap every selected element in a fresh element of this name.
pub fn Selection::wrap(self : Selection, name : String) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      ignore(data.wrap(name))
    }
  }
}

///|
/// Drop the children of every selected element.
pub fn Selection::clear(self : Selection) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      data.clear()
    }
  }
}

///|
/// Replace the children of every selected element with one text node.
pub fn Selection::set_text(self : Selection, text : String) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      data.clear()
      data.append(TextNode(text))
    }
  }
}

///|
/// Set an attribute on every selected element.
pub fn Selection::set_attr(
  self : Selection,
  name : String,
  value : String,
) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      data.set_attr(name, value)
    }
  }
}

///|
/// Remove an attribute from every selected element.
pub fn Selection::remove_attr(self : Selection, name : String) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      ignore(data.remove_attr(name))
    }
  }
}

///|
/// Add a class to every selected element.
pub fn Selection::add_class(self : Selection, name : String) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      data.add_class(name)
    }
  }
}

///|
/// Remove a class from every selected element.
pub fn Selection::remove_class(self : Selection, name : String) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      data.remove_class(name)
    }
  }
}

///|
/// Fuse adjacent text nodes under every selected element.
pub fn Selection::smooth(self : Selection) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      data.smooth()
    }
  }
}

// The same surface on Element, Node and Document, so a chain never has to
// stop. A node that is not an element has no descendants to search, so its
// query methods answer an empty selection.

///|
/// Narrow to the descendants of this element that match a CSS selector.
pub fn Element::css(self : Element, query : String) -> Selection raise Refused {
  selection_of(ElementNode(self)).css(query)
}

///|
/// The descendants of this element whose `id` attribute is `id`.
pub fn Element::by_id(self : Element, id : String) -> Selection {
  selection_of(ElementNode(self)).by_id(id)
}

///|
/// The descendants of this element that carry the class `name`.
pub fn Element::by_class(self : Element, name : String) -> Selection {
  selection_of(ElementNode(self)).by_class(name)
}

///|
/// The descendants of this element named `name`; `*` answers every element.
pub fn Element::by_tag(self : Element, name : String) -> Selection {
  selection_of(ElementNode(self)).by_tag(name)
}

///|
/// The descendants of this element whose `name` attribute is `name`.
pub fn Element::by_name(self : Element, name : String) -> Selection {
  selection_of(ElementNode(self)).by_name(name)
}

///|
/// The nearest ancestor of this element, itself included, that matches a CSS selector.
pub fn Element::closest(
  self : Element,
  query : String,
) -> Selection raise Refused {
  selection_of(ElementNode(self)).closest(query)
}

///|
/// Run the selector registered under `name`, over this element's descendants.
pub fn Element::selector(
  self : Element,
  name : String,
  query : String,
) -> Selection raise Refused {
  selection_of(ElementNode(self)).selector(name, query)
}

///|
/// Run a selector that was never registered, over this element's descendants.
pub fn Element::custom(
  self : Element,
  sel : &Selector,
) -> Selection raise Refused {
  selection_of(ElementNode(self)).custom(sel)
}

///|
/// Narrow to the descendants of this node that match a CSS selector; a node that is not an element answers empty.
pub fn Node::css(self : Node, query : String) -> Selection raise Refused {
  match self {
    ElementNode(data) => data.css(query)
    _ => Selection::new()
  }
}

///|
/// The descendants of this node whose `id` attribute is `id`.
pub fn Node::by_id(self : Node, id : String) -> Selection {
  match self {
    ElementNode(data) => data.by_id(id)
    _ => Selection::new()
  }
}

///|
/// The descendants of this node that carry the class `name`.
pub fn Node::by_class(self : Node, name : String) -> Selection {
  match self {
    ElementNode(data) => data.by_class(name)
    _ => Selection::new()
  }
}

///|
/// The descendants of this node named `name`.
pub fn Node::by_tag(self : Node, name : String) -> Selection {
  match self {
    ElementNode(data) => data.by_tag(name)
    _ => Selection::new()
  }
}

///|
/// The descendants of this node whose `name` attribute is `name`.
pub fn Node::by_name(self : Node, name : String) -> Selection {
  match self {
    ElementNode(data) => data.by_name(name)
    _ => Selection::new()
  }
}

///|
/// The nearest ancestor of this node, itself included, that matches a CSS selector.
pub fn Node::closest(self : Node, query : String) -> Selection raise Refused {
  match self {
    ElementNode(data) => data.closest(query)
    _ => Selection::new()
  }
}

///|
/// Run the selector registered under `name`, over this node's descendants.
pub fn Node::selector(
  self : Node,
  name : String,
  query : String,
) -> Selection raise Refused {
  match self {
    ElementNode(data) => data.selector(name, query)
    _ => raise UnknownSelector(name~)
  }
}

///|
/// Run a selector that was never registered, over this node's descendants.
pub fn Node::custom(self : Node, sel : &Selector) -> Selection raise Refused {
  match self {
    ElementNode(data) => data.custom(sel)
    _ => Selection::new()
  }
}

// The document's own surface. `Document::root` is a container, not an element
// in the document, so the verbs that act on one node among its siblings
// (`remove`, `replace_with`, `wrap`, `unwrap`, `parent`, `first`, `last`,
// `eq`, `length`) answer nothing a caller could mean here and are not
// forwarded. What is left is what a whole document can do: search it, read
// it, put top-level nodes in it, and empty it.

///|
/// Narrow with a CSS selector over the whole document. Descendant search from
/// the virtual root, so every element is a candidate.
pub fn Document::css(
  self : Document,
  query : String,
) -> Selection raise Refused {
  self.selection([ElementNode(self.root)]).css(query)
}

///|
/// The elements whose `id` attribute is `id` — `getElementById`, over the
/// whole document.
pub fn Document::by_id(self : Document, id : String) -> Selection {
  self.selection([ElementNode(self.root)]).by_id(id)
}

///|
/// The elements carrying the class `name`.
pub fn Document::by_class(self : Document, name : String) -> Selection {
  self.selection([ElementNode(self.root)]).by_class(name)
}

///|
/// The elements named `name`; `*` answers every element.
pub fn Document::by_tag(self : Document, name : String) -> Selection {
  self.selection([ElementNode(self.root)]).by_tag(name)
}

///|
/// The elements whose `name` attribute is `name`.
pub fn Document::by_name(self : Document, name : String) -> Selection {
  self.selection([ElementNode(self.root)]).by_name(name)
}

///|
/// Run the selector registered under `name`, built-in or the caller's own.
pub fn Document::selector(
  self : Document,
  name : String,
  query : String,
) -> Selection raise Refused {
  self.selection([ElementNode(self.root)]).selector(name, query)
}

///|
/// Run a selector that was never registered.
pub fn Document::custom(
  self : Document,
  sel : &Selector,
) -> Selection raise Refused {
  self.selection([ElementNode(self.root)]).custom(sel)
}

///|
/// The text of the whole document, concatenated.
pub fn Document::text(self : Document) -> String {
  self.selection([ElementNode(self.root)]).text()
}

///|
/// The whole document as markup, in the flavour it was read as.
pub fn Document::html(self : Document) -> String {
  self.selection([ElementNode(self.root)]).html()
}

///|
/// The document's top-level nodes — the doctype, comments and processing
/// instructions beside the document element, in document order.
pub fn Document::children(self : Document) -> Selection {
  self.selection([ElementNode(self.root)]).children()
}

///|
/// Every node in the document, in document order.
pub fn Document::descendants(self : Document) -> Selection {
  self.selection([ElementNode(self.root)]).descendants()
}

///|
/// Add a node at the end of the document: where a comment, a processing
/// instruction or a second document element would go. The usual use is a
/// doctype written before the root, which is what `prepend` is for.
pub fn Document::append(self : Document, node : Node) -> Unit {
  self.selection([ElementNode(self.root)]).append(node)
}

///|
/// Add a node before everything else in the document.
pub fn Document::prepend(self : Document, node : Node) -> Unit {
  self.selection([ElementNode(self.root)]).prepend(node)
}

///|
/// Empty the document: every top-level node goes, and the document is then
/// what a freshly created one is.
pub fn Document::clear(self : Document) -> Unit {
  self.selection([ElementNode(self.root)]).clear()
}

///|
/// Fuse adjacent text nodes everywhere in the document, which is what a
/// writer wants after editing several places.
pub fn Document::smooth(self : Document) -> Unit {
  self.selection([ElementNode(self.root)]).smooth()
}
