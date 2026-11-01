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
  mut tstate : TState
  /// The element name that ends the current raw-text state, and the tag name
  /// the specification calls "the last start tag emitted".
  mut raw_tag : String
  // Tokenizer scratch: the token being built.
  mut tok_is_end : Bool
  mut tok_name : String
  mut tok_attrs : Array[(String, String)]
  mut tok_sc : Bool
  mut attr_name : String
  mut attr_val : String
  mut comment_data : String
  mut temp : String
  mut doctype_name : String?
  mut doctype_pub : String?
  mut doctype_sys : String?
  mut doctype_quirks : Bool
  mut data_buf : String
  mut last_start_tag : String
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
  // Count the array, not the string: `String::length` and the number of code
  // units `to_array` produces differ outside the BMP.
  let cs = s.to_array()
  {
    s: cs,
    n: cs.length(),
    pos: 0,
    tstate: StData,
    raw_tag: "",
    tok_is_end: false,
    tok_name: "",
    tok_attrs: [],
    tok_sc: false,
    attr_name: "",
    attr_val: "",
    comment_data: "",
    temp: "",
    doctype_name: None,
    doctype_pub: None,
    doctype_sys: None,
    doctype_quirks: false,
    data_buf: "",
    last_start_tag: "",
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
  // Accumulate with a ceiling instead of parsing into an Int: a long run of
  // digits (or a value such as &#x80000041;) would overflow, and the result is
  // U+FFFD rather than an error.
  let base = if hex { 16 } else { 10 }
  let mut cp = 0
  let mut d = dstart
  while d < k {
    if cp <= 0x10FFFF {
      cp = cp * base + (if hex { hex_value_c(cs[d]) } else { Char::to_int(cs[d]) - 48 })
    }
    d = d + 1
  }
  let next = if k < n && cs[k] == ';' { k + 1 } else { k }
  (cp, next, true)
}

fn hex_value_c(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    Char::to_int(c) - 48
  } else if c >= 'a' && c <= 'f' {
    Char::to_int(c) - 87
  } else {
    Char::to_int(c) - 55
  }
}

fn is_dec_digit_c(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

fn is_hex_digit_c(c : Char) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

/// Read one character reference starting at `i` (which must be `&`).
/// Returns the decoded text, the position after it, and whether one was read.
/// `in_attr` selects the attribute-value rule for a legacy reference without a
/// semicolon followed by `=` or an alphanumeric.
fn H::read_char_ref(self : H, i : Int, in_attr : Bool) -> (String, Int, Bool) {
  let n = self.n
  let cs = self.s
  if i + 1 >= n || cs[i] != '&' {
    return ("", i, false)
  }
  if cs[i + 1] == '#' {
    let (cp, next, ok) = read_char_ref(cs, i + 2, n)
    if not(ok) {
      return ("", i, false)
    }
    // A reference to CR stays CR: line-ending normalisation applies to the
    // input stream, not to character references.
    let cp_norm = cp
    let safe = if cp_norm == 0 || cp_norm > 0x10FFFF || (cp_norm >= 0xD800 && cp_norm <= 0xDFFF) {
      0xFFFD
    } else {
      map_c1(cp_norm)
    }
    // HTML keeps control characters that XML would refuse; the replacement
    // above already handled NUL, surrogates and out-of-range values.
    return (Char::from_int(safe).to_string(), next, true)
  }
  let mut j = i + 1
  while j < n && is_ent_name_char(cs[j]) && j - i <= 33 {
    j = j + 1
  }
  if j == i + 1 {
    return ("", i, false)
  }
  if j < n && cs[j] == ';' {
    match entity_value(slice_of(cs, i + 1, j + 1)) {
      Some(v) => return (v, j + 1, true)
      None => ()
    }
  }
  let mut e = j
  while e > i + 1 {
    match entity_value(slice_of(cs, i + 1, e)) {
      Some(v) => {
        if in_attr && e < n {
          let nx = cs[e]
          if nx == '=' || is_ent_name_char(nx) {
            return ("", i, false)
          }
        }
        return (v, e, true)
      }
      None => e = e - 1
    }
  }
  ("", i, false)
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

fn svg_adjust_tag(t : String) -> String {
  match t {
    "foreignobject" => "foreignObject"
    "glyphref" => "glyphRef"
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

/// Flatten a doctype the way the tree and the serializer show it: the name,
/// then the public and system identifiers when either is present.
fn doctype_info(name : String?, pub_id : String?, sys_id : String?) -> String {
  let n = match name {
    Some(v) => v
    None => ""
  }
  let p = match pub_id {
    Some(v) => v
    None => ""
  }
  let sy = match sys_id {
    Some(v) => v
    None => ""
  }
  if p == "" && sy == "" {
    n
  } else {
    n + " \"" + p + "\" \"" + sy + "\""
  }
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
      h.tstate = StRcdata
      h.raw_tag = local
    } else if local == "style" || local == "xmp" || local == "iframe" || local == "noembed" || local == "noframes" {
      h.tstate = StRawtext
      h.raw_tag = local
    } else if local == "script" {
      h.tstate = StScriptData
      h.raw_tag = local
    } else if local == "plaintext" {
      h.tstate = StPlaintext
      h.raw_tag = local
    } else if local == "noscript" && scripting {
      h.tstate = StRawtext
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
  preprocess_impl(s, true)
}

/// Normalise line endings; `strip_bom` decides whether a leading U+FEFF goes.
/// The tokenizer view keeps it, because the corpus treats it as data.
fn preprocess_impl(s : String, strip_bom : Bool) -> String {
  let cs = s.to_array()
  let n = cs.length()
  let sb = StringBuilder()
  let mut i = 0
  if strip_bom && n > 0 && Char::to_int(cs[0]) == 0xFEFF {
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
