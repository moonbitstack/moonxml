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
  name : NameTest
  op : String
  value : String
  flag : String
}

///|
/// Which namespace a name test asks for: `a|p` a prefix, `*|p` any, `|p` none,
/// and `p` the default namespace — or any namespace when the caller declared
/// no default.
priv enum SpaceTest {
  Prefixed(String)
  AnySpace
  NoSpace
  DefaultSpace
}

///|
/// A type or attribute selector: a namespace requirement and a local name,
/// `*` for any. A Clark name (`{uri}local`) is carried whole in `local` and
/// compared against the whole name.
priv struct NameTest {
  space : SpaceTest
  name : String
}

///|
/// The namespaces a selector's prefixes resolve against — what `@namespace`
/// declares in a stylesheet, handed over by the caller.
///
///     doc.css("a|ref", namespaces={ default: "", prefixes: [("a", "urn:x")] })
pub(all) struct NamespaceMap {
  /// The default namespace, `""` for none.
  default : String
  /// The prefix-to-URI bindings, in no particular order.
  prefixes : Array[(String, String)]
}

///|
/// No namespaces declared: type selectors match any namespace, and an
/// unprefixed attribute selector matches the attribute with no namespace.
pub let namespace_map : NamespaceMap = { default: "", prefixes: [], }

///|
/// A pseudo-class, with its argument already parsed.
priv enum Pseudo {
  FirstChild
  LastChild
  OnlyChild
  NthChild(AnPlusB, Array[Complex])
  NthLastChild(AnPlusB, Array[Complex])
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
  Lang(String)
  Not(Array[Complex])
  Is(Array[Complex])
  Where(Array[Complex])
  Has(Array[Complex])
}

///|
/// One compound selector: the pieces that must all hold on one element.
priv struct Compound {
  mut tag : NameTest?
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
  // Whether a combinator has been written without a compound after it: a
  // selector that ends on one is not a selector.
  let mut owed = false
  skip_ws()
  if i < n && is_combinator_char(text.at(i)) {
    pending = combinator_of(text.at(i))
    owed = true
    i = i + 1
    skip_ws()
  }
  while i < n {
    let (compound, next) = parse_compound(text, i)
    if compound_is_empty(compound) {
      raise BadQuery(at=i, why="a compound selector is empty")
    }
    parts.push((pending, compound))
    owed = false
    i = next
    pending = Descendant
    skip_ws()
    if i < n && is_combinator_char(text.at(i)) {
      pending = combinator_of(text.at(i))
      owed = true
      i = i + 1
      skip_ws()
    }
  }
  if owed {
    raise BadQuery(at=i, why="a combinator needs a selector after it")
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
      // `*`, and `*|local`
      let (tag, next) = read_name_test(text, i)
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
        match read_parens(text, i) {
          Some(parts) => {
            compound.pseudos.push(parse_functional(name, parts.0, start))
            i = parts.1
          }
          None =>
            raise BadQuery(
              at=start,
              why="the pseudo-class :\{name}( is never closed",
            )
        }
      } else {
        compound.pseudos.push(parse_simple(name, start))
      }
      fresh = false
    } else if unit == 0x7B && fresh {
      // a Clark name: {uri}local, matched whole
      let (tag, next) = read_clark(text, i)
      compound.tag = Some(tag)
      i = next
      fresh = false
    } else if fresh && (is_name_start(unit) || unit == 0x7C) {
      let (tag, next) = read_name_test(text, i)
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
fn read_clark(text : String, from : Int32) -> (NameTest, Int32) {
  let close = match find_char(text, from, '}') {
    Some(at) => at
    None => text.length()
  }
  let (part, next) = read_name(text, close + 1)
  ({ space: DefaultSpace, name: text[from:close + 1].to_owned() + part, }, next)
}

///|
/// A local part in a name test: a name, or `*` for any.
fn read_local_name(text : String, from : Int32) -> (String, Int32) {
  if from < text.length() && text.at(from) == 0x2A {
    ("*", from + 1)
  } else {
    read_name(text, from)
  }
}

///|
/// A type selector: `p`, `*`, `a|p`, `*|p` or `|p`.
fn read_name_test(
  text : String,
  from : Int32,
) -> (NameTest, Int32) raise Refused {
  let n = text.length()
  let mut i = from
  if i < n && text.at(i) == 0x7C {
    let (want, next) = read_local_name(text, i + 1)
    if want.is_empty() {
      raise BadQuery(at=i, why="a type selector needs a name after `|`")
    }
    return ({ space: NoSpace, name: want, }, next)
  }
  if i < n && text.at(i) == 0x2A {
    if i + 1 < n && text.at(i + 1) == 0x7C {
      let (want, next) = read_local_name(text, i + 2)
      if want.is_empty() {
        raise BadQuery(at=i, why="a type selector needs a name after `|`")
      }
      return ({ space: AnySpace, name: want, }, next)
    }
    return ({ space: DefaultSpace, name: "*", }, i + 1)
  }
  let (head, next) = read_name(text, i)
  if head.is_empty() {
    raise BadQuery(at=i, why="a type selector needs a name")
  }
  i = next
  if i < n && text.at(i) == 0x7C {
    let (want, after) = read_local_name(text, i + 1)
    if want.is_empty() {
      raise BadQuery(at=i, why="a type selector needs a name after `|`")
    }
    return ({ space: Prefixed(head), name: want, }, after)
  }
  ({ space: DefaultSpace, name: head, }, i)
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
/// An attribute selector's name: `title`, `a|title`, `*|title` or `|title`.
fn read_attribute_test(
  inner : String,
  at : Int32,
) -> (NameTest, Int32) raise Refused {
  let n = inner.length()
  if n > 0 && inner.at(0) == 0x7C {
    let (want, next) = read_local_name(inner, 1)
    if want.is_empty() || want == "*" {
      raise BadQuery(at~, why="an attribute selector needs a name")
    }
    return ({ space: NoSpace, name: want, }, next)
  }
  if n > 0 && inner.at(0) == 0x2A {
    if n > 1 && inner.at(1) == 0x7C {
      let (want, next) = read_local_name(inner, 2)
      if want.is_empty() || want == "*" {
        raise BadQuery(at~, why="an attribute selector needs a name")
      }
      return ({ space: AnySpace, name: want, }, next)
    }
    raise BadQuery(at~, why="an attribute selector needs a name")
  }
  let (head, next) = read_name(inner, 0)
  if head.is_empty() {
    raise BadQuery(at~, why="an attribute selector needs a name")
  }
  // `a|=v` is the dash-match operator, not a namespace: the `|` only splits a
  // name when it is followed by a name or a `*`.
  if next < n &&
    inner.at(next) == 0x7C &&
    next + 1 < n &&
    inner.at(next + 1) != 0x3D {
    let (want, after) = read_local_name(inner, next + 1)
    if want.is_empty() || want == "*" {
      raise BadQuery(at~, why="an attribute selector needs a name")
    }
    return ({ space: Prefixed(head), name: want, }, after)
  }
  ({ space: DefaultSpace, name: head, }, next)
}

///|
/// `[attr]`, `[attr op value]`, with the optional case flag.
fn parse_attr(text : String, from : Int32) -> (AttrReq, Int32) raise Refused {
  let close = match find_close(text, from) {
    Some(at) => at
    None => raise BadQuery(at=from, why="an attribute selector is never closed")
  }
  let inner = text[from + 1:close].trim().to_owned()
  let (name, at) = read_attribute_test(inner, from + 1)
  let rest = inner[at:inner.length()].trim()
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
/// The text between balanced parentheses starting at the `(`, and where the
/// `)` after it ends. A function that is never closed has no argument to read,
/// so the selector is refused rather than read to the end of the query.
fn read_parens(text : String, from : Int32) -> (String, Int32)? {
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
        return Some((out.to_string(), i + 1))
      }
      out.write_char(u16_char(unit))
    } else {
      out.write_char(u16_char(unit))
    }
    i = i + 1
  }
  None
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
    "nth-child" => {
      let (anb, of) = parse_nth(arg, at)
      NthChild(anb, of)
    }
    "nth-last-child" => {
      let (anb, of) = parse_nth(arg, at)
      NthLastChild(anb, of)
    }
    "nth-of-type" => NthOfType(parse_an_plus_b(arg, at))
    "nth-last-of-type" => NthLastOfType(parse_an_plus_b(arg, at))
    "lang" => Lang(arg.trim().to_owned())
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
/// The argument of `:nth-child()`, which may carry a selector list after `of`:
/// the siblings the formula counts are the ones that list accepts.
fn parse_nth(
  text : String,
  at : Int32,
) -> (AnPlusB, Array[Complex]) raise Refused {
  match split_of(text) {
    Some(parts) => (parse_an_plus_b(parts.0, at), parse_inner(parts.1, at))
    None => (parse_an_plus_b(text, at), [])
  }
}

///|
/// Split an `An+B of S` argument at the `of` that stands as a word of its own
/// outside brackets and quotes. Everything before it is the formula, everything
/// after it the selector list.
fn split_of(text : String) -> (String, String)? {
  let n = text.length()
  let mut depth = 0
  let mut quote : UInt16 = 0
  let mut i = 0
  while i < n {
    let ch = text.at(i)
    if quote != 0 {
      if ch == quote {
        quote = 0
      }
    } else if ch == 0x22 || ch == 0x27 {
      quote = ch
    } else if ch == 0x28 || ch == 0x5B {
      depth = depth + 1
    } else if ch == 0x29 || ch == 0x5D {
      depth = depth - 1
    } else if depth == 0 &&
      (ch == 0x6F || ch == 0x4F) &&
      i + 1 < n &&
      (text.at(i + 1) == 0x66 || text.at(i + 1) == 0x46) &&
      i > 0 &&
      is_css_space(text.at(i - 1)) &&
      (i + 2 == n || is_css_space(text.at(i + 2))) {
      return Some((text[0:i].to_owned(), text[i + 2:n].trim().to_owned()))
    }
    i = i + 1
  }
  None
}

///|
fn is_css_space(ch : UInt16) -> Bool {
  ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0C || ch == 0x0D
}

///|
/// Whether `element` holds the position `anb` names among its siblings once
/// `of` has filtered them. Both ends of the list are counted from the side the
/// pseudo-class names, and an element the list refuses is never a position.
fn position_matches(
  anb : AnPlusB,
  of : Array[Complex],
  siblings : Array[Element],
  element : Element,
  namespaces : NamespaceMap,
  from_end~ : Bool,
) -> Bool {
  let mut counted = 0
  let mut at = 0
  for k = 0; k < siblings.length(); k = k + 1 {
    let sibling = if from_end {
      siblings[siblings.length() - 1 - k]
    } else {
      siblings[k]
    }
    if of.is_empty() || complex_list_matches(of, sibling, namespaces) {
      counted = counted + 1
      if physical_equal(sibling, element) {
        at = counted
      }
    }
  }
  at > 0 && an_plus_b_holds(anb, at)
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
fn complex_list_matches(
  complexes : Array[Complex],
  element : Element,
  namespaces : NamespaceMap,
) -> Bool {
  for complex in complexes {
    if complex_matches(complex, element, namespaces) {
      return true
    }
  }
  false
}

///|
fn complex_matches(
  complex : Complex,
  element : Element,
  namespaces : NamespaceMap,
) -> Bool {
  let last = complex.parts.length() - 1
  let (_, subject) = complex.parts[last]
  if !compound_matches(subject, element, namespaces) {
    return false
  }
  chain_matches(complex, last - 1, element, namespaces)
}

///|
/// `idx` is the compound to the left of `element`; the combinator between
/// them sits in `parts[idx + 1]`.
fn chain_matches(
  complex : Complex,
  idx : Int32,
  element : Element,
  namespaces : NamespaceMap,
) -> Bool {
  if idx < 0 {
    return true
  }
  let comb = complex.parts[idx + 1].0
  let compound = complex.parts[idx].1
  match comb {
    Child =>
      match element.parent {
        Some(parent) =>
          compound_matches(compound, parent, namespaces) &&
          chain_matches(complex, idx - 1, parent, namespaces)
        None => false
      }
    Descendant => {
      let mut current = element.parent
      while current is Some(ancestor) {
        if compound_matches(compound, ancestor, namespaces) &&
          chain_matches(complex, idx - 1, ancestor, namespaces) {
          return true
        }
        current = ancestor.parent
      }
      false
    }
    NextSibling =>
      match element.previous_element_sibling() {
        Some(sibling) =>
          compound_matches(compound, sibling, namespaces) &&
          chain_matches(complex, idx - 1, sibling, namespaces)
        None => false
      }
    LaterSibling =>
      match element.parent {
        Some(parent) => {
          let siblings = parent.child_elements()
          let mut found = false
          for sibling in siblings {
            if physical_equal(sibling, element) {
              break
            }
            if compound_matches(compound, sibling, namespaces) &&
              chain_matches(complex, idx - 1, sibling, namespaces) {
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
fn compound_matches(
  compound : Compound,
  element : Element,
  namespaces : NamespaceMap,
) -> Bool {
  match compound.tag {
    Some(probe) =>
      if !type_matches(element.name, probe, namespaces) {
        return false
      }
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
    if !attr_matches(element, req, namespaces) {
      return false
    }
  }
  for pseudo in compound.pseudos {
    if !pseudo_matches(pseudo, element, namespaces) {
      return false
    }
  }
  true
}

///|
/// The namespace a prefix stands for, from the map the caller passed.
fn prefix_uri(namespaces : NamespaceMap, prefix : String) -> String? {
  for pair in namespaces.prefixes {
    if pair.0 == prefix {
      return Some(pair.1)
    }
  }
  None
}

///|
/// A type selector against a `{uri}local` name. A Clark selector names the
/// whole name; otherwise the local part has to agree, and the namespace does
/// too — except that a prefix the caller did not bind matches by local part,
/// because the tree keeps no prefix map and a wrong namespace is worse than an
/// honest match.
fn type_matches(
  full : String,
  probe : NameTest,
  namespaces : NamespaceMap,
) -> Bool {
  if probe.name.contains("{") {
    return full == probe.name
  }
  if probe.name != "*" && local_of(full) != probe.name {
    return false
  }
  let uri = namespace_of(full)
  match probe.space {
    AnySpace => true
    NoSpace => uri is None
    // With no default namespace declared, a type selector matches elements in
    // any namespace — Selectors' rule for a stylesheet that declares none.
    DefaultSpace =>
      if namespaces.default.is_empty() {
        true
      } else {
        uri == Some(namespaces.default)
      }
    Prefixed(prefix) =>
      match prefix_uri(namespaces, prefix) {
        Some(wanted) => uri == Some(wanted)
        None => true
      }
  }
}

///|
fn attr_matches(
  element : Element,
  req : AttrReq,
  namespaces : NamespaceMap,
) -> Bool {
  match attribute_value(element, req.name, namespaces) {
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
fn attribute_value(
  element : Element,
  probe : NameTest,
  namespaces : NamespaceMap,
) -> String? {
  for pair in element.attrs {
    if attribute_name_matches(pair.0, probe, namespaces) {
      return Some(pair.1)
    }
  }
  None
}

///|
/// An attribute selector against a `{uri}local` attribute name. An unprefixed
/// attribute test is always the no-namespace attribute: the default namespace
/// does not reach attributes.
fn attribute_name_matches(
  full : String,
  probe : NameTest,
  namespaces : NamespaceMap,
) -> Bool {
  if probe.name.contains("{") {
    return full == probe.name
  }
  if probe.name != "*" && local_of(full) != probe.name {
    return false
  }
  let uri = namespace_of(full)
  match probe.space {
    AnySpace => true
    NoSpace => uri is None
    DefaultSpace => uri is None
    Prefixed(prefix) =>
      match prefix_uri(namespaces, prefix) {
        Some(wanted) => uri == Some(wanted)
        None => true
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
fn pseudo_matches(
  pseudo : Pseudo,
  element : Element,
  namespaces : NamespaceMap,
) -> Bool {
  match pseudo {
    FirstChild => element.previous_element_sibling() is None
    LastChild => element.next_element_sibling() is None
    OnlyChild =>
      element.previous_element_sibling() is None &&
      element.next_element_sibling() is None
    NthChild(anb, of) =>
      match element.parent {
        Some(parent) =>
          position_matches(
            anb,
            of,
            parent.child_elements(),
            element,
            namespaces,
            from_end=false,
          )
        None => false
      }
    NthLastChild(anb, of) =>
      match element.parent {
        Some(parent) =>
          position_matches(
            anb,
            of,
            parent.child_elements(),
            element,
            namespaces,
            from_end=true,
          )
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
    // Only an element HTML lets a document disable can be either; a paragraph
    // is neither enabled nor disabled, which `:not(:enabled):not(:disabled)`
    // is the way to ask for.
    Disabled => is_disableable(element) && element.has_attr("disabled")
    Enabled => is_disableable(element) && !element.has_attr("disabled")
    Required => element.has_attr("required")
    Optional => !element.has_attr("required")
    Lang(wanted) => element.is_lang(wanted)
    Not(list) => !complex_list_matches(list, element, namespaces)
    Is(list) => complex_list_matches(list, element, namespaces)
    Where(list) => complex_list_matches(list, element, namespaces)
    Has(list) => has_matches(list, element, namespaces)
  }
}

///|
/// The elements HTML gives a disabled state: the form controls and the two
/// grouping elements. Everything else is outside both `:enabled` and
/// `:disabled`.
fn is_disableable(element : Element) -> Bool {
  match local_of(element.name) {
    "button"
    | "input"
    | "select"
    | "textarea"
    | "optgroup"
    | "option"
    | "fieldset" => true
    _ => false
  }
}

///|
/// One-based position among the siblings that share this element's name.
fn of_type_position(element : Element, from_end~ : Bool) -> Int32 {
  match element.parent {
    Some(parent) => {
      let siblings = parent.child_elements()
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
fn has_matches(
  list : Array[Complex],
  element : Element,
  namespaces : NamespaceMap,
) -> Bool {
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
        match element.next_element_sibling() {
          Some(sibling) => candidates.push(sibling)
          None => ()
        }
      LaterSibling =>
        match element.parent {
          Some(parent) => {
            let siblings = parent.child_elements()
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
      if compound_matches(first, candidate, namespaces) &&
        relative_chain(complex, 0, candidate, namespaces) {
        return true
      }
    }
  }
  false
}

///|
/// The rest of a relative selector, walked left-to-right from `element`.
fn relative_chain(
  complex : Complex,
  idx : Int32,
  element : Element,
  namespaces : NamespaceMap,
) -> Bool {
  if idx + 1 >= complex.parts.length() {
    return true
  }
  let (comb, compound) = complex.parts[idx + 1]
  match comb {
    Descendant => {
      for data in descendant_elements(element) {
        if compound_matches(compound, data, namespaces) &&
          relative_chain(complex, idx + 1, data, namespaces) {
          return true
        }
      }
      false
    }
    Child => {
      for child in element.children {
        if child is ElementNode(data) &&
          compound_matches(compound, data, namespaces) &&
          relative_chain(complex, idx + 1, data, namespaces) {
          return true
        }
      }
      false
    }
    NextSibling =>
      match element.next_element_sibling() {
        Some(sibling) =>
          compound_matches(compound, sibling, namespaces) &&
          relative_chain(complex, idx + 1, sibling, namespaces)
        None => false
      }
    LaterSibling =>
      match element.parent {
        Some(parent) => {
          let siblings = parent.child_elements()
          let mut past = false
          for sibling in siblings {
            if past && compound_matches(compound, sibling, namespaces) {
              if relative_chain(complex, idx + 1, sibling, namespaces) {
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
