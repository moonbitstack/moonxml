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
///        .items[2].childrens[0].css("span").text()
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
pub fn Selection::childrens(self : Selection) -> Selection {
  let out : Array[Node] = []
  for node in self.items {
    if node is ElementNode(data) {
      for child in data.childrens {
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
/// The inner HTML of the first selected element, written in the flavor its
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
pub fn Element::html(self : Element) -> String {
  inner_html(self)
}

///|
fn inner_html(element : Element) -> String {
  let out = StringBuilder()
  let html = match element.document() {
    Some(doc) => doc.flavor is Html
    None => false
  }
  for child in element.childrens {
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
pub fn Selection::append(self : Selection, node : Node) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      data.append(node)
    }
  }
}

///|
pub fn Selection::prepend(self : Selection, node : Node) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      data.prepend(node)
    }
  }
}

///|
pub fn Selection::remove(self : Selection) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      ignore(data.remove())
    }
  }
}

///|
pub fn Selection::replace_with(self : Selection, node : Node) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      ignore(data.replace_with(node))
    }
  }
}

///|
pub fn Selection::unwrap(self : Selection) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      ignore(data.unwrap())
    }
  }
}

///|
pub fn Selection::wrap(self : Selection, name : String) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      ignore(data.wrap(name))
    }
  }
}

///|
pub fn Selection::clear(self : Selection) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      data.clear()
    }
  }
}

///|
pub fn Selection::set_text(self : Selection, text : String) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      data.clear()
      data.append(TextNode(text))
    }
  }
}

///|
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
pub fn Selection::remove_attr(self : Selection, name : String) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      ignore(data.remove_attr(name))
    }
  }
}

///|
pub fn Selection::add_class(self : Selection, name : String) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      data.add_class(name)
    }
  }
}

///|
pub fn Selection::remove_class(self : Selection, name : String) -> Unit {
  for item in self.items {
    if item is ElementNode(data) {
      data.remove_class(name)
    }
  }
}

///|
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
pub fn Element::css(self : Element, query : String) -> Selection raise Refused {
  selection_of(ElementNode(self)).css(query)
}

///|
pub fn Element::by_id(self : Element, id : String) -> Selection {
  selection_of(ElementNode(self)).by_id(id)
}

///|
pub fn Element::by_class(self : Element, name : String) -> Selection {
  selection_of(ElementNode(self)).by_class(name)
}

///|
pub fn Element::by_tag(self : Element, name : String) -> Selection {
  selection_of(ElementNode(self)).by_tag(name)
}

///|
pub fn Element::by_name(self : Element, name : String) -> Selection {
  selection_of(ElementNode(self)).by_name(name)
}

///|
pub fn Element::filter(self : Element, keep : (Node) -> Bool) -> Selection {
  selection_of(ElementNode(self)).filter(keep)
}

///|
pub fn Element::closest(
  self : Element,
  query : String,
) -> Selection raise Refused {
  selection_of(ElementNode(self)).closest(query)
}

///|
pub fn Element::selector(
  self : Element,
  name : String,
  query : String,
) -> Selection raise Refused {
  selection_of(ElementNode(self)).selector(name, query)
}

///|
pub fn Element::custom(
  self : Element,
  sel : &Selector,
) -> Selection raise Refused {
  selection_of(ElementNode(self)).custom(sel)
}

///|
pub fn Node::css(self : Node, query : String) -> Selection raise Refused {
  match self {
    ElementNode(data) => data.css(query)
    _ => Selection::new()
  }
}

///|
pub fn Node::by_id(self : Node, id : String) -> Selection {
  match self {
    ElementNode(data) => data.by_id(id)
    _ => Selection::new()
  }
}

///|
pub fn Node::by_class(self : Node, name : String) -> Selection {
  match self {
    ElementNode(data) => data.by_class(name)
    _ => Selection::new()
  }
}

///|
pub fn Node::by_tag(self : Node, name : String) -> Selection {
  match self {
    ElementNode(data) => data.by_tag(name)
    _ => Selection::new()
  }
}

///|
pub fn Node::by_name(self : Node, name : String) -> Selection {
  match self {
    ElementNode(data) => data.by_name(name)
    _ => Selection::new()
  }
}

///|
pub fn Node::filter(self : Node, keep : (Node) -> Bool) -> Selection {
  match self {
    ElementNode(data) => data.filter(keep)
    _ => Selection::new()
  }
}

///|
pub fn Node::closest(self : Node, query : String) -> Selection raise Refused {
  match self {
    ElementNode(data) => data.closest(query)
    _ => Selection::new()
  }
}

///|
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
pub fn Node::custom(self : Node, sel : &Selector) -> Selection raise Refused {
  match self {
    ElementNode(data) => data.custom(sel)
    _ => Selection::new()
  }
}

///|
pub fn Document::css(
  self : Document,
  query : String,
) -> Selection raise Refused {
  self.selection([ElementNode(self.root)]).css(query)
}

///|
pub fn Document::by_id(self : Document, id : String) -> Selection {
  self.selection([ElementNode(self.root)]).by_id(id)
}

///|
pub fn Document::by_class(self : Document, name : String) -> Selection {
  self.selection([ElementNode(self.root)]).by_class(name)
}

///|
pub fn Document::by_tag(self : Document, name : String) -> Selection {
  self.selection([ElementNode(self.root)]).by_tag(name)
}

///|
pub fn Document::by_name(self : Document, name : String) -> Selection {
  self.selection([ElementNode(self.root)]).by_name(name)
}

///|
pub fn Document::filter(self : Document, keep : (Node) -> Bool) -> Selection {
  self.selection([ElementNode(self.root)]).filter(keep)
}

///|
pub fn Document::closest(
  self : Document,
  query : String,
) -> Selection raise Refused {
  self.selection([ElementNode(self.root)]).closest(query)
}

///|
pub fn Document::selector(
  self : Document,
  name : String,
  query : String,
) -> Selection raise Refused {
  self.selection([ElementNode(self.root)]).selector(name, query)
}

///|
pub fn Document::custom(
  self : Document,
  sel : &Selector,
) -> Selection raise Refused {
  self.selection([ElementNode(self.root)]).custom(sel)
}

///|
pub fn Document::length(self : Document) -> Int32 {
  self.selection([ElementNode(self.root)]).length()
}

///|
pub fn Document::text(self : Document) -> String {
  self.selection([ElementNode(self.root)]).text()
}

///|
pub fn Document::html(self : Document) -> String {
  self.selection([ElementNode(self.root)]).html()
}

///|
pub fn Document::attr(self : Document, name : String) -> String? {
  self.selection([ElementNode(self.root)]).attr(name)
}

///|
pub fn Document::first(self : Document) -> Selection {
  self.selection([ElementNode(self.root)]).first()
}

///|
pub fn Document::last(self : Document) -> Selection {
  self.selection([ElementNode(self.root)]).last()
}

///|
pub fn Document::eq(self : Document, i : Int32) -> Selection {
  self.selection([ElementNode(self.root)]).eq(i)
}

///|
pub fn Document::childrens(self : Document) -> Selection {
  self.selection([ElementNode(self.root)]).childrens()
}

///|
pub fn Document::parent(self : Document) -> Selection {
  self.selection([ElementNode(self.root)]).parent()
}

///|
pub fn Document::descendants(self : Document) -> Selection {
  self.selection([ElementNode(self.root)]).descendants()
}

///|
pub fn Document::append(self : Document, node : Node) -> Unit {
  self.selection([ElementNode(self.root)]).append(node)
}

///|
pub fn Document::prepend(self : Document, node : Node) -> Unit {
  self.selection([ElementNode(self.root)]).prepend(node)
}

///|
pub fn Document::remove(self : Document) -> Unit {
  self.selection([ElementNode(self.root)]).remove()
}

///|
pub fn Document::replace_with(self : Document, node : Node) -> Unit {
  self.selection([ElementNode(self.root)]).replace_with(node)
}

///|
pub fn Document::unwrap(self : Document) -> Unit {
  self.selection([ElementNode(self.root)]).unwrap()
}

///|
pub fn Document::wrap(self : Document, name : String) -> Unit {
  self.selection([ElementNode(self.root)]).wrap(name)
}

///|
pub fn Document::clear(self : Document) -> Unit {
  self.selection([ElementNode(self.root)]).clear()
}

///|
pub fn Document::set_text(self : Document, text : String) -> Unit {
  self.selection([ElementNode(self.root)]).set_text(text)
}

///|
pub fn Document::set_attr(
  self : Document,
  name : String,
  value : String,
) -> Unit {
  self.selection([ElementNode(self.root)]).set_attr(name, value)
}

///|
pub fn Document::remove_attr(self : Document, name : String) -> Unit {
  self.selection([ElementNode(self.root)]).remove_attr(name)
}

///|
pub fn Document::add_class(self : Document, name : String) -> Unit {
  self.selection([ElementNode(self.root)]).add_class(name)
}

///|
pub fn Document::remove_class(self : Document, name : String) -> Unit {
  self.selection([ElementNode(self.root)]).remove_class(name)
}

///|
pub fn Document::smooth(self : Document) -> Unit {
  self.selection([ElementNode(self.root)]).smooth()
}
