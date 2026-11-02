// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One node of the tree. Mixed content survives: text, CDATA, elements,
/// comments, processing instructions and the doctype are all nodes, in
/// document order — none of which fits in a JSON-shaped value, which is why
/// this is not moonjson.
pub(all) enum Node {
  ElementNode(Element)
  TextNode(String)
  CDataNode(String)
  CommentNode(String)
  ProcessingInstructionNode(ProcessingInstruction)
  DoctypeNode(String)
  AttributeNode(Attribute)
  NamespaceNode(Namespace)
}

///|
/// An attribute as a node of its own: XPath's attribute node. It is not a
/// child of its element — the element's attributes stay in `attrs`, which is
/// what the writer reads — but a query that asks for `@href` or for the
/// attribute axis answers these, so that `attribute::x/self::node()` has
/// something with an identity to answer.
pub(all) struct Attribute {
  owner : Element
  name : String
  value : String
}

///|
/// A namespace as a node of its own: XPath's namespace node, answered by the
/// `namespace` axis. `prefix` is `""` for the default namespace.
pub(all) struct Namespace {
  owner : Element
  prefix : String
  uri : String
}

///|
/// A processing instruction: `<?target data?>`, with `data` the raw text
/// between the target and the `?>`, so an instruction round-trips exactly.
pub(all) struct ProcessingInstruction {
  target : String
  data : String
}

///|
/// How a document was read, and therefore how it writes itself back.
pub(all) enum Flavour {
  Xml
  Html
} derive(Eq, Debug)

///|
pub extend Flavour with Eq::{equal, not_equal}

///|
pub extend Flavour with Debug::{to_repr}

///|
pub impl Show for Flavour with fn output(self, logger) {
  logger.write_string(
    match self {
      Xml => "xml"
      Html => "html"
    },
  )
}

///|
pub extend Flavour with Show::{output, to_string}

///|
/// An element: the `{uri}local` name — the James Clark spelling, chosen over
/// registered prefixes so a node reads the same whichever prefixes the
/// document declared — its attributes in document order, its children, its
/// parent, and how it was closed (`<a/>` versus `<a></a>`) for the writer.
pub struct Element {
  name : String
  attrs : Array[(String, String)]
  children : Array[Node]
  mut parent : Element?
  mut closed : Bool
  priv mut home : Document?
  priv mut content : Element?
}

///|
/// A document: the virtual root (named `#document`) holding the top-level
/// nodes, the flavour it was read as, the selector registry, and — for HTML —
/// the tally of what the parser repaired.
pub struct Document {
  root : Element
  priv selectors : Map[String, &Selector]
  priv mut flavour : Flavour
  priv mut repairs : Repairs
  priv mut nesting : Array[Element]
  priv mut unresolved : Array[String]
}

///|
/// A fresh document. A tree built by hand has no syntax it was read from, so
/// it writes back with XML's exact rules; ask for `flavour=Html` when the tree
/// came from HTML.
pub fn Document::new(flavour~ : Flavour = Xml) -> Document {
  let root = Element::new("#document")
  let doc : Document = {
    root,
    selectors: Map([]),
    flavour,
    repairs: Repairs::new(),
    nesting: [],
    unresolved: [],
  }
  root.home = Some(doc)
  doc.seed_selectors()
  doc
}

///|
/// The contents of a `<template>`: a fragment of its own, the way the DOM keeps
/// them, and `None` for every other element.
///
/// What sits in a template is inert — it is not a child of the element, so a
/// query does not reach it and `text()` does not read it, which is what a
/// browser does too. `set_content` is how a caller that builds a template by
/// hand gives it contents.
pub fn Element::content(self : Element) -> Element? {
  self.content
}

///|
/// Give a `<template>` a content fragment. A caller who builds one by hand
/// uses this; the parser does it on its own.
pub fn Element::set_content(self : Element, content : Element) -> Unit {
  content.parent = Some(self)
  self.content = Some(content)
}

///|
/// The document an element belongs to, or `None` when it is detached: the
/// registry a `selector(name, ..)` call consults lives on the document.
pub fn Element::document(self : Element) -> Document? {
  let mut top = self
  let mut climbing = true
  while climbing {
    match top.parent {
      Some(above) => top = above
      None => climbing = false
    }
  }
  top.home
}

///|
/// The document element — the root's first element child, `documentElement`
/// in the DOM, `getroot()` in lxml.
pub fn Document::document_element(self : Document) -> Element? {
  for child in self.root.children {
    if child is ElementNode(data) {
      return Some(data)
    }
  }
  None
}

///|
/// The flavour this document writes itself back in.
pub fn Document::flavour(self : Document) -> Flavour {
  self.flavour
}

///|
/// What the HTML parser repaired; a tree that was not parsed as HTML has an
/// empty tally.
pub fn Document::repairs(self : Document) -> Repairs {
  self.repairs
}

///|
/// Record what a parser repaired; the parsers call this when they are done.
pub fn Document::set_repairs(self : Document, repairs : Repairs) -> Unit {
  self.repairs = repairs
}

///|
/// The external entities the document named but the parser did not read, in
/// the order they were referenced, each name once.
///
/// The library does no I/O, so a document whose entities live in a file beside
/// it is read without them: XML 1.0 says a non-validating processor need not
/// read them, but must tell the application which ones it skipped. That is
/// this list. It is empty for a document that needed nothing from outside.
pub fn Document::unresolved(self : Document) -> Array[String] {
  self.unresolved
}

///|
/// Record the external entities a reader skipped; the XML parser calls this.
pub fn Document::set_unresolved(self : Document, names : Array[String]) -> Unit {
  self.unresolved = names
}

///|
/// A fresh element. The constructor claims the parentage of the children it
/// is given, so a tree built this way keeps its parent pointers true.
pub fn Element::new(
  name : String,
  children~ : Array[Node] = [],
  attrs~ : Array[(String, String)] = [],
  closed~ : Bool = false,
) -> Element {
  let element : Element = {
    name,
    attrs,
    children,
    parent: None,
    closed,
    home: None,
    content: None,
  }
  for child in element.children {
    if child is ElementNode(data) {
      ignore(detach(data))
      data.parent = Some(element)
    }
  }
  element
}

///|
/// An element's name, or `""` for a node that is not an element.
pub fn Node::name(self : Node) -> String {
  match self {
    ElementNode(data) => data.name
    _ => ""
  }
}

///|
/// Whether the node is an element.
pub fn Node::is_element(self : Node) -> Bool {
  self is ElementNode(_)
}

///|
/// Text, CDATA included: XPath's `text()` node test matches both.
pub fn Node::is_text(self : Node) -> Bool {
  self is TextNode(_) || self is CDataNode(_)
}

///|
/// The language an element declares: its `lang` attribute in HTML, `xml:lang`
/// in XML. A tree read from either may carry both spellings, so both are read.
pub fn Element::lang(self : Element) -> String? {
  for pair in self.attrs {
    if pair.0 == "lang" ||
      pair.0 == "xml:lang" ||
      pair.0 == "{http://www.w3.org/XML/1998/namespace}lang" {
      return Some(pair.1)
    }
  }
  None
}

///|
/// Whether an element's language is `wanted`, or a regional variety of it:
/// a document in `en-GB` answers `lang("en")` and `lang("en-gb")`.
pub fn Element::is_lang(self : Element, wanted : String) -> Bool {
  let mut current : Element? = Some(self)
  while current is Some(here) {
    match here.lang() {
      Some(have) => return language_prefix(have, wanted)
      None => ()
    }
    current = here.parent
  }
  false
}

///|
/// A language tag against a wanted one: equal, or the wanted one followed by a
/// region subtag, in either case.
fn language_prefix(have : String, wanted : String) -> Bool {
  let have_lower = ascii_fold(have)
  let wanted_lower = ascii_fold(wanted)
  if have_lower == wanted_lower {
    return true
  }
  have_lower.has_prefix(wanted_lower + "-")
}

///|
fn ascii_fold(text : String) -> String {
  let out = StringBuilder()
  for ch in text {
    if ch >= 'A' && ch <= 'Z' {
      out.write_char((ch.to_int() + 0x20).unsafe_to_char())
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// The children of a node that is an element; a node with no children
/// answers an empty list.
pub fn Node::children(self : Node) -> Array[Node] {
  match self {
    ElementNode(data) => data.children
    _ => []
  }
}

///|
/// A node's text content — the DOM's `textContent`: an element answers the
/// text of its descendants, a text, CDATA, comment or processing-instruction
/// node answers what it carries.
pub fn Node::text(self : Node) -> String {
  match self {
    TextNode(text) => text
    CDataNode(text) => text
    CommentNode(text) => text
    ProcessingInstructionNode(pi) => pi.data
    DoctypeNode(_) => ""
    AttributeNode(attr) => attr.value
    NamespaceNode(space) => space.uri
    ElementNode(_) => {
      let out = StringBuilder()
      fn walk(node : Node) -> Unit {
        match node {
          TextNode(text) => out.write_string(text)
          CDataNode(text) => out.write_string(text)
          ElementNode(data) =>
            for child in data.children {
              walk(child)
            }
          _ => ()
        }
      }
      walk(self)
      out.to_string()
    }
  }
}

///|
/// The text of this element and everything under it.
pub fn Element::text(self : Element) -> String {
  Node::text(ElementNode(self))
}

///|
/// The element children, in order: what a walk of the tree skips the text of.
pub fn Element::child_elements(self : Element) -> Array[Element] {
  let out : Array[Element] = []
  for child in self.children {
    if child is ElementNode(data) {
      out.push(data)
    }
  }
  out
}

///|
/// The position among the parent's children, counting every node; `-1` when
/// the element has no parent.
pub fn Element::index_in_parent(self : Element) -> Int32 {
  match self.parent {
    Some(parent) =>
      match index_of(parent, self) {
        Some(at) => at
        None => -1
      }
    None => -1
  }
}

///|
/// The element just before this one among its siblings, skipping text and the
/// other node kinds.
pub fn Element::previous_element_sibling(self : Element) -> Element? {
  match self.parent {
    Some(parent) => {
      let siblings = parent.child_elements()
      for k = 1; k < siblings.length(); k = k + 1 {
        if physical_equal(siblings[k], self) {
          return Some(siblings[k - 1])
        }
      }
      None
    }
    None => None
  }
}

///|
/// The element just after this one among its siblings, skipping text and the
/// other node kinds.
pub fn Element::next_element_sibling(self : Element) -> Element? {
  match self.parent {
    Some(parent) => {
      let siblings = parent.child_elements()
      for k = 0; k + 1 < siblings.length(); k = k + 1 {
        if physical_equal(siblings[k], self) {
          return Some(siblings[k + 1])
        }
      }
      None
    }
    None => None
  }
}

// The editing verbs, bs4's set. Each is the element's method — the tree is
// mutable with parent pointers, and a verb repairs the pointers it breaks. A
// node has one parent: placing one that already sits in a tree moves it
// there, the way the DOM and lxml both do it.

///|
/// Append a child node, claiming its parentage.
pub fn Element::append(self : Element, node : Node) -> Unit {
  self.insert(self.children.length(), node)
}

///|
/// Insert `node` as the first child.
pub fn Element::prepend(self : Element, node : Node) -> Unit {
  self.insert(0, node)
}

///|
/// Insert `node` at `at`; an index past either end clamps to it.
pub fn Element::insert(self : Element, at : Int32, node : Node) -> Unit {
  if node is ElementNode(data) {
    ignore(detach(data))
  }
  let n = self.children.length()
  let idx = if at < 0 { 0 } else if at > n { n } else { at }
  if node is ElementNode(data) {
    data.parent = Some(self)
  }
  self.children.insert(idx, node)
}

///|
/// Detach self from the parent, answering true when there was one. bs4's
/// `extract`; the collector owns the rest.
pub fn Element::remove(self : Element) -> Bool {
  match self.parent {
    Some(parent) =>
      if drop_child(parent, self) {
        self.parent = None
        true
      } else {
        false
      }
    None => false
  }
}

///|
/// Take self's place in the parent. bs4's `replace_with`; false when self
/// has no parent.
pub fn Element::replace_with(self : Element, node : Node) -> Bool {
  match self.parent {
    Some(parent) =>
      match index_of(parent, self) {
        Some(at) => {
          ignore(drop_child(parent, self))
          self.parent = None
          claim(parent, node)
          parent.children.insert(at, node)
          true
        }
        None => false
      }
    None => false
  }
}

///|
/// Insert `node` before self among its siblings.
pub fn Element::insert_before(self : Element, node : Node) -> Bool {
  match self.parent {
    Some(parent) =>
      match index_of(parent, self) {
        Some(at) => {
          parent.insert(at, node)
          true
        }
        None => false
      }
    None => false
  }
}

///|
/// Insert `node` after self among its siblings.
pub fn Element::insert_after(self : Element, node : Node) -> Bool {
  match self.parent {
    Some(parent) =>
      match index_of(parent, self) {
        Some(at) => {
          parent.insert(at + 1, node)
          true
        }
        None => false
      }
    None => false
  }
}

///|
/// Unwrap the element: its children move up to its place, the element itself
/// is dropped. bs4's `unwrap`; false when the element has no parent.
pub fn Element::unwrap(self : Element) -> Bool {
  match self.parent {
    Some(parent) =>
      match index_of(parent, self) {
        Some(at) => {
          let inner = self.children.copy()
          ignore(drop_child(parent, self))
          self.parent = None
          for k = 0; k < inner.length(); k = k + 1 {
            claim(parent, inner[k])
            parent.children.insert(at + k, inner[k])
          }
          self.children.clear()
          true
        }
        None => false
      }
    None => false
  }
}

///|
/// Wrap self in a fresh element with the given name, answering the wrapper.
/// `None` when self has no parent to be replaced in.
pub fn Element::wrap(self : Element, name : String) -> Element? {
  match self.parent {
    Some(parent) =>
      match index_of(parent, self) {
        Some(at) => {
          let wrapper = Element::new(name)
          ignore(drop_child(parent, self))
          wrapper.parent = Some(parent)
          wrapper.append(ElementNode(self))
          parent.children.insert(at, ElementNode(wrapper))
          Some(wrapper)
        }
        None => None
      }
    None => None
  }
}

///|
/// Drop every child, answering each of them to no parent: a node that is no
/// longer in a tree must not still name the tree it left.
pub fn Element::clear(self : Element) -> Unit {
  for child in self.children {
    if child is ElementNode(data) {
      data.parent = None
    }
  }
  self.children.clear()
}

///|
/// Replace the contents with one text node: the DOM's `textContent = …`, and
/// what an edit that rewrites a label wants.
pub fn Element::set_text(self : Element, text : String) -> Unit {
  self.clear()
  self.append(TextNode(text))
}

///|
/// Replace the children with these, in this order. Every node named is taken
/// out of wherever it sat, and every node the element held is let go, so the
/// parent pointers are true afterwards whichever side of the edit a node was
/// on.
pub fn Element::set_children(self : Element, children : Array[Node]) -> Unit {
  self.clear()
  for child in children {
    self.append(child)
  }
}

///|
/// Fuse adjacent text nodes. What a writer wants after edits, and what keeps
/// a tree that was cut and rebuilt from carrying confetti. CDATA is left
/// alone: it is a distinct kind so it can round-trip.
pub fn Element::smooth(self : Element) -> Unit {
  let mut k = 0
  while k + 1 < self.children.length() {
    let here = self.children[k]
    let next = self.children[k + 1]
    if here is TextNode(a) && next is TextNode(b) {
      self.children[k] = TextNode(a + b)
      ignore(self.children.remove(k + 1))
    } else {
      k = k + 1
    }
  }
  // A text node that carries nothing is not a node a writer needs: an edit that
  // cut a run down to nothing should leave the tree without it.
  let mut k = 0
  while k < self.children.length() {
    let empty = match self.children[k] {
      TextNode(text) => text.is_empty()
      _ => false
    }
    if empty {
      ignore(self.children.remove(k))
    } else {
      k = k + 1
    }
  }
  for child in self.children {
    if child is ElementNode(data) {
      data.smooth()
    }
  }
}

///|
/// A copy of this node and everything under it, belonging to no tree: editing
/// the copy leaves the original alone. An attribute or a namespace node answers
/// itself — it is not a tree of its own, it is a name on an element, and
/// copying the element copies it.
pub fn Node::clone_deep(self : Node) -> Node {
  match self {
    ElementNode(element) => ElementNode(clone_element(element))
    TextNode(text) => TextNode(text)
    CDataNode(text) => CDataNode(text)
    CommentNode(text) => CommentNode(text)
    ProcessingInstructionNode(pi) =>
      ProcessingInstructionNode({ target: pi.target, data: pi.data, })
    DoctypeNode(text) => DoctypeNode(text)
    other => other
  }
}

///|
/// The element copy: the same name, attributes, closed form and contents, with
/// every child copied.
fn clone_element(element : Element) -> Element {
  let copy = Element::new(
    element.name,
    attrs=element.attrs.copy(),
    closed=element.closed,
  )
  for child in element.children {
    copy.append(child.clone_deep())
  }
  // A template's contents are not its children, and they travel with it.
  match element.content() {
    Some(fragment) => {
      let inner = Element::new("#content")
      for child in fragment.children {
        inner.append(child.clone_deep())
      }
      copy.set_content(inner)
    }
    None => ()
  }
  copy
}

///|
/// The value of an attribute, or `None` when the element does not carry it.
pub fn Element::attr(self : Element, name : String) -> String? {
  for pair in self.attrs {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// Whether the element carries an attribute of this name.
pub fn Element::has_attr(self : Element, name : String) -> Bool {
  self.attr(name) is Some(_)
}

///|
/// Set or replace an attribute, keeping its place when it is already there.
pub fn Element::set_attr(self : Element, name : String, value : String) -> Unit {
  for k = 0; k < self.attrs.length(); k = k + 1 {
    if self.attrs[k].0 == name {
      self.attrs[k] = (name, value)
      return
    }
  }
  self.attrs.push((name, value))
}

///|
/// Drop an attribute; true when it was there.
pub fn Element::remove_attr(self : Element, name : String) -> Bool {
  for k = 0; k < self.attrs.length(); k = k + 1 {
    if self.attrs[k].0 == name {
      ignore(self.attrs.remove(k))
      return true
    }
  }
  false
}

///|
/// The class list: the `class` attribute split on whitespace, empty parts
/// dropped, as HTML says.
pub fn Element::classes(self : Element) -> Array[String] {
  let out : Array[String] = []
  match self.attr("class") {
    Some(list) =>
      for part in list.split(" ") {
        if !part.is_empty() {
          out.push(part.to_owned())
        }
      }
    None => ()
  }
  out
}

///|
/// Whether the element's class list names this class.
pub fn Element::has_class(self : Element, name : String) -> Bool {
  self.classes().contains(name)
}

///|
/// Add a class; an element that already carries it is untouched.
pub fn Element::add_class(self : Element, name : String) -> Unit {
  if self.has_class(name) {
    return
  }
  match self.attr("class") {
    Some(list) =>
      self.set_attr(
        "class",
        if list.is_empty() {
          name
        } else {
          list + " " + name
        },
      )
    None => self.set_attr("class", name)
  }
}

///|
/// Remove one class. The attribute stays, empty if that is what is left —
/// bs4's behaviour, so a caller is never surprised by a missing attribute.
pub fn Element::remove_class(self : Element, name : String) -> Unit {
  match self.attr("class") {
    Some(_) => {
      let kept = self.classes().filter(fn(part) { part != name })
      self.set_attr("class", kept.join(" "))
    }
    None => ()
  }
}

///|
/// Pre-order walk over the whole subtree. Iterative, so a deep tree cannot
/// outrun the stack.
pub fn Element::walk(self : Element, visit : (Node) -> Unit) -> Unit {
  let stack : Array[Node] = []
  for k = self.children.length() - 1; k >= 0; k = k - 1 {
    stack.push(self.children[k])
  }
  while !stack.is_empty() {
    let node = stack.pop().unwrap()
    visit(node)
    if node is ElementNode(data) {
      for k = data.children.length() - 1; k >= 0; k = k - 1 {
        stack.push(data.children[k])
      }
    }
  }
}

///|
/// Take `node` out of the tree it sits in, if it sits in one: a node has one
/// parent, so every verb that places a node calls this first.
fn detach(element : Element) -> Bool {
  element.remove()
}

///|
/// Point `node`'s parentage at `parent`.
fn claim(parent : Element, node : Node) -> Unit {
  if node is ElementNode(data) {
    data.parent = Some(parent)
  }
}

///|
/// Where `element` sits among `parent`'s children, by identity rather than by
/// value: two `<p>` with the same text are not the same node.
fn index_of(parent : Element, element : Element) -> Int32? {
  for k = 0; k < parent.children.length(); k = k + 1 {
    if parent.children[k] is ElementNode(data) && physical_equal(data, element) {
      return Some(k)
    }
  }
  None
}

///|
fn drop_child(parent : Element, element : Element) -> Bool {
  match index_of(parent, element) {
    Some(at) => {
      ignore(parent.children.remove(at))
      true
    }
    None => false
  }
}
