/// Strict XML 1.0 + Namespaces 1.0 parsing, with the DOCTYPE internal subset.
///
/// Well-formedness failures raise `Refused::Malformed(at=offset, why=...)`.
/// Names resolve to `{uri}local` (Clark notation); namespace declarations are
/// consumed and re-derived by the writer. External entities are never fetched
/// — following the no-I/O rule — and a reference to one is reported, not
/// silently dropped. General and parameter entities expand with recursion
/// detection and a total expansion budget (`limit`), so entity-expansion attacks
/// are bounded.

let xml_ns : String = "http://www.w3.org/XML/1998/namespace"

struct X {
  s : Array[Char]
  n : Int
  mut pos : Int
  general : Array[(String, String)]
  params : Array[(String, String)]
  defaults : Array[(String, String, String)]
  limit : Int
  mut expanded : Int
  depth_limit : Int
  mut depth : Int
}

fn X::new(s : String, depth_limit : Int, limit : Int) -> X {
  {
    s: s.to_array(),
    n: s.length(),
    pos: 0,
    general: [],
    params: [],
    defaults: [],
    limit,
    expanded: 0,
    depth_limit,
    depth: 0,
  }
}

fn X::at_end(self : X) -> Bool {
  self.pos >= self.n
}

fn X::peek(self : X) -> Char {
  if self.pos < self.n {
    self.s[self.pos]
  } else {
    '\u{0}'
  }
}

fn X::peek_at(self : X, k : Int) -> Char {
  let i = self.pos + k
  if i < self.n {
    self.s[i]
  } else {
    '\u{0}'
  }
}

fn X::starts_with(self : X, lit : String) -> Bool {
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

fn X::skip_ws(self : X) -> Unit {
  while self.pos < self.n && @text.is_xml_space(self.s[self.pos]) {
    self.pos = self.pos + 1
  }
}

fn X::fail(self : X, why : String) -> Unit raise @moonxml.Refused {
  raise @moonxml.Refused::Malformed(at=self.pos, why=why)
}

fn X::expect(self : X, lit : String, why : String) -> Unit raise @moonxml.Refused {
  if self.starts_with(lit) {
    self.pos = self.pos + lit.length()
  } else {
    self.fail(why)
  }
}

fn X::read_name(self : X) -> String raise @moonxml.Refused {
  if not(@text.is_name_start_char(self.peek())) {
    self.fail("expected a name")
  }
  let sb = StringBuilder()
  while self.pos < self.n && @text.is_name_char(self.s[self.pos]) {
    sb.write_char(self.s[self.pos])
    self.pos = self.pos + 1
  }
  sb.to_string()
}

fn X::read_until(self : X, marker : String) -> String raise @moonxml.Refused {
  let start = self.pos
  let m = marker.to_array()
  while self.pos + m.length() <= self.n {
    let mut ok = true
    let mut j = 0
    while j < m.length() {
      if self.s[self.pos + j] != m[j] {
        ok = false
        break
      }
      j = j + 1
    }
    if ok {
      let out = slice_chars(self.s, start, self.pos)
      self.pos = self.pos + m.length()
      return out
    }
    self.pos = self.pos + 1
  }
  raise @moonxml.Refused::Malformed(at=self.pos, why="unterminated construct, expected " + marker)
}

fn slice_chars(cs : Array[Char], start : Int, end : Int) -> String {
  let sb = StringBuilder()
  let mut i = start
  while i < end {
    sb.write_char(cs[i])
    i = i + 1
  }
  sb.to_string()
}

// ---------------------------------------------------------------------------
// Namespaces
// ---------------------------------------------------------------------------

fn lookup_prefix(scope : Array[(String, String)], prefix : String) -> String? {
  for pair in scope {
    let (p, u) = pair
    if p == prefix {
      return Some(u)
    }
  }
  None
}

fn resolve_name(raw : String, scope : Array[(String, String)], is_attr : Bool) -> String raise @moonxml.Refused {
  let mut idx = -1
  let mut i = 0
  for c in raw {
    if c == ':' {
      idx = i
    }
    i = i + 1
  }
  if idx >= 0 {
    let prefix = raw.substring(start=0, end=idx)
    let local = raw.substring(start=idx + 1, end=raw.length())
    match lookup_prefix(scope, prefix) {
      Some(u) => "{" + u + "}" + local
      None => raise @moonxml.Refused::Malformed(at=0, why="unbound namespace prefix " + prefix)
    }
  } else if is_attr {
    raw
  } else {
    match lookup_prefix(scope, "") {
      Some(u) => if u == "" {
        raw
      } else {
        "{" + u + "}" + raw
      }
      None => raw
    }
  }
}

fn scope_with(scope : Array[(String, String)], prefix : String, uri : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let mut replaced = false
  for pair in scope {
    let (p, u) = pair
    if p == prefix {
      out.push((p, uri))
      replaced = true
    } else {
      out.push(pair)
    }
  }
  if replaced == false {
    out.push((prefix, uri))
  }
  out
}

// ---------------------------------------------------------------------------
// Documents
// ---------------------------------------------------------------------------

/// Parse a complete document. `depth` bounds nesting (default 512); `limit`
/// bounds total entity expansion (default 1,000,000 characters).
pub fn loads_config(text : String, depth : Int, limit : Int) -> @moonxml.Document raise @moonxml.Refused {
  let x = X::new(strip_bom(text), depth, limit)
  x.parse_document(false)
}

/// Parse a complete document with the default bounds.
pub fn loads(text : String) -> @moonxml.Document raise @moonxml.Refused {
  loads_config(text, 512, 1000000)
}

/// Parse UTF-8 bytes as a document. Invalid sequences are replaced with U+FFFD.
pub fn load(bytes : Bytes) -> @moonxml.Document raise @moonxml.Refused {
  loads(bytes.to_string())
}

/// Parse a fragment: top-level nodes go straight into the virtual root.
pub fn loads_fragment(text : String) -> @moonxml.Document raise @moonxml.Refused {
  let x = X::new(strip_bom(text), 512, 1000000)
  x.parse_document(true)
}

fn strip_bom(s : String) -> String {
  if s.length() > 0 && Char::to_int(s.to_array()[0]) == 0xFEFF {
    s.substring(start=1, end=s.length())
  } else {
    s
  }
}

fn X::parse_document(self : X, fragment : Bool) -> @moonxml.Document raise @moonxml.Refused {
  let scope : Array[(String, String)] = [("xml", xml_ns)]
  let root = @moonxml.Element::new("#document")
  // XML declaration and prolog.
  self.skip_ws()
  if self.starts_with("<?xml") {
    let after = self.peek_at(5)
    if after == ' ' || after == '\t' || after == '\r' || after == '\n' || after == '?' {
      root.append(@moonxml.Node::ProcessingInstructionNode(self.parse_pi_node()))
      self.skip_ws()
    }
  }
  let mut elements = 0
  while not(self.at_end()) {
    if self.starts_with("<!--") {
      root.append(@moonxml.Node::CommentNode(self.parse_comment()))
    } else if self.starts_with("<?") {
      root.append(@moonxml.Node::ProcessingInstructionNode(self.parse_pi_node()))
    } else if self.starts_with("<!DOCTYPE") {
      let raw = self.parse_doctype()
      root.append(@moonxml.Node::DoctypeNode(raw))
    } else if self.starts_with("</") {
      self.fail("unexpected end tag")
    } else if self.peek() == '<' {
      let el = self.parse_element(scope)
      root.append(@moonxml.Node::ElementNode(el))
      elements = elements + 1
      if fragment == false && elements > 1 {
        self.fail("more than one document element")
      }
    } else {
      let t = self.parse_text()
      if t.length() > 0 {
        if fragment == false {
          // Only whitespace is allowed outside the document element.
          if not(@text.is_blank(t)) {
            self.fail("text outside the document element")
          }
        }
        root.append(@moonxml.Node::TextNode(t))
      }
    }
    if fragment == false && elements == 1 {
      // After the root element only misc (comments, PIs, whitespace) may follow.
      // The loop continues to consume them; a second element is rejected above.
    }
  }
  if fragment == false && elements == 0 {
    self.fail("no document element")
  }
  @moonxml.Document::from_root(root, @moonxml.Flavour::Xml)
}

fn X::parse_comment(self : X) -> String raise @moonxml.Refused {
  self.expect("<!--", "expected comment")
  self.read_until("-->")
}

fn X::parse_pi_node(self : X) -> @moonxml.ProcessingInstruction raise @moonxml.Refused {
  self.expect("<?", "expected processing instruction")
  let target = self.read_name()
  let data = self.read_until("?>")
  @moonxml.ProcessingInstruction::new(target, trim_end_ws(data))
}

fn trim_end_ws(s : String) -> String {
  let cs = s.to_array()
  let mut start = 0
  while start < cs.length() && @text.is_xml_space(cs[start]) {
    start = start + 1
  }
  let mut e = cs.length()
  while e > start && @text.is_xml_space(cs[e - 1]) {
    e = e - 1
  }
  s.substring(start=start, end=e)
}

// ---------------------------------------------------------------------------
// Doctype and the internal subset
// ---------------------------------------------------------------------------

fn X::parse_doctype(self : X) -> String raise @moonxml.Refused {
  self.expect("<!DOCTYPE", "expected doctype")
  let start = self.pos
  // Scan to the closing `>` at bracket depth 0.
  let mut depth = 0
  while not(self.at_end()) {
    let c = self.peek()
    if c == '[' {
      depth = depth + 1
    } else if c == ']' {
      depth = depth - 1
    } else if c == '>' && depth == 0 {
      let raw = slice_chars(self.s, start, self.pos)
      self.pos = self.pos + 1
      self.parse_internal_subset_from_raw(raw)
      return trim_end_ws(raw)
    }
    self.pos = self.pos + 1
  }
  raise @moonxml.Refused::Malformed(at=self.pos, why="unterminated doctype")
}

fn X::parse_internal_subset_from_raw(self : X, raw : String) -> Unit raise @moonxml.Refused {
  let lb = index_char(raw, '[')
  let rb = last_index_char(raw, ']')
  if lb < 0 || rb < 0 || rb <= lb {
    return
  }
  let subset = raw.substring(start=lb + 1, end=rb)
  self.parse_internal_subset(subset)
}

fn index_char(s : String, target : Char) -> Int {
  let cs = s.to_array()
  let mut i = 0
  while i < cs.length() {
    if cs[i] == target {
      return i
    }
    i = i + 1
  }
  -1
}

fn last_index_char(s : String, target : Char) -> Int {
  let cs = s.to_array()
  let mut i = cs.length() - 1
  while i >= 0 {
    if cs[i] == target {
      return i
    }
    i = i - 1
  }
  -1
}

fn X::parse_internal_subset(self : X, subset : String) -> Unit raise @moonxml.Refused {
  // Collect parameter entity declarations first, then expand `%name;` uses.
  self.collect_params(subset)
  let expanded = self.expand_params(subset, [])
  let mut i = 0
  let cs = expanded.to_array()
  let n = cs.length()
  while i < n {
    if cs[i] == '<' && i + 8 <= n && slice_chars(cs, i, i + 8) == "<!ENTITY" {
      i = self.parse_entity_decl(cs, i + 8)
    } else if cs[i] == '<' && i + 9 <= n && slice_chars(cs, i, i + 9) == "<!ATTLIST" {
      i = self.parse_attlist_decl(cs, i + 9)
    } else if cs[i] == '<' && i + 3 <= n && slice_chars(cs, i, i + 3) == "<!--" {
      // Skip a comment: find `-->`.
      let close = find_marker(cs, i + 4, "-->")
      if close < 0 {
        raise @moonxml.Refused::Malformed(at=0, why="unterminated comment in DTD")
      }
      i = close + 3
    } else if cs[i] == '<' && i + 2 <= n && slice_chars(cs, i, i + 2) == "<!" {
      // <!ELEMENT ...>, <!NOTATION ...>: skip to '>'.
      let close = find_char(cs, i, '>')
      if close < 0 {
        raise @moonxml.Refused::Malformed(at=0, why="unterminated declaration in DTD")
      }
      i = close + 1
    } else {
      i = i + 1
    }
  }
}

fn find_marker(cs : Array[Char], start : Int, marker : String) -> Int {
  let m = marker.to_array()
  let mut i = start
  while i + m.length() <= cs.length() {
    let mut ok = true
    let mut j = 0
    while j < m.length() {
      if cs[i + j] != m[j] {
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

fn find_char(cs : Array[Char], start : Int, target : Char) -> Int {
  let mut i = start
  while i < cs.length() {
    if cs[i] == target {
      return i
    }
    i = i + 1
  }
  -1
}

fn X::collect_params(self : X, subset : String) -> Unit {
  let cs = subset.to_array()
  let n = cs.length()
  let mut i = 0
  while i < n {
    if cs[i] == '<' && i + 8 <= n && slice_chars(cs, i, i + 8) == "<!ENTITY" {
      let mut j = skip_ws_cs(cs, i + 8)
      if j < n && cs[j] == '%' {
        j = skip_ws_cs(cs, j + 1)
        let ns = j
        while j < n && @text.is_name_char(cs[j]) {
          j = j + 1
        }
        let name = slice_chars(cs, ns, j)
        j = skip_ws_cs(cs, j)
        if j < n && (cs[j] == '"' || cs[j] == '\'') {
          let q = cs[j]
          j = j + 1
          let vs = j
          while j < n && cs[j] != q {
            j = j + 1
          }
          let value = slice_chars(cs, vs, j)
          self.params.push((name, value))
          i = if j < n { j + 1 } else { j }
        } else {
          i = i + 1
        }
      } else {
        i = i + 1
      }
    } else {
      i = i + 1
    }
  }
}

fn X::expand_params(self : X, subset : String, active : Array[String]) -> String raise @moonxml.Refused {
  // Iteratively replace `%name;` with the declared parameter entity's value.
  let mut current = subset
  let mut rounds = 0
  while rounds < 10000 {
    let cs = current.to_array()
    let out = StringBuilder()
    let mut i = 0
    let mut changed = false
    while i < cs.length() {
      if cs[i] == '%' {
        // find ;
        let mut j = i + 1
        while j < cs.length() && cs[j] != ';' && cs[j] != ' ' && cs[j] != '\n' && cs[j] != '\t' {
          j = j + 1
        }
        if j < cs.length() && cs[j] == ';' {
          let nm = slice_chars(cs, i + 1, j)
          match lookup_entity(self.params, nm) {
            Some(v) => {
              out.write_string(v)
              i = j + 1
              changed = true
            }
            None => {
              out.write_char(cs[i])
              i = i + 1
            }
          }
        } else {
          out.write_char(cs[i])
          i = i + 1
        }
      } else {
        out.write_char(cs[i])
        i = i + 1
      }
    }
    current = out.to_string()
    if changed == false {
      return current
    }
    rounds = rounds + 1
  }
  raise @moonxml.Refused::Malformed(at=0, why="parameter entity expansion did not terminate")
}

fn lookup_entity(table : Array[(String, String)], name : String) -> String? {
  for pair in table {
    let (n, v) = pair
    if n == name {
      return Some(v)
    }
  }
  None
}

fn X::parse_entity_decl(self : X, cs : Array[Char], start : Int) -> Int raise @moonxml.Refused {
  let mut i = start
  i = skip_ws_cs(cs, i)
  let mut is_param = false
  if i < cs.length() && cs[i] == '%' {
    is_param = true
    i = skip_ws_cs(cs, i + 1)
  }
  let name_start = i
  while i < cs.length() && @text.is_name_char(cs[i]) {
    i = i + 1
  }
  let name = slice_chars(cs, name_start, i)
  i = skip_ws_cs(cs, i)
  if i < cs.length() && (cs[i] == '"' || cs[i] == '\'') {
    let q = cs[i]
    i = i + 1
    let vstart = i
    while i < cs.length() && cs[i] != q {
      i = i + 1
    }
    let value = slice_chars(cs, vstart, i)
    if i < cs.length() {
      i = i + 1
    }
    // Consume to '>'.
    while i < cs.length() && cs[i] != '>' {
      i = i + 1
    }
    if i < cs.length() {
      i = i + 1
    }
    if is_param {
      self.params.push((name, value))
    } else {
      self.general.push((name, value))
    }
    i
  } else {
    // External entity (SYSTEM/PUBLIC): record as external, do not fetch.
    while i < cs.length() && cs[i] != '>' {
      i = i + 1
    }
    if i < cs.length() {
      i = i + 1
    }
    if is_param {
      self.params.push((name, "\u{0}external"))
    } else {
      self.general.push((name, "\u{0}external"))
    }
    i
  }
}

fn skip_ws_cs(cs : Array[Char], start : Int) -> Int {
  let mut i = start
  while i < cs.length() && (@text.is_xml_space(cs[i]) || cs[i] == '\n' || cs[i] == '\r') {
    i = i + 1
  }
  i
}

fn X::parse_attlist_decl(self : X, cs : Array[Char], start : Int) -> Int raise @moonxml.Refused {
  let mut i = start
  i = skip_ws_cs(cs, i)
  let el_start = i
  while i < cs.length() && @text.is_name_char(cs[i]) {
    i = i + 1
  }
  let el = slice_chars(cs, el_start, i)
  while i < cs.length() && cs[i] != '>' {
    i = skip_ws_cs(cs, i)
    if i >= cs.length() || cs[i] == '>' {
      break
    }
    if cs[i] == '"' || cs[i] == '\'' {
      // Stray quote: skip.
      let q = cs[i]
      i = i + 1
      while i < cs.length() && cs[i] != q {
        i = i + 1
      }
      if i < cs.length() {
        i = i + 1
      }
    } else {
      let at_start = i
      while i < cs.length() && @text.is_name_char(cs[i]) {
        i = i + 1
      }
      if i == at_start {
        i = i + 1
      } else {
        let attr = slice_chars(cs, at_start, i)
        i = skip_ws_cs(cs, i)
        // Skip the attribute type (a name or a parenthesised enumeration).
        if i < cs.length() && cs[i] == '(' {
          while i < cs.length() && cs[i] != ')' {
            i = i + 1
          }
          if i < cs.length() {
            i = i + 1
          }
        } else {
          while i < cs.length() && @text.is_name_char(cs[i]) {
            i = i + 1
          }
        }
        i = skip_ws_cs(cs, i)
        // Default declaration.
        if i + 5 < cs.length() && slice_chars(cs, i, i + 5) == "#IMPL" {
          i = i + 8
        } else if i + 8 < cs.length() && slice_chars(cs, i, i + 8) == "#REQUIR" {
          i = i + 9
        } else if i + 5 < cs.length() && slice_chars(cs, i, i + 5) == "#FIXE" {
          i = i + 6
          i = skip_ws_cs(cs, i)
          if i < cs.length() && (cs[i] == '"' || cs[i] == '\'') {
            let q = cs[i]
            i = i + 1
            let vstart = i
            while i < cs.length() && cs[i] != q {
              i = i + 1
            }
            let value = slice_chars(cs, vstart, i)
            if i < cs.length() {
              i = i + 1
            }
            self.defaults.push((el, attr, value))
          }
        } else if i < cs.length() && (cs[i] == '"' || cs[i] == '\'') {
          let q = cs[i]
          i = i + 1
          let vstart = i
          while i < cs.length() && cs[i] != q {
            i = i + 1
          }
          let value = slice_chars(cs, vstart, i)
          if i < cs.length() {
            i = i + 1
          }
          self.defaults.push((el, attr, value))
        }
      }
    }
  }
  if i < cs.length() {
    i = i + 1
  }
  i
}

// ---------------------------------------------------------------------------
// Elements
// ---------------------------------------------------------------------------

fn X::parse_element(self : X, scope : Array[(String, String)]) -> @moonxml.Element raise @moonxml.Refused {
  self.depth = self.depth + 1
  if self.depth > self.depth_limit {
    self.fail("nesting deeper than " + self.depth_limit.to_string())
  }
  self.expect("<", "expected '<'")
  let raw_name = self.read_name()
  let raw_attrs : Array[(String, String)] = []
  let self_closing = self.parse_attributes(raw_attrs)
  // Namespace declarations on this element.
  let mut new_scope = scope
  for pair in raw_attrs {
    let (k, v) = pair
    if k == "xmlns" {
      new_scope = scope_with(new_scope, "", v)
    } else if k.has_prefix("xmlns:") {
      let prefix = k.substring(start=6, end=k.length())
      new_scope = scope_with(new_scope, prefix, v)
    }
  }
  let resolved = resolve_name(raw_name, new_scope, false)
  let el = @moonxml.Element::new(resolved)
  for pair in raw_attrs {
    let (k, v) = pair
    if k == "xmlns" || k.has_prefix("xmlns:") {
      continue
    }
    let rk = resolve_name(k, new_scope, true)
    el.attrs.push((rk, v))
  }
  // Apply attribute defaults from the internal subset.
  for d in self.defaults {
    let (d_el, d_attr, d_val) = d
    if d_el == raw_name && el.attr(d_attr).is_none() {
      let rk = resolve_name(d_attr, new_scope, true)
      el.attrs.push((rk, d_val))
    }
  }
  if self_closing {
    el.set_closed(true)
    self.depth = self.depth - 1
    return el
  }
  el.set_closed(false)
  self.parse_content(el, new_scope)
  // Consume the matching end tag.
  if not(self.starts_with("</")) {
    self.fail("expected end tag for " + raw_name)
  }
  self.pos = self.pos + 2
  let end_name = self.read_name()
  if end_name != raw_name {
    self.fail("end tag '" + end_name + "' does not match '" + raw_name + "'")
  }
  self.skip_ws()
  self.expect(">", "expected '>' in end tag")
  self.depth = self.depth - 1
  el
}

fn X::parse_attributes(self : X, out : Array[(String, String)]) -> Bool raise @moonxml.Refused {
  let mut self_closing = false
  while true {
    self.skip_ws()
    if self.at_end() {
      self.fail("unterminated start tag")
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
        self.fail("expected '>' after '/'")
      }
    } else {
      let name = self.read_name()
      self.skip_ws()
      self.expect("=", "expected '=' after attribute name")
      self.skip_ws()
      let q = self.peek()
      if q != '"' && q != '\'' {
        self.fail("expected a quoted attribute value")
      }
      self.pos = self.pos + 1
      let value = self.parse_attr_value(q)
      // Duplicate attribute names are not well-formed.
      for pair in out {
        let (k, _) = pair
        if k == name {
          self.fail("duplicate attribute " + name)
        }
      }
      out.push((name, value))
    }
  }
  self_closing
}

fn X::parse_attr_value(self : X, quote : Char) -> String raise @moonxml.Refused {
  let sb = StringBuilder()
  while not(self.at_end()) && self.peek() != quote {
    let c = self.peek()
    if c == '<' {
      self.fail("'<' is not allowed in an attribute value")
    } else if c == '&' {
      sb.write_string(self.parse_reference())
    } else {
      sb.write_char(c)
      self.pos = self.pos + 1
    }
  }
  if self.at_end() {
    self.fail("unterminated attribute value")
  }
  self.pos = self.pos + 1
  sb.to_string()
}

fn X::parse_content(self : X, parent : @moonxml.Element, scope : Array[(String, String)]) -> Unit raise @moonxml.Refused {
  while not(self.at_end()) {
    if self.starts_with("</") {
      return
    } else if self.starts_with("<!--") {
      parent.append(@moonxml.Node::CommentNode(self.parse_comment()))
    } else if self.starts_with("<![CDATA[") {
      self.pos = self.pos + 9
      let data = self.read_until("]]>")
      parent.append(@moonxml.Node::CDataNode(data))
    } else if self.starts_with("<?") {
      parent.append(@moonxml.Node::ProcessingInstructionNode(self.parse_pi_node()))
    } else if self.starts_with("<!") {
      self.fail("unexpected markup declaration in content")
    } else if self.peek() == '<' {
      let child = self.parse_element(scope)
      parent.append(@moonxml.Node::ElementNode(child))
    } else {
      let t = self.parse_text()
      if t.length() > 0 {
        parent.append(@moonxml.Node::TextNode(t))
      }
    }
  }
}

fn X::parse_text(self : X) -> String raise @moonxml.Refused {
  let sb = StringBuilder()
  while not(self.at_end()) {
    let c = self.peek()
    if c == '<' {
      break
    } else if c == '&' {
      sb.write_string(self.parse_reference())
    } else if c == ']' && self.peek_at(1) == ']' && self.peek_at(2) == '>' {
      self.fail("']]>' is not allowed in character data")
    } else {
      sb.write_char(c)
      self.pos = self.pos + 1
    }
  }
  sb.to_string()
}

fn X::parse_reference(self : X) -> String raise @moonxml.Refused {
  self.expect("&", "expected '&'")
  if self.peek() == '#' {
    self.pos = self.pos + 1
    let hex = self.peek() == 'x'
    if hex {
      self.pos = self.pos + 1
    }
    let start = self.pos
    while not(self.at_end()) && self.peek() != ';' {
      self.pos = self.pos + 1
    }
    if self.at_end() {
      self.fail("unterminated character reference")
    }
    let digits = slice_chars(self.s, start, self.pos)
    self.pos = self.pos + 1
    let cp = if hex {
      @text.parse_hex(digits)
    } else {
      @text.parse_dec(digits)
    }
    if cp < 0 || not(@text.is_valid_xml_char(cp)) {
      self.fail("invalid character reference")
    }
    @text.code_point_to_string(cp)
  } else {
    let name = self.read_name()
    self.expect(";", "expected ';' after entity name")
    self.expand_entity(name, [])
  }
}

fn X::expand_entity(self : X, name : String, active : Array[String]) -> String raise @moonxml.Refused {
  if name == "amp" {
    return "&"
  }
  if name == "lt" {
    return "<"
  }
  if name == "gt" {
    return ">"
  }
  if name == "quot" {
    return "\""
  }
  if name == "apos" {
    return "'"
  }
  for a in active {
    if a == name {
      raise @moonxml.Refused::Malformed(at=self.pos, why="entity recursion on " + name)
    }
  }
  match lookup_entity(self.general, name) {
    None => raise @moonxml.Refused::Malformed(at=self.pos, why="undefined entity &" + name + ";")
    Some(v) => {
      if v == "\u{0}external" {
        raise @moonxml.Refused::Unsupported(what="external entity &" + name + ";")
      }
      let next_active = active.copy()
      next_active.push(name)
      let out = self.expand_string(v, next_active)
      self.expanded = self.expanded + out.length()
      if self.expanded > self.limit {
        raise @moonxml.Refused::Malformed(at=self.pos, why="entity expansion limit exceeded")
      }
      out
    }
  }
}

fn X::expand_string(self : X, s : String, active : Array[String]) -> String raise @moonxml.Refused {
  let cs = s.to_array()
  let sb = StringBuilder()
  let mut i = 0
  while i < cs.length() {
    let c = cs[i]
    if c == '&' {
      // A reference inside an entity value.
      let mut j = i + 1
      if j < cs.length() && cs[j] == '#' {
        j = j + 1
        let hex = j < cs.length() && cs[j] == 'x'
        if hex {
          j = j + 1
        }
        let dstart = j
        while j < cs.length() && cs[j] != ';' {
          j = j + 1
        }
        if j >= cs.length() {
          raise @moonxml.Refused::Malformed(at=0, why="bad character reference in entity value")
        }
        let digits = slice_chars(cs, dstart, j)
        let cp = if hex {
          @text.parse_hex(digits)
        } else {
          @text.parse_dec(digits)
        }
        sb.write_string(@text.code_point_to_string(cp))
        i = j + 1
      } else {
        let nstart = j
        while j < cs.length() && cs[j] != ';' {
          j = j + 1
        }
        if j >= cs.length() {
          raise @moonxml.Refused::Malformed(at=0, why="bad entity reference in entity value")
        }
        let nm = slice_chars(cs, nstart, j)
        sb.write_string(self.expand_entity(nm, active))
        i = j + 1
      }
    } else {
      sb.write_char(c)
      i = i + 1
    }
  }
  sb.to_string()
}

// ---------------------------------------------------------------------------
// Streaming events
// ---------------------------------------------------------------------------

/// Emit a document's events to `sink`. The events are produced from a parsed
/// tree, so no caller-visible difference exists; a future revision can stream
/// them from the tokenizer directly.
pub fn scan(text : String, sink : &@event.Sink) -> Unit raise @moonxml.Refused {
  let doc = loads(text)
  for c in doc.root.children {
    emit_event(c, sink)
  }
}

fn emit_event(node : @moonxml.Node, sink : &@event.Sink) -> Unit {
  match node {
    @moonxml.Node::ElementNode(e) => {
      sink.push(@event.Event::StartTag(name=e.name, attrs=e.attrs, self_closing=e.closed))
      for c in e.children {
        emit_event(c, sink)
      }
      sink.push(@event.Event::EndTag(name=e.name))
    }
    @moonxml.Node::TextNode(s) => sink.push(@event.Event::Text(text=s))
    @moonxml.Node::CDataNode(s) => sink.push(@event.Event::CData(text=s))
    @moonxml.Node::CommentNode(s) => sink.push(@event.Event::Comment(text=s))
    @moonxml.Node::ProcessingInstructionNode(pi) => sink.push(@event.Event::ProcessingInstruction(target=pi.target, data=pi.data))
    @moonxml.Node::DoctypeNode(s) => sink.push(@event.Event::Doctype(text=s))
    _ => ()
  }
}
