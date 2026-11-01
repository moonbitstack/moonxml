/// Insertion modes and the primitives every mode handler shares.
///
/// The parser is a state machine over tokens. The mode is an explicit variable
/// that the handlers set, never something inferred from the open-element stack;
/// that is what makes table parts, templates and cell boundaries behave the way
/// the specification says they do.
///
/// The mode graph, with the tag that moves the parser from one mode to another:
///
///   Initial --doctype--> BeforeHtml --html--> BeforeHead --head--> InHead
///   InHead --/head--> AfterHead --body--> InBody
///   InHead --noscript--> InHeadNoscript --/noscript--> InHead
///   AfterHead --frameset--> InFrameset --/frameset--> AfterFrameset
///   InBody --body--> AfterBody --/html--> AfterAfterBody
///   AfterFrameset --/html--> AfterAfterFrameset
///   InBody --script/style/textarea/title/xmp/iframe/noembed/noframes--> Text
///   Text --/tag--> the mode it came from (InBody, InHead, InTable)
///   InBody --table--> InTable
///   InTable --caption--> InCaption --/caption--> InTable
///   InTable --colgroup--> InColumnGroup --/colgroup--> InTable
///   InTable --tbody/thead/tfoot--> InTableBody --tr--> InRow --td/th--> InCell
///   InCell --/td,/th--> InRow --/tr--> InTableBody --/tbody..--> InTable
///   InTable --tr--> (InTableBody) --tr-->
///   InBody --select--> InSelect (or InSelectInTable inside a table part)
///   InHead/InBody/InTable --template--> InTemplate --/template--> InHead
///
/// The five table states are InTable, InTableBody, InRow, InCell and
/// InCaption, with InColumnGroup and InTableText alongside them; a template
/// carries its own stack of modes so that `</template>` restores the mode that
/// was current when the template was opened.

enum Mode {
  MInitial
  MBeforeHtml
  MBeforeHead
  MInHead
  MInHeadNoscript
  MAfterHead
  MInBody
  MText
  MInTable
  MInTableText
  MInCaption
  MInColumnGroup
  MInTableBody
  MInRow
  MInCell
  MInSelect
  MInSelectInTable
  MInTemplate
  MAfterBody
  MInFrameset
  MAfterFrameset
  MAfterAfterBody
  MAfterAfterFrameset
}

/// The name of a mode, for diagnostics and for the tests that assert on mode
/// transitions.
fn mode_name(m : Mode) -> String {
  match m {
    MInitial => "initial"
    MBeforeHtml => "before html"
    MBeforeHead => "before head"
    MInHead => "in head"
    MInHeadNoscript => "in head noscript"
    MAfterHead => "after head"
    MInBody => "in body"
    MText => "text"
    MInTable => "in table"
    MInTableText => "in table text"
    MInCaption => "in caption"
    MInColumnGroup => "in column group"
    MInTableBody => "in table body"
    MInRow => "in row"
    MInCell => "in cell"
    MInSelect => "in select"
    MInSelectInTable => "in select in table"
    MInTemplate => "in template"
    MAfterBody => "after body"
    MInFrameset => "in frameset"
    MAfterFrameset => "after frameset"
    MAfterAfterBody => "after after body"
    MAfterAfterFrameset => "after after frameset"
  }
}

/// Scope flavours. Every one of them stops at `html`, and the table one also
/// stops at `table`.
enum Scope {
  ScDefault
  ScList
  ScButton
  ScTable
  ScSelect
} derive(Eq)

// ---------------------------------------------------------------------------
// Stack and insertion primitives
// ---------------------------------------------------------------------------

fn H::depth(self : H) -> Int {
  self.stack.length()
}

/// The current node, or the document when the stack is empty.
fn H::cur(self : H) -> @moonxml.Element {
  let n = self.stack.length()
  if n == 0 {
    self.doc
  } else {
    self.stack[n - 1]
  }
}

/// The spec's "adjusted current node": in a fragment with nothing inserted yet
/// it is the context element, which is what decides foreign content.
fn H::adjusted(self : H) -> @moonxml.Element {
  if self.fragment && self.stack.length() == 1 {
    match self.context {
      Some(c) => return c
      None => ()
    }
  }
  self.cur()
}

fn H::adjusted_ns(self : H) -> String {
  ns_of(self.adjusted().name)
}

fn H::cur_local(self : H) -> String {
  local_of(self.cur().name).to_lower()
}

fn H::cur_ns(self : H) -> String {
  ns_of(self.cur().name)
}

/// Whether the adjusted current node is in a foreign namespace, which is what
/// lets the tokenizer accept a CDATA section.
fn H::adjusted_foreign(self : H) -> Bool {
  ns_of(self.cur().name) != ""
}

fn H::at_current(self : H, name : String) -> Bool {
  self.stack.length() > 0 && self.cur_local() == name
}

fn H::pop(self : H) -> Unit {
  // The document element always stays: nothing pops past it.
  if self.stack.length() > 1 {
    let _ = self.stack.pop()
  }
}

/// Pop the current node, returning it.
fn H::pop_el(self : H) -> @moonxml.Element? {
  self.stack.pop()
}

fn H::pop_until(self : H, name : String) -> Unit {
  while self.stack.length() > 1 {
    let l = self.cur_local()
    self.pop()
    if l == name {
      return
    }
  }
}

fn H::pop_until_any(self : H, names : Array[String]) -> Unit {
  while self.stack.length() > 1 {
    let l = self.cur_local()
    self.pop()
    for n in names {
      if l == n {
        return
      }
    }
  }
}

/// Pop through a particular element, inclusive.
fn H::pop_until_node(self : H, el : @moonxml.Element) -> Unit {
  while self.stack.length() > 0 {
    let top = self.cur()
    self.pop()
    if physical_equal(top, el) {
      return
    }
  }
}

fn H::pop_until_index(self : H, idx : Int) -> Unit {
  while self.stack.length() > idx {
    self.pop()
  }
}

/// Where a node goes: the current node, or — while foster parenting — the spot
/// just before the table. The index is `-1` for "append".
fn H::location(self : H) -> (@moonxml.Element, Int) {
  // Foster parenting only displaces content that would otherwise land inside a
  // table part; anything already outside the table stays where it is.
  if not(self.foster) || not(is_table_scope_tag(self.cur_local())) {
    return (self.cur(), -1)
  }
  let mut ti = -1
  let mut i = self.stack.length() - 1
  while i >= 0 {
    if local_of(self.stack[i].name).to_lower() == "table" {
      ti = i
      break
    }
    i = i - 1
  }
  if ti < 0 {
    // No table to foster before: the node still belongs beside the current one,
    // which is how template content collects stray table parts.
    let cur = self.cur()
    if cur.parent.is_some() {
      match cur.parent {
        Some(p) => return (p, -1)
        None => ()
      }
    }
    return (cur, -1)
  }
  let table = self.stack[ti]
  match table.parent {
    Some(p) => (p, table.index_in_parent())
    None => if ti > 0 { (self.stack[ti - 1], -1) } else { (self.doc, -1) }
  }
}

fn H::insert_node(self : H, node : @moonxml.Node) -> Unit {
  let (parent, idx) = self.location()
  if idx < 0 {
    parent.append(node)
  } else {
    parent.insert(idx, node)
  }
}

/// Insert character data, merging with an adjacent text node so the tree never
/// holds two text nodes side by side.
fn H::insert_text(self : H, s : String) -> Unit {
  if s.length() == 0 {
    return
  }
  let (parent, idx) = self.location()
  if idx < 0 {
    append_text_to(parent, s)
    return
  }
  if idx > 0 {
    match parent.children[idx - 1] {
      @moonxml.Node::TextNode(prev) => {
        parent.children[idx - 1] = @moonxml.Node::TextNode(prev + s)
        return
      }
      _ => ()
    }
  }
  parent.insert(idx, @moonxml.Node::TextNode(s))
}

fn H::insert_comment(self : H, s : String) -> Unit {
  let (parent, idx) = self.location()
  if idx < 0 {
    parent.append(@moonxml.Node::CommentNode(s))
  } else {
    parent.insert(idx, @moonxml.Node::CommentNode(s))
  }
}

/// Insert an HTML element and make it the current node.
fn H::insert_el(self : H, name : String, attrs : Array[(String, String)]) -> @moonxml.Element {
  let el = @moonxml.Element::with_attrs(name, attrs)
  self.insert_node(@moonxml.Node::ElementNode(el))
  self.stack.push(el)
  el
}

/// Insert an HTML element without pushing it (void elements).
fn H::insert_void(self : H, name : String, attrs : Array[(String, String)]) -> @moonxml.Element {
  let el = @moonxml.Element::with_attrs(name, attrs)
  self.insert_node(@moonxml.Node::ElementNode(el))
  el
}

/// Insert an element in a foreign namespace and make it current.
fn H::insert_foreign(
  self : H,
  ns : String,
  local : String,
  attrs : Array[(String, String)]
) -> @moonxml.Element {
  let el = @moonxml.Element::with_attrs("{" + ns + "}" + local, attrs)
  self.insert_node(@moonxml.Node::ElementNode(el))
  self.stack.push(el)
  el
}

fn H::pop_void(self : H) -> Unit {
  self.pop()
}

// ---------------------------------------------------------------------------
// Scope
// ---------------------------------------------------------------------------

fn is_scope_boundary(l : String, ns : String, kind : Scope) -> Bool {
  match kind {
    ScTable => l == "html" || l == "table" || l == "template"
    ScSelect => not(l == "optgroup" || l == "option")
    _ => {
      if l == "applet" || l == "caption" || l == "html" || l == "table" || l == "td" || l == "th" || l == "marquee" || l == "object" || l == "template" {
        return true
      }
      // MathML and SVG integration points also bound a scope.
      if ns != "" {
        if l == "mi" || l == "mo" || l == "mn" || l == "ms" || l == "mtext" || l == "annotation-xml" {
          return true
        }
        if l == "foreignobject" || l == "desc" || l == "title" {
          return true
        }
      }
      match kind {
        ScList => l == "ol" || l == "ul"
        ScButton => l == "button"
        _ => false
      }
    }
  }
}

fn H::has_in_scope(self : H, name : String, kind : Scope) -> Bool {
  let mut i = self.stack.length() - 1
  while i >= 0 {
    let node = self.stack[i]
    let l = local_of(node.name).to_lower()
    if l == name && (kind == ScSelect || ns_of(node.name) == "") {
      return true
    }
    if is_scope_boundary(l, ns_of(node.name), kind) {
      return false
    }
    i = i - 1
  }
  false
}

/// Whether a particular element is in scope, by identity.
fn H::el_in_scope(self : H, el : @moonxml.Element, kind : Scope) -> Bool {
  let mut i = self.stack.length() - 1
  while i >= 0 {
    let node = self.stack[i]
    let l = local_of(node.name).to_lower()
    if physical_equal(node, el) {
      return true
    }
    if is_scope_boundary(l, ns_of(node.name), kind) {
      return false
    }
    i = i - 1
  }
  false
}

/// Whether any element at all with this name is on the stack.
fn H::has_open(self : H, name : String) -> Bool {
  let mut i = 0
  while i < self.stack.length() {
    if local_of(self.stack[i].name).to_lower() == name {
      return true
    }
    i = i + 1
  }
  false
}

fn H::index_of(self : H, el : @moonxml.Element) -> Int {
  let mut i = 0
  while i < self.stack.length() {
    if physical_equal(self.stack[i], el) {
      return i
    }
    i = i + 1
  }
  -1
}

fn H::remove_from_stack(self : H, el : @moonxml.Element) -> Unit {
  let i = self.index_of(el)
  if i >= 0 {
    let _ = self.stack.remove(i)
  }
}

// ---------------------------------------------------------------------------
// Implied end tags
// ---------------------------------------------------------------------------

fn is_implied_end(l : String) -> Bool {
  l == "dd" || l == "dt" || l == "li" || l == "optgroup" || l == "option" || l == "p" || l == "rb" || l == "rp" || l == "rt" || l == "rtc"
}

/// Pop the elements whose end tag may be omitted. `except` names one that must
/// stay (the spec's "except for" argument).
fn H::generate_implied_end(self : H, except : String) -> Unit {
  while self.stack.length() > 0 {
    let l = self.cur_local()
    if is_implied_end(l) && l != except {
      self.pop()
    } else {
      return
    }
  }
}

fn H::generate_implied_end_thoroughly(self : H) -> Unit {
  while self.stack.length() > 0 {
    let l = self.cur_local()
    if is_implied_end(l) {
      self.pop()
    } else {
      return
    }
  }
}

/// Close an open `p` in button scope, if there is one.
fn H::close_p(self : H) -> Unit {
  if self.has_in_scope("p", ScButton) {
    self.generate_implied_end("p")
    self.pop_until("p")
  }
}

fn H::clear_back_to_table_context(self : H) -> Unit {
  while self.stack.length() > 0 {
    let l = self.cur_local()
    if l == "table" || l == "template" || l == "html" {
      return
    }
    self.pop()
  }
}

fn H::clear_back_to_table_body_context(self : H) -> Unit {
  while self.stack.length() > 0 {
    let l = self.cur_local()
    if l == "tbody" || l == "tfoot" || l == "thead" || l == "template" || l == "html" {
      return
    }
    self.pop()
  }
}

fn H::clear_back_to_row_context(self : H) -> Unit {
  while self.stack.length() > 0 {
    let l = self.cur_local()
    if l == "tr" || l == "template" || l == "html" {
      return
    }
    self.pop()
  }
}

// ---------------------------------------------------------------------------
// Active formatting elements
// ---------------------------------------------------------------------------

fn H::afe_push(self : H, el : @moonxml.Element) -> Unit {
  // Noah's Ark: at most three equal entries after the last marker.
  let equals : Array[Int] = []
  let mut i = self.afe.length() - 1
  let mut stop = false
  while i >= 0 && not(stop) {
    match self.afe[i] {
      AFMarker => stop = true
      AFElement(e) => if same_fmt(e, el) {
        equals.push(i)
      }
    }
    i = i - 1
  }
  if equals.length() >= 3 {
    let earliest = equals[equals.length() - 1]
    let _ = self.afe.remove(earliest)
  }
  self.afe.push(AFElement(el))
}

fn H::afe_marker(self : H) -> Unit {
  self.afe.push(AFMarker)
}

fn H::afe_clear_to_marker(self : H) -> Unit {
  while self.afe.length() > 0 {
    match self.afe.pop() {
      Some(AFMarker) => return
      _ => ()
    }
  }
}

fn H::afe_index(self : H, el : @moonxml.Element) -> Int {
  let mut i = 0
  for item in self.afe {
    match item {
      AFElement(e) => if physical_equal(e, el) {
        return i
      }
      AFMarker => ()
    }
    i = i + 1
  }
  -1
}

fn H::afe_remove(self : H, el : @moonxml.Element) -> Unit {
  let i = self.afe_index(el)
  if i >= 0 {
    let _ = self.afe.remove(i)
  }
}

fn H::afe_has(self : H, el : @moonxml.Element) -> Bool {
  self.afe_index(el) >= 0
}

/// The last formatting element with this name, stopping at the last marker.
fn H::afe_last_named(self : H, name : String) -> Int {
  let mut i = self.afe.length() - 1
  while i >= 0 {
    match self.afe[i] {
      AFMarker => return -1
      AFElement(e) => if local_of(e.name).to_lower() == name {
        return i
      }
    }
    i = i - 1
  }
  -1
}

/// Reopen the formatting elements that were closed, so their effect continues.
fn H::reconstruct(self : H) -> Unit {
  if self.afe.length() == 0 {
    return
  }
  match self.afe[self.afe.length() - 1] {
    AFMarker => return
    AFElement(e) => if self.index_of(e) >= 0 {
      return
    }
  }
  let mut start = self.afe.length() - 1
  let mut j = start
  let mut stop = false
  while j > 0 && not(stop) {
    match self.afe[j - 1] {
      AFMarker => stop = true
      AFElement(e) => if self.index_of(e) >= 0 {
        stop = true
      } else {
        start = j - 1
        j = j - 1
      }
    }
  }
  let mut k = start
  while k < self.afe.length() {
    match self.afe[k] {
      AFElement(e) => {
        // Insert through the normal path so foster parenting still applies.
        let c = clone_shallow(e)
        self.insert_node(@moonxml.Node::ElementNode(c))
        self.stack.push(c)
        self.afe[k] = AFElement(c)
      }
      AFMarker => ()
    }
    k = k + 1
  }
}

// ---------------------------------------------------------------------------
// Reset the insertion mode
// ---------------------------------------------------------------------------

/// The spec's "reset the insertion mode appropriately": walk the stack down
/// until an element names a mode.
fn H::reset_mode(self : H) -> Unit {
  let mut idx = self.stack.length() - 1
  if idx < 0 {
    self.mode = MInBody
    return
  }
  let mut last = false
  while true {
    if idx == 0 {
      if self.fragment {
        // A fragment's root stands in for the context element, which the spec
        // would have reached with `last` already true.
        self.mode = MInBody
        return
      }
      last = true
    }
    let node = self.stack[idx]
    let l = local_of(node.name).to_lower()
    let ns = ns_of(node.name)
    if l == "select" && ns == "" {
      let mut j = idx - 1
      let mut done = false
      while j >= 0 {
        let al = local_of(self.stack[j].name).to_lower()
        if al == "template" {
          done = true
          break
        }
        if al == "table" {
          self.mode = MInSelectInTable
          return
        }
        j = j - 1
      }
      let _ = done
      self.mode = MInSelect
      return
    }
    if (l == "td" || l == "th") && not(last) && ns == "" {
      self.mode = MInCell
      return
    }
    if l == "tr" && ns == "" {
      self.mode = MInRow
      return
    }
    if (l == "tbody" || l == "thead" || l == "tfoot") && ns == "" {
      self.mode = MInTableBody
      return
    }
    if l == "caption" && ns == "" {
      self.mode = MInCaption
      return
    }
    if l == "colgroup" && ns == "" {
      self.mode = MInColumnGroup
      return
    }
    if l == "table" && ns == "" {
      self.mode = MInTable
      return
    }
    if l == "template" && ns == "" {
      if self.template_modes.length() > 0 {
        self.mode = self.template_modes[self.template_modes.length() - 1]
      } else {
        self.mode = MInTemplate
      }
      return
    }
    if l == "head" && not(last) && ns == "" {
      self.mode = MInHead
      return
    }
    if l == "body" && ns == "" {
      self.mode = MInBody
      return
    }
    if l == "frameset" && ns == "" {
      self.mode = MInFrameset
      return
    }
    if l == "html" && ns == "" {
      if self.head.is_some() {
        self.mode = MAfterHead
      } else {
        self.mode = MBeforeHead
      }
      return
    }
    if last {
      self.mode = MInBody
      return
    }
    idx = idx - 1
    if idx < 0 {
      self.mode = MInBody
      return
    }
  }
}

/// The first `html` element: the document element.
fn H::html_element(self : H) -> @moonxml.Element? {
  let mut i = 0
  while i < self.stack.length() {
    let l = local_of(self.stack[i].name).to_lower()
    if l == "html" && ns_of(self.stack[i].name) == "" {
      return Some(self.stack[i])
    }
    i = i + 1
  }
  None
}

/// The insertion mode a fragment starts in: the spec's "reset the insertion
/// mode appropriately" with the context element as the starting node and no
/// ancestors, which makes the `last` guard send cells and head to "in body".
fn fragment_mode(ctx : @moonxml.Element) -> Mode {
  let l = local_of(ctx.name).to_lower()
  if ns_of(ctx.name) != "" {
    return MInBody
  }
  if l == "select" {
    return MInSelect
  }
  if l == "td" || l == "th" {
    return MInBody
  }
  if l == "tr" {
    return MInRow
  }
  if l == "tbody" || l == "thead" || l == "tfoot" {
    return MInTableBody
  }
  if l == "caption" {
    return MInCaption
  }
  if l == "colgroup" {
    return MInColumnGroup
  }
  if l == "table" {
    return MInTable
  }
  if l == "template" {
    return MInTemplate
  }
  if l == "frameset" {
    return MInFrameset
  }
  if l == "html" {
    return MBeforeHead
  }
  MInBody
}

/// Split a character token into its leading HTML whitespace and the rest, so a
/// mode can insert the whitespace where it belongs and reprocess the remainder.
fn split_lead_ws(s : String) -> (String, String) {
  let cs = s.to_array()
  let mut i = 0
  while i < cs.length() && @text.is_html_space(cs[i]) {
    i = i + 1
  }
  if i == 0 {
    ("", s)
  } else if i == cs.length() {
    (s, "")
  } else {
    (slice_of(cs, 0, i), slice_of(cs, i, cs.length()))
  }
}
