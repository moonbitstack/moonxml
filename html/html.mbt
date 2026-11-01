/// HTML parsing: a WHATWG tokenizer and a tree builder driven by explicit
/// insertion modes.
///
/// The parser never raises on malformed markup; it repairs. Its shape follows
/// the specification: the tokenizer hands the tree builder one token at a time,
/// the tree builder keeps a current insertion mode as a variable, and every
/// mode is a function over tokens that either handles one or asks for it to be
/// reprocessed. The five table states, templates with their own mode stack, the
/// "in select" pair, and the text/RCDATA handover all fall out of that.
///
/// Names in foreign content are Clark names (`{uri}local`); HTML names stay
/// bare.

let svg_ns : String = "http://www.w3.org/2000/svg"
let math_ns : String = "http://www.w3.org/1998/Math/MathML"

struct H {
  // Input and tokenizer state.
  s : Array[Char]
  n : Int
  mut pos : Int
  /// The content model the tokenizer is in; the tree builder switches it when
  /// it starts a `script`, `style`, `textarea` and so on.
  mut tstate : TokState
  /// The element name that ends the current raw-text state.
  mut raw_tag : String
  // Tree under construction.
  mut doc : @moonxml.Element
  stack : Array[@moonxml.Element]
  afe : Array[AFEItem]
  // Insertion modes.
  mut mode : Mode
  /// Where to return after a `Text` or `InTableText` excursion.
  mut orig_mode : Mode
  template_modes : Array[Mode]
  // Pointers the spec keeps outside the tree.
  mut head : @moonxml.Element?
  mut form : @moonxml.Element?
  // Flags.
  mut scripting : Bool
  mut frameset_ok : Bool
  mut foster : Bool
  mut pending_text : String
  mut pending_nonws : Bool
  mut ignore_lf : Bool
  mut quirks : Bool
  repairs : Int
  mut fragment : Bool
  /// The fragment's context element. It is not in the tree and not on the
  /// stack; it only supplies the namespace and the initial insertion mode.
  mut context : @moonxml.Element?
}

fn H::new(s : String) -> H {
  {
    s: s.to_array(),
    n: s.length(),
    pos: 0,
    tstate: TsData,
    raw_tag: "",
    doc: @moonxml.Element::new("#document"),
    stack: [],
    afe: [],
    mode: MInitial,
    orig_mode: MInitial,
    template_modes: [],
    head: None,
    form: None,
    scripting: false,
    frameset_ok: true,
    foster: false,
    pending_text: "",
    pending_nonws: false,
    ignore_lf: false,
    quirks: false,
    repairs: 0,
    fragment: false,
    context: None,
  }
}

/// Consume tokens until the input ends. The tree builder's whole loop.
fn H::run(self : H) -> Unit {
  while true {
    let mut tok = self.next_token()
    if self.ignore_lf {
      self.ignore_lf = false
      match tok {
        Chars(s) => {
          if s.length() > 0 && s.to_array()[0] == '\n' {
            if s.length() == 1 {
              continue
            }
            tok = Chars(s.substring(start=1, end=s.length()))
          }
        }
        _ => ()
      }
    }
    self.dispatch(tok)
    match tok {
      Eof => break
      _ => ()
    }
  }
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
          let cp_norm = if cp == 0x0D {
            0x0A
          } else {
            cp
          }
          let safe = if cp_norm == 0 || cp_norm > 0x10FFFF || (cp_norm >= 0xD800 && cp_norm <= 0xDFFF) {
            0xFFFD
          } else {
            map_c1(cp_norm)
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

/// NUL is ignored in ordinary text.
fn strip_nul(s : String) -> String {
  if s.contains("\u{0}") == false {
    return s
  }
  let sb = StringBuilder()
  for c in s {
    if c != '\u{0}' {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

/// NUL becomes U+FFFD in raw text and CDATA.
fn nul_to_fffd(s : String) -> String {
  if s.contains("\u{0}") == false {
    return s
  }
  let sb = StringBuilder()
  for c in s {
    if c == '\u{0}' {
      sb.write_string("\u{FFFD}")
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

/// Read a tag name, skipping NUL the way the tokenizer does.
fn H::read_tag_name(self : H) -> String {
  let sb = StringBuilder()
  while not(self.at_end()) {
    let c = self.peek()
    if c == '\u{0}' {
      self.pos = self.pos + 1
    } else if is_tag_name_char(c) || c == '<' {
      sb.write_char(lower_char(c))
      self.pos = self.pos + 1
    } else {
      break
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
// Tag and attribute tables
// ---------------------------------------------------------------------------

fn is_tag_name_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == ':' || c == '.'
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
    _ => n
  }
}

let xlink_ns_h : String = "http://www.w3.org/1999/xlink"
let xml_ns_h : String = "http://www.w3.org/XML/1998/namespace"
let xmlns_ns_h : String = "http://www.w3.org/2000/xmlns/"

/// Foreign attributes keep their namespace: `xlink:href` becomes a Clark name.
fn adjust_attrs_foreign(attrs : Array[(String, String)]) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for pair in attrs {
    let (n, v) = pair
    if n == "xmlns" {
      out.push(("{" + xmlns_ns_h + "}xmlns", v))
    } else if n.has_prefix("xlink:") {
      out.push(("{" + xlink_ns_h + "}" + n.substring(start=6, end=n.length()), v))
    } else if n.has_prefix("xml:") {
      out.push(("{" + xml_ns_h + "}" + n.substring(start=4, end=n.length()), v))
    } else if n.has_prefix("xmlns:") {
      out.push(("{" + xmlns_ns_h + "}" + n.substring(start=6, end=n.length()), v))
    } else {
      out.push(pair)
    }
  }
  out
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

fn is_html_breakout(t : String) -> Bool {
  match t {
    "b" | "big" | "blockquote" | "body" | "br" | "center" | "code" | "dd" | "div" | "dl" |
    "dt" | "em" | "embed" | "h1" | "h2" | "h3" | "h4" | "h5" | "h6" | "head" | "hr" | "i" |
    "img" | "li" | "listing" | "menu" | "meta" | "nobr" | "ol" | "p" | "pre" | "ruby" |
    "s" | "small" | "span" | "strong" | "strike" | "sub" | "sup" | "table" | "tt" | "u" |
    "ul" | "var" => true
    _ => false
  }
}

fn is_heading(l : String) -> Bool {
  l == "h1" || l == "h2" || l == "h3" || l == "h4" || l == "h5" || l == "h6"
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

fn is_table_scope(l : String) -> Bool {
  l == "table" || l == "tbody" || l == "thead" || l == "tfoot" || l == "tr" || l == "colgroup"
}

fn append_text_to(el : @moonxml.Element, s : String) -> Unit {
  let n = el.children.length()
  if n > 0 {
    match el.children[n - 1] {
      @moonxml.Node::TextNode(prev) => {
        el.children[n - 1] = @moonxml.Node::TextNode(prev + s)
        return
      }
      _ => ()
    }
  }
  el.append(@moonxml.Node::TextNode(s))
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

fn has_child_named(el : @moonxml.Element, name : String) -> Bool {
  for c in el.children {
    match c {
      @moonxml.Node::ElementNode(e) => if local_of(e.name).to_lower() == name {
        return true
      }
      _ => ()
    }
  }
  false
}

/// Only whitespace survives as text inside a frameset.
fn keep_ws(s : String) -> String {
  let sb = StringBuilder()
  for c in s {
    if @text.is_html_space(c) {
      sb.write_char(c)
    }
  }
  sb.to_string()
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

fn H::skip_ws_h(self : H) -> Unit {
  while not(self.at_end()) && @text.is_html_space(self.peek()) {
    self.pos = self.pos + 1
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
        st = 0
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
        st = 0
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

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

/// Parse a complete HTML document, wrapping loose content in `html`/`body`.
pub fn loads(text : String) -> @moonxml.Document {
  loads_internal(text, false, "body", false)
}

/// Parse with the scripting flag on, which makes `noscript` content raw text.
pub fn loads_with_scripting(text : String, scripting : Bool) -> @moonxml.Document {
  loads_internal(text, false, "body", scripting)
}

/// Parse UTF-8 bytes as HTML. Invalid sequences are replaced with U+FFFD.
pub fn load(bytes : Bytes) -> @moonxml.Document {
  loads(bytes.to_string())
}

/// Parse an HTML fragment in the given context element, the way `innerHTML`
/// does: the context names the element whose children are being parsed, and
/// `svg ` / `math ` prefixes put it in a foreign namespace.
pub fn loads_fragment(text : String, context? : String = "body") -> @moonxml.Document {
  loads_internal(text, true, context, false)
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
  // `svg title` and `math ms` name an element in that namespace.
  if context.has_prefix("svg ") {
    context.substring(start=4, end=context.length())
  } else if context.has_prefix("math ") {
    context.substring(start=5, end=context.length())
  } else {
    context
  }
}

fn loads_internal(text : String, fragment : Bool, context : String, scripting : Bool) -> @moonxml.Document {
  let h = H::new(preprocess_h(text))
  h.scripting = scripting
  h.fragment = fragment
  if fragment {
    let local = context_local(context).to_lower()
    let ns = if context.has_prefix("svg ") {
      svg_ns
    } else if context.has_prefix("math ") {
      math_ns
    } else {
      ""
    }
    let name = if ns == "" { local } else { "{" + ns + "}" + local }
    let ctx = @moonxml.Element::new(name)
    let root = @moonxml.Element::new("html")
    h.doc = root
    h.stack.push(root)
    h.context = Some(ctx)
    h.frameset_ok = false
    // A fragment starts in the content model its context element implies.
    if ns != "" {
      // A foreign context is never RCDATA: `svg title` is an SVG element.
    } else if local == "title" || local == "textarea" {
      h.tstate = TsRcdata
      h.raw_tag = local
    } else if local == "style" || local == "xmp" || local == "iframe" || local == "noembed" || local == "noframes" {
      h.tstate = TsRawtext
      h.raw_tag = local
    } else if local == "script" {
      h.tstate = TsScript
      h.raw_tag = local
    } else if local == "plaintext" {
      h.tstate = TsPlaintext
      h.raw_tag = local
    } else if local == "noscript" && scripting {
      h.tstate = TsRawtext
      h.raw_tag = local
    }
    if local == "template" {
      h.template_modes.push(MInTemplate)
    }
    h.mode = fragment_mode(ctx)
  } else {
    h.mode = MInitial
  }
  h.run()
  let doc = @moonxml.Document::from_root(h.doc, @moonxml.Flavour::Html)
  if h.repairs > 0 {
    doc.repairs.note("html parser repaired " + h.repairs.to_string() + " token(s)")
  }
  doc
}

/// Input-stream preprocessing: drop a BOM and normalise CRLF and CR to LF, the
/// way a browser reads bytes. NUL goes on to the tokenizer, which drops it in
/// data and replaces it with U+FFFD in raw text.
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
    if c == '\r' {
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
