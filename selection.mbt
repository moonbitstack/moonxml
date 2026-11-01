/// The chain: one mutable tree, narrowed by CSS, by XPath, and by any selector a
/// caller registers.
///
/// A `Selection` carries the nodes a query returned and the document they belong
/// to; every query method narrows it and returns a new one. An empty selection
/// stays empty — the empty result is an empty list, never a special value, so a
/// chain never has to branch.

/// A caller-implementable selector. `select` narrows `ctx` by `query`; a
/// selector that takes no text ignores it. `self` carries whatever state the
/// implementation wants.
/// A named selector, the extension point behind `Document::selector`.
///
/// The trait is open, like `@event.Sink`: a caller in another package registers
/// its own by implementing it.
pub(open) trait Selector {
  /// Narrow `ctx`. Most selectors search the descendants of its nodes; that is
  /// the convention the built-ins follow.
  select(Self, ctx : Selection, query : String) -> Selection raise Refused
}

/// A list of nodes plus the document they came from.
pub struct Selection {
  /// Where `selector(name, ..)` looks names up. `None` for a selection reached
  /// through a bare `Element`.
  priv doc : Document?
  /// The selected nodes, in document order.
  items : Array[Node]
}

/// A selection over `items`, with no document attached.
pub fn Selection::new(items : Array[Node]) -> Selection {
  { doc: None, items }
}

fn Selection::with_doc(doc : Document?, items : Array[Node]) -> Selection {
  { doc, items }
}

fn element_selection(el : Element) -> Selection {
  Selection::with_doc(None, [ElementNode(el)])
}

fn doc_selection(doc : Document) -> Selection {
  Selection::with_doc(Some(doc), [ElementNode(doc.root)])
}

// ---------------------------------------------------------------------------
// Selector implementations and the registry
// ---------------------------------------------------------------------------

/// The built-in CSS selector; backs `css(q)` and the registry name `"css"`.
pub struct CssSelector {}

impl Selector for CssSelector with select(self, ctx, query) {
  css_select(ctx, query)
}

/// The built-in XPath selector; backs `xpath(q)` and the registry name `"xpath"`.
pub struct XPathSelector {}

impl Selector for XPathSelector with select(self, ctx, query) {
  xpath_select(ctx, query)
}

/// Matches an `id` attribute; registry name `"id"`.
pub struct IdSelector {}

impl Selector for IdSelector with select(self, ctx, query) {
  ctx.by_id(query)
}

/// Matches a class token; registry name `"class"`.
pub struct ClassSelector {}

impl Selector for ClassSelector with select(self, ctx, query) {
  ctx.by_class(query)
}

/// Matches a tag name, `*` for any; registry name `"tag"`.
pub struct TagSelector {}

impl Selector for TagSelector with select(self, ctx, query) {
  ctx.by_tag(query)
}

/// Matches a `name` attribute; registry name `"name"`.
pub struct NameSelector {}

impl Selector for NameSelector with select(self, ctx, query) {
  ctx.by_name(query)
}

fn seed_selectors() -> Array[(String, &Selector)] {
  let out : Array[(String, &Selector)] = []
  let css : &Selector = CssSelector::{}
  let xpath : &Selector = XPathSelector::{}
  let id : &Selector = IdSelector::{}
  let klass : &Selector = ClassSelector::{}
  let tag : &Selector = TagSelector::{}
  let name : &Selector = NameSelector::{}
  out.push(("css", css))
  out.push(("xpath", xpath))
  out.push(("id", id))
  out.push(("class", klass))
  out.push(("tag", tag))
  out.push(("name", name))
  out
}

fn lookup_selector(reg : Array[(String, &Selector)], name : String) -> &Selector? {
  for pair in reg {
    let (n, s) = pair
    if n == name {
      return Some(s)
    }
  }
  None
}

fn builtin_lookup(name : String) -> &Selector? {
  if name == "css" {
    Some(CssSelector::{} as &Selector)
  } else if name == "xpath" {
    Some(XPathSelector::{} as &Selector)
  } else if name == "id" {
    Some(IdSelector::{} as &Selector)
  } else if name == "class" {
    Some(ClassSelector::{} as &Selector)
  } else if name == "tag" {
    Some(TagSelector::{} as &Selector)
  } else if name == "name" {
    Some(NameSelector::{} as &Selector)
  } else {
    None
  }
}

/// Register `sel` under `name`, replacing any existing entry (including a
/// built-in's). The built-in is still reachable through its own method: `css(q)`
/// calls the CSS engine directly and never consults the registry.
pub fn Document::register(self : Document, name : String, sel : &Selector) -> Unit {
  let mut i = 0
  while i < self.selectors.length() {
    let (n, _) = self.selectors[i]
    if n == name {
      self.selectors[i] = (name, sel)
      return
    }
    i = i + 1
  }
  self.selectors.push((name, sel))
}

/// Run the selector registered as `name` against the whole document.
pub fn Document::selector(self : Document, name : String, query : String) -> Selection raise Refused {
  match lookup_selector(self.selectors, name) {
    Some(s) => s.select(doc_selection(self), query)
    None => raise Refused::UnknownSelector(name=name)
  }
}

/// The names of the registered selectors, in registration order.
pub fn Document::selector_names(self : Document) -> Array[String] {
  let out : Array[String] = []
  for pair in self.selectors {
    let (n, _) = pair
    out.push(n)
  }
  out
}

// ---------------------------------------------------------------------------
// Node gathering and document order
// ---------------------------------------------------------------------------

/// All descendant elements of every element in `ctx`, in document order,
/// deduplicated by identity.
pub fn gather_elements(ctx : Selection) -> Array[Element] {
  let out : Array[Element] = []
  for item in ctx.items {
    match item {
      ElementNode(e) => {
        for d in e.descendant_elements() {
          if not(array_has_element(out, d)) {
            out.push(d)
          }
        }
      }
      _ => ()
    }
  }
  out
}

fn array_has_element(arr : Array[Element], e : Element) -> Bool {
  for a in arr {
    if physical_equal(a, e) {
      return true
    }
  }
  false
}

/// Deduplicate element nodes by identity while preserving order. Non-element
/// nodes pass through unchanged (they have no stable identity to collide on).
fn dedup_nodes(items : Array[Node]) -> Array[Node] {
  let out : Array[Node] = []
  for item in items {
    match item {
      ElementNode(e) => if not(array_has_node_element(out, e)) {
        out.push(item)
      }
      _ => out.push(item)
    }
  }
  out
}

fn array_has_node_element(arr : Array[Node], e : Element) -> Bool {
  for a in arr {
    match a {
      ElementNode(x) => if physical_equal(x, e) {
        return true
      }
      _ => ()
    }
  }
  false
}

/// Whether `el` matches `query` on its own, used by `closest`.
pub fn matches_one(el : Element, query : String) -> Bool raise Refused {
  css_matches_one(el, query)
}

// ---------------------------------------------------------------------------
// Query methods
// ---------------------------------------------------------------------------

/// Narrow by a Selectors expression.
pub fn Selection::css(self : Selection, query : String) -> Selection raise Refused {
  css_select(self, query)
}

/// Narrow by an XPath 1.0 expression. A non-node-set answer becomes its XPath
/// string value, wrapped as one text node, so the chain never breaks.
pub fn Selection::xpath(self : Selection, query : String) -> Selection raise Refused {
  xpath_select(self, query)
}

/// The typed answer of an XPath expression: nodes, string, number or boolean.
pub fn Selection::xpath_value(self : Selection, query : String) -> XPathValue raise Refused {
  xpath_value_of(self, query)
}

/// Run the selector registered under `name`, where it lives (this selection's
/// document) or a built-in.
pub fn Selection::selector(self : Selection, name : String, query : String) -> Selection raise Refused {
  let s = resolve_selector(self, name)
  s.select(self, query)
}

fn resolve_selector(sel : Selection, name : String) -> &Selector raise Refused {
  match sel.doc {
    Some(d) => match lookup_selector(d.selectors, name) {
      Some(s) => s
      None => raise Refused::UnknownSelector(name=name)
    }
    None => match builtin_lookup(name) {
      Some(s) => s
      None => raise Refused::UnknownSelector(name=name)
    }
  }
}

/// Run a selector that was never registered.
pub fn Selection::custom(self : Selection, sel : &Selector) -> Selection raise Refused {
  sel.select(self, "")
}

/// Descendants with the given `id`.
pub fn Selection::by_id(self : Selection, v : String) -> Selection {
  let out : Array[Node] = []
  for e in gather_elements(self) {
    if e.attr("id") == Some(v) {
      out.push(ElementNode(e))
    }
  }
  Selection::with_doc(self.doc, dedup_nodes(out))
}

/// Descendants carrying class token `v`.
pub fn Selection::by_class(self : Selection, v : String) -> Selection {
  let out : Array[Node] = []
  for e in gather_elements(self) {
    if e.has_class(v) {
      out.push(ElementNode(e))
    }
  }
  Selection::with_doc(self.doc, dedup_nodes(out))
}

/// Descendants whose tag name matches `v` (local name, or `*` for any).
pub fn Selection::by_tag(self : Selection, v : String) -> Selection {
  let out : Array[Node] = []
  for e in gather_elements(self) {
    if v == "*" || name_matches(e, v) {
      out.push(ElementNode(e))
    }
  }
  Selection::with_doc(self.doc, dedup_nodes(out))
}

/// Descendants with the given `name` attribute.
pub fn Selection::by_name(self : Selection, v : String) -> Selection {
  let out : Array[Node] = []
  for e in gather_elements(self) {
    if e.attr("name") == Some(v) {
      out.push(ElementNode(e))
    }
  }
  Selection::with_doc(self.doc, dedup_nodes(out))
}

/// Keep the items for which `f` returns true.
pub fn Selection::filter(self : Selection, f : (Node) -> Bool) -> Selection {
  let out : Array[Node] = []
  for item in self.items {
    if f(item) {
      out.push(item)
    }
  }
  Selection::with_doc(self.doc, out)
}

/// For each selected element, the nearest ancestor-or-self matching `query`.
pub fn Selection::closest(self : Selection, query : String) -> Selection raise Refused {
  let out : Array[Node] = []
  for item in self.items {
    match item {
      ElementNode(e) => {
        let mut cur : Element? = Some(e)
        while true {
          match cur {
            None => break
            Some(c) => {
              if css_matches_one(c, query) {
                out.push(ElementNode(c))
                break
              }
              cur = c.parent
            }
          }
        }
      }
      _ => ()
    }
  }
  Selection::with_doc(self.doc, dedup_nodes(out))
}

// ---------------------------------------------------------------------------
// Traversal
// ---------------------------------------------------------------------------

/// The first selected node, or an empty selection.
pub fn Selection::first(self : Selection) -> Selection {
  if self.items.length() > 0 {
    Selection::with_doc(self.doc, [self.items[0]])
  } else {
    Selection::with_doc(self.doc, [])
  }
}

/// The last selected node, or an empty selection.
pub fn Selection::last(self : Selection) -> Selection {
  let n = self.items.length()
  if n > 0 {
    Selection::with_doc(self.doc, [self.items[n - 1]])
  } else {
    Selection::with_doc(self.doc, [])
  }
}

/// The node at index `i` (negative counts from the end), or an empty selection.
pub fn Selection::eq(self : Selection, i : Int) -> Selection {
  let n = self.items.length()
  let idx = if i < 0 { n + i } else { i }
  if idx >= 0 && idx < n {
    Selection::with_doc(self.doc, [self.items[idx]])
  } else {
    Selection::with_doc(self.doc, [])
  }
}

/// The direct element children of every selected element.
pub fn Selection::children(self : Selection) -> Selection {
  let out : Array[Node] = []
  for item in self.items {
    match item {
      ElementNode(e) => for c in e.children_elements() {
        out.push(ElementNode(c))
      }
      _ => ()
    }
  }
  Selection::with_doc(self.doc, dedup_nodes(out))
}

/// The unique parents of the selected elements.
pub fn Selection::parent(self : Selection) -> Selection {
  let out : Array[Node] = []
  for item in self.items {
    match item {
      ElementNode(e) => match e.parent {
        Some(p) => out.push(ElementNode(p))
        None => ()
      }
      _ => ()
    }
  }
  Selection::with_doc(self.doc, dedup_nodes(out))
}

/// All descendant nodes of every selected element, in document order.
pub fn Selection::descendants(self : Selection) -> Selection {
  let out : Array[Node] = []
  for item in self.items {
    match item {
      ElementNode(e) => for d in e.descendants() {
        out.push(d)
      }
      _ => ()
    }
  }
  Selection::with_doc(self.doc, dedup_nodes(out))
}

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

/// How many nodes are selected.
pub fn Selection::length(self : Selection) -> Int {
  self.items.length()
}

/// Whether nothing is selected.
pub fn Selection::is_empty(self : Selection) -> Bool {
  self.items.length() == 0
}

/// The concatenated text content of every selected node (jQuery's `text()`).
pub fn Selection::text(self : Selection) -> String {
  let sb = StringBuilder()
  for item in self.items {
    sb.write_string(item.text_content())
  }
  sb.to_string()
}

/// The first selected element's inner HTML, in the document's flavour; `""`
/// when nothing is selected.
pub fn Selection::html(self : Selection) -> String {
  let flav = match self.doc {
    Some(d) => d.flavour
    None => Flavour::Xml
  }
  for item in self.items {
    match item {
      ElementNode(e) => return inner_html_flavoured(e, flav)
      _ => ()
    }
  }
  ""
}

/// The first selected element's attribute `name`, if it has one.
pub fn Selection::attr(self : Selection, name : String) -> String? {
  for item in self.items {
    match item {
      ElementNode(e) => return e.attr(name)
      _ => ()
    }
  }
  None
}
