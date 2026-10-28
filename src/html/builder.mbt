// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The tree builder: the stack of open elements, the list of active formatting
// elements, the insertion modes and the foreign content rules. Everything the
// modes do to the tree goes through the helpers here, so the pointer repairs
// and the insertion point are written once.

///|
/// The three namespaces an HTML document can put an element in. A name in the
/// HTML namespace is the local name; the other two are `{uri}local`, the
/// spelling the rest of the library uses.
let html_namespace : String = ""

///|
let svg_namespace : String = "http://www.w3.org/2000/svg"

///|
let mathml_namespace : String = "http://www.w3.org/1998/Math/MathML"

///|
let xlink_namespace : String = "http://www.w3.org/1999/xlink"

///|
let xml_namespace : String = "http://www.w3.org/XML/1998/namespace"

///|
let xmlns_namespace : String = "http://www.w3.org/2000/xmlns/"

///|
/// The insertion modes of the standard, in its order.
priv enum Mode {
  Initial
  BeforeHtml
  BeforeHead
  InHead
  InHeadNoscript
  AfterHead
  InBody
  Text
  InTable
  InTableText
  InCaption
  InColumnGroup
  InTableBody
  InRow
  InCell
  InSelect
  InSelectInTable
  InTemplate
  AfterBody
  InFrameset
  AfterFrameset
  AfterAfterBody
  AfterAfterFrameset
}

///|
/// Which elements end a scope: the standard's families.
priv enum Scope {
  Default
  ListItem
  Button
  Table
  Select
}

///|
/// What the parser carries from one token to the next.
priv struct Builder {
  doc : @moonxml.Document
  stack : Array[@moonxml.Element]
  /// The active formatting elements; `None` is a marker.
  afe : Array[@moonxml.Element?]
  mut mode : Mode
  /// The mode a text element returns to when its end tag arrives.
  mut text_mode : Mode
  /// The template insertion modes, innermost last.
  templates : Array[Mode]
  mut head : @moonxml.Element?
  mut form : @moonxml.Element?
  repairs : @moonxml.Repairs
  mut quirks : Bool
  mut frameset_ok : Bool
  mut foster : Bool
  /// Set when the element just opened keeps a newline it did not write: a
  /// `<pre>` whose content begins with one loses it.
  mut skip_lf : Bool
  /// The mode to go back to when the characters a table was holding are done.
  mut prior_mode : Mode
  /// The characters "in table text" is holding.
  mut pending : StringBuilder
  mut pending_space : Bool
  /// The element a fragment is being read in, if one is.
  mut context : @moonxml.Element?
  /// The root of the document being built.
  root : @moonxml.Element
}

///|
fn Builder::new(doc : @moonxml.Document) -> Builder {
  {
    doc,
    stack: [],
    afe: [],
    mode: Initial,
    text_mode: InBody,
    templates: [],
    head: None,
    form: None,
    repairs: @moonxml.Repairs::new(),
    quirks: false,
    frameset_ok: true,
    foster: false,
    skip_lf: false,
    prior_mode: InBody,
    pending: StringBuilder(),
    pending_space: true,
    context: None,
    root: doc.root,
  }
}

///|
/// An element the parser invented rather than read.
fn note_implied(b : Builder) -> Unit {
  b.repairs.implied = b.repairs.implied + 1
}

///|
/// A token the parser threw away.
fn note_dropped(b : Builder) -> Unit {
  b.repairs.dropped = b.repairs.dropped + 1
}

///|
/// A node the parser moved, or a subtree it took apart and put back.
fn note_reparented(b : Builder) -> Unit {
  b.repairs.reparented = b.repairs.reparented + 1
}

// ------------------------------------------------------------- the stack

///|
fn current(b : Builder) -> @moonxml.Element {
  match b.stack.last() {
    Some(el) => el
    None => b.root
  }
}

///|
fn current_is(b : Builder, name : String) -> Bool {
  current(b).name == name
}

///|
fn push(b : Builder, element : @moonxml.Element) -> Unit {
  b.stack.push(element)
}

///|
fn pop(b : Builder) -> @moonxml.Element {
  match b.stack.pop() {
    Some(el) => el
    None => b.root
  }
}

///|
/// Whether a name sits anywhere on the stack.
fn has_on_stack(b : Builder, name : String) -> Bool {
  for each in b.stack {
    if each.name == name {
      return true
    }
  }
  false
}

///|
fn on_stack(b : Builder, element : @moonxml.Element) -> Bool {
  for each in b.stack {
    if physical_equal(each, element) {
      return true
    }
  }
  false
}

///|
fn index_on_stack(b : Builder, element : @moonxml.Element) -> Int32? {
  let mut k = 0
  while k < b.stack.length() {
    if physical_equal(b.stack[k], element) {
      return Some(k)
    }
    k = k + 1
  }
  None
}

///|
fn namespace_of_name(name : String) -> String {
  match @moonxml.namespace_of(name) {
    Some(uri) => uri
    None => html_namespace
  }
}

///|
/// Whether a name ends every scope. The integration points of foreign content
/// are on the list too: what is inside an SVG `<desc>` or a MathML `<mi>` is a
/// world of its own.
fn is_namespace_boundary(name : String) -> Bool {
  if name.has_prefix("{") {
    let local_name = @moonxml.local_of(name)
    if namespace_of_name(name) == mathml_namespace {
      return match local_name {
        "mi" | "mo" | "mn" | "ms" | "mtext" | "annotation-xml" => true
        _ => false
      }
    }
    if namespace_of_name(name) == svg_namespace {
      return match local_name {
        "foreignObject" | "desc" | "title" => true
        _ => false
      }
    }
    return false
  }
  match name {
    "applet"
    | "caption"
    | "html"
    | "table"
    | "td"
    | "th"
    | "marquee"
    | "object" => true
    // a template element is a boundary of its own
    "template" => true
    _ => false
  }
}

///|
fn in_scope_kind(name : String, scope : Scope) -> Bool {
  match scope {
    Default => is_namespace_boundary(name)
    ListItem => is_namespace_boundary(name) || name == "ol" || name == "ul"
    Button => is_namespace_boundary(name) || name == "button"
    Table => name == "html" || name == "table" || name == "template"
    Select =>
      is_namespace_boundary(name) && name != "optgroup" && name != "option"
  }
}

///|
fn has_in_scope(b : Builder, name : String, scope : Scope) -> Bool {
  let mut k = b.stack.length() - 1
  while k >= 0 {
    let here = b.stack[k].name
    if here == name {
      return true
    }
    if in_scope_kind(here, scope) {
      return false
    }
    k = k - 1
  }
  false
}

///|
fn has_any_in_scope(b : Builder, names : Array[String], scope : Scope) -> Bool {
  for name in names {
    if has_in_scope(b, name, scope) {
      return true
    }
  }
  false
}

///|
fn element_in_scope(
  b : Builder,
  element : @moonxml.Element,
  scope : Scope,
) -> Bool {
  let mut k = b.stack.length() - 1
  while k >= 0 {
    let here = b.stack[k]
    if physical_equal(here, element) {
      return true
    }
    if in_scope_kind(here.name, scope) {
      return false
    }
    k = k - 1
  }
  false
}

///|
/// Pop elements until one with this name has been popped.
fn pop_until_name(b : Builder, name : String) -> Unit {
  while b.stack.length() > 0 {
    let top = pop(b)
    if top.name == name {
      return
    }
  }
}

///|
fn pop_until_any(b : Builder, names : Array[String]) -> Unit {
  while b.stack.length() > 0 {
    let top = pop(b)
    for name in names {
      if top.name == name {
        return
      }
    }
  }
}

///|
fn generate_implied_end(b : Builder, except : String) -> Unit {
  while b.stack.length() > 0 {
    let here = current(b).name
    if here == except || !is_implied_end(here) {
      return
    }
    ignore(pop(b))
  }
}

///|
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
fn close_p(b : Builder) -> Unit {
  generate_implied_end(b, "p")
  pop_until_name(b, "p")
}

///|
fn clear_to_table(b : Builder) -> Unit {
  while b.stack.length() > 0 {
    let here = current(b).name
    if here == "table" || here == "template" || here == "html" {
      return
    }
    ignore(pop(b))
  }
}

///|
fn clear_to_table_body(b : Builder) -> Unit {
  while b.stack.length() > 0 {
    match current(b).name {
      "tbody" | "tfoot" | "thead" | "template" | "html" => return
      _ => ignore(pop(b))
    }
  }
}

///|
fn clear_to_row(b : Builder) -> Unit {
  while b.stack.length() > 0 {
    match current(b).name {
      "tr" | "template" | "html" => return
      _ => ignore(pop(b))
    }
  }
}

// ---------------------------------------------------- the insertion point

///|
/// Where the next node goes. Normally that is the current node; while a table
/// is being fostered, it is in front of the innermost table instead, which is
/// how a stray `<div>` outside a table ends up before it.
fn insertion_point(b : Builder) -> (@moonxml.Element, @moonxml.Element?) {
  insertion_point_at(b, current(b), foster=b.foster)
}

///|
/// The appropriate place for inserting a node, given the target it is inserted
/// into and whether the table rules apply. `foster` is what decides between
/// going inside a table and going in front of it: the table modes set it, and
/// the adoption agency asks for it when the node it is placing belongs above
/// the table the formatting element was found in.
fn insertion_point_at(
  b : Builder,
  target : @moonxml.Element,
  foster~ : Bool,
) -> (@moonxml.Element, @moonxml.Element?) {
  // A template's children are its contents: the element itself holds nothing.
  if target.name == "template" {
    match target.content() {
      Some(fragment) => return (fragment, None)
      None => ()
    }
  }
  if !foster {
    return (target, None)
  }
  if !is_table_part(target.name) {
    return (target, None)
  }
  let mut last_table = -1
  let mut last_template = -1
  let mut k = b.stack.length() - 1
  while k >= 0 {
    let here = b.stack[k].name
    if here == "table" && last_table < 0 {
      last_table = k
    }
    if here == "template" && last_template < 0 {
      last_template = k
    }
    k = k - 1
  }
  if last_template >= 0 && last_template > last_table {
    match b.stack[last_template].content() {
      Some(fragment) => return (fragment, None)
      None => ()
    }
  }
  if last_table < 0 {
    return (b.stack[0], None)
  }
  match b.stack[last_table].parent {
    Some(parent) => (parent, Some(b.stack[last_table]))
    None =>
      if last_table >= 1 {
        (b.stack[last_table - 1], None)
      } else {
        (b.stack[0], None)
      }
  }
}

///|
/// Append a node to an element, going into a template's contents when the
/// element is one: a template holds nothing itself.
fn append_into(parent : @moonxml.Element, node : @moonxml.Node) -> Unit {
  if parent.name == "template" {
    match parent.content() {
      Some(fragment) => {
        fragment.append(node)
        return
      }
      None => ()
    }
  }
  parent.append(node)
}

///|
fn place(
  parent : @moonxml.Element,
  before : @moonxml.Element?,
  node : @moonxml.Node,
) -> Unit {
  match before {
    Some(marker) =>
      match index_of(parent, marker) {
        Some(at) => parent.insert(at, node)
        None => append_into(parent, node)
      }
    None => append_into(parent, node)
  }
}

///|
fn index_of(parent : @moonxml.Element, element : @moonxml.Element) -> Int32? {
  let mut k = 0
  while k < parent.children.length() {
    if parent.children[k] is @moonxml.ElementNode(data) &&
      physical_equal(data, element) {
      return Some(k)
    }
    k = k + 1
  }
  None
}

///|
/// Insert an element, using the name it carries — a local name for HTML, a
/// `{uri}local` one for foreign content.
fn insert_element(
  b : Builder,
  name : String,
  attrs : Array[(String, String)],
) -> @moonxml.Element {
  let element = @moonxml.Element::new(name, attrs~)
  let (parent, before) = insertion_point(b)
  place(parent, before, @moonxml.ElementNode(element))
  element
}

///|
fn insert_element_open(
  b : Builder,
  name : String,
  attrs : Array[(String, String)],
) -> @moonxml.Element {
  let element = insert_element(b, name, attrs)
  push(b, element)
  element
}

///|
/// A `<template>` carries a content fragment of its own, created the moment the
/// element is.
fn insert_template(
  b : Builder,
  attrs : Array[(String, String)],
) -> @moonxml.Element {
  let element = insert_element(b, "template", attrs)
  let fragment = @moonxml.Element::new("#content")
  element.set_content(fragment)
  element
}

///|
fn insert_text(b : Builder, text : String) -> Unit {
  if text.is_empty() {
    return
  }
  let (parent, before) = insertion_point(b)
  // A tree has one node per run of text, so a run that arrives in pieces joins
  // the one before it — except at the top of a fostered table, where the run
  // before is the one in front of the table.
  let at = match before {
    Some(marker) =>
      match index_of(parent, marker) {
        Some(found) => found
        None => parent.children.length()
      }
    None => parent.children.length()
  }
  if at > 0 && parent.children[at - 1] is @moonxml.TextNode(existing) {
    parent.children[at - 1] = @moonxml.TextNode(existing + text)
  } else {
    parent.insert(at, @moonxml.TextNode(text))
  }
}

///|
fn insert_comment(b : Builder, text : String) -> Unit {
  let (parent, before) = insertion_point(b)
  place(parent, before, @moonxml.CommentNode(text))
}

///|
fn insert_comment_into(parent : @moonxml.Element, text : String) -> Unit {
  parent.append(@moonxml.CommentNode(text))
}

///|
/// The `html` element of the document being built, if it has one.
fn html_element(b : Builder) -> @moonxml.Element? {
  for node in b.root.children {
    if node is @moonxml.ElementNode(data) {
      if data.name == "html" {
        return Some(data)
      }
      return None
    }
  }
  None
}

///|
fn body_element(b : Builder) -> @moonxml.Element? {
  let html = match html_element(b) {
    Some(found) => found
    None => return None
  }
  for node in html.children {
    if node is @moonxml.ElementNode(data) &&
      (data.name == "body" || data.name == "frameset") {
      return Some(data)
    }
  }
  None
}

// -------------------------------------------- active formatting elements

///|
fn push_afe(b : Builder, element : @moonxml.Element) -> Unit {
  // Noah's Ark: three identical formatting elements are enough.
  let mut identical = 0
  let mut first_identical = -1
  let mut k = b.afe.length() - 1
  while k >= 0 {
    match b.afe[k] {
      None => break
      Some(have) =>
        if have.name == element.name && same_attrs(have, element) {
          identical = identical + 1
          // The earliest of them is the one Noah's Ark drops.
          first_identical = k
        }
    }
    k = k - 1
  }
  if identical >= 3 && first_identical >= 0 {
    ignore(b.afe.remove(first_identical))
  }
  b.afe.push(Some(element))
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
fn push_marker(b : Builder) -> Unit {
  b.afe.push(None)
}

///|
fn clear_afe_to_marker(b : Builder) -> Unit {
  while !b.afe.is_empty() {
    match b.afe.pop() {
      Some(None) => return
      _ => ()
    }
  }
}

///|
fn afe_index(b : Builder, element : @moonxml.Element) -> Int32? {
  let mut k = 0
  while k < b.afe.length() {
    match b.afe[k] {
      None => ()
      Some(have) => if physical_equal(have, element) { return Some(k) }
    }
    k = k + 1
  }
  None
}

///|
/// The last formatting element with this name, above the last marker.
fn find_afe(b : Builder, name : String) -> @moonxml.Element? {
  let mut k = b.afe.length() - 1
  while k >= 0 {
    match b.afe[k] {
      None => return None
      Some(have) => if have.name == name { return Some(have) }
    }
    k = k - 1
  }
  None
}

///|
/// Put back the formatting elements a block closed, so `<b>a<p>b</b>` keeps the
/// bold running across the paragraph.
fn reconstruct_afe(b : Builder) -> Unit {
  if b.afe.is_empty() {
    return
  }
  let mut idx = b.afe.length() - 1
  match b.afe[idx] {
    None => return
    Some(last) => if on_stack(b, last) { return }
  }
  while idx > 0 {
    match b.afe[idx - 1] {
      None => break
      Some(previous) => if on_stack(b, previous) { break }
    }
    idx = idx - 1
  }
  while idx < b.afe.length() {
    match b.afe[idx] {
      None => return
      Some(wanted) => {
        let fresh = insert_element_open(b, wanted.name, wanted.attrs.copy())
        b.afe[idx] = Some(fresh)
      }
    }
    idx = idx + 1
  }
}

// ------------------------------------------------------ foreign content

///|
/// The node the foreign content rules look at: the context element at the top
/// of a fragment, the current node otherwise.
fn adjusted_current(b : Builder) -> @moonxml.Element? {
  if b.stack.length() == 1 {
    match b.context {
      Some(context) => return Some(context)
      None => ()
    }
  }
  b.stack.last()
}

///|
/// Whether the tokenizer is reading foreign content, which is what decides
/// between a CDATA section and a bogus comment.
fn Builder::in_foreign(self : Builder) -> Bool {
  match adjusted_current(self) {
    Some(el) => el.name.has_prefix("{")
    None => false
  }
}

///|
fn namespace_of_element(el : @moonxml.Element) -> String {
  namespace_of_name(el.name)
}

///|
fn is_mathml_text_integration_point(el : @moonxml.Element) -> Bool {
  if namespace_of_element(el) != mathml_namespace {
    return false
  }
  match @moonxml.local_of(el.name) {
    "mi" | "mo" | "mn" | "ms" | "mtext" => true
    _ => false
  }
}

///|
fn is_html_integration_point(el : @moonxml.Element) -> Bool {
  let uri = namespace_of_element(el)
  if uri == svg_namespace {
    match @moonxml.local_of(el.name) {
      "foreignObject" | "desc" | "title" => return true
      _ => return false
    }
  }
  if uri == mathml_namespace && @moonxml.local_of(el.name) == "annotation-xml" {
    match el.attr("encoding") {
      Some(value) => {
        let lower = value.to_lower()
        return lower == "text/html" || lower == "application/xhtml+xml"
      }
      None => return false
    }
  }
  false
}

///|
/// The tags that break out of foreign content back into HTML: a stray `<div>`
/// inside an `<svg>` closes it, which is what a browser does.
fn is_breakout(name : String) -> Bool {
  match name {
    "b"
    | "big"
    | "blockquote"
    | "body"
    | "br"
    | "center"
    | "code"
    | "dd"
    | "div"
    | "dl"
    | "dt"
    | "em"
    | "embed"
    | "h1"
    | "h2"
    | "h3"
    | "h4"
    | "h5"
    | "h6"
    | "head"
    | "hr"
    | "i"
    | "img"
    | "li"
    | "listing"
    | "menu"
    | "meta"
    | "nobr"
    | "ol"
    | "p"
    | "pre"
    | "ruby"
    | "s"
    | "small"
    | "span"
    | "strong"
    | "strike"
    | "sub"
    | "sup"
    | "table"
    | "tt"
    | "u"
    | "ul"
    | "var" => true
    _ => false
  }
}

///|
/// The SVG element names that are spelled with a capital letter, and the
/// spelling the standard gives them.
fn adjust_svg_tag(name : String) -> String {
  match name {
    "altglyph" => "altGlyph"
    "altglyphdef" => "altGlyphDef"
    "altglyphitem" => "altGlyphItem"
    "animatecolor" => "animateColor"
    "animatemotion" => "animateMotion"
    "animatetransform" => "animateTransform"
    "clippath" => "clipPath"
    "feblend" => "feBlend"
    "fecolormatrix" => "feColorMatrix"
    "fecomponenttransfer" => "feComponentTransfer"
    "fecomposite" => "feComposite"
    "feconvolvematrix" => "feConvolveMatrix"
    "fediffuselighting" => "feDiffuseLighting"
    "fedisplacementmap" => "feDisplacementMap"
    "fedistantlight" => "feDistantLight"
    "fedropshadow" => "feDropShadow"
    "feflood" => "feFlood"
    "fefunca" => "feFuncA"
    "fefuncb" => "feFuncB"
    "fefuncg" => "feFuncG"
    "fefuncr" => "feFuncR"
    "fegaussianblur" => "feGaussianBlur"
    "feimage" => "feImage"
    "femerge" => "feMerge"
    "femergenode" => "feMergeNode"
    "femorphology" => "feMorphology"
    "feoffset" => "feOffset"
    "fepointlight" => "fePointLight"
    "fespecularlighting" => "feSpecularLighting"
    "fespotlight" => "feSpotLight"
    "fetile" => "feTile"
    "feturbulence" => "feTurbulence"
    "foreignobject" => "foreignObject"
    "glyphref" => "glyphRef"
    "lineargradient" => "linearGradient"
    "radialgradient" => "radialGradient"
    "textpath" => "textPath"
    _ => name
  }
}

///|
/// The SVG attribute names that are spelled with a capital letter.
fn adjust_svg_attr(name : String) -> String {
  match name {
    "attributename" => "attributeName"
    "attributetype" => "attributeType"
    "basefrequency" => "baseFrequency"
    "baseprofile" => "baseProfile"
    "calcmode" => "calcMode"
    "clippathunits" => "clipPathUnits"
    "diffuseconstant" => "diffuseConstant"
    "edgemode" => "edgeMode"
    "filterunits" => "filterUnits"
    "glyphref" => "glyphRef"
    "gradienttransform" => "gradientTransform"
    "gradientunits" => "gradientUnits"
    "kernelmatrix" => "kernelMatrix"
    "kernelunitlength" => "kernelUnitLength"
    "keypoints" => "keyPoints"
    "keysplines" => "keySplines"
    "keytimes" => "keyTimes"
    "lengthadjust" => "lengthAdjust"
    "limitingconeangle" => "limitingConeAngle"
    "markerheight" => "markerHeight"
    "markerunits" => "markerUnits"
    "markerwidth" => "markerWidth"
    "maskcontentunits" => "maskContentUnits"
    "maskunits" => "maskUnits"
    "numoctaves" => "numOctaves"
    "pathlength" => "pathLength"
    "patterncontentunits" => "patternContentUnits"
    "patterntransform" => "patternTransform"
    "patternunits" => "patternUnits"
    "pointsatx" => "pointsAtX"
    "pointsaty" => "pointsAtY"
    "pointsatz" => "pointsAtZ"
    "preservealpha" => "preserveAlpha"
    "preserveaspectratio" => "preserveAspectRatio"
    "primitiveunits" => "primitiveUnits"
    "refx" => "refX"
    "refy" => "refY"
    "repeatcount" => "repeatCount"
    "repeatdur" => "repeatDur"
    "requiredextensions" => "requiredExtensions"
    "requiredfeatures" => "requiredFeatures"
    "specularconstant" => "specularConstant"
    "specularexponent" => "specularExponent"
    "spreadmethod" => "spreadMethod"
    "startoffset" => "startOffset"
    "stddeviation" => "stdDeviation"
    "stitchtiles" => "stitchTiles"
    "surfacescale" => "surfaceScale"
    "systemlanguage" => "systemLanguage"
    "tablevalues" => "tableValues"
    "targetx" => "targetX"
    "targety" => "targetY"
    "textlength" => "textLength"
    "viewbox" => "viewBox"
    "viewtarget" => "viewTarget"
    "xchannelselector" => "xChannelSelector"
    "ychannelselector" => "yChannelSelector"
    "zoomandpan" => "zoomAndPan"
    _ => name
  }
}

///|
/// An attribute name in a foreign space: the two prefixes the standard gives
/// namespaces to become Clark names, the rest stay as they were written.
fn adjust_foreign_attr(name : String) -> String {
  let attr = match name {
    "xlink:actuate" => "actuate"
    "xlink:arcrole" => "arcrole"
    "xlink:href" => "href"
    "xlink:role" => "role"
    "xlink:show" => "show"
    "xlink:title" => "title"
    "xlink:type" => "type"
    _ => ""
  }
  if !attr.is_empty() {
    return "{" + xlink_namespace + "}" + attr
  }
  let xml_attr = match name {
    "xml:lang" => "lang"
    "xml:space" => "space"
    _ => ""
  }
  if !xml_attr.is_empty() {
    return "{" + xml_namespace + "}" + xml_attr
  }
  if name == "xmlns" {
    return "{" + xmlns_namespace + "}xmlns"
  }
  if name == "xmlns:xlink" {
    return "{" + xmlns_namespace + "}xlink"
  }
  name
}

///|
/// The attributes a foreign element's start tag carries, adjusted the way its
/// namespace says.
fn adjust_foreign_attrs(
  attrs : Array[(String, String)],
  space : String,
) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for pair in attrs {
    let name = if space == mathml_namespace && pair.0 == "definitionurl" {
      "definitionURL"
    } else if space == svg_namespace {
      adjust_svg_attr(pair.0)
    } else {
      pair.0
    }
    out.push((adjust_foreign_attr(name), pair.1))
  }
  out
}

///|
/// Insert an element in a foreign namespace, with its names adjusted.
fn insert_foreign(
  b : Builder,
  name : String,
  attrs : Array[(String, String)],
  space : String,
) -> @moonxml.Element {
  let local_name = if space == svg_namespace {
    adjust_svg_tag(name)
  } else {
    name
  }
  let clark = if space.is_empty() {
    local_name
  } else {
    "{" + space + "}" + local_name
  }
  insert_element(b, clark, adjust_foreign_attrs(attrs, space))
}

// ------------------------------------------------------------ small sets

///|
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
    | "search"
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
    | "xmp" => true
    _ => name.has_prefix("{")
  }
}

///|
fn is_heading(name : String) -> Bool {
  match name {
    "h1" | "h2" | "h3" | "h4" | "h5" | "h6" => true
    _ => false
  }
}

///|
fn is_table_part(name : String) -> Bool {
  match name {
    "table" | "tbody" | "tfoot" | "thead" | "tr" => true
    _ => false
  }
}
