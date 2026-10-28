// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// XPath 1.0: the whole grammar, all thirteen axes, predicates carrying full
/// expressions, and the core function library. The result is typed —
/// `XPathValue` — which is what `xpath_value` answers; `xpath` answers the
/// node-set, or the string value of anything else as one text node, so the
/// chain never breaks.
///
/// Two documented departures: the `namespace` axis answers empty, because the
/// tree carries Clark names rather than namespace nodes; and the attribute
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
  let value = Some(@string.parse_double(text)) catch { _ => None }
  match value {
    Some(value) => (value, i)
    None => raise BadQuery(at=from, why="a number that does not read")
  }
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
/// A node with the position and size the predicate that sees it was given.
priv struct Ctx {
  node : Node
  order : Int32
  size : Int32
}

///|
fn eval_expr(
  expr : Expr,
  ctx : Ctx,
  doc : Document?,
) -> XPathValue raise Refused {
  match expr {
    Literal(text) => Str(text)
    Number(value) => Num(value)
    Variable(name) =>
      raise Unsupported(what="the XPath variable $\{name} has no binding")
    Path(absolute~, steps~) => {
      let start = if absolute { document_root(ctx.node) } else { ctx.node }
      let found = walk_steps([start], steps, doc)
      Nodes(selection_for(found, doc))
    }
    Union(lhs~, rhs~) => {
      let left = nodes_of(eval_expr(lhs, ctx, doc), doc)
      let right = nodes_of(eval_expr(rhs, ctx, doc), doc)
      let merged : Array[Node] = []
      for node in left {
        merged.push(node)
      }
      for node in right {
        merged.push(node)
      }
      Nodes(selection_for(normalize(merged), doc))
    }
    Filter(base~, predicates~) => {
      let base_value = eval_expr(base, ctx, doc)
      match base_value {
        Nodes(sel) => {
          let kept = apply_predicates(sel.items, predicates, doc)
          Nodes(selection_for(kept, doc))
        }
        other => other
      }
    }
    StepsFrom(base~, steps~) => {
      let base_value = eval_expr(base, ctx, doc)
      let found = walk_steps(nodes_of(base_value, doc), steps, doc)
      Nodes(selection_for(found, doc))
    }
    Or(lhs~, rhs~) =>
      Flag(truthy(eval_expr(lhs, ctx, doc)) || truthy(eval_expr(rhs, ctx, doc)))
    And(lhs~, rhs~) =>
      Flag(truthy(eval_expr(lhs, ctx, doc)) && truthy(eval_expr(rhs, ctx, doc)))
    Eq(lhs~, rhs~) =>
      Flag(compare(eval_expr(lhs, ctx, doc), eval_expr(rhs, ctx, doc), "="))
    Ne(lhs~, rhs~) =>
      Flag(compare(eval_expr(lhs, ctx, doc), eval_expr(rhs, ctx, doc), "!="))
    Lt(lhs~, rhs~) =>
      Flag(compare(eval_expr(lhs, ctx, doc), eval_expr(rhs, ctx, doc), "<"))
    Le(lhs~, rhs~) =>
      Flag(compare(eval_expr(lhs, ctx, doc), eval_expr(rhs, ctx, doc), "<="))
    Gt(lhs~, rhs~) =>
      Flag(compare(eval_expr(lhs, ctx, doc), eval_expr(rhs, ctx, doc), ">"))
    Ge(lhs~, rhs~) =>
      Flag(compare(eval_expr(lhs, ctx, doc), eval_expr(rhs, ctx, doc), ">="))
    Add(lhs~, rhs~) =>
      Num(numeric(eval_expr(lhs, ctx, doc)) + numeric(eval_expr(rhs, ctx, doc)))
    Sub(lhs~, rhs~) =>
      Num(numeric(eval_expr(lhs, ctx, doc)) - numeric(eval_expr(rhs, ctx, doc)))
    Mul(lhs~, rhs~) =>
      Num(numeric(eval_expr(lhs, ctx, doc)) * numeric(eval_expr(rhs, ctx, doc)))
    Div(lhs~, rhs~) =>
      Num(numeric(eval_expr(lhs, ctx, doc)) / numeric(eval_expr(rhs, ctx, doc)))
    Mod(lhs~, rhs~) =>
      Num(numeric(eval_expr(lhs, ctx, doc)) % numeric(eval_expr(rhs, ctx, doc)))
    Neg(inner) => Num(0.0 - numeric(eval_expr(inner, ctx, doc)))
    Call(name~, args~) => call(name, args, ctx, doc)
  }
}

///|
/// The document root of a node: walk up as far as there is a parent.
fn document_root(node : Node) -> Node {
  match node {
    ElementNode(start) => {
      let mut top = start
      let mut climbing = true
      while climbing {
        match top.parent {
          Some(above) => top = above
          None => climbing = false
        }
      }
      ElementNode(top)
    }
    _ => node
  }
}

///|
/// The nodes of a typed value: a node-set answers itself, anything else is a
/// type error where a node-set is required, so it answers nothing.
fn nodes_of(value : XPathValue, doc : Document?) -> Array[Node] {
  match value {
    Nodes(sel) => sel.items
    _ => {
      ignore(doc)
      []
    }
  }
}

///|
/// A selection over these nodes, carrying the document they were found in.
fn selection_for(nodes : Array[Node], doc : Document?) -> Selection {
  match doc {
    Some(doc) => doc.selection(nodes)
    None => { doc: None, items: nodes, }
  }
}

///|
/// Run the steps from the starting nodes.
fn walk_steps(
  start : Array[Node],
  steps : Array[Step],
  doc : Document?,
) -> Array[Node] raise Refused {
  let mut current = start
  for step in steps {
    // A step is evaluated with respect to each context node and its
    // predicates see that node's own node-set — which is why `//div/p[1]` is
    // the first paragraph of every div, not the first of all of them.
    let gathered : Array[Node] = []
    for node in current {
      let reached = if step.axis is Axis::Attribute {
        // An attribute is not a node here, so the axis answers the test
        // itself: `@id` keeps the id, `@*` keeps them all.
        attribute_values(node, step.probe)
      } else {
        apply_test(step.probe, apply_axis(step.axis, node), doc)
      }
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
/// Every node the axis reaches from the context node, in the axis's own order.
fn apply_axis(axis : Axis, node : Node) -> Array[Node] {
  let out : Array[Node] = []
  match axis {
    Axis::SelfAxis => out.push(node)
    Axis::Child =>
      for child in node.children() {
        out.push(child)
      }
    Axis::Descendant => {
      for child in node.children() {
        out.push(child)
      }
      match node {
        ElementNode(data) => data.walk(fn(found) { out.push(found) })
        _ => ()
      }
    }
    Axis::DescendantOrSelf => {
      out.push(node)
      match node {
        ElementNode(data) => data.walk(fn(found) { out.push(found) })
        _ => ()
      }
    }
    Axis::Parent =>
      match node {
        ElementNode(data) =>
          match data.parent {
            Some(above) =>
              if !is_virtual_root(above) {
                out.push(ElementNode(above))
              }
            None => ()
          }
        _ => ()
      }
    Axis::Ancestor =>
      match node {
        ElementNode(start) => {
          let mut current = start.parent
          while current is Some(above) {
            if !is_virtual_root(above) {
              out.push(ElementNode(above))
            }
            current = above.parent
          }
        }
        _ => ()
      }
    Axis::AncestorOrSelf => {
      out.push(node)
      match node {
        ElementNode(start) => {
          let mut current = start.parent
          while current is Some(above) {
            if !is_virtual_root(above) {
              out.push(ElementNode(above))
            }
            current = above.parent
          }
        }
        _ => ()
      }
    }
    Axis::FollowingSibling =>
      match node {
        ElementNode(data) =>
          match data.parent {
            Some(parent) => {
              let siblings = element_children_of(parent)
              let mut past = false
              for sibling in siblings {
                if past {
                  out.push(ElementNode(sibling))
                }
                if physical_equal(sibling, data) {
                  past = true
                }
              }
            }
            None => ()
          }
        _ => ()
      }
    Axis::PrecedingSibling =>
      match node {
        ElementNode(data) =>
          match data.parent {
            Some(parent) => {
              let siblings = element_children_of(parent)
              let before : Array[Element] = []
              for sibling in siblings {
                if physical_equal(sibling, data) {
                  break
                }
                before.push(sibling)
              }
              // proximity order: nearest first
              for k = before.length() - 1; k >= 0; k = k - 1 {
                out.push(ElementNode(before[k]))
              }
            }
            None => ()
          }
        _ => ()
      }
    Axis::Following =>
      match document_root(node) {
        ElementNode(root) => {
          let all : Array[Node] = []
          root.walk(fn(found) { all.push(found) })
          let mut past = false
          for found in all {
            if past && !is_descendant_of(found, node) {
              out.push(found)
            }
            if physical_equal_node(found, node) {
              past = true
            }
          }
        }
        _ => ()
      }
    Axis::Preceding =>
      match document_root(node) {
        ElementNode(root) => {
          let all : Array[Node] = []
          root.walk(fn(found) { all.push(found) })
          let before : Array[Node] = []
          for found in all {
            if physical_equal_node(found, node) {
              break
            }
            if !is_descendant_of(node, found) {
              before.push(found)
            }
          }
          for k = before.length() - 1; k >= 0; k = k - 1 {
            out.push(before[k])
          }
        }
        _ => ()
      }
    Axis::Attribute => ()
    Axis::Namespace => ()
  }
  out
}

///|

///|
/// The attribute axis: each value the probe names, as a text node.
fn attribute_values(node : Node, probe : Test) -> Array[Node] {
  let out : Array[Node] = []
  match node {
    ElementNode(data) =>
      for pair in data.attrs {
        let keep = match probe {
          Name(probe) => probe == "*" || pair.0 == probe
          AnyTest => true
          _ => false
        }
        if keep {
          out.push(TextNode(pair.1))
        }
      }
    _ => ()
  }
  out
}

///|
/// Whether an element is the document's virtual container: infrastructure,
/// never a match, so `ancestor::*` answers the elements a reader can see.
fn is_virtual_root(element : Element) -> Bool {
  element.name == "#document" && element.parent is None
}

///|
fn element_children_of(parent : Element) -> Array[Element] {
  let out : Array[Element] = []
  for child in parent.children {
    if child is ElementNode(data) {
      out.push(data)
    }
  }
  out
}

///|
/// Whether `node` sits inside `ancestor`'s subtree (itself excluded).
fn is_descendant_of(node : Node, ancestor : Node) -> Bool {
  match node {
    ElementNode(data) => {
      let mut current = data.parent
      while current is Some(above) {
        if physical_equal_node(ElementNode(above), ancestor) {
          return true
        }
        current = above.parent
      }
      false
    }
    _ => false
  }
}

///|
/// Identity for a node: elements by reference, the rest by their text — a text
/// node carries no pointer, so it can only be the same node if it is the same
/// place in the same walk, which the ranges this is called with guarantee.
fn physical_equal_node(a : Node, b : Node) -> Bool {
  match (a, b) {
    (ElementNode(x), ElementNode(y)) => physical_equal(x, y)
    _ => false
  }
}

///|
/// The nodes of an axis result that the test keeps.
fn apply_test(
  probe : Test,
  nodes : Array[Node],
  doc : Document?,
) -> Array[Node] {
  let out : Array[Node] = []
  for node in nodes {
    let keep = match probe {
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
      Name(probe) =>
        match node {
          ElementNode(data) => name_matches(data.name, probe)
          _ => false
        }
    }
    if keep {
      out.push(node)
    } else {
      ignore(doc)
    }
  }
  out
}

///|
/// Apply the predicates in order: each sees the node-set as it stands, with
/// the position and size the node had among it.
fn apply_predicates(
  nodes : Array[Node],
  predicates : Array[Expr],
  doc : Document?,
) -> Array[Node] raise Refused {
  let mut current = nodes
  for predicate in predicates {
    let kept : Array[Node] = []
    let size = current.length()
    for k = 0; k < size; k = k + 1 {
      let ctx : Ctx = { node: current[k], order: k + 1, size, }
      let value = eval_expr(predicate, ctx, doc)
      let hold = match value {
        Num(wanted) => wanted.to_int() == k + 1
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
/// The string value of a node.
fn string_value(node : Node) -> String {
  match node {
    TextNode(text) => text
    CDataNode(text) => text
    CommentNode(text) => text
    ProcessingInstructionNode(pi) => pi.data
    ElementNode(data) => data.text()
    DoctypeNode(_) => ""
  }
}

///|
fn to_string_value(value : XPathValue) -> String {
  match value {
    Str(text) => text
    Num(number) => number_to_string(number)
    Flag(flag) => if flag { "true" } else { "false" }
    Nodes(sel) =>
      if sel.items.is_empty() {
        ""
      } else {
        string_value(sel.items[0])
      }
  }
}

///|
fn numeric(value : XPathValue) -> Double {
  match value {
    Num(number) => number
    Str(text) => text_to_number(text)
    Flag(flag) => if flag { 1.0 } else { 0.0 }
    Nodes(sel) =>
      if sel.items.is_empty() {
        f64_nan()
      } else {
        text_to_number(string_value(sel.items[0]))
      }
  }
}

///|
fn truthy(value : XPathValue) -> Bool {
  match value {
    Flag(flag) => flag
    Num(number) => number != 0.0 && !is_nan(number)
    Str(text) => !text.is_empty()
    Nodes(sel) => !sel.items.is_empty()
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
/// The comparisons of §3.4, with their node-set rules.
fn compare(lhs : XPathValue, rhs : XPathValue, op : String) -> Bool {
  match (lhs, rhs) {
    (Nodes(left), Nodes(right)) => {
      let relational = op != "=" && op != "!="
      for a in left.items {
        for b in right.items {
          let same = if relational {
            compare_numbers(
              text_to_number(string_value(a)),
              text_to_number(string_value(b)),
              op,
            )
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
    (Nodes(left), other) => node_set_against(left, other, op)
    (other, Nodes(right)) => node_set_against(right, other, op)
    (Flag(a), _) => compare_booleans(a, truthy(rhs), op)
    (_, Flag(b)) => compare_booleans(truthy(lhs), b, op)
    (Num(a), _) => compare_numbers(a, numeric(rhs), op)
    (_, Num(b)) => compare_numbers(numeric(lhs), b, op)
    (Str(a), Str(b)) => compare_strings(a, b, op)
  }
}

///|
fn node_set_against(nodes : Selection, other : XPathValue, op : String) -> Bool {
  match other {
    Flag(flag) => return compare_booleans(!nodes.items.is_empty(), flag, op)
    Num(wanted) =>
      for node in nodes.items {
        if compare_numbers(text_to_number(string_value(node)), wanted, op) {
          return true
        }
      }
    Str(wanted) =>
      for node in nodes.items {
        if compare_strings(string_value(node), wanted, op) {
          return true
        }
      }
    Nodes(other_nodes) =>
      for a in nodes.items {
        for b in other_nodes.items {
          if compare_strings(string_value(a), string_value(b), op) {
            return true
          }
        }
      }
  }
  false
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
) -> XPathValue raise Refused {
  match name {
    "last" => Num(ctx.size.to_double())
    "position" => Num(ctx.order.to_double())
    "count" => Num(nodes_arg(args, 0, ctx, doc).length().to_double())
    "id" => id_function(args, ctx, doc)
    "local-name" => name_part(args, ctx, doc, LocalName)
    "namespace-uri" => name_part(args, ctx, doc, NamespaceUri)
    "name" => name_part(args, ctx, doc, FullName)
    "string" =>
      if args.is_empty() {
        Str(string_value(ctx.node))
      } else {
        Str(to_string_value(eval_expr(args[0], ctx, doc)))
      }
    "concat" => {
      let out = StringBuilder()
      for arg in args {
        out.write_string(to_string_value(eval_expr(arg, ctx, doc)))
      }
      Str(out.to_string())
    }
    "starts-with" => {
      let text = to_string_value(eval_expr(arg_at(args, 0), ctx, doc))
      let part = to_string_value(eval_expr(arg_at(args, 1), ctx, doc))
      Flag(starts_with_text(text, part))
    }
    "contains" => {
      let text = to_string_value(eval_expr(arg_at(args, 0), ctx, doc))
      let part = to_string_value(eval_expr(arg_at(args, 1), ctx, doc))
      Flag(text.contains(part))
    }
    "substring-before" => {
      let text = to_string_value(eval_expr(arg_at(args, 0), ctx, doc))
      let part = to_string_value(eval_expr(arg_at(args, 1), ctx, doc))
      Str(
        match find_text(text, part, 0) {
          Some(at) => text[0:at].to_owned()
          None => ""
        },
      )
    }
    "substring-after" => {
      let text = to_string_value(eval_expr(arg_at(args, 0), ctx, doc))
      let part = to_string_value(eval_expr(arg_at(args, 1), ctx, doc))
      Str(
        match find_text(text, part, 0) {
          Some(at) => text[at + part.length():text.length()].to_owned()
          None => ""
        },
      )
    }
    "substring" => {
      let text = to_string_value(eval_expr(arg_at(args, 0), ctx, doc))
      let start = numeric(eval_expr(arg_at(args, 1), ctx, doc)).round().to_int()
      let length = if args.length() > 2 {
        Some(numeric(eval_expr(args[2], ctx, doc)).round().to_int())
      } else {
        None
      }
      Str(substring_of(text, start, length))
    }
    "string-length" => {
      let text = if args.is_empty() {
        string_value(ctx.node)
      } else {
        to_string_value(eval_expr(args[0], ctx, doc))
      }
      Num(text.char_length().to_double())
    }
    "normalize-space" => {
      let text = if args.is_empty() {
        string_value(ctx.node)
      } else {
        to_string_value(eval_expr(args[0], ctx, doc))
      }
      Str(normalise_space(text))
    }
    "translate" => {
      let text = to_string_value(eval_expr(arg_at(args, 0), ctx, doc))
      let from = to_string_value(eval_expr(arg_at(args, 1), ctx, doc))
      let to = to_string_value(eval_expr(arg_at(args, 2), ctx, doc))
      Str(translate_text(text, from, to))
    }
    "boolean" => Flag(truthy(eval_expr(arg_at(args, 0), ctx, doc)))
    "not" => Flag(!truthy(eval_expr(arg_at(args, 0), ctx, doc)))
    "true" => Flag(true)
    "false" => Flag(false)
    "number" =>
      if args.is_empty() {
        Num(text_to_number(string_value(ctx.node)))
      } else {
        Num(numeric(eval_expr(args[0], ctx, doc)))
      }
    "sum" => {
      let sel = nodes_arg(args, 0, ctx, doc)
      let mut total = 0.0
      for node in sel {
        total = total + text_to_number(string_value(node))
      }
      Num(total)
    }
    "floor" => Num(numeric(eval_expr(arg_at(args, 0), ctx, doc)).floor())
    "ceiling" => Num(numeric(eval_expr(arg_at(args, 0), ctx, doc)).ceil())
    "round" => Num(round_half_up(numeric(eval_expr(arg_at(args, 0), ctx, doc))))
    "lang" =>
      Flag(
        lang_matches(
          ctx.node,
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
) -> Array[Node] raise Refused {
  if at >= args.length() {
    return []
  }
  nodes_of(eval_expr(args[at], ctx, doc), doc)
}

///|
/// `id()`: a string of whitespace-separated ids, or a node-set whose nodes'
/// string values are such lists.
fn id_function(
  args : Array[Expr],
  ctx : Ctx,
  doc : Document?,
) -> XPathValue raise Refused {
  let wanted : Array[String] = []
  if args.is_empty() {
    ignore(ctx)
  } else {
    match eval_expr(args[0], ctx, doc) {
      Nodes(sel) =>
        for node in sel.items {
          for part in string_value(node).split(" ") {
            if !part.is_empty() {
              wanted.push(part.to_owned())
            }
          }
        }
      Str(text) =>
        for part in text.split(" ") {
          if !part.is_empty() {
            wanted.push(part.to_owned())
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
  let root = document_root(ctx.node)
  let found : Array[Node] = []
  match root {
    ElementNode(data) =>
      data.walk(fn(node) {
        if node is ElementNode(element) {
          match element.attr("id") {
            Some(id) => if wanted.contains(id) { found.push(node) }
            None => ()
          }
        }
      })
    _ => ()
  }
  Nodes(selection_for(normalize(found), doc))
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
) -> XPathValue raise Refused {
  let nodes = if args.is_empty() {
    [ctx.node]
  } else {
    nodes_arg(args, 0, ctx, doc)
  }
  if nodes.is_empty() {
    return Str("")
  }
  let name = match nodes[0] {
    ElementNode(data) => data.name
    _ => ""
  }
  Str(
    match part {
      LocalName => local_of(name)
      NamespaceUri =>
        match namespace_of(name) {
          Some(uri) => uri
          None => ""
        }
      FullName => name
    },
  )
}

///|
/// `lang()`: the `xml:lang` of the node or its nearest ancestor that carries
/// one, matched case-insensitively by prefix.
fn lang_matches(node : Node, wanted : String) -> Bool {
  let mut current = match node {
    ElementNode(data) => Some(data)
    _ => None
  }
  while current is Some(element) {
    match element.attr("xml:lang") {
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
/// XPath's substring(): one-based, with the rounding the spec spells out.
fn substring_of(text : String, start : Int32, length : Int32?) -> String {
  let chars = text.to_array()
  let n = chars.length()
  let mut from = start
  if from < 1 {
    from = 1
  }
  let mut to = n + 1
  match length {
    Some(size) => to = start + size
    None => ()
  }
  if to > n + 1 {
    to = n + 1
  }
  if from >= to {
    return ""
  }
  let out = StringBuilder()
  for k = from - 1; k < to - 1 && k < chars.length(); k = k + 1 {
    out.write_char(chars[k])
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
/// XPath's round(): the nearest integer, halves going up.
fn round_half_up(number : Double) -> Double {
  if is_nan(number) {
    return number
  }
  let floor = number.floor()
  if number - floor >= 0.5 {
    floor + 1.0
  } else {
    floor
  }
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
/// Deduplicate by identity and sort into document order. The rank of a node is
/// its place in a pre-order walk of the root it hangs from; the walk is taken
/// once per call, and only when there is something to sort.
fn normalize(nodes : Array[Node]) -> Array[Node] {
  if nodes.length() <= 1 {
    return nodes
  }
  let unique : Array[Node] = []
  for node in nodes {
    let mut seen = false
    for have in unique {
      if same_node(node, have) {
        seen = true
        break
      }
    }
    if !seen {
      unique.push(node)
    }
  }
  let ranked : Array[(Int32, Node)] = []
  let root = document_root(unique[0])
  let walk : Array[Node] = []
  match root {
    ElementNode(data) => data.walk(fn(found) { walk.push(found) })
    _ => ()
  }
  for node in unique {
    let mut rank = walk.length()
    for k = 0; k < walk.length(); k = k + 1 {
      if same_node(walk[k], node) {
        rank = k
        break
      }
    }
    ranked.push((rank, node))
  }
  ranked.sort_by(fn(a : (Int32, Node), b : (Int32, Node)) -> Int32 {
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
  let out : Array[Node] = []
  for pair in ranked {
    out.push(pair.1)
  }
  out
}

///|
/// Identity for nodes: elements by reference; the other kinds have no
/// pointer, so they compare by the values they carry.
fn same_node(a : Node, b : Node) -> Bool {
  match (a, b) {
    (ElementNode(x), ElementNode(y)) => physical_equal(x, y)
    (TextNode(x), TextNode(y)) => x == y
    (CDataNode(x), CDataNode(y)) => x == y
    (CommentNode(x), CommentNode(y)) => x == y
    (DoctypeNode(x), DoctypeNode(y)) => x == y
    (ProcessingInstructionNode(x), ProcessingInstructionNode(y)) =>
      x.target == y.target && x.data == y.data
    _ => false
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
  let out : Array[Node] = []
  for node in self.items {
    match eval_expr(expr, { node, order: 1, size: 1, }, self.doc) {
      Nodes(sel) =>
        for found in sel.items {
          out.push(found)
        }
      other => out.push(TextNode(to_string_value(other)))
    }
  }
  selection_for(normalize(out), self.doc)
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
      eval_expr(expr, { node: first, order: 1, size: 1, }, self.doc)
  }
}

///|
pub fn Element::xpath(
  self : Element,
  query : String,
) -> Selection raise Refused {
  selection_of(ElementNode(self)).xpath(query)
}

///|
pub fn Element::xpath_value(
  self : Element,
  query : String,
) -> XPathValue raise Refused {
  selection_of(ElementNode(self)).xpath_value(query)
}

///|
pub fn Node::xpath(self : Node, query : String) -> Selection raise Refused {
  selection_of(self).xpath(query)
}

///|
pub fn Node::xpath_value(
  self : Node,
  query : String,
) -> XPathValue raise Refused {
  selection_of(self).xpath_value(query)
}

///|
pub fn Document::xpath(
  self : Document,
  query : String,
) -> Selection raise Refused {
  self.selection([ElementNode(self.root)]).xpath(query)
}

///|
pub fn Document::xpath_value(
  self : Document,
  query : String,
) -> XPathValue raise Refused {
  self.selection([ElementNode(self.root)]).xpath_value(query)
}
