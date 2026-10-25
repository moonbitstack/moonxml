// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// ------------------------------------------------------------ small decisions

///|
fn is_table_like(name : String) -> Bool {
  name == "table" ||
  name == "tbody" ||
  name == "tfoot" ||
  name == "thead" ||
  name == "tr"
}

///|
fn is_void(name : String) -> Bool {
  match name {
    "area"
    | "base"
    | "basefont"
    | "bgsound"
    | "br"
    | "col"
    | "embed"
    | "frame"
    | "hr"
    | "img"
    | "input"
    | "keygen"
    | "link"
    | "meta"
    | "param"
    | "source"
    | "track"
    | "wbr" => true
    _ => false
  }
}

///|
/// The elements the spec calls special: a wall the "any other end tag" walk
/// stops at.
fn is_special(name : String) -> Bool {
  match name {
    "address"
    | "applet"
    | "area"
    | "article"
    | "aside"
    | "base"
    | "basefont"
    | "bgsound"
    | "blockquote"
    | "body"
    | "br"
    | "button"
    | "caption"
    | "center"
    | "col"
    | "colgroup"
    | "dd"
    | "details"
    | "dir"
    | "div"
    | "dl"
    | "dt"
    | "embed"
    | "fieldset"
    | "figcaption"
    | "figure"
    | "footer"
    | "form"
    | "frame"
    | "frameset"
    | "h1"
    | "h2"
    | "h3"
    | "h4"
    | "h5"
    | "h6"
    | "head"
    | "header"
    | "hgroup"
    | "hr"
    | "html"
    | "iframe"
    | "img"
    | "input"
    | "keygen"
    | "li"
    | "link"
    | "listing"
    | "main"
    | "marquee"
    | "menu"
    | "meta"
    | "nav"
    | "noembed"
    | "noframes"
    | "noscript"
    | "object"
    | "ol"
    | "p"
    | "param"
    | "plaintext"
    | "pre"
    | "script"
    | "section"
    | "select"
    | "source"
    | "style"
    | "summary"
    | "table"
    | "tbody"
    | "td"
    | "template"
    | "textarea"
    | "tfoot"
    | "th"
    | "thead"
    | "title"
    | "tr"
    | "track"
    | "ul"
    | "wbr"
    | "xmp"
    | "#document" => true
    _ => false
  }
}

///|
/// The elements an implied end tag closes.
fn is_implied_end(name : String) -> Bool {
  match name {
    "dd"
    | "dt"
    | "li"
    | "optgroup"
    | "option"
    | "p"
    | "rb"
    | "rp"
    | "rt"
    | "rtc" => true
    _ => false
  }
}

///|
/// The elements that end every scope: the outermost walls the spec names.
fn is_base_boundary(name : String) -> Bool {
  match name {
    "applet"
    | "caption"
    | "html"
    | "table"
    | "td"
    | "th"
    | "marquee"
    | "object"
    | "template"
    | "#document" => true
    _ => false
  }
}

///|
/// Whether `name` ends the given scope. The five families differ only in what
/// they add to the base wall, which is why `<td><p>` and `<table><p>` scope a
/// paragraph differently.
fn is_scoped_by(name : String, scope : Scope) -> Bool {
  match scope {
    Default => is_base_boundary(name)
    ListItem => is_base_boundary(name) || name == "ol" || name == "ul"
    Button => is_base_boundary(name) || name == "button"
    Table =>
      name == "html" ||
      name == "table" ||
      name == "template" ||
      name == "#document"
    Select => name == "optgroup" || name == "option"
  }
}

// ------------------------------------------------------------- stack plumbing

///|
fn current(builder : Builder) -> @moonxml.Element {
  match builder.stack.last() {
    Some(el) => el
    None => builder.doc.root
  }
}

///|
fn current_is(builder : Builder, name : String) -> Bool {
  current(builder).name == name
}

///|
fn push_stack(builder : Builder, element : @moonxml.Element) -> Unit {
  builder.stack.push(element)
}

///|
/// Pop the innermost element — never the document container, which is the
/// stack's floor.
fn pop_stack(builder : Builder) -> @moonxml.Element {
  let top = match builder.stack.pop() {
    Some(el) => el
    None => builder.doc.root
  }
  if builder.stack.is_empty() {
    builder.stack.push(builder.doc.root)
  }
  top
}

///|
fn on_stack(builder : Builder, element : @moonxml.Element) -> Bool {
  for each in builder.stack {
    if physical_equal(each, element) {
      return true
    }
  }
  false
}

///|
fn has_on_stack(builder : Builder, name : String) -> Bool {
  for each in builder.stack {
    if each.name == name {
      return true
    }
  }
  false
}

///|
/// The innermost element with the given name, or `None`.
fn find_on_stack(builder : Builder, name : String) -> @moonxml.Element? {
  let mut k = builder.stack.length() - 1
  while k >= 0 {
    if builder.stack[k].name == name {
      return Some(builder.stack[k])
    }
    k = k - 1
  }
  None
}

///|
/// Whether `name` has an instance in the given scope: the walk stops at the
/// scope's own boundary elements, which is what makes `<table><p>` a different
/// document from `<p><table>`.
fn has_in_scope(builder : Builder, name : String, scope : Scope) -> Bool {
  let mut k = builder.stack.length() - 1
  while k >= 0 {
    let here = builder.stack[k].name
    if here == name {
      return true
    }
    if is_scoped_by(here, scope) {
      return false
    }
    k = k - 1
  }
  false
}

///|
fn has_any_in_scope(
  builder : Builder,
  names : Array[String],
  scope : Scope,
) -> Bool {
  let mut k = builder.stack.length() - 1
  while k >= 0 {
    let here = builder.stack[k].name
    for name in names {
      if here == name {
        return true
      }
    }
    if is_scoped_by(here, scope) {
      return false
    }
    k = k - 1
  }
  false
}

///|
/// Pop elements until `name` has been popped; the spec's "pop elements from
/// the stack until an element has been popped".
fn pop_through(builder : Builder, name : String) -> Unit {
  // Nothing to close: popping anyway would empty the stack and put the rest of
  // the document beside the html element.
  if !has_on_stack(builder, name) {
    return
  }
  while builder.stack.length() > 1 {
    let top = pop_stack(builder)
    if top.name == name {
      return
    }
  }
}

///|
fn pop_until(builder : Builder, names : Array[String]) -> Unit {
  while builder.stack.length() > 1 {
    let top = pop_stack(builder)
    for name in names {
      if top.name == name {
        return
      }
    }
  }
}

///|
/// Close every element an implied end tag closes, innermost first.
fn generate_implied_end(builder : Builder) -> Unit {
  while builder.stack.length() > 1 && is_implied_end(current(builder).name) {
    ignore(pop_stack(builder))
  }
}

///|
/// Close the paragraphs an implied end tag would, without touching anything
/// else.
fn close_p(builder : Builder) -> Unit {
  generate_implied_except(builder, "p")
  pop_through(builder, "p")
}

///|
/// Pop back to a table context: everything above the innermost table, template
/// or the document container.
fn clear_to_table(builder : Builder) -> Unit {
  while builder.stack.length() > 1 {
    let here = current(builder).name
    if here == "table" || here == "template" || here == "#document" {
      return
    }
    ignore(pop_stack(builder))
  }
}

///|
fn clear_to_table_body(builder : Builder) -> Unit {
  while builder.stack.length() > 1 {
    let here = current(builder).name
    if here == "tbody" ||
      here == "tfoot" ||
      here == "thead" ||
      here == "template" ||
      here == "#document" {
      return
    }
    ignore(pop_stack(builder))
  }
}

///|
fn clear_to_row(builder : Builder) -> Unit {
  while builder.stack.length() > 1 {
    let here = current(builder).name
    if here == "tr" || here == "template" || here == "#document" {
      return
    }
    ignore(pop_stack(builder))
  }
}

// ------------------------------------------------------------ node insertions

///|
/// The place a node goes: the current element, or — while fostering — the
/// content in front of the innermost table. Fostering moves nothing unless the
/// current node really is a table part, which is why `<table><div>x<div>` nests
/// the second div inside the first.
fn insert_at(builder : Builder) -> @moonxml.Element? {
  if !builder.foster {
    return None
  }
  let here = current(builder)
  if !is_table_like(here.name) {
    return None
  }
  match find_on_stack(builder, "table") {
    Some(table) =>
      match table.parent {
        Some(_) => Some(table)
        None => None
      }
    None => None
  }
}

///|
fn insert_element(
  builder : Builder,
  name : String,
  attrs : Array[(String, String)],
) -> @moonxml.Element {
  let element = @moonxml.Element::new(name, attrs~)
  match insert_at(builder) {
    Some(table) => ignore(table.insert_before(@moonxml.ElementNode(element)))
    None => current(builder).append(@moonxml.ElementNode(element))
  }
  element
}

///|
/// Insert an element and leave it open.
fn insert_open(
  builder : Builder,
  name : String,
  attrs : Array[(String, String)],
) -> @moonxml.Element {
  let element = insert_element(builder, name, attrs)
  push_stack(builder, element)
  element
}

///|
fn index_of_child(
  parent : @moonxml.Element,
  element : @moonxml.Element,
) -> Int32? {
  let mut k = 0
  while k < parent.childrens.length() {
    if parent.childrens[k] is @moonxml.ElementNode(data) &&
      physical_equal(data, element) {
      return Some(k)
    }
    k = k + 1
  }
  None
}

///|
fn insert_text(builder : Builder, text : String) -> Unit {
  if text.is_empty() {
    return
  }
  match insert_at(builder) {
    Some(table) => {
      // Fostered text merges with the run just before the table, the same way
      // text in place does.
      let merged = match table.parent {
        Some(parent) =>
          match index_of_child(parent, table) {
            Some(at) =>
              if at > 0 &&
                parent.childrens[at - 1] is @moonxml.TextNode(existing) {
                parent.childrens[at - 1] = @moonxml.TextNode(existing + text)
                true
              } else {
                false
              }
            None => false
          }
        None => false
      }
      if !merged {
        ignore(table.insert_before(@moonxml.TextNode(text)))
      }
    }
    None => {
      // A tree has one node per run of text, so a run that arrives in pieces
      // joins the one before it.
      let parent = current(builder)
      let kids = parent.childrens
      let n = kids.length()
      if n > 0 && kids[n - 1] is @moonxml.TextNode(existing) {
        kids[n - 1] = @moonxml.TextNode(existing + text)
      } else {
        parent.append(@moonxml.TextNode(text))
      }
    }
  }
}

///|
fn insert_comment(builder : Builder, text : String) -> Unit {
  match insert_at(builder) {
    Some(table) => ignore(table.insert_before(@moonxml.CommentNode(text)))
    None => current(builder).append(@moonxml.CommentNode(text))
  }
}

///|
fn insert_comment_into(parent : @moonxml.Element, text : String) -> Unit {
  parent.append(@moonxml.CommentNode(text))
}

// ------------------------------------------------- active formatting elements

///|
/// Keep a formatting element for the reconstruction rule, collapsing the
/// earlier identical ones the way the spec's Noah's Ark clause does.
fn push_afe(builder : Builder, element : @moonxml.Element) -> Unit {
  let mut identical = 0
  let mut k = builder.afe.length() - 1
  while k >= 0 {
    match builder.afe[k] {
      None => break
      Some(have) =>
        if have.name == element.name && same_attrs(have, element) {
          identical = identical + 1
        }
    }
    k = k - 1
  }
  if identical >= 3 {
    let mut j = 0
    let mut dropped = false
    while j < builder.afe.length() && !dropped {
      match builder.afe[j] {
        None => ()
        Some(have) =>
          if have.name == element.name && same_attrs(have, element) {
            ignore(builder.afe.remove(j))
            dropped = true
          } else {
            j = j + 1
          }
      }
      if !dropped {
        j = j + 1
      }
    }
  }
  builder.afe.push(Some(element))
}

///|
fn same_attrs(a : @moonxml.Element, b : @moonxml.Element) -> Bool {
  if a.attrs.length() != b.attrs.length() {
    return false
  }
  for pair in a.attrs {
    let mut found = false
    for other in b.attrs {
      if pair.0 == other.0 && pair.1 == other.1 {
        found = true
      }
    }
    if !found {
      return false
    }
  }
  true
}

///|
fn clear_afe_to_marker(builder : Builder) -> Unit {
  while !builder.afe.is_empty() {
    match builder.afe.pop() {
      Some(None) => return
      _ => ()
    }
  }
}

///|
/// Find the innermost formatting element with this name above the last marker.
fn find_afe(builder : Builder, name : String) -> @moonxml.Element? {
  let mut k = builder.afe.length() - 1
  while k >= 0 {
    match builder.afe[k] {
      None => return None
      Some(have) => if have.name == name { return Some(have) }
    }
    k = k - 1
  }
  None
}

///|
fn afe_index(builder : Builder, element : @moonxml.Element) -> Int32? {
  let mut k = 0
  while k < builder.afe.length() {
    match builder.afe[k] {
      None => ()
      Some(have) => if physical_equal(have, element) { return Some(k) }
    }
    k = k + 1
  }
  None
}

///|
/// Put back the formatting elements a block closed, so `<b>a<p>b</b>` keeps the
/// bold running across the paragraph.
fn reconstruct_afe(builder : Builder) -> Unit {
  if builder.afe.is_empty() {
    return
  }
  let last = builder.afe[builder.afe.length() - 1]
  let mut entry = match last {
    None => return
    Some(el) => el
  }
  if on_stack(builder, entry) {
    return
  }
  let mut idx = builder.afe.length() - 1
  while idx > 0 {
    let previous = builder.afe[idx - 1]
    match previous {
      None => break
      Some(el) =>
        if on_stack(builder, el) {
          break
        } else {
          idx = idx - 1
          entry = el
        }
    }
  }
  while idx < builder.afe.length() {
    let wanted = match builder.afe[idx] {
      Some(el) => el
      None => return
    }
    let fresh = insert_open(builder, wanted.name, wanted.attrs.copy())
    builder.afe[idx] = Some(fresh)
    idx = idx + 1
  }
}

// ------------------------------------------------------------------ dispatch

///|
/// How many insertion modes one token may pass through before the parser gives
/// up. Each "reprocess the token" step changes the mode, so a well-formed
/// document needs a handful; the bound is here so that a document that does
/// not cannot loop for ever.
fn reprocess_bound() -> Int32 {
  32
}

///|
fn builder_chars(builder : Builder, text : String) -> Unit {
  let mut again = true
  let mut steps = 0
  while again && steps < reprocess_bound() {
    steps = steps + 1
    again = chars_in(builder, text)
  }
}

///|
fn builder_start(
  builder : Builder,
  name : String,
  attrs : Array[(String, String)],
  self_closing~ : Bool,
) -> Unit {
  let mut again = true
  let mut steps = 0
  while again && steps < reprocess_bound() {
    steps = steps + 1
    again = start_in(builder, name, attrs, self_closing~)
  }
}

///|
fn builder_end(builder : Builder, name : String) -> Unit {
  let mut again = true
  let mut steps = 0
  while again && steps < reprocess_bound() {
    steps = steps + 1
    again = end_in(builder, name)
  }
}

///|
fn builder_comment(builder : Builder, text : String) -> Unit {
  let mut again = true
  let mut steps = 0
  while again && steps < reprocess_bound() {
    steps = steps + 1
    again = comment_in(builder, text)
  }
}

///|
fn builder_doctype(builder : Builder, name : String, quirks~ : Bool) -> Unit {
  let mut again = true
  let mut steps = 0
  while again && steps < reprocess_bound() {
    steps = steps + 1
    again = doctype_in(builder, name, quirks~)
  }
}

///|
fn builder_eof(builder : Builder) -> Unit {
  if builder.mode is InTableText {
    flush_table_text(builder)
    builder.mode = InTable
  }
  // The document may end before it ever said where its content goes.
  match builder.mode {
    Initial | BeforeHtml => {
      builder.quirks = true
      imply_html(builder)
      imply_head(builder)
      close_head(builder)
      imply_body(builder)
    }
    BeforeHead => {
      imply_head(builder)
      close_head(builder)
      imply_body(builder)
    }
    InHead => {
      close_head(builder)
      imply_body(builder)
    }
    AfterHead => imply_body(builder)
    _ => ()
  }
  // Whatever is still open closes at the end of the document.
  while builder.stack.length() > 1 {
    ignore(pop_stack(builder))
    builder.repairs.closed_at_eof = builder.repairs.closed_at_eof + 1
  }
}
