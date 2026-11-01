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
}

fn H::new(s : String) -> H {
  { s: s.to_array(), n: s.length(), pos: 0, stack: [], afe: [], repairs: 0 }
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

fn named_entity(name : String) -> String? {
  if name == "amp" { return Some("&") }
  if name == "lt" { return Some("<") }
  if name == "gt" { return Some(">") }
  if name == "quot" { return Some("\"") }
  if name == "apos" { return Some("'") }
  if name == "nbsp" { return Some("\u{A0}") }
  if name == "copy" { return Some("\u{A9}") }
  if name == "reg" { return Some("\u{AE}") }
  if name == "trade" { return Some("\u{2122}") }
  if name == "hellip" { return Some("\u{2026}") }
  if name == "mdash" { return Some("\u{2014}") }
  if name == "ndash" { return Some("\u{2013}") }
  if name == "lsquo" { return Some("\u{2018}") }
  if name == "rsquo" { return Some("\u{2019}") }
  if name == "ldquo" { return Some("\u{201C}") }
  if name == "rdquo" { return Some("\u{201D}") }
  if name == "laquo" { return Some("\u{AB}") }
  if name == "raquo" { return Some("\u{BB}") }
  if name == "times" { return Some("\u{D7}") }
  if name == "divide" { return Some("\u{F7}") }
  if name == "euro" { return Some("\u{20AC}") }
  if name == "pound" { return Some("\u{A3}") }
  if name == "yen" { return Some("\u{A5}") }
  if name == "cent" { return Some("\u{A2}") }
  if name == "sect" { return Some("\u{A7}") }
  if name == "deg" { return Some("\u{B0}") }
  if name == "plusmn" { return Some("\u{B1}") }
  if name == "micro" { return Some("\u{B5}") }
  if name == "para" { return Some("\u{B6}") }
  if name == "middot" { return Some("\u{B7}") }
  if name == "bull" { return Some("\u{2022}") }
  if name == "larr" { return Some("\u{2190}") }
  if name == "rarr" { return Some("\u{2192}") }
  if name == "uarr" { return Some("\u{2191}") }
  if name == "darr" { return Some("\u{2193}") }
  None
}

fn decode_entities(s : String) -> String {
  let cs = s.to_array()
  let n = cs.length()
  let sb = StringBuilder()
  let mut i = 0
  while i < n {
    let c = cs[i]
    if c == '&' {
      let mut j = i + 1
      if j < n && cs[j] == '#' {
        j = j + 1
        let hex = j < n && (cs[j] == 'x' || cs[j] == 'X')
        if hex {
          j = j + 1
        }
        let dstart = j
        while j < n && cs[j] != ';' && j - dstart < 8 {
          j = j + 1
        }
        if j < n && cs[j] == ';' {
          let digits = slice_of(cs, dstart, j)
          let cp = if hex {
            @text.parse_hex(digits)
          } else {
            @text.parse_dec(digits)
          }
          if cp >= 0 {
            sb.write_string(@text.code_point_to_string(cp))
            i = j + 1
          } else {
            sb.write_char(c)
            i = i + 1
          }
        } else {
          sb.write_char(c)
          i = i + 1
        }
      } else {
        let nstart = j
        while j < n && cs[j] != ';' && j - nstart < 32 {
          j = j + 1
        }
        if j < n && cs[j] == ';' {
          let nm = slice_of(cs, nstart, j)
          match named_entity(nm) {
            Some(rep) => {
              sb.write_string(rep)
              i = j + 1
            }
            None => {
              sb.write_char(c)
              i = i + 1
            }
          }
        } else {
          sb.write_char(c)
          i = i + 1
        }
      }
    } else {
      sb.write_char(c)
      i = i + 1
    }
  }
  sb.to_string()
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

fn adjust_attrs_svg(attrs : Array[(String, String)]) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for pair in attrs {
    let (n, v) = pair
    out.push((svg_adjust_attr(n), v))
  }
  out
}

fn closes_p(t : String) -> Bool {
  if t == "address" || t == "article" || t == "aside" || t == "blockquote" {
    return true
  }
  if t == "div" || t == "dl" || t == "fieldset" || t == "footer" {
    return true
  }
  if t == "form" || t == "h1" || t == "h2" || t == "h3" || t == "h4" {
    return true
  }
  if t == "h5" || t == "h6" || t == "header" || t == "hr" {
    return true
  }
  if t == "nav" || t == "ol" || t == "p" || t == "pre" || t == "section" {
    return true
  }
  t == "table" || t == "ul"
}

fn H::pop_while_current(self : H, tag : String) -> Unit {
  while self.stack.length() > 1 && local_of(self.current().name).to_lower() == tag {
    self.pop()
  }
}

fn H::auto_close(self : H, tag : String) -> Unit {
  if closes_p(tag) {
    self.pop_while_current("p")
  }
  if tag == "li" {
    self.pop_while_current("li")
  }
  if tag == "dt" || tag == "dd" {
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
    self.pop_while_current("thead")
    self.pop_while_current("tbody")
    self.pop_while_current("tfoot")
  }
  if tag == "button" {
    self.pop_while_current("button")
  }
}

fn H::current_child_ns(self : H) -> String {
  let cur = self.current()
  let local = local_of(cur.name).to_lower()
  if local == "foreignobject" || local == "desc" || local == "title" {
    ""
  } else {
    ns_of(cur.name)
  }
}

fn H::append_node(self : H, node : @moonxml.Node) -> Unit {
  self.current().append(node)
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

fn H::append_text(self : H, s : String) -> Unit {
  let cur = local_of(self.current().name).to_lower()
  if is_table_scope(cur) && not(@text.is_blank(s)) {
    match self.find_table() {
      Some(t) => {
        let _ = t.insert_before(@moonxml.Node::TextNode(s))
        return
      }
      None => ()
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
      let start = self.pos
      let close = find_marker_ci(self.s, self.pos, "-->")
      let text = if close < 0 {
        slice_of(self.s, start, self.n)
      } else {
        let t = slice_of(self.s, start, close)
        self.pos = close + 3
        t
      }
      if close < 0 {
        self.pos = self.n
      }
      self.append_node(@moonxml.Node::CommentNode(text))
    } else if self.starts_with_ci("<!doctype") {
      self.pos = self.pos + 9
      let start = self.pos
      while not(self.at_end()) && self.peek() != '>' {
        self.pos = self.pos + 1
      }
      let raw = slice_of(self.s, start, self.pos)
      if not(self.at_end()) {
        self.pos = self.pos + 1
      }
      root.append(@moonxml.Node::DoctypeNode(trim_h(raw)))
    } else if self.starts_with("</") {
      self.parse_end_tag()
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
      }
    }
  }
  root
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
  if formatting_tag(name) {
    self.adoption(name)
    return
  }
  // Pop to the matching open element, if any.
  let mut i = self.stack.length() - 1
  let mut found = false
  while i >= 0 {
    if local_of(self.stack[i].name).to_lower() == name {
      found = true
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
          avalue = decode_entities(slice_of(self.s, vstart, self.pos))
          if not(self.at_end()) {
            self.pos = self.pos + 1
          }
        } else {
          let vstart = self.pos
          while not(self.at_end()) && @text.is_html_space(self.peek()) == false && self.peek() != '>' {
            self.pos = self.pos + 1
          }
          avalue = decode_entities(slice_of(self.s, vstart, self.pos))
        }
      }
      if aname.length() > 0 {
        attrs.push((aname, avalue))
      }
    }
  }
  // Auto-closing for optional end tags, then reconstruction.
  self.auto_close(raw_name)
  self.reconstruct()
  // Namespace decision.
  let child_ns = self.current_child_ns()
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

fn H::consume_rawtext(self : H, tag : String, decode : Bool) -> Unit {
  let close_marker = "</" + tag
  let mut i = self.pos
  let mut found = -1
  while i + close_marker.length() <= self.n {
    let mut ok = true
    let mut j = 0
    while j < close_marker.length() {
      if lower_char(self.s[i + j]) != lower_char(close_marker.to_array()[j]) {
        ok = false
        break
      }
      j = j + 1
    }
    if ok {
      found = i
      break
    }
    i = i + 1
  }
  let end = if found < 0 {
    self.n
  } else {
    found
  }
  let raw = slice_of(self.s, self.pos, end)
  if raw.length() > 0 {
    let text = if decode {
      decode_entities(raw)
    } else {
      raw
    }
    self.append_node(@moonxml.Node::TextNode(text))
  }
  if found < 0 {
    self.pos = self.n
  } else {
    // Consume the end tag.
    self.pos = found
    let mut k = found + close_marker.length()
    while k < self.n && self.s[k] != '>' {
      k = k + 1
    }
    self.pos = if k < self.n { k + 1 } else { self.n }
  }
}

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

/// Parse a complete HTML document, wrapping loose content in `html`/`body`.
pub fn loads(text : String) -> @moonxml.Document {
  loads_internal(text, false)
}

/// Parse UTF-8 bytes as HTML. Invalid sequences are replaced with U+FFFD.
pub fn load(bytes : Bytes) -> @moonxml.Document {
  loads(bytes.to_string())
}

/// Parse an HTML fragment; content goes straight into the virtual root.
pub fn loads_fragment(text : String, context? : String = "body") -> @moonxml.Document {
  ignore(context)
  loads_internal(text, true)
}

fn loads_internal(text : String, fragment : Bool) -> @moonxml.Document {
  let h = H::new(strip_bom_h(text))
  let root = h.parse()
  if fragment == false && not_has_html(root) {
    wrap_in_html(root)
  }
  let doc = @moonxml.Document::from_root(root, @moonxml.Flavour::Html)
  if h.repairs > 0 {
    doc.repairs.note("html parser repaired " + h.repairs.to_string() + " token(s)")
  }
  doc
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
