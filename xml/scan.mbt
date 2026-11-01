/// Streaming XML events, tokenizer-level: `scan` emits events as it reads and
/// never builds a tree, so a very large document is consumed incrementally.
///
/// Names are resolved to `{uri}local` exactly as the tree parser does, so the
/// two reads agree. General entities declared in the internal subset expand with
/// recursion detection and the same expansion budget. Parameter entities and
/// attribute defaults are a tree-building concern and are handled by `loads`.

struct XScan {
  src : Array[Char]
  len : Int
  mut pos : Int
  general : Array[(String, String)]
  limit : Int
  mut expanded : Int
}

/// Stream the events of `text` to `sink`, without materialising a tree.
pub fn scan(text : String, sink : &@event.Sink) -> Unit raise @moonxml.Refused {
  let sc = XScan::new(strip_bom(text), 1000000)
  let scope : Array[(String, String)] = [("xml", xml_ns)]
  sc.skip_ws()
  if sc.starts_with("<?xml") {
    let after = sc.peek_at(5)
    if after == ' ' || after == '\t' || after == '\r' || after == '\n' || after == '?' {
      sc.parse_pi(sink)
      sc.skip_ws()
    }
  }
  while not(sc.at_end()) {
    if sc.starts_with("<!--") {
      sc.pos = sc.pos + 4
      let text = sc.read_until("-->")
      sink.push(@event.Event::Comment(text=text))
    } else if sc.starts_with("<?") {
      sc.parse_pi(sink)
    } else if sc.starts_with("<!DOCTYPE") {
      sc.parse_doctype(sink)
    } else if sc.starts_with("</") {
      sc.fail("unexpected end tag")
    } else if sc.peek() == '<' {
      sc.parse_element(scope, sink)
    } else {
      let t = sc.parse_text()
      if t.length() > 0 {
        sink.push(@event.Event::Text(text=t))
      }
    }
  }
}

fn XScan::new(s : String, limit : Int) -> XScan {
  { src: s.to_array(), len: s.length(), pos: 0, general: [], limit, expanded: 0 }
}

fn XScan::at_end(self : XScan) -> Bool {
  self.pos >= self.len
}

fn XScan::peek(self : XScan) -> Char {
  if self.pos < self.len {
    self.src[self.pos]
  } else {
    '\u{0}'
  }
}

fn XScan::peek_at(self : XScan, k : Int) -> Char {
  let i = self.pos + k
  if i < self.len {
    self.src[i]
  } else {
    '\u{0}'
  }
}

fn XScan::starts_with(self : XScan, lit : String) -> Bool {
  let l = lit.to_array()
  if self.pos + l.length() > self.len {
    return false
  }
  let mut i = 0
  while i < l.length() {
    if self.src[self.pos + i] != l[i] {
      return false
    }
    i = i + 1
  }
  true
}

fn XScan::skip_ws(self : XScan) -> Unit {
  while self.pos < self.len && @text.is_xml_space(self.src[self.pos]) {
    self.pos = self.pos + 1
  }
}

fn XScan::fail(self : XScan, why : String) -> Unit raise @moonxml.Refused {
  raise @moonxml.Refused::Malformed(at=self.pos, why=why)
}

fn XScan::expect(self : XScan, lit : String, why : String) -> Unit raise @moonxml.Refused {
  if self.starts_with(lit) {
    self.pos = self.pos + lit.length()
  } else {
    self.fail(why)
  }
}

fn XScan::read_name(self : XScan) -> String raise @moonxml.Refused {
  if not(@text.is_name_start_char(self.peek())) {
    self.fail("expected a name")
  }
  let sb = StringBuilder()
  while self.pos < self.len && @text.is_name_char(self.src[self.pos]) {
    sb.write_char(self.src[self.pos])
    self.pos = self.pos + 1
  }
  sb.to_string()
}

fn XScan::read_until(self : XScan, marker : String) -> String raise @moonxml.Refused {
  let start = self.pos
  let m = marker.to_array()
  while self.pos + m.length() <= self.len {
    let mut ok = true
    let mut j = 0
    while j < m.length() {
      if self.src[self.pos + j] != m[j] {
        ok = false
        break
      }
      j = j + 1
    }
    if ok {
      let out = slice_chars(self.src, start, self.pos)
      self.pos = self.pos + m.length()
      return out
    }
    self.pos = self.pos + 1
  }
  raise @moonxml.Refused::Malformed(at=self.pos, why="unterminated construct, expected " + marker)
}

fn XScan::parse_pi(self : XScan, sink : &@event.Sink) -> Unit raise @moonxml.Refused {
  self.expect("<?", "expected processing instruction")
  let target = self.read_name()
  let data = self.read_until("?>")
  sink.push(@event.Event::ProcessingInstruction(target=target, data=trim_end_ws(data)))
}

fn XScan::parse_doctype(self : XScan, sink : &@event.Sink) -> Unit raise @moonxml.Refused {
  self.expect("<!DOCTYPE", "expected doctype")
  let start = self.pos
  let mut depth = 0
  while not(self.at_end()) {
    let c = self.peek()
    if c == '[' {
      depth = depth + 1
    } else if c == ']' {
      depth = depth - 1
    } else if c == '>' && depth == 0 {
      let raw = slice_chars(self.src, start, self.pos)
      self.pos = self.pos + 1
      self.collect_general(raw)
      sink.push(@event.Event::Doctype(text=trim_end_ws(raw)))
      return
    }
    self.pos = self.pos + 1
  }
  self.fail("unterminated doctype")
}

fn XScan::collect_general(self : XScan, raw : String) -> Unit {
  let lb = index_char(raw, '[')
  let rb = last_index_char(raw, ']')
  if lb < 0 || rb <= lb {
    return
  }
  let subset = raw.substring(start=lb + 1, end=rb)
  let cs = subset.to_array()
  let n = cs.length()
  let mut i = 0
  while i < n {
    if cs[i] == '<' && i + 8 <= n && slice_chars(cs, i, i + 8) == "<!ENTITY" {
      let mut j = skip_ws_cs(cs, i + 8)
      if j < n && cs[j] == '%' {
        // Parameter entities are a tree-building concern; skip the declaration.
        while j < n && cs[j] != '>' {
          j = j + 1
        }
        i = if j < n { j + 1 } else { j }
      } else {
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
          self.general.push((name, value))
          while j < n && cs[j] != '>' {
            j = j + 1
          }
          i = if j < n { j + 1 } else { j }
        } else {
          i = i + 1
        }
      }
    } else {
      i = i + 1
    }
  }
}

fn XScan::parse_element(self : XScan, scope : Array[(String, String)], sink : &@event.Sink) -> Unit raise @moonxml.Refused {
  self.expect("<", "expected '<'")
  let raw_name = self.read_name()
  let raw_attrs : Array[(String, String)] = []
  let self_closing = self.parse_attrs(raw_attrs)
  let mut new_scope = scope
  for pair in raw_attrs {
    let (k, v) = pair
    if k == "xmlns" {
      new_scope = scope_with(new_scope, "", v)
    } else if k.has_prefix("xmlns:") {
      new_scope = scope_with(new_scope, k.substring(start=6, end=k.length()), v)
    }
  }
  let resolved = resolve_name(raw_name, new_scope, false)
  let out_attrs : Array[(String, String)] = []
  for pair in raw_attrs {
    let (k, v) = pair
    if k == "xmlns" || k.has_prefix("xmlns:") {
      continue
    }
    out_attrs.push((resolve_name(k, new_scope, true), v))
  }
  sink.push(@event.Event::StartTag(name=resolved, attrs=out_attrs, self_closing=self_closing))
  if self_closing {
    sink.push(@event.Event::EndTag(name=resolved))
    return
  }
  self.parse_content(new_scope, sink)
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
  sink.push(@event.Event::EndTag(name=resolved))
}

fn XScan::parse_attrs(self : XScan, out : Array[(String, String)]) -> Bool raise @moonxml.Refused {
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
      out.push((name, value))
    }
  }
  self_closing
}

fn XScan::parse_attr_value(self : XScan, quote : Char) -> String raise @moonxml.Refused {
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

fn XScan::parse_content(self : XScan, scope : Array[(String, String)], sink : &@event.Sink) -> Unit raise @moonxml.Refused {
  while not(self.at_end()) {
    if self.starts_with("</") {
      return
    } else if self.starts_with("<!--") {
      self.pos = self.pos + 4
      sink.push(@event.Event::Comment(text=self.read_until("-->")))
    } else if self.starts_with("<![CDATA[") {
      self.pos = self.pos + 9
      sink.push(@event.Event::CData(text=self.read_until("]]>")))
    } else if self.starts_with("<?") {
      self.parse_pi(sink)
    } else if self.starts_with("<!") {
      self.fail("unexpected markup declaration in content")
    } else if self.peek() == '<' {
      self.parse_element(scope, sink)
    } else {
      let t = self.parse_text()
      if t.length() > 0 {
        sink.push(@event.Event::Text(text=t))
      }
    }
  }
}

fn XScan::parse_text(self : XScan) -> String raise @moonxml.Refused {
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

fn XScan::parse_reference(self : XScan) -> String raise @moonxml.Refused {
  self.pos = self.pos + 1
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
    let digits = slice_chars(self.src, start, self.pos)
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

fn XScan::expand_entity(self : XScan, name : String, active : Array[String]) -> String raise @moonxml.Refused {
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

fn XScan::expand_string(self : XScan, s : String, active : Array[String]) -> String raise @moonxml.Refused {
  let cs = s.to_array()
  let sb = StringBuilder()
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '&' {
      let mut j = i + 1
      if j < cs.length() && cs[j] == '#' {
        j = j + 1
        let hex = j < cs.length() && cs[j] == 'x'
        if hex {
          j = j + 1
        }
        let ds = j
        while j < cs.length() && cs[j] != ';' {
          j = j + 1
        }
        if j >= cs.length() {
          raise @moonxml.Refused::Malformed(at=0, why="bad character reference in entity value")
        }
        let digits = slice_chars(cs, ds, j)
        let cp = if hex {
          @text.parse_hex(digits)
        } else {
          @text.parse_dec(digits)
        }
        sb.write_string(@text.code_point_to_string(cp))
        i = j + 1
      } else {
        let ns = j
        while j < cs.length() && cs[j] != ';' {
          j = j + 1
        }
        if j >= cs.length() {
          raise @moonxml.Refused::Malformed(at=0, why="bad entity reference in entity value")
        }
        let nm = slice_chars(cs, ns, j)
        sb.write_string(self.expand_entity(nm, active))
        i = j + 1
      }
    } else {
      sb.write_char(cs[i])
      i = i + 1
    }
  }
  sb.to_string()
}
