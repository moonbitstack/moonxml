// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// XPath 1.0: the whole grammar, all thirteen axes, predicates carrying full
/// expressions, and the core function library. The result is typed —
/// `XPathValue` — which is what `xpath_value` answers; `xpath` answers the
/// node-set, or the string value of anything else as one text node, so the
/// chain never breaks.
///
/// Two documented departures: the `space` axis answers empty, because the
/// tree carries Clark names rather than space nodes; and the attribute
/// axis answers each value as a text node, because attributes are not nodes in
/// this tree — which is what makes `//a/@href` answer the links' URLs.

///|
/// A location step's axis.
priv enum Axis {
  Child
  Descendant
  Parent
  Ancestor
  FollowingSibling
  PrecedingSibling
  Following
  Preceding
  Attribute
  Namespace
  SelfAxis
  DescendantOrSelf
  AncestorOrSelf
}

///|
/// What a step keeps among the nodes its axis reaches.
priv enum Test {
  Name(String)
  TextTest
  CommentTest
  PiTest(String?)
  AnyTest
}

///|
/// One step: an axis, a test, and the predicates that filter it.
priv struct Step {
  axis : Axis
  probe : Test
  predicates : Array[Expr]
}

///|
/// The expression language.
priv enum Expr {
  Path(absolute~ : Bool, steps~ : Array[Step])
  Filter(base~ : Expr, predicates~ : Array[Expr])
  StepsFrom(base~ : Expr, steps~ : Array[Step])
  Union(lhs~ : Expr, rhs~ : Expr)
  Or(lhs~ : Expr, rhs~ : Expr)
  And(lhs~ : Expr, rhs~ : Expr)
  Eq(lhs~ : Expr, rhs~ : Expr)
  Ne(lhs~ : Expr, rhs~ : Expr)
  Lt(lhs~ : Expr, rhs~ : Expr)
  Le(lhs~ : Expr, rhs~ : Expr)
  Gt(lhs~ : Expr, rhs~ : Expr)
  Ge(lhs~ : Expr, rhs~ : Expr)
  Add(lhs~ : Expr, rhs~ : Expr)
  Sub(lhs~ : Expr, rhs~ : Expr)
  Mul(lhs~ : Expr, rhs~ : Expr)
  Div(lhs~ : Expr, rhs~ : Expr)
  Mod(lhs~ : Expr, rhs~ : Expr)
  Neg(Expr)
  Literal(String)
  Number(Double)
  Variable(String)
  Call(name~ : String, args~ : Array[Expr])
}

///|
/// An XPath 1.0 result: what the expression actually answered.
pub(all) enum XPathValue {
  Nodes(Selection)
  Str(String)
  Num(Double)
  Flag(Bool)
}

///|
pub impl Show for XPathValue with fn output(self, logger) {
  match self {
    Nodes(nodes) => logger.write_string("\{nodes.items.length()} nodes")
    Str(text) => logger.write_string(text)
    Num(number) => logger.write_string(number.to_string())
    Flag(flag) => logger.write_string(if flag { "true" } else { "false" })
  }
}

///|
pub extend XPathValue with Show::{output, to_string}

// The lexer. The one rule that needs care is XPath's own: `*`, `div`, `mod`,
// `and` and `or` are operators after an operand and names before one.

///|
priv enum Tok {
  Name(String)
  Num(Double)
  Str(String)
  Slash
  Slope
  Dot
  DotDot
  At
  ColonColon
  LBracket
  RBracket
  LParen
  RParen
  Comma
  Pipe
  Plus
  Minus
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
  Star
  Var(String)
  End
}

///|
fn tokenize(query : String) -> Array[Tok] raise Refused {
  let out : Array[Tok] = []
  let n = query.length()
  let mut i = 0
  let mut operand = false
  fn push(tok : Tok) -> Unit {
    out.push(tok)
  }
  while i < n {
    let unit = query.at(i)
    if unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D {
      i = i + 1
      continue
    }
    if unit == 0x2F {
      // '/', '//'
      if i + 1 < n && query.at(i + 1) == 0x2F {
        push(Slope)
        i = i + 2
      } else {
        push(Slash)
        i = i + 1
      }
      operand = false
      continue
    }
    if unit == 0x2E {
      if i + 1 < n && query.at(i + 1) == 0x2E {
        push(DotDot)
        i = i + 2
        operand = true
        continue
      }
      if i + 1 < n && is_digit(query.at(i + 1)) {
        let (value, next) = read_number(query, i)
        push(Num(value))
        i = next
        operand = true
        continue
      }
      push(Dot)
      i = i + 1
      operand = true
      continue
    }
    if is_digit(unit) {
      let (value, next) = read_number(query, i)
      push(Num(value))
      i = next
      operand = true
      continue
    }
    if unit == 0x22 || unit == 0x27 {
      let quote = query.at(i)
      let mut j = i + 1
      let run = StringBuilder()
      while j < n && query.at(j) != quote {
        run.write_char(u16_char(query.at(j)))
        j = j + 1
      }
      if j >= n {
        raise BadQuery(at=i, why="a string literal is unterminated")
      }
      push(Str(run.to_string()))
      i = j + 1
      operand = true
      continue
    }
    if unit == 0x40 {
      push(At)
      i = i + 1
      operand = false
      continue
    }
    if unit == 0x5B {
      push(LBracket)
      i = i + 1
      operand = false
      continue
    }
    if unit == 0x5D {
      push(RBracket)
      i = i + 1
      operand = true
      continue
    }
    if unit == 0x28 {
      push(LParen)
      i = i + 1
      operand = false
      continue
    }
    if unit == 0x29 {
      push(RParen)
      i = i + 1
      operand = true
      continue
    }
    if unit == 0x2C {
      push(Comma)
      i = i + 1
      operand = false
      continue
    }
    if unit == 0x7C {
      push(Pipe)
      i = i + 1
      operand = false
      continue
    }
    if unit == 0x2B {
      push(Plus)
      i = i + 1
      operand = false
      continue
    }
    if unit == 0x2D {
      push(Minus)
      i = i + 1
      operand = false
      continue
    }
    if unit == 0x3D {
      push(Eq)
      i = i + 1
      operand = false
      continue
    }
    if unit == 0x21 {
      if i + 1 < n && query.at(i + 1) == 0x3D {
        push(Ne)
        i = i + 2
        operand = false
        continue
      }
      raise BadQuery(at=i, why="`!` must be followed by `=`")
    }
    if unit == 0x3C {
      if i + 1 < n && query.at(i + 1) == 0x3D {
        push(Le)
        i = i + 2
      } else {
        push(Lt)
        i = i + 1
      }
      operand = false
      continue
    }
    if unit == 0x3E {
      if i + 1 < n && query.at(i + 1) == 0x3D {
        push(Ge)
        i = i + 2
      } else {
        push(Gt)
        i = i + 1
      }
      operand = false
      continue
    }
    if unit == 0x2A {
      // '*' is multiply after an operand, a wildcard before one
      push(Star)
      i = i + 1
      if operand {
        operand = false
      } else {
        operand = true
      }
      continue
    }
    if unit == 0x24 {
      // '$name'
      let (name, next) = read_var_name(query, i + 1)
      if name.is_empty() {
        raise BadQuery(at=i, why="a variable reference needs a name")
      }
      push(Var(name))
      i = next
      operand = true
      continue
    }
    if unit == 0x3A {
      // '::'
      if i + 1 < n && query.at(i + 1) == 0x3A {
        push(ColonColon)
        i = i + 2
        operand = false
        continue
      }
      raise BadQuery(at=i, why="a colon must be part of a name or `::`")
    }
    if is_xname_start(unit) {
      let run = StringBuilder()
      let mut j = i
      while j < n {
        let unit = query.at(j)
        if is_xname_char(unit) {
          run.write_char(u16_char(unit))
          j = j + 1
        } else if unit == 0x3A &&
          j + 1 < n &&
          !(query.at(j + 1) == 0x3A) &&
          is_xname_start(query.at(j + 1)) {
          // a QName's colon, not the axis separator
          run.write_char(':')
          j = j + 1
        } else {
          break
        }
      }
      push(Name(run.to_string()))
      i = j
      operand = true
      continue
    }
    raise BadQuery(at=i, why="an unexpected character")
  }
  push(End)
  out
}

///|
/// The name after a `$`.
fn read_var_name(query : String, from : Int32) -> (String, Int32) {
  let out = StringBuilder()
  let n = query.length()
  let mut i = from
  while i < n && is_xname_char(query.at(i)) {
    out.write_char(u16_char(query.at(i)))
    i = i + 1
  }
  (out.to_string(), i)
}

///|
/// A number: digits with an optional fraction and an optional exponent.
/// XPath 1.0 spells no exponent, but libxml2 accepts one and the corpus uses
/// it, so `1.23e3` reads as 1230 here too. The exponent is applied by hand:
/// `1e2147483648` is beyond what any parser's arithmetic should be asked to
/// raise, and the answer the corpus wants is simply infinity.
fn read_number(query : String, from : Int32) -> (Double, Int32) raise Refused {
  let n = query.length()
  let mut i = from
  let run = StringBuilder()
  while i < n && is_digit(query.at(i)) {
    run.write_char(u16_char(query.at(i)))
    i = i + 1
  }
  if i < n && query.at(i) == 0x2E {
    run.write_char('.')
    i = i + 1
    while i < n && is_digit(query.at(i)) {
      run.write_char(u16_char(query.at(i)))
      i = i + 1
    }
  }
  let text = run.to_string()
  let mantissa = Some(@string.parse_double(text)) catch { _ => None }
  let value = match mantissa {
    Some(value) => value
    None => raise BadQuery(at=from, why="a number that does not read")
  }
  let (exponent, next) = read_exponent(query, i)
  (scale_by_power_of_ten(value, exponent), next)
}

///|
/// The exponent of a number, as a count of decimal places to move: `e3` is 3,
/// `e-3` is -3, and no exponent at all is 0.
fn read_exponent(query : String, from : Int32) -> (Int32, Int32) {
  let n = query.length()
  if from >= n || (query.at(from) != 0x65 && query.at(from) != 0x45) {
    return (0, from)
  }
  let mut i = from + 1
  let mut negative = false
  if i < n && (query.at(i) == 0x2B || query.at(i) == 0x2D) {
    negative = query.at(i) == 0x2D
    i = i + 1
  }
  if i >= n || !is_digit(query.at(i)) {
    return (0, from)
  }
  // A saturating count: past a thousand places the answer is infinity or
  // zero either way, and a number that big would only overflow.
  let mut magnitude = 0
  while i < n && is_digit(query.at(i)) {
    if magnitude < 100000 {
      magnitude = magnitude * 10 + (Char::to_int(u16_char(query.at(i))) - 48)
    }
    i = i + 1
  }
  (if negative { -magnitude } else { magnitude }, i)
}

///|
fn infinity() -> Double {
  1.0 / 0.0
}

///|
fn scale_by_power_of_ten(value : Double, exponent : Int32) -> Double {
  if exponent == 0 {
    return value
  }
  if exponent > 400 {
    if value == 0.0 {
      return value
    }
    return if value < 0.0 { -infinity() } else { infinity() }
  }
  if exponent < -400 {
    return if value < 0.0 { -0.0 } else { 0.0 }
  }
  let mut out = value
  let mut left = if exponent < 0 { -exponent } else { exponent }
  while left > 0 {
    if exponent > 0 {
      out = out * 10.0
    } else {
      out = out / 10.0
    }
    left = left - 1
  }
  out
}

///|
fn is_digit(unit : UInt16) -> Bool {
  unit >= 0x30 && unit <= 0x39
}

///|
fn is_xname_start(unit : UInt16) -> Bool {
  (unit >= 0x61 && unit <= 0x7A) ||
  (unit >= 0x41 && unit <= 0x5A) ||
  unit == 0x5F ||
  unit > 0x7F
}

///|
fn is_xname_char(unit : UInt16) -> Bool {
  is_xname_start(unit) || is_digit(unit) || unit == 0x2D
}

// The parser, a recursive descent over the token array.

///|
priv struct Parser {
  toks : Array[Tok]
  mut at : Int32
}

///|
fn Parser::new(toks : Array[Tok]) -> Parser {
  { toks, at: 0, }
}

///|
fn Parser::peek(self : Parser) -> Tok {
  self.toks[self.at]
}

///|
fn Parser::take(self : Parser) -> Tok {
  let tok = self.toks[self.at]
  self.at = self.at + 1
  tok
}

///|
/// Parse a whole expression.
fn xpath_parse(query : String) -> Expr raise Refused {
  let parser = Parser::new(tokenize(query))
  let expr = parse_or(parser)
  if !(parser.peek() is End) {
    raise BadQuery(at=0, why="the expression continues past its end")
  }
  expr
}

///|
fn parse_or(p : Parser) -> Expr raise Refused {
  let mut lhs = parse_and(p)
  while p.peek() is Name(word) && word == "or" {
    ignore(p.take())
    lhs = Or(lhs~, rhs=parse_and(p))
  }
  lhs
}

///|
fn parse_and(p : Parser) -> Expr raise Refused {
  let mut lhs = parse_equality(p)
  while p.peek() is Name(word) && word == "and" {
    ignore(p.take())
    lhs = And(lhs~, rhs=parse_equality(p))
  }
  lhs
}

///|
fn parse_equality(p : Parser) -> Expr raise Refused {
  let mut lhs = parse_relational(p)
  while true {
    let op = p.peek()
    if op is Eq {
      ignore(p.take())
      lhs = Eq(lhs~, rhs=parse_relational(p))
    } else if op is Ne {
      ignore(p.take())
      lhs = Ne(lhs~, rhs=parse_relational(p))
    } else {
      return lhs
    }
  }
  lhs
}

///|
fn parse_relational(p : Parser) -> Expr raise Refused {
  let mut lhs = parse_additive(p)
  while true {
    let op = p.peek()
    if op is Lt {
      ignore(p.take())
      lhs = Lt(lhs~, rhs=parse_additive(p))
    } else if op is Le {
      ignore(p.take())
      lhs = Le(lhs~, rhs=parse_additive(p))
    } else if op is Gt {
      ignore(p.take())
      lhs = Gt(lhs~, rhs=parse_additive(p))
    } else if op is Ge {
      ignore(p.take())
      lhs = Ge(lhs~, rhs=parse_additive(p))
    } else {
      return lhs
    }
  }
  lhs
}

///|
fn parse_additive(p : Parser) -> Expr raise Refused {
  let mut lhs = parse_multiplicative(p)
  while true {
    let op = p.peek()
    if op is Plus {
      ignore(p.take())
      lhs = Add(lhs~, rhs=parse_multiplicative(p))
    } else if op is Minus {
      ignore(p.take())
      lhs = Sub(lhs~, rhs=parse_multiplicative(p))
    } else {
      return lhs
    }
  }
  lhs
}

///|
fn parse_multiplicative(p : Parser) -> Expr raise Refused {
  let mut lhs = parse_unary(p)
  while true {
    let op = p.peek()
    if op is Star {
      ignore(p.take())
      lhs = Mul(lhs~, rhs=parse_unary(p))
    } else if op is Name(word) && (word == "div" || word == "mod") {
      ignore(p.take())
      lhs = if word == "div" {
        Div(lhs~, rhs=parse_unary(p))
      } else {
        Mod(lhs~, rhs=parse_unary(p))
      }
    } else {
      return lhs
    }
  }
  lhs
}

///|
fn parse_unary(p : Parser) -> Expr raise Refused {
  if p.peek() is Minus {
    ignore(p.take())
    Neg(parse_unary(p))
  } else {
    parse_union(p)
  }
}

///|
fn parse_union(p : Parser) -> Expr raise Refused {
  let mut lhs = parse_path(p)
  while p.peek() is Pipe {
    ignore(p.take())
    lhs = Union(lhs~, rhs=parse_path(p))
  }
  lhs
}

///|
/// PathExpr: a location path, a primary expression, or a primary expression
/// continued with `/` or `//` and steps.
fn parse_path(p : Parser) -> Expr raise Refused {
  let start = p.peek()
  let is_step_start = match start {
    Slash | Slope | Dot | DotDot | At | Star => true
    Name(name) => !starts_call(p, name)
    _ => false
  }
  if is_step_start {
    return parse_location_path(p)
  }
  let mut base = parse_primary(p)
  let predicates : Array[Expr] = []
  while p.peek() is LBracket {
    ignore(p.take())
    predicates.push(parse_or(p))
    expect_rbracket(p)
  }
  if !predicates.is_empty() {
    base = Filter(base~, predicates~)
  }
  // FilterExpr '/' steps, which run from the nodes the filter answered
  let steps : Array[Step] = []
  let mut continued = false
  while true {
    let op = p.peek()
    if op is Slash {
      ignore(p.take())
    } else if op is Slope {
      ignore(p.take())
      steps.push(descendant_or_self_step())
    } else {
      break
    }
    steps.push(parse_step(p))
    continued = true
  }
  if !continued {
    base
  } else {
    StepsFrom(base~, steps~)
  }
}

///|
/// Whether a name begins a function call rather than a step.
fn starts_call(p : Parser, name : String) -> Bool {
  ignore(name)
  match p.toks[p.at + 1] {
    LParen => true
    _ => false
  }
}

///|
fn parse_location_path(p : Parser) -> Expr raise Refused {
  let mut absolute = false
  let steps : Array[Step] = []
  if p.peek() is Slash {
    ignore(p.take())
    absolute = true
  } else if p.peek() is Slope {
    ignore(p.take())
    absolute = true
    steps.push(descendant_or_self_step())
  }
  if p.peek() is End {
    return Path(absolute~, steps~)
  }
  steps.push(parse_step(p))
  while true {
    let op = p.peek()
    if op is Slash {
      ignore(p.take())
      steps.push(parse_step(p))
    } else if op is Slope {
      ignore(p.take())
      steps.push(descendant_or_self_step())
      steps.push(parse_step(p))
    } else {
      break
    }
  }
  Path(absolute~, steps~)
}

///|
/// The step `//` stands for: `descendant-or-self::node()`.
fn descendant_or_self_step() -> Step {
  { axis: Axis::DescendantOrSelf, probe: AnyTest, predicates: [], }
}

///|
fn parse_step(p : Parser) -> Step raise Refused {
  if p.peek() is Dot {
    ignore(p.take())
    return { axis: Axis::SelfAxis, probe: AnyTest, predicates: [], }
  }
  if p.peek() is DotDot {
    ignore(p.take())
    return { axis: Axis::Parent, probe: AnyTest, predicates: [], }
  }
  let mut axis : Axis = Axis::Child
  if p.peek() is At {
    ignore(p.take())
    axis = Axis::Attribute
  } else if p.peek() is Name(name) {
    // axis:: ?
    if p.toks[p.at + 1] is ColonColon {
      axis = match axis_of(name) {
        Some(axis) => axis
        None =>
          raise BadQuery(
            at=0,
            why="an axis this library does not know: \{name}",
          )
      }
      ignore(p.take())
      ignore(p.take())
    }
  }
  let probe = parse_test(p)
  let predicates : Array[Expr] = []
  while p.peek() is LBracket {
    ignore(p.take())
    predicates.push(parse_or(p))
    expect_rbracket(p)
  }
  { axis, probe, predicates, }
}

///|
fn axis_of(name : String) -> Axis? {
  match name {
    "child" => Some(Axis::Child)
    "descendant" => Some(Axis::Descendant)
    "parent" => Some(Axis::Parent)
    "ancestor" => Some(Axis::Ancestor)
    "following-sibling" => Some(Axis::FollowingSibling)
    "preceding-sibling" => Some(Axis::PrecedingSibling)
    "following" => Some(Axis::Following)
    "preceding" => Some(Axis::Preceding)
    "attribute" => Some(Axis::Attribute)
    "namespace" => Some(Axis::Namespace)
    // The axis was called `space` before it took XPath's own spelling; a query
    // written against the old name still reads.
    "space" => Some(Axis::Namespace)
    "self" => Some(Axis::SelfAxis)
    "descendant-or-self" => Some(Axis::DescendantOrSelf)
    "ancestor-or-self" => Some(Axis::AncestorOrSelf)
    _ => None
  }
}

///|
fn parse_test(p : Parser) -> Test raise Refused {
  match p.peek() {
    Star => {
      ignore(p.take())
      Name("*")
    }
    Name(name) =>
      if p.toks[p.at + 1] is LParen && is_node_type(name) {
        ignore(p.take())
        ignore(p.take())
        let target = if p.peek() is Str(text) {
          ignore(p.take())
          Some(text)
        } else {
          None
        }
        expect_rparen(p)
        match name {
          "node" => AnyTest
          "text" => TextTest
          "comment" => CommentTest
          _ => PiTest(target)
        }
      } else {
        ignore(p.take())
        Name(name)
      }
    _ => raise BadQuery(at=0, why="a step needs a node test")
  }
}

///|
fn is_node_type(name : String) -> Bool {
  name == "node" ||
  name == "text" ||
  name == "comment" ||
  name == "processing-instruction"
}

///|
fn parse_primary(p : Parser) -> Expr raise Refused {
  match p.peek() {
    Var(name) => {
      ignore(p.take())
      Variable(name)
    }
    Num(value) => {
      ignore(p.take())
      Number(value)
    }
    Str(text) => {
      ignore(p.take())
      Literal(text)
    }
    LParen => {
      ignore(p.take())
      let inner = parse_or(p)
      expect_rparen(p)
      inner
    }
    Name(name) =>
      if p.toks[p.at + 1] is LParen {
        ignore(p.take())
        ignore(p.take())
        let args : Array[Expr] = []
        if !(p.peek() is RParen) {
          args.push(parse_or(p))
          while p.peek() is Comma {
            ignore(p.take())
            args.push(parse_or(p))
          }
        }
        expect_rparen(p)
        Call(name~, args~)
      } else {
        raise BadQuery(at=0, why="a bare name is not an expression: \{name}")
      }
    End => raise BadQuery(at=0, why="the expression ends early")
    _ => raise BadQuery(at=0, why="the expression is not one")
  }
}

///|
fn expect_rbracket(p : Parser) -> Unit raise Refused {
  if p.peek() is RBracket {
    ignore(p.take())
  } else {
    raise BadQuery(at=0, why="a predicate needs its `]`")
  }
}

///|
fn expect_rparen(p : Parser) -> Unit raise Refused {
  if p.peek() is RParen {
    ignore(p.take())
  } else {
    raise BadQuery(at=0, why="a call needs its `)`")
  }
}

// Evaluation.

///|
/// Where a node sits in its tree. Text, comment, CDATA and
/// processing-instruction nodes carry no pointer, so a node is named by the
/// place it occupies — its parent and its index — rather than by its value.
/// Two text nodes that hold the same characters are still two nodes, which is
/// what `//.` and deduplication need. Attributes and namespaces are nodes of
/// their own, named by their owner and their name or prefix.
priv enum Spot {
  El(Element)
  Kid(Element, Int32)
  Attr(Element, String)
  Space(Element, String)
}

///|
/// The node a spot names.
fn spot_node(spot : Spot) -> Node {
  match spot {
    El(element) => ElementNode(element)
    Kid(parent, at) => parent.children[at]
    Attr(owner, name) =>
      AttributeNode({ owner, name, value: owner.attr(name).unwrap_or(""), })
    Space(owner, prefix) =>
      NamespaceNode({
        owner,
        prefix,
        uri: namespace_uri_in_scope(owner, prefix).unwrap_or(""),
      })
  }
}

///|
/// The element a spot names, or `None` for a spot that is not one.
fn spot_element(spot : Spot) -> Element? {
  match spot {
    El(element) => Some(element)
    Kid(parent, at) =>
      match parent.children[at] {
        ElementNode(data) => Some(data)
        _ => None
      }
    _ => None
  }
}

///|
/// The element that owns a spot whatever the spot's kind: what `lang()`, the
/// following and preceding axes and the writer ask for.
fn spot_owner(spot : Spot) -> Element? {
  match spot {
    El(element) => Some(element)
    Kid(parent, at) =>
      match parent.children[at] {
        ElementNode(data) => Some(data)
        _ => Some(parent)
      }
    Attr(owner, _) => Some(owner)
    Space(owner, _) => Some(owner)
  }
}

///|
/// The spot of an element: the root, which has no parent, is the only element
/// named on its own.
fn spot_of_element(element : Element) -> Spot {
  match element.parent {
    Some(parent) => {
      for k = 0; k < parent.children.length(); k = k + 1 {
        match parent.children[k] {
          ElementNode(data) =>
            if physical_equal(data, element) {
              return Kid(parent, k)
            }
          _ => ()
        }
      }
      El(element)
    }
    None => El(element)
  }
}

///|
/// Whether a spot is the document's root node — the virtual container that
/// XPath calls the root rather than an element.
fn spot_is_root(spot : Spot) -> Bool {
  match spot {
    El(element) => element.parent is None && element.name == "#document"
    _ => false
  }
}

///|
fn same_spot(a : Spot, b : Spot) -> Bool {
  match (a, b) {
    (El(x), El(y)) => physical_equal(x, y)
    (Kid(px, ax), Kid(py, ay)) => ax == ay && physical_equal(px, py)
    (Attr(ox, nx), Attr(oy, ny)) => nx == ny && physical_equal(ox, oy)
    (Space(ox, nx), Space(oy, ny)) => nx == ny && physical_equal(ox, oy)
    _ => false
  }
}

///|
fn is_namespace_declaration(name : String) -> Bool {
  name == "xmlns" || name.has_prefix("xmlns:")
}

///|
/// The prefix an `xmlns` attribute declares, `""` for the default namespace.
fn declared_prefix(name : String) -> String? {
  if name == "xmlns" {
    Some("")
  } else if name.has_prefix("xmlns:") {
    Some(name[6:name.length()].to_owned())
  } else {
    None
  }
}

///|
/// The namespaces in scope on an element, nearest declaration first, with the
/// `xml` prefix always there. An undeclaration (`xmlns=""`) declares nothing.
fn namespaces_in_scope(element : Element) -> Array[(String, String)] {
  let out : Array[(String, String)] = [
    ("xml", "http://www.w3.org/XML/1998/namespace"),
  ]
  let mut current : Element? = Some(element)
  while current is Some(here) {
    for pair in here.attrs {
      match declared_prefix(pair.0) {
        Some(prefix) =>
          if pair.1 != "" && !out.iter().any(seen => seen.0 == prefix) {
            out.push((prefix, pair.1))
          }
        None => ()
      }
    }
    current = here.parent
  }
  out
}

///|
fn namespace_uri_in_scope(element : Element, prefix : String) -> String? {
  for pair in namespaces_in_scope(element) {
    if pair.0 == prefix {
      return Some(pair.1)
    }
  }
  None
}

///|
fn spot_parent(spot : Spot) -> Spot? {
  match spot {
    El(element) =>
      match element.parent {
        Some(above) => Some(spot_of_element(above))
        None => None
      }
    Kid(parent, _) => Some(spot_of_element(parent))
    Attr(owner, _) => Some(spot_of_element(owner))
    Space(owner, _) => Some(spot_of_element(owner))
  }
}

///|
fn is_xml_declaration(parent : Element, node : Node) -> Bool {
  match node {
    ProcessingInstructionNode(pi) =>
      pi.target == "xml" && parent.name == "#document"
    _ => false
  }
}

///|
/// The children of a spot, in document order. The XML declaration is not a
/// node of XPath's data model, so it is not a child here either.
fn spot_children(spot : Spot) -> Array[Spot] {
  let out : Array[Spot] = []
  match spot_element(spot) {
    Some(element) =>
      for at = 0; at < element.children.length(); at = at + 1 {
        if !is_xml_declaration(element, element.children[at]) {
          out.push(Kid(element, at))
        }
      }
    None => ()
  }
  out
}

///|
/// The attribute nodes of a spot, in document order. A namespace declaration
/// is not an attribute.
fn spot_attributes(spot : Spot) -> Array[Spot] {
  let out : Array[Spot] = []
  match spot_element(spot) {
    Some(element) =>
      for pair in element.attrs {
        if !is_namespace_declaration(pair.0) {
          out.push(Attr(element, pair.0))
        }
      }
    None => ()
  }
  out
}

///|
fn spot_namespaces(spot : Spot) -> Array[Spot] {
  let out : Array[Spot] = []
  match spot_element(spot) {
    Some(element) =>
      for pair in namespaces_in_scope(element) {
        out.push(Space(element, pair.0))
      }
    None => ()
  }
  out
}

///|
fn push_descendants(spot : Spot, out : Array[Spot]) -> Unit {
  for child in spot_children(spot) {
    out.push(child)
    push_descendants(child, out)
  }
}

///|
/// Every spot of the tree under `spot`, in document order: a node, then the
/// namespaces and attributes of an element, then its children.
fn push_walk(spot : Spot, out : Array[Spot]) -> Unit {
  out.push(spot)
  match spot_element(spot) {
    Some(_) => {
      for found in spot_namespaces(spot) {
        out.push(found)
      }
      for found in spot_attributes(spot) {
        out.push(found)
      }
      for child in spot_children(spot) {
        push_walk(child, out)
      }
    }
    None => ()
  }
}

///|
fn document_root_spot(spot : Spot) -> Spot {
  match spot_owner(spot) {
    Some(start) => {
      let mut top = start
      let mut climbing = true
      while climbing {
        match top.parent {
          Some(above) => top = above
          None => climbing = false
        }
      }
      El(top)
    }
    None => spot
  }
}

///|
/// Whether `spot` sits inside `ancestor`'s subtree, itself excluded.
fn is_descendant_spot(spot : Spot, ancestor : Spot) -> Bool {
  let mut current = spot_parent(spot)
  while current is Some(above) {
    if same_spot(above, ancestor) {
      return true
    }
    current = spot_parent(above)
  }
  false
}

///|
/// A spot's value as a number, for the node-set rules of §3.4.
fn spot_number(spot : Spot) -> Double {
  text_to_number(string_value(spot))
}

///|
/// A spot's string value: an element answers its text, an attribute its value,
/// a namespace its URI.
fn string_value(spot : Spot) -> String {
  match spot {
    Kid(parent, at) => node_string(parent.children[at])
    El(element) => element.text()
    Attr(owner, name) => owner.attr(name).unwrap_or("")
    Space(owner, prefix) => namespace_uri_in_scope(owner, prefix).unwrap_or("")
  }
}

///|
fn node_string(node : Node) -> String {
  match node {
    TextNode(text) => text
    CDataNode(text) => text
    CommentNode(text) => text
    ProcessingInstructionNode(pi) => pi.data
    AttributeNode(attr) => attr.value
    NamespaceNode(space) => space.uri
    ElementNode(element) => element.text()
    DoctypeNode(_) => ""
  }
}

///|
/// A spot with the position and size the predicate that sees it was given.
priv struct Ctx {
  spot : Spot
  order : Int32
  size : Int32
}

///|
/// An XPath value while it is being computed: node-sets are arrays of spots,
/// so that two nodes carrying the same text stay two nodes.
priv enum Val {
  VNodes(Array[Spot])
  VStr(String)
  VNum(Double)
  VFlag(Bool)
}

///|
fn eval_expr(expr : Expr, ctx : Ctx, doc : Document?) -> Val raise Refused {
  match expr {
    Literal(text) => VStr(text)
    Number(value) => VNum(value)
    Variable(name) =>
      raise Unsupported(what="the XPath variable $\{name} has no binding")
    Path(absolute~, steps~) => {
      let start = if absolute { document_root_spot(ctx.spot) } else { ctx.spot }
      VNodes(walk_steps([start], steps, doc))
    }
    Union(lhs~, rhs~) => {
      let merged : Array[Spot] = []
      match eval_expr(lhs, ctx, doc) {
        VNodes(found) => merged.push_iter(found.iter())
        _ => ()
      }
      match eval_expr(rhs, ctx, doc) {
        VNodes(found) => merged.push_iter(found.iter())
        _ => ()
      }
      VNodes(normalize(merged))
    }
    Filter(base~, predicates~) =>
      match eval_expr(base, ctx, doc) {
        VNodes(found) => VNodes(apply_predicates(found, predicates, doc))
        other => other
      }
    StepsFrom(base~, steps~) =>
      match eval_expr(base, ctx, doc) {
        VNodes(found) => VNodes(walk_steps(found, steps, doc))
        _ => VNodes([])
      }
    Or(lhs~, rhs~) =>
      VFlag(
        truthy(eval_expr(lhs, ctx, doc)) || truthy(eval_expr(rhs, ctx, doc)),
      )
    And(lhs~, rhs~) =>
      VFlag(
        truthy(eval_expr(lhs, ctx, doc)) && truthy(eval_expr(rhs, ctx, doc)),
      )
    Eq(lhs~, rhs~) =>
      VFlag(compare(eval_expr(lhs, ctx, doc), eval_expr(rhs, ctx, doc), "="))
    Ne(lhs~, rhs~) =>
      VFlag(compare(eval_expr(lhs, ctx, doc), eval_expr(rhs, ctx, doc), "!="))
    Lt(lhs~, rhs~) =>
      VFlag(compare(eval_expr(lhs, ctx, doc), eval_expr(rhs, ctx, doc), "<"))
    Le(lhs~, rhs~) =>
      VFlag(compare(eval_expr(lhs, ctx, doc), eval_expr(rhs, ctx, doc), "<="))
    Gt(lhs~, rhs~) =>
      VFlag(compare(eval_expr(lhs, ctx, doc), eval_expr(rhs, ctx, doc), ">"))
    Ge(lhs~, rhs~) =>
      VFlag(compare(eval_expr(lhs, ctx, doc), eval_expr(rhs, ctx, doc), ">="))
    Add(lhs~, rhs~) =>
      VNum(
        numeric(eval_expr(lhs, ctx, doc)) + numeric(eval_expr(rhs, ctx, doc)),
      )
    Sub(lhs~, rhs~) =>
      VNum(
        numeric(eval_expr(lhs, ctx, doc)) - numeric(eval_expr(rhs, ctx, doc)),
      )
    Mul(lhs~, rhs~) =>
      VNum(
        numeric(eval_expr(lhs, ctx, doc)) * numeric(eval_expr(rhs, ctx, doc)),
      )
    Div(lhs~, rhs~) =>
      VNum(
        numeric(eval_expr(lhs, ctx, doc)) / numeric(eval_expr(rhs, ctx, doc)),
      )
    Mod(lhs~, rhs~) =>
      VNum(
        numeric(eval_expr(lhs, ctx, doc)) % numeric(eval_expr(rhs, ctx, doc)),
      )
    // Unary minus negates rather than subtracting from zero: `-0` has to stay
    // negative, because `1 div -0` is -Infinity and the sign is observable.
    Neg(inner) => VNum(-numeric(eval_expr(inner, ctx, doc)))
    Call(name~, args~) => call(name, args, ctx, doc)
  }
}

///|
/// Run the steps from the starting spots.
fn walk_steps(
  start : Array[Spot],
  steps : Array[Step],
  doc : Document?,
) -> Array[Spot] raise Refused {
  let mut current = start
  for step in steps {
    // A step is evaluated with respect to each context node and its
    // predicates see that node's own node-set — which is why `//div/p[1]` is
    // the first paragraph of every div, not the first of all of them.
    let gathered : Array[Spot] = []
    for spot in current {
      let reached = apply_test(
        step.probe,
        step.axis,
        apply_axis(step.axis, spot),
        doc,
      )
      // The axis already answers in its own order — proximity first for a
      // reverse axis — which is the order a predicate's position counts in.
      for found in apply_predicates(reached, step.predicates, doc) {
        gathered.push(found)
      }
    }
    current = normalize(gathered)
  }
  current
}

///|
/// Every spot the axis reaches from the context node, in the axis's own order.
fn apply_axis(axis : Axis, spot : Spot) -> Array[Spot] {
  let out : Array[Spot] = []
  match axis {
    Axis::SelfAxis => out.push(spot)
    Axis::Child => out.push_iter(spot_children(spot).iter())
    Axis::Descendant => push_descendants(spot, out)
    Axis::DescendantOrSelf => {
      out.push(spot)
      push_descendants(spot, out)
    }
    Axis::Parent =>
      match spot_parent(spot) {
        Some(above) => out.push(above)
        None => ()
      }
    Axis::Ancestor => {
      let mut current = spot_parent(spot)
      while current is Some(above) {
        out.push(above)
        current = spot_parent(above)
      }
    }
    Axis::AncestorOrSelf => {
      out.push(spot)
      let mut current = spot_parent(spot)
      while current is Some(above) {
        out.push(above)
        current = spot_parent(above)
      }
    }
    Axis::FollowingSibling =>
      match spot {
        Kid(parent, at) =>
          for k = at + 1; k < parent.children.length(); k = k + 1 {
            if !is_xml_declaration(parent, parent.children[k]) {
              out.push(Kid(parent, k))
            }
          }
        _ => ()
      }
    Axis::PrecedingSibling =>
      match spot {
        Kid(parent, at) =>
          for k = at - 1; k >= 0; k = k - 1 {
            if !is_xml_declaration(parent, parent.children[k]) {
              out.push(Kid(parent, k))
            }
          }
        _ => ()
      }
    Axis::Following => {
      let walk : Array[Spot] = []
      push_walk(document_root_spot(spot), walk)
      let mut past = false
      for found in walk {
        if past && !is_descendant_spot(found, spot) {
          match found {
            Attr(_, _) | Space(_, _) => ()
            _ => out.push(found)
          }
        }
        if !past && same_spot(found, spot) {
          past = true
        }
      }
    }
    Axis::Preceding => {
      let walk : Array[Spot] = []
      push_walk(document_root_spot(spot), walk)
      let before : Array[Spot] = []
      for found in walk {
        if same_spot(found, spot) {
          break
        }
        match found {
          Attr(_, _) | Space(_, _) => ()
          _ => if !is_descendant_spot(spot, found) { before.push(found) }
        }
      }
      for k = before.length() - 1; k >= 0; k = k - 1 {
        out.push(before[k])
      }
    }
    Axis::Attribute => out.push_iter(spot_attributes(spot).iter())
    Axis::Namespace => out.push_iter(spot_namespaces(spot).iter())
  }
  out
}

///|
/// The nodes of an axis result that the test keeps.
fn apply_test(
  probe : Test,
  axis : Axis,
  spots : Array[Spot],
  doc : Document?,
) -> Array[Spot] {
  let out : Array[Spot] = []
  for spot in spots {
    let node = spot_node(spot)
    let keep = match probe {
      // `node()` is every node of the data model but the doctype: XPath has no
      // node for a document type declaration.
      AnyTest => !(node is DoctypeNode(_))
      TextTest => node.is_text()
      CommentTest => node is CommentNode(_)
      PiTest(target) =>
        match node {
          ProcessingInstructionNode(pi) =>
            match target {
              Some(wanted) => pi.target == wanted
              None => true
            }
          _ => false
        }
      // A name test keeps the axis's principal node type: attributes on the
      // attribute axis, namespaces on the namespace axis, elements elsewhere.
      // So `attribute::*` is every attribute while `self::*` on an attribute
      // is nothing.
      Name(wanted) =>
        match axis {
          Axis::Attribute =>
            match spot {
              Attr(_, name) => wanted == "*" || name == wanted
              _ => false
            }
          Axis::Namespace =>
            match spot {
              Space(_, prefix) => wanted == "*" || prefix == wanted
              _ => false
            }
          _ =>
            match spot {
              El(element) =>
                !spot_is_root(spot) && xpath_name_matches(element.name, wanted)
              Kid(parent, at) =>
                match parent.children[at] {
                  ElementNode(element) =>
                    xpath_name_matches(element.name, wanted)
                  _ => false
                }
              _ => false
            }
        }
    }
    if keep {
      out.push(spot)
    } else {
      ignore(doc)
    }
  }
  out
}

///|
/// A name test against a `{uri}local` name. XPath here binds no prefixes, so a
/// prefixed test matches by its local part, and a test with no prefix matches
/// the local part of any name.
fn xpath_name_matches(full : String, probe : String) -> Bool {
  if probe == "*" || full == probe {
    return true
  }
  if probe.contains("{") {
    return false
  }
  let want = match probe.find(":") {
    Some(at) => probe[at + 1:probe.length()].to_owned()
    None => probe
  }
  local_of(full) == want
}

///|
/// Apply the predicates in order: each sees the node-set as it stands, with
/// the position and size the node had among it.
fn apply_predicates(
  spots : Array[Spot],
  predicates : Array[Expr],
  doc : Document?,
) -> Array[Spot] raise Refused {
  let mut current = spots
  for predicate in predicates {
    let kept : Array[Spot] = []
    let size = current.length()
    for k = 0; k < size; k = k + 1 {
      let ctx : Ctx = { spot: current[k], order: k + 1, size, }
      let value = eval_expr(predicate, ctx, doc)
      let hold = match value {
        VNum(wanted) => wanted == (k + 1).to_double()
        other => truthy(other)
      }
      if hold {
        kept.push(current[k])
      }
    }
    current = kept
  }
  current
}

// Typed conversions, XPath 1.0 §4.

///|
fn to_string_value(value : Val) -> String {
  match value {
    VStr(text) => text
    VNum(number) => number_to_string(number)
    VFlag(flag) => if flag { "true" } else { "false" }
    VNodes(spots) => if spots.is_empty() { "" } else { string_value(spots[0]) }
  }
}

///|
fn numeric(value : Val) -> Double {
  match value {
    VNum(number) => number
    VStr(text) => text_to_number(text)
    VFlag(flag) => if flag { 1.0 } else { 0.0 }
    VNodes(spots) =>
      if spots.is_empty() {
        f64_nan()
      } else {
        spot_number(spots[0])
      }
  }
}

///|
fn truthy(value : Val) -> Bool {
  match value {
    VFlag(flag) => flag
    VNum(number) => number != 0.0 && !is_nan(number)
    VStr(text) => !text.is_empty()
    VNodes(spots) => !spots.is_empty()
  }
}

///|
/// XPath's number() over a string: leading and trailing whitespace ignored,
/// anything that is not a number is NaN.
fn text_to_number(text : String) -> Double {
  let trimmed = text.trim()
  if trimmed.is_empty() {
    return f64_nan()
  }
  @string.parse_double(trimmed) catch {
    _ => f64_nan()
  }
}

///|
/// XPath's string() over a number (§4.2): integers without a decimal point,
/// NaN and the infinities spelled out.
fn number_to_string(number : Double) -> String {
  if is_nan(number) {
    return "NaN"
  }
  if number > 1.7976931348623157e308 {
    return "Infinity"
  }
  if number < -1.7976931348623157e308 {
    return "-Infinity"
  }
  if number == 0.0 {
    return "0"
  }
  let negative = number < 0.0
  let magnitude = if negative { 0.0 - number } else { number }
  if magnitude == magnitude.floor() && magnitude < 1.0e18 {
    let whole = magnitude.to_int()
    let digits = whole.to_string()
    return if negative { "-" + digits } else { digits }
  }
  number.to_string()
}

///|
/// The comparisons of §3.4. A relational comparison is numeric on both sides —
/// `'b' > 'a'` compares two NaNs and is false, which is the specification's
/// answer, not lexicographic order. Equality compares strings when neither
/// side is a number or a boolean.
fn compare(lhs : Val, rhs : Val, op : String) -> Bool {
  let relational = op == "<" || op == "<=" || op == ">" || op == ">="
  match (lhs, rhs) {
    (VNodes(left), VNodes(right)) => {
      for a in left {
        for b in right {
          let same = if relational {
            compare_numbers(spot_number(a), spot_number(b), op)
          } else if op == "=" {
            string_value(a) == string_value(b)
          } else {
            string_value(a) != string_value(b)
          }
          if same {
            return true
          }
        }
      }
      false
    }
    (VNodes(left), other) => spot_set_against(left, other, op, relational)
    (other, VNodes(right)) => spot_set_against(right, other, op, relational)
    _ =>
      if relational {
        compare_numbers(numeric(lhs), numeric(rhs), op)
      } else {
        match (lhs, rhs) {
          (VFlag(a), _) => compare_booleans(a, truthy(rhs), op)
          (_, VFlag(b)) => compare_booleans(truthy(lhs), b, op)
          (VNum(a), _) => compare_numbers(a, numeric(rhs), op)
          (_, VNum(b)) => compare_numbers(numeric(lhs), b, op)
          (VStr(a), VStr(b)) => compare_strings(a, b, op)
          _ => false
        }
      }
  }
}

///|
fn spot_set_against(
  spots : Array[Spot],
  other : Val,
  op : String,
  relational : Bool,
) -> Bool {
  match other {
    VFlag(flag) => compare_booleans(!spots.is_empty(), flag, op)
    VNum(wanted) =>
      spots.iter().any(spot => compare_numbers(spot_number(spot), wanted, op))
    VStr(wanted) =>
      if relational {
        let number = text_to_number(wanted)
        spots.iter().any(spot => compare_numbers(spot_number(spot), number, op))
      } else if op == "=" {
        spots.iter().any(spot => string_value(spot) == wanted)
      } else {
        spots.iter().any(spot => string_value(spot) != wanted)
      }
    VNodes(_) => false
  }
}

///|
fn compare_booleans(a : Bool, b : Bool, op : String) -> Bool {
  match op {
    "=" => a == b
    "!=" => a != b
    "<" => !a && b
    "<=" => !a || b
    ">" => a && !b
    ">=" => a || !b
    _ => false
  }
}

///|
fn compare_numbers(a : Double, b : Double, op : String) -> Bool {
  match op {
    "=" => a == b
    "!=" => a != b
    "<" => a < b
    "<=" => a <= b
    ">" => a > b
    ">=" => a >= b
    _ => false
  }
}

///|
fn compare_strings(a : String, b : String, op : String) -> Bool {
  let order = compare_lexicographic(a, b)
  match op {
    "=" => order == 0
    "!=" => order != 0
    "<" => order < 0
    "<=" => order <= 0
    ">" => order > 0
    ">=" => order >= 0
    _ => false
  }
}

///|
/// A string comparison for XPath, which is code point by code point — not
/// MoonBit's `String` order, which compares length first.
fn compare_lexicographic(a : String, b : String) -> Int32 {
  let n = a.length()
  let m = b.length()
  let limit = if n < m { n } else { m }
  let mut i = 0
  while i < limit {
    let left = a.at(i)
    let right = b.at(i)
    if left != right {
      return if left < right { -1 } else { 1 }
    }
    i = i + 1
  }
  if n == m {
    0
  } else if n < m {
    -1
  } else {
    1
  }
}

// The core function library, XPath 1.0 §4.

///|
fn call(
  name : String,
  args : Array[Expr],
  ctx : Ctx,
  doc : Document?,
) -> Val raise Refused {
  match name {
    "last" => VNum(ctx.size.to_double())
    "position" => VNum(ctx.order.to_double())
    "count" => VNum(nodes_arg(args, 0, ctx, doc).length().to_double())
    "id" => id_function(args, ctx, doc)
    "local-name" => name_part(args, ctx, doc, LocalName)
    "namespace-uri" => name_part(args, ctx, doc, NamespaceUri)
    // `space-uri` is the spelling this library used before it took XPath's
    // own, and a query written against it still reads.
    "space-uri" => name_part(args, ctx, doc, NamespaceUri)
    "name" => name_part(args, ctx, doc, FullName)
    "string" =>
      if args.is_empty() {
        VStr(string_value(ctx.spot))
      } else {
        VStr(to_string_value(eval_expr(args[0], ctx, doc)))
      }
    "concat" => {
      let out = StringBuilder()
      for arg in args {
        out.write_string(to_string_value(eval_expr(arg, ctx, doc)))
      }
      VStr(out.to_string())
    }
    "starts-with" => {
      let text = to_string_value(eval_expr(arg_at(args, 0), ctx, doc))
      let part = to_string_value(eval_expr(arg_at(args, 1), ctx, doc))
      VFlag(starts_with_text(text, part))
    }
    "contains" => {
      let text = to_string_value(eval_expr(arg_at(args, 0), ctx, doc))
      let part = to_string_value(eval_expr(arg_at(args, 1), ctx, doc))
      VFlag(text.contains(part))
    }
    "substring-before" => {
      let text = to_string_value(eval_expr(arg_at(args, 0), ctx, doc))
      let part = to_string_value(eval_expr(arg_at(args, 1), ctx, doc))
      VStr(
        match find_text(text, part, 0) {
          Some(at) => text[0:at].to_owned()
          None => ""
        },
      )
    }
    "substring-after" => {
      let text = to_string_value(eval_expr(arg_at(args, 0), ctx, doc))
      let part = to_string_value(eval_expr(arg_at(args, 1), ctx, doc))
      VStr(
        match find_text(text, part, 0) {
          Some(at) => text[at + part.length():text.length()].to_owned()
          None => ""
        },
      )
    }
    "substring" => {
      let text = to_string_value(eval_expr(arg_at(args, 0), ctx, doc))
      let start = round_half_up(numeric(eval_expr(arg_at(args, 1), ctx, doc)))
      let length = if args.length() > 2 {
        Some(round_half_up(numeric(eval_expr(args[2], ctx, doc))))
      } else {
        None
      }
      VStr(substring_of(text, start, length))
    }
    "string-length" => {
      let text = if args.is_empty() {
        string_value(ctx.spot)
      } else {
        to_string_value(eval_expr(args[0], ctx, doc))
      }
      VNum(text.char_length().to_double())
    }
    "normalize-space" => {
      let text = if args.is_empty() {
        string_value(ctx.spot)
      } else {
        to_string_value(eval_expr(args[0], ctx, doc))
      }
      VStr(normalise_space(text))
    }
    "translate" => {
      let text = to_string_value(eval_expr(arg_at(args, 0), ctx, doc))
      let from = to_string_value(eval_expr(arg_at(args, 1), ctx, doc))
      let to = to_string_value(eval_expr(arg_at(args, 2), ctx, doc))
      VStr(translate_text(text, from, to))
    }
    "boolean" => VFlag(truthy(eval_expr(arg_at(args, 0), ctx, doc)))
    "not" => VFlag(!truthy(eval_expr(arg_at(args, 0), ctx, doc)))
    "true" => VFlag(true)
    "false" => VFlag(false)
    "number" =>
      if args.is_empty() {
        VNum(text_to_number(string_value(ctx.spot)))
      } else {
        VNum(numeric(eval_expr(args[0], ctx, doc)))
      }
    "sum" => {
      let mut total = 0.0
      for spot in nodes_arg(args, 0, ctx, doc) {
        total = total + spot_number(spot)
      }
      VNum(total)
    }
    "floor" => VNum(numeric(eval_expr(arg_at(args, 0), ctx, doc)).floor())
    "ceiling" => VNum(numeric(eval_expr(arg_at(args, 0), ctx, doc)).ceil())
    "round" =>
      VNum(round_half_up(numeric(eval_expr(arg_at(args, 0), ctx, doc))))
    "lang" =>
      VFlag(
        lang_matches(
          ctx.spot,
          to_string_value(eval_expr(arg_at(args, 0), ctx, doc)),
        ),
      )
    _ => raise Unsupported(what="the XPath function \{name}")
  }
}

///|
fn arg_at(args : Array[Expr], at : Int32) -> Expr {
  if at < args.length() {
    args[at]
  } else {
    Literal("")
  }
}

///|
/// The node-set an argument names, for the functions that take one.
fn nodes_arg(
  args : Array[Expr],
  at : Int32,
  ctx : Ctx,
  doc : Document?,
) -> Array[Spot] raise Refused {
  if at >= args.length() {
    return []
  }
  match eval_expr(args[at], ctx, doc) {
    VNodes(spots) => spots
    _ => []
  }
}

///|
/// `id()`: a string of whitespace-separated ids, or a node-set whose nodes'
/// string values are such lists.
fn id_function(
  args : Array[Expr],
  ctx : Ctx,
  doc : Document?,
) -> Val raise Refused {
  let wanted : Array[String] = []
  if args.is_empty() {
    ignore(ctx)
  } else {
    match eval_expr(args[0], ctx, doc) {
      VNodes(spots) =>
        for spot in spots {
          for part in string_value(spot).split(" ") {
            if !part.is_empty() {
              wanted.push(part.to_owned())
            }
          }
        }
      other =>
        for part in to_string_value(other).split(" ") {
          if !part.is_empty() {
            wanted.push(part.to_owned())
          }
        }
    }
  }
  let found : Array[Spot] = []
  match document_root_spot(ctx.spot) {
    El(root) =>
      root.walk(fn(node) {
        if node is ElementNode(element) {
          match element.attr("id") {
            Some(id) =>
              if wanted.contains(id) {
                found.push(spot_of_element(element))
              }
            None => ()
          }
        }
      })
    _ => ()
  }
  VNodes(normalize(found))
}

///|
/// Which part of a node's name a function asks for.
priv enum NamePart {
  LocalName
  NamespaceUri
  FullName
}

///|
fn name_part(
  args : Array[Expr],
  ctx : Ctx,
  doc : Document?,
  part : NamePart,
) -> Val raise Refused {
  let spots = if args.is_empty() {
    [ctx.spot]
  } else {
    nodes_arg(args, 0, ctx, doc)
  }
  if spots.is_empty() {
    return VStr("")
  }
  VStr(
    match spots[0] {
      El(element) => name_of_text(element.name, part)
      Kid(parent, at) =>
        match parent.children[at] {
          ElementNode(element) => name_of_text(element.name, part)
          _ => ""
        }
      // An attribute's name is its own; a namespace's is its prefix, and a
      // namespace node has no URI of its own.
      Attr(_, name) =>
        match part {
          FullName => name
          LocalName =>
            match namespace_of(name) {
              Some(_) => local_of(name)
              None => name
            }
          NamespaceUri =>
            match namespace_of(name) {
              Some(uri) => uri
              None => ""
            }
        }
      Space(_, prefix) =>
        match part {
          NamespaceUri => ""
          _ => prefix
        }
    },
  )
}

///|
fn name_of_text(name : String, part : NamePart) -> String {
  match part {
    LocalName => local_of(name)
    NamespaceUri =>
      match namespace_of(name) {
        Some(uri) => uri
        None => ""
      }
    FullName => name
  }
}

///|
/// `lang()`: the `xml:lang` of the node or its nearest ancestor that carries
/// one, matched case-insensitively by prefix.
fn lang_matches(spot : Spot, wanted : String) -> Bool {
  let mut current = spot_owner(spot)
  while current is Some(element) {
    let mut found : String? = None
    for pair in element.attrs {
      if pair.0 == "{http://www.w3.org/XML/1998/namespace}lang" ||
        pair.0 == "xml:lang" ||
        pair.0 == "lang" {
        found = Some(pair.1)
        break
      }
    }
    match found {
      Some(have) => return lang_prefix(have, wanted)
      None => ()
    }
    current = element.parent
  }
  false
}

///|
fn lang_prefix(have : String, wanted : String) -> Bool {
  let have_lower = ascii_lower_text(have)
  let wanted_lower = ascii_lower_text(wanted)
  if have_lower == wanted_lower {
    return true
  }
  have_lower.has_prefix(wanted_lower + "-")
}

///|
fn ascii_lower_text(text : String) -> String {
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
fn starts_with_text(text : String, part : String) -> Bool {
  if part.length() > text.length() {
    return false
  }
  text[0:part.length()] == part
}

///|
fn find_text(text : String, part : String, from : Int32) -> Int32? {
  let n = text.length()
  let m = part.length()
  let mut i = from
  while i + m <= n {
    if text[i:i + m] == part {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// XPath's substring(): the characters at positions `p` with
/// `p >= round(start)` and `p < round(start) + round(length)`, one-based. The
/// arithmetic stays in doubles all the way, because the arguments can be NaN or
/// beyond what an `Int` holds, and truncating either would answer wrongly.
fn substring_of(text : String, start : Double, length : Double?) -> String {
  let chars = text.to_array()
  let n = chars.length().to_double()
  if start != start {
    return ""
  }
  let from = if start < 1.0 { 1.0 } else { start }
  let to = match length {
    Some(size) => if size != size { return "" } else { start + size }
    None => n + 1.0
  }
  if from >= to || from > n {
    return ""
  }
  let last = if to > n + 1.0 { n + 1.0 } else { to }
  let out = StringBuilder()
  let mut k = from.to_int() - 1
  while (k + 1).to_double() < last && k < chars.length() {
    if k >= 0 {
      out.write_char(chars[k])
    }
    k = k + 1
  }
  out.to_string()
}

///|
/// XPath's normalize-space: leading and trailing whitespace dropped, runs of
/// it inside folded to one space.
fn normalise_space(text : String) -> String {
  let out = StringBuilder()
  let mut pending = false
  let mut started = false
  for ch in text {
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      if started {
        pending = true
      }
    } else {
      if pending {
        out.write_char(' ')
        pending = false
      }
      out.write_char(ch)
      started = true
    }
  }
  out.to_string()
}

///|
/// XPath's translate(): each character of `from` becomes the character at the
/// same place in `to`; past the end of `to`, it is dropped.
fn translate_text(text : String, from : String, to : String) -> String {
  let source = from.to_array()
  let target = to.to_array()
  let out = StringBuilder()
  for ch in text {
    let mut at = -1
    for k = 0; k < source.length(); k = k + 1 {
      if source[k] == ch {
        at = k
        break
      }
    }
    if at < 0 {
      out.write_char(ch)
    } else if at < target.length() {
      out.write_char(target[at])
    }
  }
  out.to_string()
}

///|
/// XPath's round(): the nearest integer, halves going up, and a small negative
/// number rounds to negative zero — `1 div round(-0.1)` is -Infinity, so the
/// sign has to survive.
fn round_half_up(number : Double) -> Double {
  if is_nan(number) {
    return number
  }
  let floor = number.floor()
  let rounded = if number - floor >= 0.5 { floor + 1.0 } else { floor }
  if rounded == 0.0 && number < 0.0 {
    return -0.0
  }
  rounded
}

///|
fn is_nan(number : Double) -> Bool {
  number != number
}

///|
/// Not a number, spelled without a literal the language lacks.
fn f64_nan() -> Double {
  0.0 / 0.0
}

// Document order.

///|
/// Deduplicate by identity and sort into document order. A spot's rank is its
/// place in a walk of the tree it hangs from, and that walk names every node
/// exactly once — so two text nodes that carry the same characters keep their
/// places, and the node reached twice is one node.
fn normalize(spots : Array[Spot]) -> Array[Spot] {
  if spots.length() <= 1 {
    return spots
  }
  let unique : Array[Spot] = []
  for spot in spots {
    if !unique.iter().any(seen => same_spot(seen, spot)) {
      unique.push(spot)
    }
  }
  if unique.length() <= 1 {
    return unique
  }
  let walk : Array[Spot] = []
  push_walk(document_root_spot(unique[0]), walk)
  let ranked : Array[(Int32, Spot)] = []
  for spot in unique {
    let mut rank = walk.length()
    for k = 0; k < walk.length(); k = k + 1 {
      if same_spot(walk[k], spot) {
        rank = k
        break
      }
    }
    ranked.push((rank, spot))
  }
  ranked.sort_by(fn(a : (Int32, Spot), b : (Int32, Spot)) -> Int32 {
    let (left, _) = a
    let (right, _) = b
    if left < right {
      -1
    } else if left > right {
      1
    } else {
      0
    }
  })
  let out : Array[Spot] = []
  for pair in ranked {
    out.push(pair.1)
  }
  out
}

///|
/// A node-set as the public answer: the nodes of its spots, in document order.
fn selection_for(spots : Array[Spot], doc : Document?) -> Selection {
  let nodes : Array[Node] = []
  for spot in spots {
    nodes.push(spot_node(spot))
  }
  match doc {
    Some(document) => document.selection(nodes)
    None => { doc: None, items: nodes, }
  }
}

///|
fn to_value(value : Val, doc : Document?) -> XPathValue {
  match value {
    VNodes(spots) => Nodes(selection_for(spots, doc))
    VStr(text) => Str(text)
    VNum(number) => Num(number)
    VFlag(flag) => Flag(flag)
  }
}

// The chain's XPath surface.

///|
/// Narrow the selection with an XPath 1.0 expression, evaluated with each
/// selected node as the context node.
///
/// The answer is a node-set; an expression that evaluates to a string, number
/// or boolean answers its string value as one text node, so the chain never
/// breaks — `doc.xpath("string(//h1)").text()` reads the way it should.
/// `xpath_value` is the typed answer.
pub fn Selection::xpath(
  self : Selection,
  query : String,
) -> Selection raise Refused {
  let expr = xpath_parse(query)
  let spots : Array[Spot] = []
  let texts : Array[Node] = []
  for node in self.items {
    let spot = spot_of_node(node, self.doc)
    match eval_expr(expr, { spot, order: 1, size: 1, }, self.doc) {
      VNodes(found) => spots.push_iter(found.iter())
      other => texts.push(TextNode(to_string_value(other)))
    }
  }
  let found = selection_for(normalize(spots), self.doc)
  for text in texts {
    found.items.push(text)
  }
  found
}

///|
/// Where a node sits, for a node that came from outside a step: an element is
/// found in its tree, and a node without a pointer is anchored to the first
/// place its value occupies.
fn spot_of_node(node : Node, doc : Document?) -> Spot {
  match node {
    ElementNode(element) => spot_of_element(element)
    AttributeNode(attr) => Attr(attr.owner, attr.name)
    NamespaceNode(space) => Space(space.owner, space.prefix)
    _ =>
      match doc {
        Some(document) =>
          match find_child_spot(El(document.root), node) {
            Some(found) => found
            None => El(document.root)
          }
        None => El(Element::new("#document"))
      }
  }
}

///|
/// The first place in a tree where a node with this value lies.
fn find_child_spot(spot : Spot, node : Node) -> Spot? {
  for child in spot_children(spot) {
    if same_node_value(child, node) {
      return Some(child)
    }
    match find_child_spot(child, node) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  None
}

///|
fn same_node_value(spot : Spot, node : Node) -> Bool {
  match spot {
    Kid(parent, at) =>
      match (parent.children[at], node) {
        (TextNode(have), TextNode(text)) => have == text
        (CDataNode(have), CDataNode(text)) => have == text
        (CommentNode(have), CommentNode(text)) => have == text
        (DoctypeNode(have), DoctypeNode(text)) => have == text
        (ProcessingInstructionNode(have), ProcessingInstructionNode(pi)) =>
          have.target == pi.target && have.data == pi.data
        (ElementNode(have), ElementNode(other)) => physical_equal(have, other)
        _ => false
      }
    El(element) =>
      match node {
        ElementNode(other) => physical_equal(element, other)
        _ => false
      }
    _ => false
  }
}

///|
/// The typed XPath 1.0 answer: nodes, a string, a number or a boolean.
pub fn Selection::xpath_value(
  self : Selection,
  query : String,
) -> XPathValue raise Refused {
  let expr = xpath_parse(query)
  match self.items {
    [] => Flag(false)
    [first, ..] =>
      to_value(
        eval_expr(
          expr,
          { spot: spot_of_node(first, self.doc), order: 1, size: 1, },
          self.doc,
        ),
        self.doc,
      )
  }
}

///|
/// Narrow to the nodes an XPath 1.0 expression answers from this element.
pub fn Element::xpath(
  self : Element,
  query : String,
) -> Selection raise Refused {
  selection_of(ElementNode(self)).xpath(query)
}

///|
/// The typed answer of an XPath 1.0 expression, read from this element.
pub fn Element::xpath_value(
  self : Element,
  query : String,
) -> XPathValue raise Refused {
  selection_of(ElementNode(self)).xpath_value(query)
}

///|
/// Narrow to the nodes an XPath 1.0 expression answers from this node.
pub fn Node::xpath(self : Node, query : String) -> Selection raise Refused {
  selection_of(self).xpath(query)
}

///|
/// The typed answer of an XPath 1.0 expression, read from this node.
pub fn Node::xpath_value(
  self : Node,
  query : String,
) -> XPathValue raise Refused {
  selection_of(self).xpath_value(query)
}

///|
/// Narrow to the nodes an XPath 1.0 expression answers, over the whole document.
pub fn Document::xpath(
  self : Document,
  query : String,
) -> Selection raise Refused {
  self.selection([ElementNode(self.root)]).xpath(query)
}

///|
/// The typed answer of an XPath 1.0 expression, read from the whole document.
pub fn Document::xpath_value(
  self : Document,
  query : String,
) -> XPathValue raise Refused {
  self.selection([ElementNode(self.root)]).xpath_value(query)
}
