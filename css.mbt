/// CSS selectors: the statically decidable part of Selectors Level 4.
///
/// Supported: type and universal selectors; `#id`; `.class`; attribute
/// selectors (`[a]`, `[a=v]`, `[a~=v]`, `[a|=v]`, `[a^=v]`, `[a$=v]`,
/// `[a*=v]`, `[a!=v]`); the four combinators; structural pseudo-classes
/// (`:first-child`, `:last-child`, `:only-child`, the `-of-type` family, and
/// `:nth-*` with an optional `of S`); `:root`, `:empty`; and the functional
/// `:not`, `:is`, `:where`, `:has`. Dynamic pseudo-classes (`:hover`, `:focus`)
/// are a parse error naming the pseudo-class, not a silent miss.

enum Combinator {
  Descendant
  Child
  Adjacent
  Sibling
}

struct AttrSel {
  name : String
  op : String
  value : String
}

struct Compound {
  universal : Bool
  tag : String?
  ids : Array[String]
  classes : Array[String]
  attrs : Array[AttrSel]
  pseudos : Array[Pseudo]
}

struct Complex {
  parts : Array[(Combinator, Compound)]
}

enum Pseudo {
  FirstChild
  LastChild
  OnlyChild
  FirstOfType
  LastOfType
  OnlyOfType
  NthChild(Int, Int, Array[Complex])
  NthLastChild(Int, Int, Array[Complex])
  NthOfType(Int, Int)
  NthLastOfType(Int, Int)
  Root
  Empty
  Not(Array[Complex])
  Is(Array[Complex])
  Where(Array[Complex])
  Has(Array[Complex], Bool)
}

struct P {
  chars : Array[Char]
  mut pos : Int
  end : Int
}

fn P::at_end(self : P) -> Bool {
  self.pos >= self.end
}

fn P::peek(self : P) -> Char {
  if self.pos < self.end {
    self.chars[self.pos]
  } else {
    '\u{0}'
  }
}

fn P::peek_at(self : P, n : Int) -> Char {
  let i = self.pos + n
  if i < self.end {
    self.chars[i]
  } else {
    '\u{0}'
  }
}

fn css_ws(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\u{0C}'
}

fn P::skip_ws(self : P) -> Unit {
  while self.pos < self.end && css_ws(self.chars[self.pos]) {
    self.pos = self.pos + 1
  }
}

fn P::advance_ws(self : P) -> Bool {
  let start = self.pos
  self.skip_ws()
  self.pos > start
}

fn ident_start(c : Char) -> Bool {
  if c >= 'a' && c <= 'z' {
    return true
  }
  if c >= 'A' && c <= 'Z' {
    return true
  }
  if c == '_' || c == '-' {
    return true
  }
  if Char::to_int(c) >= 0x80 {
    return true
  }
  false
}

fn ident_char(c : Char) -> Bool {
  ident_start(c) || (c >= '0' && c <= '9')
}

fn is_attr_op_char(c : Char) -> Bool {
  c == '~' || c == '|' || c == '^' || c == '$' || c == '*' || c == '!'
}

fn P::parse_ident(self : P) -> String raise Refused {
  let sb = StringBuilder()
  while self.pos < self.end && ident_char(self.chars[self.pos]) {
    sb.write_char(self.chars[self.pos])
    self.pos = self.pos + 1
  }
  if sb.to_string().length() == 0 {
    raise Refused::BadQuery(at=self.pos, why="expected an identifier")
  }
  sb.to_string()
}

fn P::parse_string(self : P) -> String raise Refused {
  let quote = self.chars[self.pos]
  self.pos = self.pos + 1
  let sb = StringBuilder()
  while self.pos < self.end && self.chars[self.pos] != quote {
    if self.chars[self.pos] == '\\' && self.pos + 1 < self.end {
      self.pos = self.pos + 1
      sb.write_char(self.chars[self.pos])
      self.pos = self.pos + 1
    } else {
      sb.write_char(self.chars[self.pos])
      self.pos = self.pos + 1
    }
  }
  if self.pos >= self.end {
    raise Refused::BadQuery(at=self.pos, why="unterminated string")
  }
  self.pos = self.pos + 1
  sb.to_string()
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

fn parse_selector_list(s : String) -> Array[Complex] raise Refused {
  let p = P::{ chars: s.to_array(), pos: 0, end: s.length() }
  p.skip_ws()
  if p.at_end() {
    raise Refused::BadQuery(at=0, why="empty selector")
  }
  let out : Array[Complex] = []
  while true {
    out.push(parse_complex(p))
    p.skip_ws()
    if p.at_end() {
      break
    }
    if p.peek() == ',' {
      p.pos = p.pos + 1
      p.skip_ws()
      if p.at_end() {
        raise Refused::BadQuery(at=p.pos, why="trailing comma")
      }
    } else {
      raise Refused::BadQuery(at=p.pos, why="expected ','")
    }
  }
  out
}

fn parse_complex(p : P) -> Complex raise Refused {
  let parts : Array[(Combinator, Compound)] = []
  parts.push((Combinator::Descendant, parse_compound(p)))
  while true {
    let had_ws = p.advance_ws()
    if p.at_end() || p.peek() == ',' || p.peek() == ')' {
      break
    }
    let c = p.peek()
    let mut comb = Combinator::Descendant
    if c == '>' || c == '+' || c == '~' {
      p.pos = p.pos + 1
      comb = if c == '>' {
        Combinator::Child
      } else if c == '+' {
        Combinator::Adjacent
      } else {
        Combinator::Sibling
      }
      p.skip_ws()
    } else if had_ws == false {
      raise Refused::BadQuery(at=p.pos, why="expected a combinator")
    }
    parts.push((comb, parse_compound(p)))
  }
  Complex::{ parts }
}

fn parse_compound(p : P) -> Compound raise Refused {
  let mut universal = false
  let mut tag : String? = None
  let ids : Array[String] = []
  let classes : Array[String] = []
  let attrs : Array[AttrSel] = []
  let pseudos : Array[Pseudo] = []
  let mut any = false
  let c0 = p.peek()
  if c0 == '*' {
    universal = true
    any = true
    p.pos = p.pos + 1
  } else if ident_start(c0) {
    tag = Some(p.parse_ident())
    any = true
  }
  while true {
    if p.at_end() {
      break
    }
    let c = p.peek()
    if c == '#' {
      p.pos = p.pos + 1
      ids.push(p.parse_ident())
      any = true
    } else if c == '.' {
      p.pos = p.pos + 1
      classes.push(p.parse_ident())
      any = true
    } else if c == '[' {
      p.pos = p.pos + 1
      attrs.push(parse_attr(p))
      any = true
    } else if c == ':' {
      p.pos = p.pos + 1
      pseudos.push(parse_pseudo(p))
      any = true
    } else {
      break
    }
  }
  if any == false {
    raise Refused::BadQuery(at=p.pos, why="expected a selector")
  }
  Compound::{ universal, tag, ids, classes, attrs, pseudos }
}

fn parse_attr(p : P) -> AttrSel raise Refused {
  p.skip_ws()
  let name = p.parse_ident()
  p.skip_ws()
  let mut op = ""
  let mut value = ""
  if p.at_end() == false && p.peek() != ']' {
    let c = p.peek()
    if c == '=' {
      op = "="
      p.pos = p.pos + 1
    } else if is_attr_op_char(c) && p.peek_at(1) == '=' {
      op = c.to_string() + "="
      p.pos = p.pos + 2
    } else {
      raise Refused::BadQuery(at=p.pos, why="bad attribute operator")
    }
    p.skip_ws()
    if p.at_end() == false && (p.peek() == '"' || p.peek() == '\'') {
      value = p.parse_string()
    } else {
      value = p.parse_ident()
    }
    p.skip_ws()
  }
  if p.at_end() || p.peek() != ']' {
    raise Refused::BadQuery(at=p.pos, why="expected ']'")
  }
  p.pos = p.pos + 1
  AttrSel::{ name, op, value }
}

fn parse_paren_list(p : P) -> Array[Complex] raise Refused {
  let out : Array[Complex] = []
  p.skip_ws()
  while true {
    out.push(parse_complex(p))
    p.skip_ws()
    if p.at_end() {
      raise Refused::BadQuery(at=p.pos, why="expected ')'")
    }
    if p.peek() == ',' {
      p.pos = p.pos + 1
      p.skip_ws()
    } else if p.peek() == ')' {
      p.pos = p.pos + 1
      break
    } else {
      raise Refused::BadQuery(at=p.pos, why="expected ')'")
    }
  }
  out
}

fn parse_pseudo(p : P) -> Pseudo raise Refused {
  let name = p.parse_ident().to_lower()
  if p.at_end() == false && p.peek() == '(' {
    p.pos = p.pos + 1
    let lhs = match name {
      "not" => Pseudo::Not(parse_paren_list(p))
      "is" => Pseudo::Is(parse_paren_list(p))
      "where" => Pseudo::Where(parse_paren_list(p))
      "has" => {
        p.skip_ws()
        let mut child = false
        if p.at_end() == false && p.peek() == '>' {
          child = true
          p.pos = p.pos + 1
          p.skip_ws()
        }
        Pseudo::Has(parse_paren_list(p), child)
      }
      "nth-child" => {
        let (a, b, of) = parse_nth(p)
        Pseudo::NthChild(a, b, of)
      }
      "nth-last-child" => {
        let (a, b, of) = parse_nth(p)
        Pseudo::NthLastChild(a, b, of)
      }
      "nth-of-type" => {
        let (a, b, _) = parse_nth(p)
        Pseudo::NthOfType(a, b)
      }
      "nth-last-of-type" => {
        let (a, b, _) = parse_nth(p)
        Pseudo::NthLastOfType(a, b)
      }
      _ => raise Refused::Unsupported(what="pseudo-class :" + name)
    }
    lhs
  } else {
    match name {
      "first-child" => Pseudo::FirstChild
      "last-child" => Pseudo::LastChild
      "only-child" => Pseudo::OnlyChild
      "first-of-type" => Pseudo::FirstOfType
      "last-of-type" => Pseudo::LastOfType
      "only-of-type" => Pseudo::OnlyOfType
      "root" => Pseudo::Root
      "empty" => Pseudo::Empty
      _ => raise Refused::Unsupported(what="pseudo-class :" + name)
    }
  }
}

fn parse_nth(p : P) -> (Int, Int, Array[Complex]) raise Refused {
  let sb = StringBuilder()
  while p.at_end() == false && p.peek() != ')' {
    sb.write_char(p.peek())
    p.pos = p.pos + 1
  }
  if p.at_end() {
    raise Refused::BadQuery(at=p.pos, why="expected ')'")
  }
  p.pos = p.pos + 1
  let raw = sb.to_string()
  let mut of : Array[Complex] = []
  let mut formula = raw
  let idx = find_of(raw)
  if idx >= 0 {
    formula = raw.substring(start=0, end=idx)
    of = parse_selector_list(raw.substring(start=idx + 3, end=raw.length()))
  }
  let (a, b) = nth_formula(formula)
  (a, b, of)
}

fn find_of(s : String) -> Int {
  let cs = s.to_array()
  let n = cs.length()
  let mut i = 0
  while i + 1 < n {
    let a = cs[i]
    let b = cs[i + 1]
    if (a == 'o' || a == 'O') && (b == 'f' || b == 'F') {
      return i
    }
    i = i + 1
  }
  -1
}

fn nth_formula(s : String) -> (Int, Int) raise Refused {
  let t = trim(s).to_lower()
  if t == "odd" {
    return (2, 1)
  }
  if t == "even" {
    return (2, 0)
  }
  let n = t.length()
  if n == 0 {
    raise Refused::BadQuery(at=0, why="empty nth formula")
  }
  let mut i = 0
  let mut sign_a = 1
  if char_at(t, i) == '+' {
    i = i + 1
  } else if char_at(t, i) == '-' {
    sign_a = -1
    i = i + 1
  }
  let mut digits = ""
  while i < n && char_at(t, i) >= '0' && char_at(t, i) <= '9' {
    digits = digits + char_at(t, i).to_string()
    i = i + 1
  }
  if i < n && (char_at(t, i) == 'n' || char_at(t, i) == 'N') {
    i = i + 1
    let a = if digits == "" { sign_a } else { sign_a * int_of(digits) }
    let b = if i >= n { 0 } else { int_of(trim(t.substring(start=i, end=n))) }
    (a, b)
  } else {
    if digits == "" {
      raise Refused::BadQuery(at=0, why="bad nth formula: " + s)
    }
    (0, sign_a * int_of(digits))
  }
}

fn trim(s : String) -> String {
  let n = s.length()
  let mut start = 0
  while start < n && css_ws(char_at(s, start)) {
    start = start + 1
  }
  let mut e = n
  while e > start && css_ws(char_at(s, e - 1)) {
    e = e - 1
  }
  if start == 0 && e == n {
    s
  } else {
    s.substring(start~, end=e)
  }
}

fn int_of(s : String) -> Int {
  let mut i = 0
  let mut sign = 1
  let n = s.length()
  if i < n && (char_at(s, i) == '+' || char_at(s, i) == '-') {
    if char_at(s, i) == '-' {
      sign = -1
    }
    i = i + 1
  }
  let mut v = 0
  while i < n && char_at(s, i) >= '0' && char_at(s, i) <= '9' {
    v = v * 10 + (Char::to_int(char_at(s, i)) - Char::to_int('0'))
    i = i + 1
  }
  sign * v
}

// ---------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------

/// Whether an element name satisfies a name test: the whole `{uri}local` name,
/// or — when the test has no `{` — just the local part.
pub fn name_matches(el : Element, t : String) -> Bool {
  if t == "*" {
    return true
  }
  if el.name == t {
    return true
  }
  if t.contains("{") == false {
    return el.local_name() == t
  }
  false
}

fn match_complex(el : Element, parts : Array[(Combinator, Compound)], idx : Int) -> Bool {
  let (_, comp) = parts[idx]
  if match_compound(el, comp) == false {
    return false
  }
  if idx == 0 {
    return true
  }
  let (comb, _) = parts[idx]
  match comb {
    Descendant => {
      let mut cur = el.parent
      let mut found = false
      while true {
        match cur {
          None => break
          Some(p) => {
            if match_complex(p, parts, idx - 1) {
              found = true
              break
            }
            cur = p.parent
          }
        }
      }
      found
    }
    Child => match el.parent {
      Some(p) => match_complex(p, parts, idx - 1)
      None => false
    }
    Adjacent => match el.previous_element_sibling() {
      Some(s) => match_complex(s, parts, idx - 1)
      None => false
    }
    Sibling => {
      let mut cur = el.previous_element_sibling()
      let mut found = false
      while true {
        match cur {
          None => break
          Some(s) => {
            if match_complex(s, parts, idx - 1) {
              found = true
              break
            }
            cur = s.previous_element_sibling()
          }
        }
      }
      found
    }
  }
}

fn matches_any_complex(el : Element, list : Array[Complex]) -> Bool {
  for c in list {
    if match_complex(el, c.parts, c.parts.length() - 1) {
      return true
    }
  }
  false
}

fn match_compound(el : Element, comp : Compound) -> Bool {
  if comp.universal == false {
    match comp.tag {
      Some(t) => if name_matches(el, t) == false {
        return false
      }
      None => ()
    }
  }
  for id in comp.ids {
    if el.attr("id") != Some(id) {
      return false
    }
  }
  for c in comp.classes {
    if el.has_class(c) == false {
      return false
    }
  }
  for a in comp.attrs {
    if match_attr(el, a) == false {
      return false
    }
  }
  for ps in comp.pseudos {
    if match_pseudo(el, ps) == false {
      return false
    }
  }
  true
}

fn match_attr(el : Element, a : AttrSel) -> Bool {
  let v = el.attr(a.name)
  match a.op {
    "" => v.is_some()
    "=" => v == Some(a.value)
    "~=" => match v {
      Some(x) => split_ws(x).contains(a.value)
      None => false
    }
    "|=" => match v {
      Some(x) => x == a.value || x.has_prefix(a.value + "-")
      None => false
    }
    "^=" => match v {
      Some(x) => x.has_prefix(a.value)
      None => false
    }
    "$=" => match v {
      Some(x) => x.has_suffix(a.value)
      None => false
    }
    "*=" => match v {
      Some(x) => x.contains(a.value)
      None => false
    }
    "!=" => match v {
      Some(x) => x != a.value
      None => false
    }
    _ => false
  }
}

fn type_position(el : Element) -> Int {
  match el.parent {
    None => 1
    Some(p) => {
      let idx = el.index_in_parent()
      let mut pos = 0
      let mut i = 0
      while i <= idx {
        match p.children[i] {
          ElementNode(x) => if name_matches(x, el.name) {
            pos = pos + 1
          }
          _ => ()
        }
        i = i + 1
      }
      pos
    }
  }
}

fn type_count(el : Element) -> Int {
  match el.parent {
    None => 1
    Some(p) => {
      let mut count = 0
      for c in p.children {
        match c {
          ElementNode(x) => if name_matches(x, el.name) {
            count = count + 1
          }
          _ => ()
        }
      }
      count
    }
  }
}

// Count siblings matching `of` (or all element siblings when `of` is empty).
fn filtered_position(el : Element, of : Array[Complex]) -> (Int, Int) {
  match el.parent {
    None => (1, 1)
    Some(p) => {
      let idx = el.index_in_parent()
      let mut pos = 0
      let mut total = 0
      let mut i = 0
      for c in p.children {
        match c {
          ElementNode(x) => if of.length() == 0 || matches_any_complex(x, of) {
            total = total + 1
            if i <= idx {
              pos = pos + 1
            }
          }
          _ => ()
        }
        i = i + 1
      }
      (pos, total)
    }
  }
}

fn nth_matches(pos : Int, total : Int, a : Int, b : Int, from_end : Bool) -> Bool {
  let p = if from_end { total - pos + 1 } else { pos }
  if a == 0 {
    p == b
  } else {
    let diff = p - b
    diff % a == 0 && diff / a >= 0
  }
}

fn match_pseudo(el : Element, ps : Pseudo) -> Bool {
  match ps {
    FirstChild => el.previous_element_sibling().is_none()
    LastChild => el.next_element_sibling().is_none()
    OnlyChild => el.previous_element_sibling().is_none() && el.next_element_sibling().is_none()
    FirstOfType => type_position(el) == 1
    LastOfType => type_position(el) == type_count(el)
    OnlyOfType => type_position(el) == 1 && type_count(el) == 1
    Root => match el.parent {
      Some(p) => p.name == "#document"
      None => false
    }
    Empty => element_is_empty(el)
    Not(list) => matches_any_complex(el, list) == false
    Is(list) | Where(list) => matches_any_complex(el, list)
    NthChild(a, b, of) => {
      let (pos, total) = filtered_position(el, of)
      nth_matches(pos, total, a, b, false)
    }
    NthLastChild(a, b, of) => {
      let (pos, total) = filtered_position(el, of)
      nth_matches(pos, total, a, b, true)
    }
    NthOfType(a, b) => nth_matches(type_position(el), type_count(el), a, b, false)
    NthLastOfType(a, b) => nth_matches(type_position(el), type_count(el), a, b, true)
    Has(list, child) => has_match(el, list, child)
  }
}

fn element_is_empty(el : Element) -> Bool {
  for c in el.children {
    match c {
      TextNode(s) | CDataNode(s) => if s.length() > 0 {
        return false
      }
      ElementNode(_) => return false
      _ => ()
    }
  }
  true
}

fn has_match(el : Element, list : Array[Complex], child : Bool) -> Bool {
  if child {
    for c in el.children_elements() {
      if matches_any_complex(c, list) {
        return true
      }
    }
    false
  } else {
    for d in el.descendant_elements() {
      if matches_any_complex(d, list) {
        return true
      }
    }
    false
  }
}

// ---------------------------------------------------------------------------
// Public entry points
// ---------------------------------------------------------------------------

/// Match `el` against `query` on its own, ignoring any surrounding context.
pub fn css_matches_one(el : Element, query : String) -> Bool raise Refused {
  let list = parse_selector_list(query)
  matches_any_complex(el, list)
}

/// Narrow `ctx` by `query`: every descendant element that matches, in document
/// order, deduplicated.
pub fn css_select(ctx : Selection, query : String) -> Selection raise Refused {
  let list = parse_selector_list(query)
  let out : Array[Node] = []
  for e in gather_elements(ctx) {
    if matches_any_complex(e, list) {
      out.push(ElementNode(e))
    }
  }
  Selection::with_doc(ctx.doc, dedup_nodes(out))
}
