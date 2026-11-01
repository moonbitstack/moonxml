/// HTML parsing: a WHATWG-style tokenizer and tree builder, tolerant by design.
///
/// The parser never raises on malformed markup; it repairs. It handles the
/// common insertion behaviours: void elements, optional end tags for `p`, `li`,
/// `dd`/`dt`, table cells and rows, `option`; raw-text `script`/`style` and
/// RCDATA `textarea`/`title`; comments and doctypes; the named and numeric
/// character references documents actually use; and foreign content (`svg`,
/// `math`, `foreignObject`). Full spec conformance (every html5lib insertion
/// mode) is not claimed; see the README's "not here yet".
///
/// Names in foreign content are Clark names (`{uri}local`); HTML names stay bare.

let svg_ns : String = "http://www.w3.org/2000/svg"
let math_ns : String = "http://www.w3.org/1998/Math/MathML"

struct H {
  s : Array[Char]
  n : Int
  mut pos : Int
  stack : Array[@moonxml.Element]
  afe : Array[AFEItem]
  mut repairs : Int
  /// Namespace of the fragment's context element, `""` for HTML or a document.
  mut frag_ns : String
  /// Set once `</body>` or `</html>` has been seen; later comments belong to
  /// the `html` element, not to the body.
  mut body_closed : Bool
  /// How many comments were appended after `</body>`.
  mut trailing_comments : Int
}

fn H::new(s : String) -> H {
  { s: s.to_array(), n: s.length(), pos: 0, stack: [], afe: [], repairs: 0, frag_ns: "", body_closed: false, trailing_comments: 0 }
}

fn H::at_end(self : H) -> Bool {
  self.pos >= self.n
}

fn H::peek(self : H) -> Char {
  if self.pos < self.n {
    self.s[self.pos]
  } else {
    '\u{0}'
  }
}

fn H::peek_at(self : H, k : Int) -> Char {
  let i = self.pos + k
  if i < self.n {
    self.s[i]
  } else {
    '\u{0}'
  }
}

fn H::starts_with(self : H, lit : String) -> Bool {
  let l = lit.to_array()
  if self.pos + l.length() > self.n {
    return false
  }
  let mut i = 0
  while i < l.length() {
    if self.s[self.pos + i] != l[i] {
      return false
    }
    i = i + 1
  }
  true
}

fn H::skip_ws_h(self : H) -> Unit {
  while not(self.at_end()) && @text.is_html_space(self.peek()) {
    self.pos = self.pos + 1
  }
}

fn H::starts_with_ci(self : H, lit : String) -> Bool {
  let l = lit.to_array()
  if self.pos + l.length() > self.n {
    return false
  }
  let mut i = 0
  while i < l.length() {
    if lower_char(self.s[self.pos + i]) != lower_char(l[i]) {
      return false
    }
    i = i + 1
  }
  true
}

fn lower_char(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    Char::from_int(Char::to_int(c) + 32)
  } else {
    c
  }
}

fn H::current(self : H) -> @moonxml.Element {
  self.stack[self.stack.length() - 1]
}

fn H::push(self : H, el : @moonxml.Element) -> Unit {
  self.stack.push(el)
}

fn H::pop(self : H) -> Unit {
  if self.stack.length() > 1 {
    let _ = self.stack.pop()
  }
}

fn local_of(name : String) -> String {
  if name.length() > 0 && name.to_array()[0] == '{' {
    let mut close = -1
    let mut i = 0
    for c in name {
      if c == '}' {
        close = i
        break
      }
      i = i + 1
    }
    if close >= 0 {
      name.substring(start=close + 1, end=name.length())
    } else {
      name
    }
  } else {
    name
  }
}

fn ns_of(name : String) -> String {
  if name.length() > 0 && name.to_array()[0] == '{' {
    let mut close = -1
    let mut i = 0
    for c in name {
      if c == '}' {
        close = i
        break
      }
      i = i + 1
    }
    if close > 0 {
      name.substring(start=1, end=close)
    } else {
      ""
    }
  } else {
    ""
  }
}

// ---------------------------------------------------------------------------
// Entities
// ---------------------------------------------------------------------------

fn is_ent_name_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

/// Windows-1252 replacements the spec applies to numeric references in the
/// C1 range.
fn map_c1(cp : Int) -> Int {
  match cp {
    0x80 => 0x20AC
    0x82 => 0x201A
    0x83 => 0x0192
    0x84 => 0x201E
    0x85 => 0x2026
    0x86 => 0x2020
    0x87 => 0x2021
    0x88 => 0x02C6
    0x89 => 0x2030
    0x8A => 0x0160
    0x8B => 0x2039
    0x8C => 0x0152
    0x8E => 0x017D
    0x91 => 0x2018
    0x92 => 0x2019
    0x93 => 0x201C
    0x94 => 0x201D
    0x95 => 0x2022
    0x96 => 0x2013
    0x97 => 0x2014
    0x98 => 0x02DC
    0x99 => 0x2122
    0x9A => 0x0161
    0x9B => 0x203A
    0x9C => 0x0153
    0x9E => 0x017E
    0x9F => 0x0178
    _ => cp
  }
}

/// Read a numeric character reference body starting after `&#`. Returns the
/// code point, the index after it, and whether anything was read.
fn read_char_ref(cs : Array[Char], j : Int, n : Int) -> (Int, Int, Bool) {
  let hex = j < n && (cs[j] == 'x' || cs[j] == 'X')
  let dstart = if hex { j + 1 } else { j }
  let mut k = dstart
  while k < n && (if hex { is_hex_digit_c(cs[k]) } else { is_dec_digit_c(cs[k]) }) {
    k = k + 1
  }
  if k == dstart {
    return (0, j, false)
  }
  let digits = slice_of(cs, dstart, k)
  // A reference with too many digits is out of range; the spec turns it into
  // U+FFFD rather than truncating it.
  let cp = if k - dstart > 8 {
    0x110000
  } else {
    if hex {
      @text.parse_hex(digits)
    } else {
      @text.parse_dec(digits)
    }
  }
  if cp < 0 {
    return (0, j, false)
  }
  let next = if k < n && cs[k] == ';' { k + 1 } else { k }
  (cp, next, true)
}

fn is_dec_digit_c(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

fn is_hex_digit_c(c : Char) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

/// Whether a legacy (semicolon-less) match may not be decoded here: in an
/// attribute value, the reference is left alone when followed by `=` or an
/// alphanumeric, so `?a=b&notc=1` keeps its query string.
fn legacy_blocked(next : Char?) -> Bool {
  match next {
    Some(c) => c == '=' || is_ent_name_char(c)
    None => false
  }
}

/// Decode character references. `in_attr` selects the attribute-value rule for
/// legacy references without a trailing semicolon.
fn decode_entities_mode(s : String, in_attr : Bool) -> String {
  let cs = s.to_array()
  let n = cs.length()
  let sb = StringBuilder()
  let mut i = 0
  while i < n {
    let c = cs[i]
    let mut done = false
    if c == '&' && i + 1 < n {
      if cs[i + 1] == '#' {
        let (cp, next, ok) = read_char_ref(cs, i + 2, n)
        if ok {
          let safe = if cp == 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
            0xFFFD
          } else {
            map_c1(cp)
          }
          sb.write_string(@text.code_point_to_string(safe))
          i = next
          done = true
        }
      }
      if not(done) {
        let mut j = i + 1
        while j < n && is_ent_name_char(cs[j]) && j - i <= 33 {
          j = j + 1
        }
        if j > i + 1 {
          let has_semi = j < n && cs[j] == ';'
          let mut hit = false
          if has_semi {
            match entity_value(slice_of(cs, i + 1, j + 1)) {
              Some(v) => {
                sb.write_string(v)
                i = j + 1
                hit = true
              }
              None => ()
            }
          }
          // Longest match over the bare name run.
          let mut e = j
          while e > i + 1 && not(hit) {
            match entity_value(slice_of(cs, i + 1, e)) {
              Some(v) => {
                let nextc = if e < n { Some(cs[e]) } else { None }
                if in_attr && legacy_blocked(nextc) {
                  // Leave the whole reference literal.
                  sb.write_char('&')
                  i = i + 1
                  hit = true
                } else {
                  sb.write_string(v)
                  i = e
                  hit = true
                }
              }
              None => ()
            }
            if not(hit) {
              e = e - 1
            }
          }
          if not(hit) {
            sb.write_char('&')
            i = i + 1
            done = true
          } else {
            done = true
          }
        }
      }
    }
    if not(done) {
      sb.write_char(c)
      i = i + 1
    }
  }
  sb.to_string()
}

fn decode_entities(s : String) -> String {
  decode_entities_mode(s, false)
}

fn decode_entities_attr(s : String) -> String {
  decode_entities_mode(s, true)
}

fn slice_of(cs : Array[Char], start : Int, end : Int) -> String {
  let sb = StringBuilder()
  let mut i = start
  while i < end {
    sb.write_char(cs[i])
    i = i + 1
  }
  sb.to_string()
}

// ---------------------------------------------------------------------------
// Tokenizer + tree construction
// ---------------------------------------------------------------------------

fn is_tag_name_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == ':' || c == '.'
}

fn is_void_tag(t : String) -> Bool {
  if t == "area" || t == "base" || t == "br" || t == "col" {
    return true
  }
  if t == "embed" || t == "hr" || t == "img" || t == "input" {
    return true
  }
  if t == "link" || t == "meta" || t == "param" || t == "source" {
    return true
  }
  t == "track" || t == "wbr"
}

fn is_rawtext_tag(t : String) -> Bool {
  t == "script" || t == "style" || t == "xmp" || t == "iframe" || t == "noembed" || t == "noframes"
}

fn is_rcdata_tag(t : String) -> Bool {
  t == "textarea" || t == "title"
}

fn svg_adjust_tag(t : String) -> String {
  match t {
    "foreignobject" => "foreignObject"
    "lineargradient" => "linearGradient"
    "radialgradient" => "radialGradient"
    "clippath" => "clipPath"
    "textpath" => "textPath"
    "altglyph" => "altGlyph"
    "altglyphdef" => "altGlyphDef"
    "altglyphitem" => "altGlyphItem"
    "animatecolor" => "animateColor"
    "animatemotion" => "animateMotion"
    "animatetransform" => "animateTransform"
    "feblend" => "feBlend"
    "fecolormatrix" => "feColorMatrix"
    "fecomponenttransfer" => "feComponentTransfer"
    "fecomposite" => "feComposite"
    "feconvolvematrix" => "feConvolveMatrix"
    "fediffuselighting" => "feDiffuseLighting"
    "fedisplacementmap" => "feDisplacementMap"
    "fedistantlight" => "feDistantLight"
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
    _ => t
  }
}

fn svg_adjust_attr(n : String) -> String {
  match n {
    "viewbox" => "viewBox"
    "preserveaspectratio" => "preserveAspectRatio"
    "gradientunits" => "gradientUnits"
    "gradienttransform" => "gradientTransform"
    "patternunits" => "patternUnits"
    "patterncontentunits" => "patternContentUnits"
    "patterntransform" => "patternTransform"
    "clippathunits" => "clipPathUnits"
    "markerwidth" => "markerWidth"
    "markerheight" => "markerHeight"
    "markerunits" => "markerUnits"
    "refx" => "refX"
    "refy" => "refY"
    "textlength" => "textLength"
    "lengthadjust" => "lengthAdjust"
    "spreadmethod" => "spreadMethod"
    "maskunits" => "maskUnits"
    "maskcontentunits" => "maskContentUnits"
    "filterunits" => "filterUnits"
    "primitiveunits" => "primitiveUnits"
    "attributename" => "attributeName"
    "attributetype" => "attributeType"
    "basefrequency" => "baseFrequency"
    "numoctaves" => "numOctaves"
    "stddeviation" => "stdDeviation"
    "stitchtiles" => "stitchTiles"
    "zoomandpan" => "zoomAndPan"
    _ => n
  }
}

/// MathML's one camelCase attribute.
fn adjust_attrs_math(attrs : Array[(String, String)]) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for pair in attrs {
    let (n, v) = pair
    if n == "definitionurl" {
      out.push(("definitionURL", v))
    } else {
      out.push((n, v))
    }
  }
  out
}

fn adjust_attrs_svg(attrs : Array[(String, String)]) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for pair in attrs {
    let (n, v) = pair
    out.push((svg_adjust_attr(n), v))
  }
  out
}

/// Start tags that close an open `p` element (WHATWG "in body", the block set).
fn closes_p(t : String) -> Bool {
  match t {
    "address" | "article" | "aside" | "blockquote" | "center" | "details" |
    "dialog" | "dir" | "div" | "dl" | "fieldset" | "figcaption" | "figure" |
    "footer" | "form" | "h1" | "h2" | "h3" | "h4" | "h5" | "h6" | "header" |
    "hgroup" | "hr" | "listing" | "main" | "menu" | "nav" | "ol" | "p" |
    "plaintext" | "pre" | "search" | "section" | "summary" | "table" | "ul" |
    "xmp" => true
    _ => false
  }
}

fn H::pop_while_current(self : H, tag : String) -> Unit {
  while self.stack.length() > 1 && local_of(self.current().name).to_lower() == tag {
    self.pop()
  }
}

/// Close the nearest open `p`, popping anything inside it. Formatting elements
/// are left in the active list, so the reconstruction step reopens them in the
/// new paragraph.
fn H::close_p(self : H) -> Unit {
  let mut i = self.stack.length() - 1
  let mut found = -1
  while i > 0 {
    let l = local_of(self.stack[i].name).to_lower()
    if l == "p" {
      found = i
      break
    }
    if l == "table" || l == "td" || l == "th" || l == "button" || l == "html" || l == "caption" || l == "template" {
      break
    }
    // A `p` outside a `svg`/`math` subtree is not in scope for HTML content
    // inside it.
    if ns_of(self.stack[i].name) != "" {
      break
    }
    i = i - 1
  }
  if found >= 0 {
    while self.stack.length() > found {
      self.pop()
    }
  }
}

fn H::auto_close(self : H, tag : String) -> Unit {
  if closes_p(tag) {
    self.close_p()
  }
  if tag == "li" {
    self.pop_implied([])
    self.pop_while_current("li")
  }
  if tag == "dt" || tag == "dd" {
    self.pop_implied([])
    self.pop_while_current("dt")
    self.pop_while_current("dd")
  }
  if tag == "option" {
    self.pop_while_current("option")
  }
  if tag == "tr" {
    self.pop_while_current("tr")
  }
  if tag == "td" || tag == "th" {
    self.pop_while_current("td")
    self.pop_while_current("th")
  }
  if tag == "thead" || tag == "tbody" || tag == "tfoot" {
    self.pop_while_in(["tr", "td", "th", "tbody", "thead", "tfoot"])
  }
  if tag == "caption" || tag == "colgroup" || tag == "col" || tag == "tbody" || tag == "thead" || tag == "tfoot" || tag == "tr" || tag == "td" || tag == "th" {
    self.pop_while_in(["caption"])
  }
  if tag == "tr" || tag == "tbody" || tag == "thead" || tag == "tfoot" {
    self.pop_while_in(["colgroup"])
  }
  if tag == "colgroup" || tag == "col" {
    self.pop_while_in(["colgroup"])
  }
  if tag == "button" {
    self.pop_while_current("button")
  }
  if tag == "rb" || tag == "rtc" {
    self.close_p()
    self.pop_while_in(["rb", "rt", "rp", "rtc"])
  }
  if tag == "rt" || tag == "rp" {
    self.close_p()
    self.pop_while_in(["rb", "rt", "rp"])
  }
}

fn H::pop_through_head(self : H) -> Unit {
  let mut i = self.stack.length() - 1
  let mut found = -1
  while i > 0 {
    if local_of(self.stack[i].name).to_lower() == "head" {
      found = i
      break
    }
    i = i - 1
  }
  if found >= 0 {
    while self.stack.length() > found {
      self.pop()
    }
  }
}

/// Insert a comment. After `</body>` it belongs to the `html` element.
fn H::push_comment(self : H, text : String) -> Unit {
  if self.body_closed {
    self.trailing_comments = self.trailing_comments + 1
    self.append_to_html(@moonxml.Node::CommentNode(text))
  } else {
    self.append_node(@moonxml.Node::CommentNode(text))
  }
}

/// Append a node to the `html` element, or to the current node when no `html`
/// element is open.
fn H::append_to_html(self : H, node : @moonxml.Node) -> Unit {
  let mut i = self.stack.length() - 1
  while i > 0 {
    if local_of(self.stack[i].name).to_lower() == "html" {
      self.stack[i].append(node)
      return
    }
    i = i - 1
  }
  self.append_node(node)
}

fn find_child_named(parent : @moonxml.Element, name : String) -> @moonxml.Element? {
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

/// Add attributes that `el` does not already carry.
fn H::merge_attrs_onto(self : H, tag : String, attrs : Array[(String, String)]) -> Unit {
  let mut i = self.stack.length() - 1
  while i > 0 {
    if local_of(self.stack[i].name).to_lower() == tag {
      let el = self.stack[i]
      for pair in attrs {
        let (k, v) = pair
        if el.attr(k).is_none() {
          el.set_attr(k, v)
        }
      }
      return
    }
    i = i - 1
  }
}

/// Whether a `p` is open in button scope.
fn H::p_in_scope(self : H) -> Bool {
  let mut i = self.stack.length() - 1
  while i > 0 {
    let l = local_of(self.stack[i].name).to_lower()
    if l == "p" {
      return true
    }
    if l == "table" || l == "td" || l == "th" || l == "button" || l == "html" || l == "caption" || l == "template" {
      return false
    }
    if ns_of(self.stack[i].name) != "" {
      return false
    }
    i = i - 1
  }
  false
}

/// Whether the open body already holds something, which makes a `frameset` start
/// tag ignorable.
fn H::body_has_content(self : H) -> Bool {
  let mut i = self.stack.length() - 1
  while i > 0 {
    let l = local_of(self.stack[i].name).to_lower()
    if l == "body" {
      return self.stack[i].children.length() > 0
    }
    i = i - 1
  }
  // No body element yet: content at the document level counts, except head
  // content, which is still waiting to be routed into `head`.
  let container = match find_child_named(self.stack[0], "html") {
    Some(h) => h
    None => self.stack[0]
  }
  for c in container.children {
    match c {
      @moonxml.Node::ElementNode(e) => {
        let l = local_of(e.name).to_lower()
        if l == "head" || l == "title" || l == "meta" || l == "link" || l == "style" || l == "script" || l == "base" || l == "template" || l == "noscript" {
          continue
        }
        return true
      }
      @moonxml.Node::TextNode(t) => if not(@text.is_blank(t)) {
        return true
      }
      @moonxml.Node::CommentNode(_) => ()
      _ => return true
    }
  }
  false
}

fn H::template_index(self : H) -> Int {
  let mut i = self.stack.length() - 1
  while i >= 0 {
    if local_of(self.stack[i].name).to_lower() == "template" {
      return i
    }
    i = i - 1
  }
  -1
}

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

fn H::stack_remove(self : H, el : @moonxml.Element) -> Unit {
  let mut i = 0
  while i < self.stack.length() {
    if physical_equal(self.stack[i], el) {
      let _ = self.stack.remove(i)
      break
    }
    i = i + 1
  }
}

/// Pop the implied-end-tag elements (dd, dt, li, optgroup, option, p, rb, rp,
/// rt, rtc) from the top of the stack.
fn H::pop_implied(self : H, keep : Array[String]) -> Unit {
  while self.stack.length() > 1 {
    let l = local_of(self.current().name).to_lower()
    let implied = l == "dd" || l == "dt" || l == "li" || l == "optgroup" || l == "option" || l == "p" || l == "rb" || l == "rp" || l == "rt" || l == "rtc"
    let mut kept = false
    for k in keep {
      if l == k {
        kept = true
      }
    }
    if implied && not(kept) {
      self.pop()
    } else {
      break
    }
  }
}

fn H::pop_while_in(self : H, tags : Array[String]) -> Unit {
  while self.stack.length() > 1 {
    let l = local_of(self.current().name).to_lower()
    let mut found = false
    for t in tags {
      if l == t {
        found = true
      }
    }
    if found {
      self.pop()
    } else {
      break
    }
  }
}

fn H::push_new(self : H, tag : String) -> Unit {
  let e = @moonxml.Element::new(tag)
  self.current().append(@moonxml.Node::ElementNode(e))
  self.push(e)
}

fn H::select_index(self : H) -> Int {
  let mut i = self.stack.length() - 1
  while i >= 0 {
    if local_of(self.stack[i].name).to_lower() == "select" {
      return i
    }
    i = i - 1
  }
  -1
}

fn H::pop_through_select(self : H) -> Unit {
  let si = self.select_index()
  if si >= 0 {
    while self.stack.length() > si {
      self.pop()
    }
  }
}

fn is_table_tag(t : String) -> Bool {
  t == "table" || t == "tbody" || t == "thead" || t == "tfoot" || t == "tr" || t == "td" || t == "th" || t == "caption" || t == "colgroup" || t == "col"
}

/// In-select handling. Returns true when the tag was consumed and must not be
/// inserted by the normal path.
fn H::handle_in_select(self : H, tag : String) -> Bool {
  if self.select_index() < 0 {
    return false
  }
  if tag == "option" {
    self.pop_while_in(["option"])
    return false
  }
  if tag == "optgroup" {
    self.pop_while_in(["option", "optgroup"])
    return false
  }
  if tag == "select" {
    self.pop_through_select()
    return true
  }
  if tag == "input" || tag == "keygen" || tag == "textarea" {
    self.pop_through_select()
    return false
  }
  if tag == "script" || tag == "template" || tag == "hr" {
    return false
  }
  if is_table_tag(tag) {
    self.pop_through_select()
    return false
  }
  true
}

fn H::implied_table_wrappers(self : H, tag : String) -> Unit {
  let cur = local_of(self.current().name).to_lower()
  if tag == "tr" && cur == "table" {
    self.push_new("tbody")
  } else if tag == "td" || tag == "th" {
    let c2 = local_of(self.current().name).to_lower()
    if c2 == "table" {
      self.push_new("tbody")
      self.push_new("tr")
    } else if c2 == "tbody" || c2 == "thead" || c2 == "tfoot" {
      self.push_new("tr")
    }
  } else if tag == "col" && cur == "table" {
    self.push_new("colgroup")
  }
}

fn H::current_child_ns(self : H) -> String {
  let cur = self.current()
  let local = local_of(cur.name).to_lower()
  if local == "foreignobject" || local == "desc" || local == "title" {
    return ""
  }
  if local == "mtext" || local == "mi" || local == "mo" || local == "mn" || local == "ms" {
    return ""
  }
  if local == "annotation-xml" {
    return ""
  }
  ns_of(cur.name)
}

fn is_html_breakout(t : String) -> Bool {
  match t {
    "b" | "big" | "blockquote" | "body" | "br" | "center" | "code" | "dd" | "div" | "dl" |
    "dt" | "em" | "embed" | "h1" | "h2" | "h3" | "h4" | "h5" | "h6" | "head" | "hr" | "i" |
    "img" | "li" | "listing" | "menu" | "meta" | "nobr" | "ol" | "p" | "pre" | "ruby" |
    "s" | "small" | "span" | "strong" | "strike" | "sub" | "sup" | "table" | "tt" | "u" |
    "ul" | "var" | "font" => true
    _ => false
  }
}

fn H::append_node(self : H, node : @moonxml.Node) -> Unit {
  let cur = self.current()
  // A DOM never keeps two adjacent text nodes: merge, and drop empty ones.
  match node {
    @moonxml.Node::TextNode(t) => {
      if t.length() == 0 {
        return
      }
      let n = cur.children.length()
      if n > 0 {
        match cur.children[n - 1] {
          @moonxml.Node::TextNode(prev) => {
            cur.children[n - 1] = @moonxml.Node::TextNode(prev + t)
            return
          }
          _ => ()
        }
      }
      cur.append(node)
    }
    _ => cur.append(node)
  }
}

fn is_table_scope(l : String) -> Bool {
  l == "table" || l == "tbody" || l == "thead" || l == "tfoot" || l == "tr"
}

fn table_allows(scope : String, tag : String) -> Bool {
  if tag == "style" || tag == "script" || tag == "template" || tag == "input" {
    return true
  }
  if scope == "table" {
    if tag == "caption" || tag == "colgroup" || tag == "col" {
      return true
    }
    return tag == "thead" || tag == "tbody" || tag == "tfoot" || tag == "tr"
  }
  if scope == "tr" {
    return tag == "td" || tag == "th"
  }
  tag == "tr"
}

fn H::find_table(self : H) -> @moonxml.Element? {
  let mut i = self.stack.length() - 1
  while i >= 0 {
    if local_of(self.stack[i].name).to_lower() == "table" {
      return Some(self.stack[i])
    }
    i = i - 1
  }
  None
}

/// Insert fostered text just before the table, merging with the text node
/// already there so a DOM never holds two adjacent text nodes.
fn H::foster_text(self : H, s : String) -> Bool {
  match self.find_table() {
    Some(t) => match t.parent {
      Some(p) => {
        let kids = p.children
        let mut idx = -1
        let mut i = 0
        while i < kids.length() {
          match kids[i] {
            @moonxml.Node::ElementNode(e) => if physical_equal(e, t) {
              idx = i
              break
            }
            _ => ()
          }
          i = i + 1
        }
        if idx < 0 {
          return false
        }
        if idx > 0 {
          match kids[idx - 1] {
            @moonxml.Node::TextNode(prev) => {
              kids[idx - 1] = @moonxml.Node::TextNode(prev + s)
              return true
            }
            _ => ()
          }
        }
        let next : Array[@moonxml.Node] = []
        let mut j = 0
        while j < kids.length() {
          if j == idx {
            next.push(@moonxml.Node::TextNode(s))
          }
          next.push(kids[j])
          j = j + 1
        }
        p.set_children(next)
        true
      }
      None => false
    }
    None => false
  }
}

fn H::append_text(self : H, s : String) -> Unit {
  let cur = local_of(self.current().name).to_lower()
  if is_table_scope(cur) && not(@text.is_blank(s)) {
    if self.foster_text(s) {
      return
    }
  }
  self.append_node(@moonxml.Node::TextNode(s))
}

fn H::parse(self : H) -> @moonxml.Element {
  let root = @moonxml.Element::new("#document")
  // Parse into `root`; wrapping happens in `loads`.
  self.stack.push(root)
  while not(self.at_end()) {
    if self.starts_with("<!--") {
      self.pos = self.pos + 4
      // `<!-->` and `<!--->` are empty comments.
      if not(self.at_end()) && self.peek() == '>' {
        self.pos = self.pos + 1
        self.push_comment("")
      } else if self.starts_with("->") {
        self.pos = self.pos + 2
        self.push_comment("")
      } else {
        let (text, nextpos) = scan_comment(self.s, self.pos)
        self.pos = nextpos
        self.push_comment(text)
      }
    } else if self.starts_with_ci("<!doctype") {
      self.pos = self.pos + 9
      root.append(@moonxml.Node::DoctypeNode(self.parse_doctype_html()))
    } else if self.starts_with("<?") {
      // A processing-instruction lookalike becomes a bogus comment.
      self.pos = self.pos + 1
      let start = self.pos
      while not(self.at_end()) && self.peek() != '>' {
        self.pos = self.pos + 1
      }
      let text = slice_of(self.s, start, self.pos)
      if not(self.at_end()) {
        self.pos = self.pos + 1
      }
      self.repairs = self.repairs + 1
      self.append_node(@moonxml.Node::CommentNode(text))
    } else if self.starts_with("</") {
      self.parse_end_tag()
    } else if self.starts_with("<![CDATA[") && ns_of(self.current().name) != "" {
      // A CDATA section is text inside `svg`/`math`; in HTML it is a bogus
      // comment.
      self.pos = self.pos + 9
      let start = self.pos
      let mut end = self.n
      let mut after = self.n
      let mut i = start
      while i + 2 < self.n {
        if self.s[i] == ']' && self.s[i + 1] == ']' && self.s[i + 2] == '>' {
          end = i
          after = i + 3
          break
        }
        i = i + 1
      }
      self.append_node(@moonxml.Node::TextNode(slice_of(self.s, start, end)))
      self.pos = after
    } else if self.starts_with("<!") {
      // Bogus markup: treat as a comment up to '>'.
      self.pos = self.pos + 2
      let start = self.pos
      while not(self.at_end()) && self.peek() != '>' {
        self.pos = self.pos + 1
      }
      let text = slice_of(self.s, start, self.pos)
      if not(self.at_end()) {
        self.pos = self.pos + 1
      }
      self.repairs = self.repairs + 1
      self.append_node(@moonxml.Node::CommentNode(text))
    } else if self.peek() == '<' && is_tag_name_char(self.peek_at(1)) {
      self.parse_start_tag()
    } else {
      let start = self.pos
      while not(self.at_end()) && self.peek() != '<' {
        self.pos = self.pos + 1
      }
      let raw = slice_of(self.s, start, self.pos)
      if raw.length() > 0 {
        self.reconstruct()
        self.append_text(decode_entities(raw))
      } else if not(self.at_end()) && self.peek() == '<' {
        // A '<' that did not start a tag: emit it and advance, or the loop hangs.
        self.pos = self.pos + 1
        self.append_text("<")
      }
    }
  }
  root
}

fn scan_comment(cs : Array[Char], start : Int) -> (String, Int) {
  let n = cs.length()
  let mut i = start
  while i + 2 < n {
    if cs[i] == '-' && cs[i + 1] == '-' {
      if cs[i + 2] == '>' {
        return (slice_of(cs, start, i), i + 3)
      }
      if cs[i + 2] == '!' && i + 3 < n && cs[i + 3] == '>' {
        return (slice_of(cs, start, i), i + 4)
      }
    }
    i = i + 1
  }
  (slice_of(cs, start, n), n)
}

fn H::parse_doctype_html(self : H) -> String {
  self.skip_ws_h()
  let nstart = self.pos
  while not(self.at_end()) && self.peek() != '>' && not(@text.is_html_space(self.peek())) {
    self.pos = self.pos + 1
  }
  let name = slice_of(self.s, nstart, self.pos).to_lower()
  self.skip_ws_h()
  let mut pubid = ""
  let mut sys = ""
  if self.starts_with_ci("PUBLIC") {
    self.pos = self.pos + 6
    self.skip_ws_h()
    pubid = self.read_quoted_or_empty()
    self.skip_ws_h()
    sys = self.read_quoted_or_empty()
  } else if self.starts_with_ci("SYSTEM") {
    self.pos = self.pos + 6
    self.skip_ws_h()
    sys = self.read_quoted_or_empty()
  }
  while not(self.at_end()) && self.peek() != '>' {
    self.pos = self.pos + 1
  }
  if not(self.at_end()) {
    self.pos = self.pos + 1
  }
  if pubid == "" && sys == "" {
    name
  } else {
    name + " \"" + pubid + "\" \"" + sys + "\""
  }
}

fn H::read_quoted_or_empty(self : H) -> String {
  if self.at_end() {
    return ""
  }
  let q = self.peek()
  if q != '"' && q != '\'' {
    return ""
  }
  self.pos = self.pos + 1
  let start = self.pos
  while not(self.at_end()) && self.peek() != q {
    self.pos = self.pos + 1
  }
  let out = slice_of(self.s, start, self.pos)
  if not(self.at_end()) {
    self.pos = self.pos + 1
  }
  out
}

fn trim_h(s : String) -> String {
  let cs = s.to_array()
  let mut a = 0
  while a < cs.length() && @text.is_html_space(cs[a]) {
    a = a + 1
  }
  let mut b = cs.length()
  while b > a && @text.is_html_space(cs[b - 1]) {
    b = b - 1
  }
  s.substring(start=a, end=b)
}

fn find_marker_ci(cs : Array[Char], start : Int, marker : String) -> Int {
  let m = marker.to_array()
  let mut i = start
  while i + m.length() <= cs.length() {
    let mut ok = true
    let mut j = 0
    while j < m.length() {
      if lower_char(cs[i + j]) != lower_char(m[j]) {
        ok = false
        break
      }
      j = j + 1
    }
    if ok {
      return i
    }
    i = i + 1
  }
  -1
}

fn H::parse_end_tag(self : H) -> Unit {
  self.pos = self.pos + 2
  let start = self.pos
  while not(self.at_end()) && is_tag_name_char(self.peek()) {
    self.pos = self.pos + 1
  }
  let name = slice_of(self.s, start, self.pos).to_lower()
  while not(self.at_end()) && self.peek() != '>' {
    self.pos = self.pos + 1
  }
  if not(self.at_end()) {
    self.pos = self.pos + 1
  }
  if name == "body" || name == "html" {
    self.body_closed = true
  }
  if formatting_tag(name) {
    self.adoption(name)
    return
  }
  if is_heading(name) {
    if self.pop_heading(name) {
      return
    }
  }
  if name == "p" {
    if self.p_in_scope() == false {
      // The spec inserts an empty paragraph and closes it.
      let el = @moonxml.Element::new("p")
      self.append_node(@moonxml.Node::ElementNode(el))
      return
    }
  }
  // Walk up to the matching open element. A special element (a block, a
  // button, a cell) blocks the search: `</span>` never reaches past a button.
  let mut i = self.stack.length() - 1
  let mut found = false
  while i > 0 {
    let l = local_of(self.stack[i].name).to_lower()
    if l == name {
      found = true
      break
    }
    // An end tag never reaches out of the template it is inside.
    if l == "template" && name != "template" {
      break
    }
    if is_special_el(l) && not(explicit_end_rule(name)) {
      break
    }
    i = i - 1
  }
  if found {
    while self.stack.length() - 1 >= i && self.stack.length() > 1 {
      let top = self.current()
      self.pop()
      self.afe_remove(top)
    }
  } else {
    self.repairs = self.repairs + 1
  }
}

/// End tags with a dedicated rule: they pop through anything, so the
/// special-element stop in the generic path does not apply to them.
fn explicit_end_rule(l : String) -> Bool {
  match l {
    "body" | "html" | "head" | "p" | "div" | "li" | "dd" | "dt" | "ol" | "ul" |
    "h1" | "h2" | "h3" | "h4" | "h5" | "h6" | "form" | "button" | "address" |
    "article" | "aside" | "blockquote" | "center" | "details" | "dialog" |
    "dir" | "dl" | "fieldset" | "figcaption" | "figure" | "footer" | "header" |
    "hgroup" | "main" | "menu" | "nav" | "pre" | "listing" | "section" |
    "summary" | "search" | "applet" | "marquee" | "object" | "br" | "table" |
    "tbody" | "thead" | "tfoot" | "tr" | "td" | "th" | "caption" | "colgroup" |
    "select" | "option" | "optgroup" | "template" | "script" | "style" |
    "title" | "textarea" | "noscript" | "iframe" | "noframes" | "frameset" |
    "frame" | "xmp" | "plaintext" | "sarcasm" => true
    _ => false
  }
}

fn is_heading(l : String) -> Bool {
  l == "h1" || l == "h2" || l == "h3" || l == "h4" || l == "h5" || l == "h6"
}

/// `</h2>` closes the nearest open heading, even when the names differ.
fn H::pop_heading(self : H, name : String) -> Bool {
  let mut i = self.stack.length() - 1
  let mut found = -1
  while i > 0 {
    let l = local_of(self.stack[i].name).to_lower()
    if l == name {
      found = i
      break
    }
    if is_heading(l) {
      found = i
      break
    }
    if l == "template" || l == "table" || l == "td" || l == "th" || l == "html" {
      break
    }
    i = i - 1
  }
  if found < 0 {
    return false
  }
  while self.stack.length() > found {
    self.pop()
  }
  true
}

/// The WHATWG "special" element category: end tags do not look past one.
fn is_special_el(l : String) -> Bool {
  match l {
    "address" | "applet" | "area" | "article" | "aside" | "base" | "basefont" |
    "bgsound" | "blockquote" | "body" | "br" | "button" | "caption" | "center" |
    "col" | "colgroup" | "dd" | "details" | "dir" | "div" | "dl" | "dt" |
    "embed" | "fieldset" | "figcaption" | "figure" | "footer" | "form" |
    "frame" | "frameset" | "h1" | "h2" | "h3" | "h4" | "h5" | "h6" | "head" |
    "header" | "hgroup" | "hr" | "html" | "iframe" | "img" | "input" |
    "keygen" | "li" | "link" | "listing" | "main" | "marquee" | "menu" |
    "meta" | "nav" | "noembed" | "noframes" | "noscript" | "object" | "ol" |
    "p" | "param" | "plaintext" | "pre" | "script" | "search" | "section" |
    "select" | "source" | "style" | "summary" | "table" | "tbody" | "td" |
    "template" | "textarea" | "tfoot" | "th" | "thead" | "title" | "tr" |
    "track" | "ul" | "wbr" | "xmp" => true
    _ => false
  }
}

fn H::parse_start_tag(self : H) -> Unit {
  self.pos = self.pos + 1
  let start = self.pos
  while not(self.at_end()) && is_tag_name_char(self.peek()) {
    self.pos = self.pos + 1
  }
  let raw_name = slice_of(self.s, start, self.pos).to_lower()
  if raw_name.length() == 0 {
    // A stray '<'.
    self.append_node(@moonxml.Node::TextNode("<"))
    return
  }
  let attrs : Array[(String, String)] = []
  let mut self_closing = false
  while not(self.at_end()) {
    while not(self.at_end()) && @text.is_html_space(self.peek()) {
      self.pos = self.pos + 1
    }
    if self.at_end() {
      break
    }
    let c = self.peek()
    if c == '>' {
      self.pos = self.pos + 1
      break
    } else if c == '/' {
      if self.peek_at(1) == '>' {
        self.pos = self.pos + 2
        self_closing = true
        break
      } else {
        self.pos = self.pos + 1
      }
    } else {
      let astart = self.pos
      while not(self.at_end()) && @text.is_html_space(self.peek()) == false && self.peek() != '=' && self.peek() != '>' && self.peek() != '/' {
        self.pos = self.pos + 1
      }
      let aname = slice_of(self.s, astart, self.pos).to_lower()
      while not(self.at_end()) && @text.is_html_space(self.peek()) {
        self.pos = self.pos + 1
      }
      let mut avalue = ""
      if not(self.at_end()) && self.peek() == '=' {
        self.pos = self.pos + 1
        while not(self.at_end()) && @text.is_html_space(self.peek()) {
          self.pos = self.pos + 1
        }
        if not(self.at_end()) && (self.peek() == '"' || self.peek() == '\'') {
          let q = self.peek()
          self.pos = self.pos + 1
          let vstart = self.pos
          while not(self.at_end()) && self.peek() != q {
            self.pos = self.pos + 1
          }
          avalue = decode_entities_attr(slice_of(self.s, vstart, self.pos))
          if not(self.at_end()) {
            self.pos = self.pos + 1
          }
        } else {
          let vstart = self.pos
          while not(self.at_end()) && @text.is_html_space(self.peek()) == false && self.peek() != '>' {
            self.pos = self.pos + 1
          }
          avalue = decode_entities_attr(slice_of(self.s, vstart, self.pos))
        }
      }
      if aname.length() > 0 {
        attrs.push((aname, avalue))
      }
    }
  }
  // In-select handling comes first: most tags are ignored there.
  if self.handle_in_select(raw_name) {
    return
  }
  // A second `html` start tag merges its attributes into the open one.
  if raw_name == "html" {
    if self.has_open("html") {
      self.merge_attrs_onto("html", attrs)
      return
    }
    match find_child_named(self.stack[0], "html") {
      Some(h) => {
        for pair in attrs {
          let (k, v) = pair
          if h.attr(k).is_none() {
            h.set_attr(k, v)
          }
        }
        return
      }
      None => ()
    }
  }
  // A body tag while head is still open closes head.
  if raw_name == "body" {
    self.pop_through_head()
  }
  // A heading start tag closes an open heading.
  if raw_name == "h1" || raw_name == "h2" || raw_name == "h3" || raw_name == "h4" || raw_name == "h5" || raw_name == "h6" {
    self.pop_while_in(["h1", "h2", "h3", "h4", "h5", "h6"])
  }
  // Frames outside a frameset are ignored, and inside a template they are
  // ignored too.
  if raw_name == "frame" || raw_name == "frameset" {
    if self.template_index() >= 0 || raw_name == "frame" || self.body_has_content() {
      return
    }
  }
  // A second `a` runs the adoption agency for the first, then forgets it.
  if raw_name == "a" {
    match self.afe_find_by_name("a") {
      Some(old) => {
        self.adoption("a")
        self.afe_remove(old)
        self.stack_remove(old)
      }
      None => ()
    }
  }
  // Auto-closing for optional end tags, then reconstruction.
  self.auto_close(raw_name)
  self.implied_table_wrappers(raw_name)
  self.reconstruct()
  // Break out of foreign content on an HTML start tag (unless at an
  // integration point).
  let cur_ns = ns_of(self.current().name)
  let cur_local = local_of(self.current().name).to_lower()
  let at_integration = cur_local == "foreignobject" || cur_local == "desc" || cur_local == "title" || cur_local == "mtext" || cur_local == "mi" || cur_local == "mo" || cur_local == "mn" || cur_local == "ms" || cur_local == "annotation-xml"
  if cur_ns != "" && not(at_integration) && is_html_breakout(raw_name) {
    while self.stack.length() > 1 && ns_of(self.current().name) != "" {
      self.pop()
    }
  }
  // `mglyph` and `malignmark` are MathML even in HTML content.
  if raw_name == "mglyph" || raw_name == "malignmark" {
    if self.current_child_ns() == "" {
      let mel = @moonxml.Element::with_attrs("{" + math_ns + "}" + raw_name, adjust_attrs_math(attrs))
      self.append_node(@moonxml.Node::ElementNode(mel))
      if self_closing == false {
        self.push(mel)
      }
      return
    }
  }
  // Namespace decision. A foreign fragment context supplies the namespace for
  // everything that is not an HTML breakout tag.
  let child_ns = if self.frag_ns != "" && self.stack.length() <= 1 {
    self.frag_ns
  } else {
    self.current_child_ns()
  }
  let ns = if raw_name == "svg" {
    svg_ns
  } else if raw_name == "math" {
    math_ns
  } else {
    child_ns
  }
  let adjusted = if ns == svg_ns {
    svg_adjust_tag(raw_name)
  } else {
    raw_name
  }
  let name = if ns == "" {
    adjusted
  } else {
    "{" + ns + "}" + adjusted
  }
  let final_attrs = if ns == svg_ns {
    adjust_attrs_svg(attrs)
  } else if ns == math_ns {
    adjust_attrs_math(attrs)
  } else {
    attrs
  }
  let el = @moonxml.Element::with_attrs(name, final_attrs)
  let scope = local_of(self.current().name).to_lower()
  let foster = is_table_scope(scope) && not(table_allows(scope, raw_name))
  if foster {
    match self.find_table() {
      Some(t) => {
        let _ = t.insert_before(@moonxml.Node::ElementNode(el))
      }
      None => self.append_node(@moonxml.Node::ElementNode(el))
    }
  } else {
    self.append_node(@moonxml.Node::ElementNode(el))
  }
  if is_void_tag(raw_name) {
    return
  }
  if is_rawtext_tag(raw_name) && ns == "" {
    self.push(el)
    self.consume_rawtext(raw_name, false)
    self.pop()
    return
  }
  if is_rcdata_tag(raw_name) && ns == "" {
    self.push(el)
    self.consume_rawtext(raw_name, true)
    self.pop()
    return
  }
  if self_closing {
    return
  }
  self.push(el)
  if ns == "" && formatting_tag(raw_name) {
    self.afe_add(el)
  }
}

fn is_ascii_alpha_c(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

fn is_end_tag_delim(c : Char) -> Bool {
  @text.is_html_space(c) || c == '/' || c == '>'
}

fn chars_ci_eq(name : Array[Char], lit : Array[Char]) -> Bool {
  if name.length() != lit.length() {
    return false
  }
  let mut i = 0
  while i < lit.length() {
    if lower_char(name[i]) != lower_char(lit[i]) {
      return false
    }
    i = i + 1
  }
  true
}

/// Find the `</tag` that ends a RAWTEXT/RCDATA element. The name must be
/// followed by whitespace, `/` or `>`, so `</style=` is text.
fn find_rawtext_end(cs : Array[Char], start : Int, n : Int, tag : String) -> Int {
  let tcs = tag.to_array()
  let tlen = tcs.length()
  let mut i = start
  while i + 1 < n {
    if cs[i] == '<' && cs[i + 1] == '/' {
      if i + 2 + tlen < n {
        let mut ok = true
        let mut j = 0
        while j < tlen {
          if lower_char(cs[i + 2 + j]) != lower_char(tcs[j]) {
            ok = false
            break
          }
          j = j + 1
        }
        if ok && is_end_tag_delim(cs[i + 2 + tlen]) {
          return i
        }
      }
    }
    i = i + 1
  }
  -1
}

/// Find where a `script` element's text ends, running the script-data states.
/// The escaped and double-escaped states matter: after `<!--`, a `</script>`
/// closes the element, but after `<!--<script>` it is text until `</script`
/// puts the tokenizer back into the escaped state.
fn find_script_end(cs : Array[Char], start : Int, n : Int) -> Int {
  let tcs = "script".to_array()
  let mut i = start
  let mut st = 0
  let mut tag_start = -1
  let mut name : Array[Char] = []
  while i < n {
    let c = cs[i]
    let mut advanced = true
    if st == 0 {
      if c == '<' {
        tag_start = i
        st = 1
      }
    } else if st == 1 {
      if c == '/' {
        st = 2
        name = []
      } else if c == '!' {
        st = 4
      } else {
        st = 0
        advanced = false
      }
    } else if st == 2 {
      if is_ascii_alpha_c(c) {
        name = [c]
        st = 3
      } else {
        st = 0
        advanced = false
      }
    } else if st == 3 {
      if is_ascii_alpha_c(c) {
        name.push(c)
      } else if is_end_tag_delim(c) {
        if chars_ci_eq(name, tcs) {
          return tag_start
        }
        st = 0
        advanced = false
      } else {
        st = 0
        advanced = false
      }
    } else if st == 4 {
      if c == '-' {
        st = 5
      } else {
        st = 0
        advanced = false
      }
    } else if st == 5 {
      if c == '-' {
        st = 6
      } else {
        st = 0
        advanced = false
      }
    } else if st == 6 {
      if c == '-' {
        st = 7
      } else if c == '<' {
        tag_start = i
        st = 9
      }
    } else if st == 7 {
      if c == '-' {
        st = 8
      } else if c == '<' {
        tag_start = i
        st = 9
      } else {
        st = 6
      }
    } else if st == 8 {
      if c == '-' {
        ()
      } else if c == '<' {
        tag_start = i
        st = 9
      } else if c == '>' {
        st = 6
      } else {
        st = 6
      }
    } else if st == 9 {
      if c == '/' {
        st = 10
        name = []
      } else if is_ascii_alpha_c(c) {
        name = [c]
        st = 12
      } else {
        st = 6
        advanced = false
      }
    } else if st == 10 {
      if is_ascii_alpha_c(c) {
        name = [c]
        st = 11
      } else {
        st = 6
        advanced = false
      }
    } else if st == 11 {
      if is_ascii_alpha_c(c) {
        name.push(c)
      } else if is_end_tag_delim(c) {
        if chars_ci_eq(name, tcs) {
          return tag_start
        }
        st = 6
        advanced = false
      } else {
        st = 6
        advanced = false
      }
    } else if st == 12 {
      if is_ascii_alpha_c(c) {
        name.push(c)
      } else if is_end_tag_delim(c) {
        st = if chars_ci_eq(name, tcs) { 13 } else { 6 }
      } else {
        st = 6
        advanced = false
      }
    } else if st == 13 {
      if c == '-' {
        st = 14
      } else if c == '<' {
        tag_start = i
        st = 16
      }
    } else if st == 14 {
      if c == '-' {
        st = 15
      } else if c == '<' {
        tag_start = i
        st = 16
      } else {
        st = 13
      }
    } else if st == 15 {
      if c == '<' {
        tag_start = i
        st = 16
      } else if c == '>' {
        st = 13
      } else if c != '-' {
        st = 13
      }
    } else if st == 16 {
      if c == '/' {
        st = 17
        name = []
      } else {
        st = 13
        advanced = false
      }
    } else {
      // 17: double escape end
      if is_ascii_alpha_c(c) {
        name.push(c)
      } else if is_end_tag_delim(c) {
        st = if chars_ci_eq(name, tcs) { 6 } else { 13 }
      } else {
        st = 13
        advanced = false
      }
    }
    if advanced {
      i = i + 1
    }
  }
  -1
}

fn H::consume_rawtext(self : H, tag : String, decode : Bool) -> Unit {
  let n = self.n
  let end = if tag == "script" {
    find_script_end(self.s, self.pos, n)
  } else if tag == "plaintext" {
    -1
  } else {
    find_rawtext_end(self.s, self.pos, n, tag)
  }
  let text_end = if end < 0 { n } else { end }
  let raw = slice_of(self.s, self.pos, text_end)
  if raw.length() > 0 {
    let text = if decode {
      decode_entities(raw)
    } else {
      raw
    }
    self.append_node(@moonxml.Node::TextNode(text))
  }
  if end < 0 {
    self.pos = n
  } else {
    self.pos = end
    let mut k = end + 2
    while k < n && self.s[k] != '>' {
      k = k + 1
    }
    self.pos = if k < n { k + 1 } else { n }
  }
}

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

/// Parse a complete HTML document, wrapping loose content in `html`/`body`.
pub fn loads(text : String) -> @moonxml.Document {
  loads_internal(text, false, "body")
}

/// Parse UTF-8 bytes as HTML. Invalid sequences are replaced with U+FFFD.
pub fn load(bytes : Bytes) -> @moonxml.Document {
  loads(bytes.to_string())
}

/// Parse an HTML fragment; content goes straight into the virtual root.
pub fn loads_fragment(text : String, context? : String = "body") -> @moonxml.Document {
  loads_internal(text, true, context)
}

/// Elements whose foreign children are parsed as HTML.
fn is_integration_name(l : String) -> Bool {
  match l {
    "foreignobject" | "desc" | "title" | "mi" | "mo" | "mn" | "ms" | "mtext" => true
    _ => false
  }
}

fn context_is_foreign(context : String) -> Bool {
  context.has_prefix("svg ") || context.has_prefix("math ")
}

fn context_local(context : String) -> String {
  if context.has_prefix("svg ") || context.has_prefix("math ") {
    context.substring(start=4, end=context.length())
  } else {
    context
  }
}

fn loads_internal(text : String, fragment : Bool, context : String) -> @moonxml.Document {
  if fragment && not(context_is_foreign(context)) {
    let cl = context_local(context)
    if cl == "textarea" || cl == "title" {
      let root = @moonxml.Element::new("#document")
      root.append(@moonxml.Node::TextNode(decode_entities(text)))
      return @moonxml.Document::from_root(root, @moonxml.Flavour::Html)
    }
    if cl == "style" || cl == "script" || cl == "xmp" || cl == "iframe" || cl == "noembed" || cl == "noframes" {
      let root = @moonxml.Element::new("#document")
      root.append(@moonxml.Node::TextNode(text))
      return @moonxml.Document::from_root(root, @moonxml.Flavour::Html)
    }
  }
  let h = H::new(preprocess_h(text))
  if fragment && not(is_integration_name(context_local(context))) {
    if context.has_prefix("svg ") {
      h.frag_ns = svg_ns
    } else if context.has_prefix("math ") {
      h.frag_ns = math_ns
    }
  }
  let root = h.parse()
  if fragment == false {
    normalize_document_with(root, h.trailing_comments)
  }
  let doc = @moonxml.Document::from_root(root, @moonxml.Flavour::Html)
  if h.repairs > 0 {
    doc.repairs.note("html parser repaired " + h.repairs.to_string() + " token(s)")
  }
  doc
}

/// Input-stream preprocessing: drop a BOM, drop NUL, and normalise CRLF and CR
/// to LF, the way a browser reads bytes.
fn preprocess_h(s : String) -> String {
  let cs = s.to_array()
  let n = cs.length()
  let sb = StringBuilder()
  let mut i = 0
  if n > 0 && Char::to_int(cs[0]) == 0xFEFF {
    i = 1
  }
  while i < n {
    let c = cs[i]
    if c == '\u{0}' {
      i = i + 1
    } else if c == '\r' {
      sb.write_char('\n')
      if i + 1 < n && cs[i + 1] == '\n' {
        i = i + 1
      }
      i = i + 1
    } else {
      sb.write_char(c)
      i = i + 1
    }
  }
  sb.to_string()
}

fn strip_bom_h(s : String) -> String {
  if s.length() > 0 && Char::to_int(s.to_array()[0]) == 0xFEFF {
    s.substring(start=1, end=s.length())
  } else {
    s
  }
}

fn not_has_html(root : @moonxml.Element) -> Bool {
  for c in root.children {
    match c {
      @moonxml.Node::ElementNode(e) => if local_of(e.name).to_lower() == "html" {
        return false
      }
      _ => ()
    }
  }
  true
}

fn wrap_in_html(root : @moonxml.Element) -> Unit {
  let keep : Array[@moonxml.Node] = []
  let move : Array[@moonxml.Node] = []
  for c in root.children {
    match c {
      @moonxml.Node::DoctypeNode(_) => keep.push(c)
      _ => move.push(c)
    }
  }
  let html = @moonxml.Element::new("html")
  let head_elems : Array[@moonxml.Node] = []
  let body_nodes : Array[@moonxml.Node] = []
  let mut in_body = false
  for n in move {
    if not(in_body) && is_head_element(n) {
      head_elems.push(n)
    } else {
      in_body = true
      body_nodes.push(n)
    }
  }
  if head_elems.length() > 0 {
    let head = @moonxml.Element::new("head")
    for n in head_elems {
      head.append(n)
    }
    html.append(@moonxml.Node::ElementNode(head))
  }
  let body = @moonxml.Element::new("body")
  for n in body_nodes {
    body.append(n)
  }
  html.append(@moonxml.Node::ElementNode(body))
  keep.push(@moonxml.Node::ElementNode(html))
  root.set_children(keep)
}

fn is_head_element(n : @moonxml.Node) -> Bool {
  match n {
    @moonxml.Node::ElementNode(e) => {
      let l = local_of(e.name).to_lower()
      if l == "title" || l == "meta" || l == "link" || l == "base" {
        return true
      }
      l == "style" || l == "script" || l == "noscript" || l == "template"
    }
    _ => false
  }
}
