/// The whole library's tree model and its one error family.
///
/// A document goes in, one mutable tree comes out. Nodes carry parent pointers
/// because a DOM is an object graph with identity, not a value; every editing
/// verb keeps those pointers true. This is the intentional difference from
/// `moonjson`, where `Json` is a value and `set` returns a new one.

/// The one thing a caller has to catch. Everything the library refuses to do
/// is reported through this type, so there is never a second error family.
pub(all) suberror Refused {
  /// Input that is not well-formed. `at` is a UTF-16 code-unit offset into the
  /// text that was read, the same unit `String::length` counts.
  Malformed(at~ : Int, why~ : String)
  /// A CSS selector or XPath expression that does not parse. `at` is an offset
  /// into the query string.
  BadQuery(at~ : Int, why~ : String)
  /// `selector(name, ..)` was called with a name nobody registered.
  UnknownSelector(name~ : String)
  /// A named gap: an unbound XPath variable, an external entity, and so on.
  Unsupported(what~ : String)
} derive(Eq, Debug)

/// How a document was read, and therefore how it writes itself back.
pub(all) enum Flavour {
  /// Parsed by `moonxml/xml`: strict, namespaced, byte-fidelity on round-trip.
  Xml
  /// Parsed by `moonxml/html`: WHATWG fault tolerance, normalised on write.
  Html
} derive(Eq, Debug)

/// A processing instruction: its target and the raw text after it, before `?>`.
pub(all) struct ProcessingInstruction {
  target : String
  data : String
} derive(Eq, Debug)

/// Build a processing instruction from its target and data.
pub fn ProcessingInstruction::new(target : String, data : String) -> ProcessingInstruction {
  { target, data }
}

/// One node of the tree.
pub(all) enum Node {
  /// An element: a name, ordered attributes, children, a parent, and how it was
  /// written (`<a/>` versus `<a></a>`).
  ElementNode(Element)
  /// Character data. Character and entity references were decoded on the way in.
  TextNode(String)
  /// A CDATA section, kept as its own kind so it round-trips exactly. XPath's
  /// `text()` still includes it.
  CDataNode(String)
  /// A comment, without its `<!--` and `-->`.
  CommentNode(String)
  /// A processing instruction.
  ProcessingInstructionNode(ProcessingInstruction)
  /// A doctype declaration, raw, minus `<!DOCTYPE` and `>`.
  DoctypeNode(String)
  /// A synthetic attribute node, produced by XPath's attribute axis (`@href`).
  /// It has no parent pointer; its string-value is the value.
  AttributeNode(String, String)
}

/// An element. Its fields are public: `el.children[0]`, `el.name`, `el.attrs`.
///
/// A mutable struct is a reference in MoonBit, so a child and the copy held in
/// its parent's `children` are the same object; parent pointers are real
/// pointers, not copies.
pub struct Element {
  /// The Clark-notation name, `{uri}local`, or a plain local name when the
  /// element is in no namespace.
  name : String
  /// Attributes in document order. Order is information, so this is an array of
  /// pairs, not a map.
  attrs : Array[(String, String)]
  /// Child nodes in document order.
  mut children : Array[Node]
  /// The parent element, or `None` for the document element and detached nodes.
  mut parent : Element?
  /// Whether the element was written self-closed. Drives `<a/>` versus
  /// `<a></a>` on write-back.
  mut closed : Bool
}

/// A parsed document: a virtual root, its flavour, the selector registry, and
/// the HTML parser's tally of repairs.
pub struct Document {
  /// The virtual container named `#document`, holding the top-level nodes.
  root : Element
  /// How the document was read; `dumps()` follows it.
  mut flavour : Flavour
  /// Built-in and caller-registered selectors, in registration order.
  selectors : Array[(String, &Selector)]
  /// What the HTML parser had to fix. Always empty for XML.
  mut repairs : Repairs
}

/// The repair tally an HTML parse leaves behind. XML never adds to it.
pub struct Repairs {
  /// Human-readable notes, one per repair, in the order they happened.
  mut items : Array[String]
}

/// An XPath expression's typed answer.
pub(all) enum XPathValue {
  /// A node-set, wrapped as a chain so it can keep narrowing.
  Nodes(Selection)
  /// A string result.
  Str(String)
  /// A number result.
  Num(Double)
  /// A boolean result.
  Flag(Bool)
}

// ---------------------------------------------------------------------------
// Element: construction and simple access
// ---------------------------------------------------------------------------

/// The character at index `i`. Converting the string per call is O(n), so this
/// is for one-off peeks; hot loops iterate with `for c in s` instead.
pub fn char_at(s : String, i : Int) -> Char {
  s.to_array()[i]
}

/// A fresh, empty element in no namespace, not self-closed.
pub fn Element::new(name : String) -> Element {
  { name, attrs: [], children: [], parent: None, closed: false }
}

/// A fresh element carrying `attrs` in the given order.
pub fn Element::with_attrs(name : String, attrs : Array[(String, String)]) -> Element {
  { name, attrs, children: [], parent: None, closed: false }
}

/// Record how the element was written: self-closed (`<a/>`) or not.
pub fn Element::set_closed(self : Element, b : Bool) -> Unit {
  self.closed = b
}

/// Replace the children array wholesale, repairing each child's parent pointer.
pub fn Element::set_children(self : Element, kids : Array[Node]) -> Unit {
  for c in kids {
    match c {
      ElementNode(e) => e.parent = Some(self)
      _ => ()
    }
  }
  self.children = kids
}

/// The element's local name: everything after the last `}` in a Clark name.
pub fn Element::local_name(self : Element) -> String {
  let n = self.name
  let mut last = -1
  let mut i = 0
  for c in n {
    if c == '}' {
      last = i
    }
    i = i + 1
  }
  if last >= 0 {
    n.substring(start=last + 1, end=n.length())
  } else {
    n
  }
}

/// The element's namespace URI, or `""` when it is in no namespace.
pub fn Element::namespace_uri(self : Element) -> String {
  let n = self.name
  if n.length() > 0 && char_at(n, 0) == '{' {
    let mut close = -1
    let mut i = 0
    for c in n {
      if c == '}' {
        close = i
        break
      }
      i = i + 1
    }
    if close > 0 {
      n.substring(start=1, end=close)
    } else {
      ""
    }
  } else {
    ""
  }
}

/// The value of attribute `name` (a plain local name or a Clark name), or `None`.
pub fn Element::attr(self : Element, name : String) -> String? {
  for pair in self.attrs {
    let (k, v) = pair
    if k == name {
      return Some(v)
    }
  }
  None
}

/// Set attribute `name` to `value`, replacing in place if it already exists,
/// otherwise appending. Order is preserved on replace.
pub fn Element::set_attr(self : Element, name : String, value : String) -> Unit {
  let mut i = 0
  while i < self.attrs.length() {
    let (k, _) = self.attrs[i]
    if k == name {
      self.attrs[i] = (name, value)
      return
    }
    i = i + 1
  }
  self.attrs.push((name, value))
}

/// Remove attribute `name` if present.
pub fn Element::remove_attr(self : Element, name : String) -> Unit {
  let mut i = 0
  while i < self.attrs.length() {
    let (k, _) = self.attrs[i]
    if k == name {
      self.attrs.remove(i) |> ignore
      return
    }
    i = i + 1
  }
}

/// Whether the element's `class` attribute contains `c` as a whole token.
pub fn Element::has_class(self : Element, c : String) -> Bool {
  match self.attr("class") {
    Some(v) => class_tokens(v).contains(c)
    None => false
  }
}

/// Add class `c` unless it is already present.
pub fn Element::add_class(self : Element, c : String) -> Unit {
  let cur = match self.attr("class") {
    Some(v) => v
    None => ""
  }
  if class_tokens(cur).contains(c) {
    return
  }
  if cur == "" {
    self.set_attr("class", c)
  } else {
    self.set_attr("class", cur + " " + c)
  }
}

/// Remove class `c` from the `class` attribute, dropping the attribute when the
/// list becomes empty.
pub fn Element::remove_class(self : Element, c : String) -> Unit {
  match self.attr("class") {
    None => ()
    Some(cur) => {
      let kept : Array[String] = []
      for tok in class_tokens(cur) {
        if tok != c {
          kept.push(tok)
        }
      }
      if kept.length() == 0 {
        self.remove_attr("class")
      } else {
        self.set_attr("class", join_with_space(kept))
      }
    }
  }
}

fn join_with_space(parts : Array[String]) -> String {
  let sb = StringBuilder()
  let mut first = true
  for p in parts {
    if first {
      first = false
    } else {
      sb.write_string(" ")
    }
    sb.write_string(p)
  }
  sb.to_string()
}

/// Split a `class` attribute into its whitespace-separated tokens.
pub fn class_tokens(s : String) -> Array[String] {
  split_ws(s)
}

/// Split `s` on runs of ASCII whitespace, dropping empty pieces.
pub fn split_ws(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut cur = ""
  for c in s {
    if is_ws_char(c) {
      if cur.length() > 0 {
        out.push(cur)
        cur = ""
      }
    } else {
      cur = cur + c.to_string()
    }
  }
  if cur.length() > 0 {
    out.push(cur)
  }
  out
}

fn is_ws_char(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\u{0C}'
}

// ---------------------------------------------------------------------------
// Node: kind tests and content
// ---------------------------------------------------------------------------

/// The element inside `self`, if it is one.
pub fn Node::as_element(self : Node) -> Element? {
  match self {
    ElementNode(e) => Some(e)
    _ => None
  }
}

/// Whether `self` is an element.
pub fn Node::is_element(self : Node) -> Bool {
  match self {
    ElementNode(_) => true
    _ => false
  }
}

/// Whether `self` is character data (text or CDATA).
pub fn Node::is_text(self : Node) -> Bool {
  match self {
    TextNode(_) | CDataNode(_) => true
    _ => false
  }
}

/// The child nodes of `self`: an element's children, or none for any other kind.
pub fn Node::node_children(self : Node) -> Array[Node] {
  match self {
    ElementNode(e) => e.children
    _ => []
  }
}

/// The concatenated text content of `self` — XPath's string-value for an
/// element, and simply the text for a text or CDATA node.
pub fn Node::text_content(self : Node) -> String {
  let sb = StringBuilder()
  node_text(self, sb)
  sb.to_string()
}

fn node_text(n : Node, sb : StringBuilder) -> Unit {
  match n {
    ElementNode(e) => {
      for c in e.children {
        node_text(c, sb)
      }
    }
    TextNode(s) => sb.write_string(s)
    CDataNode(s) => sb.write_string(s)
    AttributeNode(_, v) => sb.write_string(v)
    _ => ()
  }
}

/// The text content of the element: all descendant character data, concatenated.
pub fn Element::text(self : Element) -> String {
  let sb = StringBuilder()
  for c in self.children {
    node_text(c, sb)
  }
  sb.to_string()
}

/// All descendant nodes in document order (pre-order), excluding `self`.
pub fn Element::descendants(self : Element) -> Array[Node] {
  let out : Array[Node] = []
  collect_descendants(self, out)
  out
}

fn collect_descendants(e : Element, out : Array[Node]) -> Unit {
  for c in e.children {
    out.push(c)
    match c {
      ElementNode(child) => collect_descendants(child, out)
      _ => ()
    }
  }
}

/// All descendant elements in document order, excluding `self`.
pub fn Element::descendant_elements(self : Element) -> Array[Element] {
  let out : Array[Element] = []
  collect_descendant_elements(self, out)
  out
}

fn collect_descendant_elements(e : Element, out : Array[Element]) -> Unit {
  for c in e.children {
    match c {
      ElementNode(child) => {
        out.push(child)
        collect_descendant_elements(child, out)
      }
      _ => ()
    }
  }
}

/// The element's ancestor elements, nearest first.
pub fn Element::ancestors(self : Element) -> Array[Element] {
  let out : Array[Element] = []
  let mut cur = self.parent
  while true {
    match cur {
      Some(p) => {
        out.push(p)
        cur = p.parent
      }
      None => break
    }
  }
  out
}

/// The direct element children, skipping text, comments, and so on.
pub fn Element::children_elements(self : Element) -> Array[Element] {
  let out : Array[Element] = []
  for c in self.children {
    match c {
      ElementNode(e) => out.push(e)
      _ => ()
    }
  }
  out
}

/// The index of `self` among its parent's children, or `-1` when detached.
pub fn Element::index_in_parent(self : Element) -> Int {
  match self.parent {
    None => -1
    Some(p) => {
      let mut i = 0
      while i < p.children.length() {
        match p.children[i] {
          ElementNode(e) => if physical_equal(e, self) {
            return i
          }
          _ => ()
        }
        i = i + 1
      }
      -1
    }
  }
}

/// The nearest preceding sibling that is an element, if any.
pub fn Element::previous_element_sibling(self : Element) -> Element? {
  match self.parent {
    None => None
    Some(p) => {
      let idx = self.index_in_parent()
      let mut i = idx - 1
      while i >= 0 {
        match p.children[i] {
          ElementNode(e) => return Some(e)
          _ => ()
        }
        i = i - 1
      }
      None
    }
  }
}

/// The nearest following sibling that is an element, if any.
pub fn Element::next_element_sibling(self : Element) -> Element? {
  match self.parent {
    None => None
    Some(p) => {
      let idx = self.index_in_parent()
      let mut i = idx + 1
      while i < p.children.length() {
        match p.children[i] {
          ElementNode(e) => return Some(e)
          _ => ()
        }
        i = i + 1
      }
      None
    }
  }
}

/// Whether the element has no children at all (text included).
pub fn Element::is_empty(self : Element) -> Bool {
  self.children.length() == 0
}

// ---------------------------------------------------------------------------
// Document
// ---------------------------------------------------------------------------

/// A fresh document with the given flavour and the built-in selectors seeded.
pub fn Document::new(flavour : Flavour) -> Document {
  {
    root: Element::new("#document"),
    flavour,
    selectors: seed_selectors(),
    repairs: { items: [] },
  }
}

/// A document wrapping an already-built root element.
pub fn Document::from_root(root : Element, flavour : Flavour) -> Document {
  {
    root,
    flavour,
    selectors: seed_selectors(),
    repairs: { items: [] },
  }
}

/// The virtual `#document` container.
pub fn Document::root(self : Document) -> Element {
  self.root
}

/// The document element: the first element child of the virtual root.
pub fn Document::document_element(self : Document) -> Element? {
  for c in self.root.children {
    match c {
      ElementNode(e) => return Some(e)
      _ => ()
    }
  }
  None
}

/// How the document was read.
pub fn Document::flavour(self : Document) -> Flavour {
  self.flavour
}

/// The HTML parser's repair tally (empty for XML).
pub fn Document::repairs(self : Document) -> Repairs {
  self.repairs
}

/// A fresh, empty repair tally.
pub fn Repairs::new() -> Repairs {
  { items: [] }
}

/// How many repairs were recorded.
pub fn Repairs::count(self : Repairs) -> Int {
  self.items.length()
}

/// The repair notes, in the order they happened.
pub fn Repairs::log(self : Repairs) -> Array[String] {
  self.items.copy()
}

/// Record one repair note. The HTML parser calls this; callers read it back.
pub fn Repairs::note(self : Repairs, s : String) -> Unit {
  self.items.push(s)
}
