// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// CSS selectors: the statically decidable subset of Selectors Level 4 —
/// type and universal selectors, `#id`, `.class`, attribute selectors with
/// every operator and the case flag, the four combinators, selector lists,
/// the logical pseudo-classes (`:not`, `:is`, `:where`, `:has`), the
/// structural pseudo-classes, and the state pseudo-classes approximated by
/// their attribute (a tree has no history, no focus and no hover).
///
/// Dynamic pseudo-classes (`:hover`, `:focus`, …) are not statically
/// decidable, so they are a parse error naming the pseudo-class rather than a
/// selector that silently matches nothing.

///|
/// What stands between two compound selectors.
priv enum Combinator {
  Descendant
  Child
  NextSibling
  LaterSibling
}

///|
/// One attribute requirement: `[a]`, `[a=v]`, `[a~=v]`, `[a|=v]`, `[a^=v]`,
/// `[a$=v]`, `[a*=v]`, each optionally with the `i` or `s` flag.
priv struct AttrReq {
  name : String
  op : String
  value : String
  flag : String
}

///|
/// A pseudo-class, with its argument already parsed.
priv enum Pseudo {
  FirstChild
  LastChild
  OnlyChild
  NthChild(AnPlusB)
  NthLastChild(AnPlusB)
  FirstOfType
  LastOfType
  NthOfType(AnPlusB)
  NthLastOfType(AnPlusB)
  OnlyOfType
  Empty
  Root
  AnyLink
  Link
  Checked
  Disabled
  Enabled
  Required
  Optional
  Not(Array[Complex])
  Is(Array[Complex])
  Where(Array[Complex])
  Has(Array[Complex])
}

///|
/// One compound selector: the pieces that must all hold on one element.
priv struct Compound {
  mut tag : String?
  mut id : String?
  classes : Array[String]
  attrs : Array[AttrReq]
  pseudos : Array[Pseudo]
}

///|
/// A complex selector: compounds joined by combinators, the last compound the
/// subject. The first pair's combinator is the leading one — meaningful only
/// inside `:has()`, where the selector is relative to the element it hangs on.
priv struct Complex {
  parts : Array[(Combinator, Compound)]
}

///|
/// `an+b`, the argument of the positional pseudo-classes.
priv struct AnPlusB {
  a : Int32
  b : Int32
}

///|
/// Parse a selector list, raising on the first thing that is not one.
fn css_parse(query : String) -> Array[Complex] raise Refused {
  let out : Array[Complex] = []
  for part in split_top(query, ',') {
    out.push(parse_complex(part))
  }
  out
}

///|
/// Split on a separator that sits at the top level — outside brackets,
/// parentheses and quotes, where it means something else.
fn split_top(text : String, sep : Char) -> Array[String] {
  let out : Array[String] = []
  let mut depth = 0
  let mut quote : Char? = None
  let mut run = StringBuilder()
  for ch in text {
    match quote {
      Some(q) => {
        run.write_char(ch)
        if ch == q {
          quote = None
        }
      }
      None =>
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
          run.write_char(ch)
        } else if ch == '(' || ch == '[' {
          depth = depth + 1
          run.write_char(ch)
        } else if ch == ')' || ch == ']' {
          depth = depth - 1
          run.write_char(ch)
        } else if ch == sep && depth == 0 {
          out.push(run.to_string())
          run = StringBuilder()
        } else {
          run.write_char(ch)
        }
    }
  }
  out.push(run.to_string())
  out
}

///|
/// Parse one complex selector: compounds joined by combinators, where
/// whitespace is the descendant combinator.
fn parse_complex(text : String) -> Complex raise Refused {
  let parts : Array[(Combinator, Compound)] = []
  let n = text.length()
  let mut i = 0
  fn skip_ws() -> Unit {
    while i < n &&
          (
            text.at(i) == 0x20 ||
            text.at(i) == 0x09 ||
            text.at(i) == 0x0A ||
            text.at(i) == 0x0D
          ) {
      i = i + 1
    }
  }
  let mut pending : Combinator = Descendant
  skip_ws()
  if i < n && is_combinator_char(text.at(i)) {
    pending = combinator_of(text.at(i))
    i = i + 1
    skip_ws()
  }
  while i < n {
    let (compound, next) = parse_compound(text, i)
    if compound_is_empty(compound) {
      raise BadQuery(at=i, why="a compound selector is empty")
    }
    parts.push((pending, compound))
    i = next
    pending = Descendant
    skip_ws()
    if i < n && is_combinator_char(text.at(i)) {
      pending = combinator_of(text.at(i))
      i = i + 1
      skip_ws()
    }
  }
  if parts.is_empty() {
    raise BadQuery(at=0, why="a complex selector needs a compound")
  }
  Complex::{ parts, }
}

///|
fn is_combinator_char(unit : UInt16) -> Bool {
  unit == 0x3E || unit == 0x2B || unit == 0x7E
}

///|
fn combinator_of(unit : UInt16) -> Combinator {
  match unit {
    0x3E => Child
    0x2B => NextSibling
    _ => LaterSibling
  }
}

///|
fn compound_is_empty(compound : Compound) -> Bool {
  compound.tag is None &&
  compound.id is None &&
  compound.classes.is_empty() &&
  compound.attrs.is_empty() &&
  compound.pseudos.is_empty()
}

///|
/// Parse one compound selector starting at `from`, answering it and the index
/// just past it.
fn parse_compound(
  text : String,
  from : Int32,
) -> (Compound, Int32) raise Refused {
  let compound : Compound = {
    tag: None,
    id: None,
    classes: [],
    attrs: [],
    pseudos: [],
  }
  let n = text.length()
  let mut i = from
  let mut fresh = true
  while i < n {
    let unit = text.at(i)
    if unit == 0x2A && fresh {
      // *
      i = i + 1
      let (tag, next) = read_type(text, i, "*")
      compound.tag = Some(tag)
      i = next
      fresh = false
    } else if unit == 0x23 {
      // #id
      i = i + 1
      let (name, next) = read_name(text, i)
      if name.is_empty() {
        raise BadQuery(at=i, why="an id selector needs a name")
      }
      compound.id = Some(name)
      i = next
      fresh = false
    } else if unit == 0x2E {
      // .class
      i = i + 1
      let (name, next) = read_name(text, i)
      if name.is_empty() {
        raise BadQuery(at=i, why="a class selector needs a name")
      }
      compound.classes.push(name)
      i = next
      fresh = false
    } else if unit == 0x5B {
      // [attr]
      let (req, next) = parse_attr(text, i)
      compound.attrs.push(req)
      i = next
      fresh = false
    } else if unit == 0x3A {
      // :pseudo; ::pseudo-element selects nothing in a tree
      if i + 1 < n && text.at(i + 1) == 0x3A {
        raise BadQuery(at=i, why="a pseudo-element selects nothing in a tree")
      }
      let start = i
      i = i + 1
      let (name, next) = read_name(text, i)
      i = next
      if i < n && text.at(i) == 0x28 {
        let (arg, after) = read_parens(text, i)
        compound.pseudos.push(parse_functional(name, arg, start))
        i = after
      } else {
        compound.pseudos.push(parse_simple(name, start))
      }
      fresh = false
    } else if unit == 0x7B && fresh {
      // a Clark name: {uri}local
      let (tag, next) = read_clark(text, i)
      compound.tag = Some(tag)
      i = next
      fresh = false
    } else if fresh && (is_name_start(unit) || unit == 0x7C) {
      // a type selector, with an optional namespace prefix
      let head = if unit == 0x7C {
        ""
      } else {
        let (name, next) = read_name(text, i)
        i = next
        name
      }
      let (tag, next) = read_type(text, i, head)
      compound.tag = Some(tag)
      i = next
      fresh = false
    } else {
      break
    }
  }
  (compound, i)
}

///|
/// A `{uri}local` name in a type selector: the URI may carry colons and
/// slashes, so it is read up to its closing brace rather than as a name.
fn read_clark(text : String, from : Int32) -> (String, Int32) {
  let close = match find_char(text, from, '}') {
    Some(at) => at
    None => text.length()
  }
  let (part, next) = read_name(text, close + 1)
  (text[from:close + 1].to_owned() + part, next)
}

///|
/// A type selector's local part, keeping the prefix when there is one:
/// `rect`, `svg|rect`, `*|rect` and `|rect` all reach `name_matches` as
/// written, because the tree carries Clark names and keeps no prefix map.
fn read_type(text : String, from : Int32, head : String) -> (String, Int32) {
  if from < text.length() && text.at(from) == 0x7C {
    let (part, next) = read_name(text, from + 1)
    (head + "|" + part, next)
  } else {
    (head, from)
  }
}

///|
/// Read a CSS identifier, with the one escape form worth supporting: a
/// backslash and the character it stands for.
fn read_name(text : String, from : Int32) -> (String, Int32) {
  let out = StringBuilder()
  let n = text.length()
  let mut i = from
  while i < n {
    let unit = text.at(i)
    if unit == 0x5C && i + 1 < n {
      out.write_char(u16_char(text.at(i + 1)))
      i = i + 2
    } else if is_name_char(unit) {
      out.write_char(u16_char(unit))
      i = i + 1
    } else {
      break
    }
  }
  (out.to_string(), i)
}

///|
fn is_name_start(unit : UInt16) -> Bool {
  is_name_char(unit) && !(unit >= 0x30 && unit <= 0x39)
}

///|
fn is_name_char(unit : UInt16) -> Bool {
  (unit >= 0x61 && unit <= 0x7A) ||
  (unit >= 0x41 && unit <= 0x5A) ||
  (unit >= 0x30 && unit <= 0x39) ||
  unit == 0x2D ||
  unit == 0x5F ||
  unit > 0x7F
}

///|
/// `[attr]`, `[attr op value]`, with the optional case flag.
fn parse_attr(text : String, from : Int32) -> (AttrReq, Int32) raise Refused {
  let close = match find_close(text, from) {
    Some(at) => at
    None => raise BadQuery(at=from, why="an attribute selector is never closed")
  }
  let inner = text[from + 1:close].trim().to_owned()
  let n = inner.length()
  let mut at = 0
  while at < n && is_name_char(inner.at(at)) {
    at = at + 1
  }
  let name = inner[0:at].to_owned()
  if name.is_empty() {
    raise BadQuery(at=from + 1, why="an attribute selector needs a name")
  }
  let rest = inner[at:n].trim()
  if rest.is_empty() {
    return (AttrReq::{ name, op: "", value: "", flag: "", }, close + 1)
  }
  let two = if rest.length() >= 2 { rest[0:2].to_owned() } else { "" }
  let op = if two == "~=" ||
    two == "|=" ||
    two == "^=" ||
    two == "$=" ||
    two == "*=" {
    two
  } else if rest.at(0) == 0x3D {
    "="
  } else {
    raise BadQuery(
      at=from + 1 + at,
      why="an attribute operator is not one this library knows",
    )
  }
  let tail = if op.length() == 2 {
    rest[2:rest.length()].trim()
  } else {
    rest[1:rest.length()].trim()
  }
  let flag = if tail.length() >= 2 &&
    (tail.has_suffix(" i") || tail.has_suffix(" s")) {
    tail[tail.length() - 1:tail.length()].to_owned()
  } else {
    ""
  }
  let bare = if flag.is_empty() {
    tail
  } else {
    tail[0:tail.length() - 2].trim()
  }
  (
    AttrReq::{ name, op, value: strip_quotes(bare.to_owned()), flag, },
    close + 1,
  )
}

///|
/// The `]` that closes an attribute selector: past any quoted value, which
/// may carry a bracket of its own.
fn find_close(text : String, from : Int32) -> Int32? {
  let n = text.length()
  let mut i = from + 1
  let mut quote : Char? = None
  while i < n {
    let unit = text.at(i)
    match quote {
      Some(q) => if u16_char(unit) == q { quote = None }
      None =>
        if unit == 0x22 || unit == 0x27 {
          quote = Some(u16_char(unit))
        } else if unit == 0x5D {
          return Some(i)
        }
    }
    i = i + 1
  }
  None
}

///|
/// The text between balanced parentheses starting at the `(`.
fn read_parens(text : String, from : Int32) -> (String, Int32) {
  let n = text.length()
  let mut depth = 0
  let mut i = from
  let out = StringBuilder()
  while i < n {
    let unit = text.at(i)
    if unit == 0x28 {
      depth = depth + 1
      if depth > 1 {
        out.write_char(u16_char(unit))
      }
    } else if unit == 0x29 {
      depth = depth - 1
      if depth == 0 {
        return (out.to_string(), i + 1)
      }
      out.write_char(u16_char(unit))
    } else {
      out.write_char(u16_char(unit))
    }
    i = i + 1
  }
  (out.to_string(), n)
}

///|
fn strip_quotes(text : String) -> String {
  let n = text.length()
  if n >= 2 &&
    (
      (text.at(0) == 0x27 && text.at(n - 1) == 0x27) ||
      (text.at(0) == 0x22 && text.at(n - 1) == 0x22)
    ) {
    return text[1:n - 1].to_owned()
  }
  text
}

///|
/// A pseudo-class with no argument.
fn parse_simple(name : String, at : Int32) -> Pseudo raise Refused {
  match name {
    "first-child" => FirstChild
    "last-child" => LastChild
    "only-child" => OnlyChild
    "first-of-type" => FirstOfType
    "last-of-type" => LastOfType
    "only-of-type" => OnlyOfType
    "empty" => Empty
    "root" => Root
    "link" => Link
    "any-link" => AnyLink
    "checked" => Checked
    "disabled" => Disabled
    "enabled" => Enabled
    "required" => Required
    "optional" => Optional
    _ =>
      raise BadQuery(
        at~,
        why="the pseudo-class :\{name} is not statically decidable",
      )
  }
}

///|
/// A pseudo-class with an argument: `an+b` for the positional ones, a selector
/// list for the logical ones.
fn parse_functional(
  name : String,
  arg : String,
  at : Int32,
) -> Pseudo raise Refused {
  match name {
    "nth-child" => NthChild(parse_an_plus_b(arg, at))
    "nth-last-child" => NthLastChild(parse_an_plus_b(arg, at))
    "nth-of-type" => NthOfType(parse_an_plus_b(arg, at))
    "nth-last-of-type" => NthLastOfType(parse_an_plus_b(arg, at))
    "not" => Not(parse_inner(arg, at))
    "is" => Is(parse_inner(arg, at))
    "where" => Where(parse_inner(arg, at))
    "has" => Has(parse_inner(arg, at))
    _ =>
      raise BadQuery(
        at~,
        why="the pseudo-class :\{name}(..) is not statically decidable",
      )
  }
}

///|
/// The selector list inside a logical pseudo-class.
fn parse_inner(arg : String, at : Int32) -> Array[Complex] raise Refused {
  let out : Array[Complex] = []
  for part in split_top(arg, ',') {
    out.push(parse_complex(part))
  }
  if out.is_empty() {
    raise BadQuery(at~, why="a logical pseudo-class needs a selector")
  }
  out
}

///|
/// `an+b` in its spellings: `2n+1`, `odd`, `even`, `-n+3`, `n`, `3`.
fn parse_an_plus_b(text : String, at : Int32) -> AnPlusB raise Refused {
  let s = text.trim().to_lower().to_owned()
  if s == "odd" {
    return { a: 2, b: 1, }
  }
  if s == "even" {
    return { a: 2, b: 0, }
  }
  let rest = if s.has_prefix("+") { s[1:s.length()].to_owned() } else { s }
  let mark = match find_char(rest, 0, 'n') {
    Some(k) => k
    None =>
      match parse_int(rest) {
        Some(v) => return { a: 0, b: v, }
        None => raise BadQuery(at~, why="\{text} is not an an+b argument")
      }
  }
  let a_text = rest[0:mark].to_owned()
  let b_text = rest[mark + 1:rest.length()].trim().to_owned()
  let a = if a_text.is_empty() {
    1
  } else if a_text == "-" {
    -1
  } else {
    match parse_int(a_text) {
      Some(v) => v
      None => raise BadQuery(at~, why="\{text} is not an an+b argument")
    }
  }
  let b = if b_text.is_empty() {
    0
  } else {
    match parse_int(b_text) {
      Some(v) => v
      None => raise BadQuery(at~, why="\{text} is not an an+b argument")
    }
  }
  { a, b, }
}

///|
fn parse_int(text : StringView) -> Int32? {
  Some(@string.parse_int(text)) catch {
    _ => None
  }
}

///|
/// Whether `count` — one-based — is one of the positions `an+b` names.
fn an_plus_b_holds(anb : AnPlusB, count : Int32) -> Bool {
  if anb.a == 0 {
    return count == anb.b
  }
  let k = count - anb.b
  k % anb.a == 0 && k / anb.a >= 0
}

// Matching. The subject is the last compound; the chain is walked
// right-to-left, backtracking where a combinator allows more than one answer.

///|
fn complex_list_matches(complexes : Array[Complex], element : Element) -> Bool {
  for complex in complexes {
    if complex_matches(complex, element) {
      return true
    }
  }
  false
}

///|
fn complex_matches(complex : Complex, element : Element) -> Bool {
  let last = complex.parts.length() - 1
  let (_, subject) = complex.parts[last]
  if !compound_matches(subject, element) {
    return false
  }
  chain_matches(complex, last - 1, element)
}

///|
/// `idx` is the compound to the left of `element`; the combinator between
/// them sits in `parts[idx + 1]`.
fn chain_matches(complex : Complex, idx : Int32, element : Element) -> Bool {
  if idx < 0 {
    return true
  }
  let comb = complex.parts[idx + 1].0
  let compound = complex.parts[idx].1
  match comb {
    Child =>
      match element.parent {
        Some(parent) =>
          compound_matches(compound, parent) &&
          chain_matches(complex, idx - 1, parent)
        None => false
      }
    Descendant => {
      let mut current = element.parent
      while current is Some(ancestor) {
        if compound_matches(compound, ancestor) &&
          chain_matches(complex, idx - 1, ancestor) {
          return true
        }
        current = ancestor.parent
      }
      false
    }
    NextSibling =>
      match previous_element(element) {
        Some(sibling) =>
          compound_matches(compound, sibling) &&
          chain_matches(complex, idx - 1, sibling)
        None => false
      }
    LaterSibling =>
      match element.parent {
        Some(parent) => {
          let siblings = element_children(parent)
          let mut found = false
          for sibling in siblings {
            if physical_equal(sibling, element) {
              break
            }
            if compound_matches(compound, sibling) &&
              chain_matches(complex, idx - 1, sibling) {
              found = true
              break
            }
          }
          found
        }
        None => false
      }
  }
}

///|
fn compound_matches(compound : Compound, element : Element) -> Bool {
  match compound.tag {
    Some(tag) => if !name_matches(element.name, tag) { return false }
    None => ()
  }
  match compound.id {
    Some(id) =>
      match element.attr("id") {
        Some(have) => if have != id { return false }
        None => return false
      }
    None => ()
  }
  for wanted in compound.classes {
    if !element.has_class(wanted) {
      return false
    }
  }
  for req in compound.attrs {
    if !attr_matches(element, req) {
      return false
    }
  }
  for pseudo in compound.pseudos {
    if !pseudo_matches(pseudo, element) {
      return false
    }
  }
  true
}

///|
/// The one name-matching rule XPath and CSS share: the whole `{uri}local`
/// name, or — when the test carries no `{` — the local part. A prefix in the
/// test matches by local part too, because the tree keeps no prefix map and a
/// wrong resolution is worse than an honest one.
fn name_matches(full : String, probe : String) -> Bool {
  if probe == "*" {
    return true
  }
  if full == probe {
    return true
  }
  if probe.contains("|") {
    let tail = probe[probe.find("|").unwrap() + 1:probe.length()].to_owned()
    return tail == "*" || local_of(full) == tail
  }
  if !probe.contains("{") {
    return local_of(full) == probe
  }
  false
}

///|
fn attr_matches(element : Element, req : AttrReq) -> Bool {
  match element.attr(req.name) {
    None => false
    Some(have) =>
      match req.op {
        "" => true
        "=" => same_text(have, req.value, req.flag)
        "~=" =>
          if req.value.is_empty() {
            false
          } else {
            let mut found = false
            for part in have.split(" ") {
              if !part.is_empty() && same_text(part, req.value, req.flag) {
                found = true
                break
              }
            }
            found
          }
        "|=" => have == req.value || have.has_prefix(req.value + "-")
        "^=" => !req.value.is_empty() && starts_with(have, req.value, req.flag)
        "$=" => !req.value.is_empty() && ends_with(have, req.value, req.flag)
        "*=" => !req.value.is_empty() && holds_within(have, req.value, req.flag)
        _ => false
      }
  }
}

///|
fn same_text(a : StringView, b : StringView, flag : String) -> Bool {
  if flag == "i" {
    ascii_lower(a) == ascii_lower(b)
  } else {
    a == b
  }
}

///|
fn starts_with(text : StringView, part : StringView, flag : String) -> Bool {
  if part.length() > text.length() {
    return false
  }
  same_text(text[0:part.length()].to_owned(), part, flag)
}

///|
fn ends_with(text : StringView, part : StringView, flag : String) -> Bool {
  let n = text.length()
  let m = part.length()
  if m > n {
    return false
  }
  same_text(text[n - m:n].to_owned(), part, flag)
}

///|
fn holds_within(text : StringView, part : StringView, flag : String) -> Bool {
  let m = part.length()
  let n = text.length()
  if m == 0 || m > n {
    return false
  }
  let mut k = 0
  while k + m <= n {
    if same_text(text[k:k + m].to_owned(), part, flag) {
      return true
    }
    k = k + 1
  }
  false
}

///|
fn ascii_lower(text : StringView) -> String {
  let out = StringBuilder()
  for ch in text {
    if ch >= 'A' && ch <= 'Z' {
      out.write_char((ch.to_int() + 0x20).unsafe_to_char())
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
fn pseudo_matches(pseudo : Pseudo, element : Element) -> Bool {
  match pseudo {
    FirstChild => previous_element(element) is None
    LastChild => next_element(element) is None
    OnlyChild =>
      previous_element(element) is None && next_element(element) is None
    NthChild(anb) =>
      match element.parent {
        Some(parent) => {
          let siblings = element_children(parent)
          let mut at = 0
          for k = 0; k < siblings.length(); k = k + 1 {
            if physical_equal(siblings[k], element) {
              at = k + 1
              break
            }
          }
          at > 0 && an_plus_b_holds(anb, at)
        }
        None => false
      }
    NthLastChild(anb) =>
      match element.parent {
        Some(parent) => {
          let siblings = element_children(parent)
          let mut at = 0
          for k = siblings.length() - 1; k >= 0; k = k - 1 {
            if physical_equal(siblings[k], element) {
              at = siblings.length() - k
              break
            }
          }
          at > 0 && an_plus_b_holds(anb, at)
        }
        None => false
      }
    FirstOfType => of_type_position(element, from_end=false) == 1
    LastOfType => of_type_position(element, from_end=true) == 1
    OnlyOfType =>
      of_type_position(element, from_end=false) == 1 &&
      of_type_position(element, from_end=true) == 1
    NthOfType(anb) =>
      an_plus_b_holds(anb, of_type_position(element, from_end=false))
    NthLastOfType(anb) =>
      an_plus_b_holds(anb, of_type_position(element, from_end=true))
    Empty => {
      let mut empty = true
      for child in element.children {
        match child {
          ElementNode(_) => empty = false
          TextNode(text) => if !text.trim().is_empty() { empty = false }
          CDataNode(text) => if !text.trim().is_empty() { empty = false }
          _ => ()
        }
      }
      empty
    }
    Root =>
      match element.parent {
        None => true
        Some(parent) => parent.name == "#document"
      }
    AnyLink => element.has_attr("href")
    Link => element.has_attr("href")
    Checked => element.has_attr("checked") || element.has_attr("selected")
    Disabled => element.has_attr("disabled")
    Enabled => !element.has_attr("disabled")
    Required => element.has_attr("required")
    Optional => !element.has_attr("required")
    Not(list) => !complex_list_matches(list, element)
    Is(list) => complex_list_matches(list, element)
    Where(list) => complex_list_matches(list, element)
    Has(list) => has_matches(list, element)
  }
}

///|
/// One-based position among the siblings that share this element's name.
fn of_type_position(element : Element, from_end~ : Bool) -> Int32 {
  match element.parent {
    Some(parent) => {
      let siblings = element_children(parent)
      let same : Array[Element] = []
      for sibling in siblings {
        if sibling.name == element.name {
          same.push(sibling)
        }
      }
      let mut at = 0
      if from_end {
        for k = same.length() - 1; k >= 0; k = k - 1 {
          if physical_equal(same[k], element) {
            at = same.length() - k
            break
          }
        }
      } else {
        for k = 0; k < same.length(); k = k + 1 {
          if physical_equal(same[k], element) {
            at = k + 1
            break
          }
        }
      }
      at
    }
    None => 1
  }
}

///|
/// `:has(relative)`: does any element the relative selector can reach from
/// `element` match it?
fn has_matches(list : Array[Complex], element : Element) -> Bool {
  for complex in list {
    let (lead, first) = complex.parts[0]
    let candidates : Array[Element] = []
    match lead {
      Descendant =>
        for data in descendant_elements(element) {
          candidates.push(data)
        }
      Child =>
        for child in element.children {
          if child is ElementNode(data) {
            candidates.push(data)
          }
        }
      NextSibling =>
        match next_element(element) {
          Some(sibling) => candidates.push(sibling)
          None => ()
        }
      LaterSibling =>
        match element.parent {
          Some(parent) => {
            let siblings = element_children(parent)
            let mut past = false
            for sibling in siblings {
              if past {
                candidates.push(sibling)
              }
              if physical_equal(sibling, element) {
                past = true
              }
            }
          }
          None => ()
        }
    }
    for candidate in candidates {
      if compound_matches(first, candidate) &&
        relative_chain(complex, 0, candidate) {
        return true
      }
    }
  }
  false
}

///|
/// The rest of a relative selector, walked left-to-right from `element`.
fn relative_chain(complex : Complex, idx : Int32, element : Element) -> Bool {
  if idx + 1 >= complex.parts.length() {
    return true
  }
  let (comb, compound) = complex.parts[idx + 1]
  match comb {
    Descendant => {
      for data in descendant_elements(element) {
        if compound_matches(compound, data) &&
          relative_chain(complex, idx + 1, data) {
          return true
        }
      }
      false
    }
    Child => {
      for child in element.children {
        if child is ElementNode(data) &&
          compound_matches(compound, data) &&
          relative_chain(complex, idx + 1, data) {
          return true
        }
      }
      false
    }
    NextSibling =>
      match next_element(element) {
        Some(sibling) =>
          compound_matches(compound, sibling) &&
          relative_chain(complex, idx + 1, sibling)
        None => false
      }
    LaterSibling =>
      match element.parent {
        Some(parent) => {
          let siblings = element_children(parent)
          let mut past = false
          for sibling in siblings {
            if past && compound_matches(compound, sibling) {
              if relative_chain(complex, idx + 1, sibling) {
                return true
              }
            }
            if physical_equal(sibling, element) {
              past = true
            }
          }
          false
        }
        None => false
      }
  }
}

///|
/// The element descendants of an element, in document order.
fn descendant_elements(element : Element) -> Array[Element] {
  let out : Array[Element] = []
  element.walk(fn(node) { if node is ElementNode(data) { out.push(data) } })
  out
}

///|
/// The element children of a parent, in order.
fn element_children(parent : Element) -> Array[Element] {
  let out : Array[Element] = []
  for child in parent.children {
    if child is ElementNode(data) {
      out.push(data)
    }
  }
  out
}

///|
fn previous_element(element : Element) -> Element? {
  match element.parent {
    Some(parent) => {
      let siblings = element_children(parent)
      for k = 1; k < siblings.length(); k = k + 1 {
        if physical_equal(siblings[k], element) {
          return Some(siblings[k - 1])
        }
      }
      None
    }
    None => None
  }
}

///|
fn next_element(element : Element) -> Element? {
  match element.parent {
    Some(parent) => {
      let siblings = element_children(parent)
      for k = 0; k < siblings.length() - 1; k = k + 1 {
        if physical_equal(siblings[k], element) {
          return Some(siblings[k + 1])
        }
      }
      None
    }
    None => None
  }
}

///|
/// The first place a character occurs at or after `from`, if it does.
fn find_char(src : String, from : Int32, unit : Char) -> Int32? {
  let n = src.length()
  let mut i = from
  while i < n {
    if u16_char(src.at(i)) == unit {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// A code unit as a character, with a stand-in for the lone surrogates.
fn u16_char(unit : UInt16) -> Char {
  match unit.to_char() {
    Some(c) => c
    None => '?'
  }
}
