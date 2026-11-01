/// XPath 1.0: expression parsing and evaluation over the tree.
///
/// A node-set is an array of nodes in document order. The four result kinds are
/// kept apart internally (`XVal`) and surfaced as `XPathValue`: `xpath(q)`
/// yields a `Selection` (a non-node-set answer becomes its XPath string value,
/// wrapped as one text node, so a chain never breaks); `xpath_value(q)` yields
/// the typed answer.
///
/// Attributes are not part of the tree's node kinds; the attribute axis
/// synthesises `AttributeNode` values on demand, so `@href` works and its
/// string-value is the attribute's value.

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

enum Axis {
  AxChild
  AxDescendant
  AxParent
  AxAncestor
  AxFollowingSibling
  AxPrecedingSibling
  AxFollowing
  AxPreceding
  AxSelf
  AxDescendantOrSelf
  AxAncestorOrSelf
  AxAttribute
  AxNamespace
}

enum NodeTest {
  NameTest(String)
  TextTest
  CommentTest
  AnyTest
  PITest(String?)
}

struct Step {
  axis : Axis
  test_kind : NodeTest
  predicates : Array[Expr]
}

enum Expr {
  StrLit(String)
  NumLit(Double)
  PathExpr(Bool, Array[Step])
  PathFrom(Expr, Array[Step])
  FilterExpr(Expr, Array[Expr])
  UnionExpr(Expr, Expr)
  BinExpr(String, Expr, Expr)
  NegExpr(Expr)
  FunExpr(String, Array[Expr])
}

enum XVal {
  VNodes(Array[Node])
  VStr(String)
  VNum(Double)
  VBool(Bool)
}

struct XC {
  node : Node
  position : Int
  size : Int
  root : Element
}

// ---------------------------------------------------------------------------
// Scanner
// ---------------------------------------------------------------------------

struct XP {
  s : Array[Char]
  mut pos : Int
  n : Int
}

fn XP::at_end(self : XP) -> Bool {
  self.pos >= self.n
}

fn XP::peek(self : XP) -> Char {
  if self.pos < self.n {
    self.s[self.pos]
  } else {
    '\u{0}'
  }
}

fn XP::peek_at(self : XP, k : Int) -> Char {
  let i = self.pos + k
  if i < self.n {
    self.s[i]
  } else {
    '\u{0}'
  }
}

fn xp_ws(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

fn XP::skip_ws(self : XP) -> Unit {
  while self.pos < self.n && xp_ws(self.s[self.pos]) {
    self.pos = self.pos + 1
  }
}

fn pname_start(c : Char) -> Bool {
  if c >= 'a' && c <= 'z' {
    return true
  }
  if c >= 'A' && c <= 'Z' {
    return true
  }
  if c == '_' {
    return true
  }
  Char::to_int(c) >= 0x80
}

fn pname_char(c : Char) -> Bool {
  if pname_start(c) {
    return true
  }
  if c >= '0' && c <= '9' {
    return true
  }
  c == '-' || c == '.'
}

fn XP::read_name(self : XP) -> String raise Refused {
  if not(pname_start(self.peek())) {
    raise Refused::BadQuery(at=self.pos, why="expected a name")
  }
  let sb = StringBuilder()
  while self.pos < self.n && pname_char(self.s[self.pos]) {
    sb.write_char(self.s[self.pos])
    self.pos = self.pos + 1
  }
  sb.to_string()
}

fn is_nodetest_name(nm : String) -> Bool {
  nm == "text" || nm == "node" || nm == "comment" || nm == "processing-instruction"
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

fn parse_xpath(s : String) -> Expr raise Refused {
  let p = XP::{ s: s.to_array(), pos: 0, n: s.length() }
  let e = parse_or(p)
  p.skip_ws()
  if not(p.at_end()) {
    raise Refused::BadQuery(at=p.pos, why="unexpected trailing input")
  }
  e
}

fn parse_or(p : XP) -> Expr raise Refused {
  let mut left = parse_and(p)
  while true {
    p.skip_ws()
    if peek_keyword(p, "or") {
      p.pos = p.pos + 2
      left = Expr::BinExpr("or", left, parse_and(p))
    } else {
      break
    }
  }
  left
}

fn parse_and(p : XP) -> Expr raise Refused {
  let mut left = parse_equality(p)
  while true {
    p.skip_ws()
    if peek_keyword(p, "and") {
      p.pos = p.pos + 3
      left = Expr::BinExpr("and", left, parse_equality(p))
    } else {
      break
    }
  }
  left
}

fn parse_equality(p : XP) -> Expr raise Refused {
  let mut left = parse_relational(p)
  while true {
    p.skip_ws()
    let c = p.peek()
    if c == '=' {
      p.pos = p.pos + 1
      left = Expr::BinExpr("=", left, parse_relational(p))
    } else if c == '!' && p.peek_at(1) == '=' {
      p.pos = p.pos + 2
      left = Expr::BinExpr("!=", left, parse_relational(p))
    } else {
      break
    }
  }
  left
}

fn parse_relational(p : XP) -> Expr raise Refused {
  let mut left = parse_additive(p)
  while true {
    p.skip_ws()
    let c = p.peek()
    let c2 = p.peek_at(1)
    if c == '<' && c2 == '=' {
      p.pos = p.pos + 2
      left = Expr::BinExpr("<=", left, parse_additive(p))
    } else if c == '>' && c2 == '=' {
      p.pos = p.pos + 2
      left = Expr::BinExpr(">=", left, parse_additive(p))
    } else if c == '<' {
      p.pos = p.pos + 1
      left = Expr::BinExpr("<", left, parse_additive(p))
    } else if c == '>' {
      p.pos = p.pos + 1
      left = Expr::BinExpr(">", left, parse_additive(p))
    } else {
      break
    }
  }
  left
}

fn parse_additive(p : XP) -> Expr raise Refused {
  let mut left = parse_multiplicative(p)
  while true {
    p.skip_ws()
    let c = p.peek()
    if c == '+' {
      p.pos = p.pos + 1
      left = Expr::BinExpr("+", left, parse_multiplicative(p))
    } else if c == '-' {
      p.pos = p.pos + 1
      left = Expr::BinExpr("-", left, parse_multiplicative(p))
    } else {
      break
    }
  }
  left
}

fn parse_multiplicative(p : XP) -> Expr raise Refused {
  let mut left = parse_unary(p)
  while true {
    p.skip_ws()
    let c = p.peek()
    if c == '*' {
      p.pos = p.pos + 1
      left = Expr::BinExpr("*", left, parse_unary(p))
    } else if peek_keyword(p, "div") {
      p.pos = p.pos + 3
      left = Expr::BinExpr("div", left, parse_unary(p))
    } else if peek_keyword(p, "mod") {
      p.pos = p.pos + 3
      left = Expr::BinExpr("mod", left, parse_unary(p))
    } else {
      break
    }
  }
  left
}

fn parse_unary(p : XP) -> Expr raise Refused {
  p.skip_ws()
  if p.peek() == '-' {
    p.pos = p.pos + 1
    Expr::NegExpr(parse_unary(p))
  } else {
    parse_union(p)
  }
}

fn parse_union(p : XP) -> Expr raise Refused {
  let mut left = parse_path(p)
  while true {
    p.skip_ws()
    if p.peek() == '|' {
      p.pos = p.pos + 1
      left = Expr::UnionExpr(left, parse_path(p))
    } else {
      break
    }
  }
  left
}

fn peek_keyword(p : XP, kw : String) -> Bool {
  let save = p.pos
  p.skip_ws()
  let k = kw.to_array()
  let mut ok = p.pos + k.length() <= p.n
  if ok {
    let mut j = 0
    while j < k.length() {
      if p.s[p.pos + j] != k[j] {
        ok = false
        break
      }
      j = j + 1
    }
  }
  p.pos = save
  ok
}

fn starts_path(p : XP) -> Bool {
  let c = p.peek()
  if c == '/' || c == '@' || c == '*' {
    return true
  }
  if c == '.' {
    let nx = p.peek_at(1)
    if nx >= '0' && nx <= '9' {
      return false
    }
    return true
  }
  if pname_start(c) {
    let sb = StringBuilder()
    let mut i = p.pos
    while i < p.n && pname_char(p.s[i]) {
      sb.write_char(p.s[i])
      i = i + 1
    }
    let nm = sb.to_string()
    let mut j = i
    while j < p.n && xp_ws(p.s[j]) {
      j = j + 1
    }
    let after_paren = j < p.n && p.s[j] == '('
    if after_paren && not(is_nodetest_name(nm)) {
      return false
    }
    return true
  }
  false
}

fn parse_path(p : XP) -> Expr raise Refused {
  p.skip_ws()
  if starts_path(p) {
    let abs = p.peek() == '/'
    let steps = parse_steps(p, abs)
    Expr::PathExpr(abs, steps)
  } else {
    let mut base = parse_primary(p)
    let preds = parse_predicates(p)
    if preds.length() > 0 {
      base = Expr::FilterExpr(base, preds)
    }
    let steps : Array[Step] = []
    while true {
      p.skip_ws()
      if p.peek() == '/' {
        p.pos = p.pos + 1
        if p.peek() == '/' {
          p.pos = p.pos + 1
          steps.push(dos_step())
        }
        steps.push(parse_step(p))
      } else {
        break
      }
    }
    if steps.length() > 0 {
      Expr::PathFrom(base, steps)
    } else {
      base
    }
  }
}

fn dos_step() -> Step {
  { axis: Axis::AxDescendantOrSelf, test_kind: NodeTest::AnyTest, predicates: [] }
}

fn parse_steps(p : XP, absolute : Bool) -> Array[Step] raise Refused {
  let steps : Array[Step] = []
  if absolute {
    p.pos = p.pos + 1
    if p.peek() == '/' {
      p.pos = p.pos + 1
      steps.push(dos_step())
    }
    steps.push(parse_step(p))
  } else {
    steps.push(parse_step(p))
  }
  while true {
    p.skip_ws()
    if p.peek() == '/' {
      p.pos = p.pos + 1
      if p.peek() == '/' {
        p.pos = p.pos + 1
        steps.push(dos_step())
      }
      steps.push(parse_step(p))
    } else {
      break
    }
  }
  steps
}

fn axis_of(nm : String) -> Axis raise Refused {
  match nm {
    "child" => Axis::AxChild
    "descendant" => Axis::AxDescendant
    "parent" => Axis::AxParent
    "ancestor" => Axis::AxAncestor
    "following-sibling" => Axis::AxFollowingSibling
    "preceding-sibling" => Axis::AxPrecedingSibling
    "following" => Axis::AxFollowing
    "preceding" => Axis::AxPreceding
    "self" => Axis::AxSelf
    "descendant-or-self" => Axis::AxDescendantOrSelf
    "ancestor-or-self" => Axis::AxAncestorOrSelf
    "attribute" => Axis::AxAttribute
    "namespace" => Axis::AxNamespace
    _ => raise Refused::BadQuery(at=0, why="unknown axis " + nm)
  }
}

fn parse_node_test(p : XP) -> NodeTest raise Refused {
  if p.peek() == '*' {
    p.pos = p.pos + 1
    return NodeTest::NameTest("*")
  }
  let nm = p.read_name()
  if is_nodetest_name(nm) && p.peek() == '(' {
    parse_nodetest_call(nm, p)
  } else if p.peek() == ':' && p.peek_at(1) != ':' {
    p.pos = p.pos + 1
    let local = if p.peek() == '*' {
      p.pos = p.pos + 1
      "*"
    } else {
      p.read_name()
    }
    NodeTest::NameTest(nm + ":" + local)
  } else {
    NodeTest::NameTest(nm)
  }
}

fn parse_nodetest_call(nm : String, p : XP) -> NodeTest raise Refused {
  p.pos = p.pos + 1
  let kind = if nm == "text" {
    NodeTest::TextTest
  } else if nm == "comment" {
    NodeTest::CommentTest
  } else if nm == "node" {
    NodeTest::AnyTest
  } else {
    p.skip_ws()
    let target = if p.peek() == '\'' || p.peek() == '"' {
      Some(parse_string_lit(p))
    } else {
      None
    }
    NodeTest::PITest(target)
  }
  p.skip_ws()
  if p.peek() != ')' {
    raise Refused::BadQuery(at=p.pos, why="expected ')'")
  }
  p.pos = p.pos + 1
  kind
}

fn parse_step(p : XP) -> Step raise Refused {
  p.skip_ws()
  if p.peek() == '.' && p.peek_at(1) == '.' {
    p.pos = p.pos + 2
    { axis: Axis::AxParent, test_kind: NodeTest::AnyTest, predicates: [] }
  } else if p.peek() == '.' {
    p.pos = p.pos + 1
    { axis: Axis::AxSelf, test_kind: NodeTest::AnyTest, predicates: [] }
  } else {
    let mut axis = Axis::AxChild
    if p.peek() == '@' {
      p.pos = p.pos + 1
      axis = Axis::AxAttribute
    }
    let mut kind = NodeTest::AnyTest
    if p.peek() == '*' {
      p.pos = p.pos + 1
      kind = NodeTest::NameTest("*")
    } else {
      let nm = p.read_name()
      if p.peek() == ':' && p.peek_at(1) == ':' {
        p.pos = p.pos + 2
        axis = axis_of(nm)
        kind = parse_node_test(p)
      } else if p.peek() == ':' {
        p.pos = p.pos + 1
        let local = if p.peek() == '*' {
          p.pos = p.pos + 1
          "*"
        } else {
          p.read_name()
        }
        kind = NodeTest::NameTest(nm + ":" + local)
      } else if is_nodetest_name(nm) && p.peek() == '(' {
        kind = parse_nodetest_call(nm, p)
      } else {
        kind = NodeTest::NameTest(nm)
      }
    }
    { axis, test_kind: kind, predicates: parse_predicates(p) }
  }
}

fn parse_predicates(p : XP) -> Array[Expr] raise Refused {
  let out : Array[Expr] = []
  while true {
    p.skip_ws()
    if p.peek() == '[' {
      p.pos = p.pos + 1
      let e = parse_or(p)
      p.skip_ws()
      if p.peek() != ']' {
        raise Refused::BadQuery(at=p.pos, why="expected ']'")
      }
      p.pos = p.pos + 1
      out.push(e)
    } else {
      break
    }
  }
  out
}

fn parse_primary(p : XP) -> Expr raise Refused {
  p.skip_ws()
  let c = p.peek()
  if c == '(' {
    p.pos = p.pos + 1
    let e = parse_or(p)
    p.skip_ws()
    if p.peek() != ')' {
      raise Refused::BadQuery(at=p.pos, why="expected ')'")
    }
    p.pos = p.pos + 1
    e
  } else if c == '\'' || c == '"' {
    Expr::StrLit(parse_string_lit(p))
  } else if c >= '0' && c <= '9' {
    Expr::NumLit(parse_number_lit(p))
  } else if c == '.' {
    Expr::NumLit(parse_number_lit(p))
  } else if c == '$' {
    raise Refused::Unsupported(what="XPath variables")
  } else if pname_start(c) {
    let nm = p.read_name()
    p.skip_ws()
    if p.peek() != '(' {
      raise Refused::BadQuery(at=p.pos, why="expected '(' after function name")
    }
    p.pos = p.pos + 1
    let args : Array[Expr] = []
    p.skip_ws()
    if p.peek() != ')' {
      while true {
        args.push(parse_or(p))
        p.skip_ws()
        if p.peek() == ',' {
          p.pos = p.pos + 1
        } else {
          break
        }
      }
    }
    p.skip_ws()
    if p.peek() != ')' {
      raise Refused::BadQuery(at=p.pos, why="expected ')'")
    }
    p.pos = p.pos + 1
    // Arity is checked while parsing, so a call with the wrong shape raises a
    // query error instead of indexing past the argument list while evaluating.
    if not(arity_ok(nm, args.length())) {
      raise Refused::BadQuery(at=p.pos, why="wrong number of arguments to " + nm + "()")
    }
    Expr::FunExpr(nm, args)
  } else {
    raise Refused::BadQuery(at=p.pos, why="expected an expression")
  }
}

/// Whether `name` takes `n` arguments. A name outside the core library is left
/// to the evaluator, which reports it as unsupported.
fn arity_ok(name : String, n : Int) -> Bool {
  if name == "last" || name == "position" || name == "true" || name == "false" {
    return n == 0
  }
  if name == "count" || name == "sum" || name == "id" || name == "not" || name == "boolean" {
    return n == 1
  }
  if name == "floor" || name == "ceiling" || name == "round" || name == "lang" {
    return n == 1
  }
  if name == "starts-with" || name == "contains" || name == "substring-before" {
    return n == 2
  }
  if name == "substring-after" || name == "translate" {
    return n == 2 || (name == "translate" && n == 3)
  }
  if name == "substring" {
    return n == 2 || n == 3
  }
  if name == "concat" {
    return n >= 2
  }
  if name == "string" || name == "string-length" || name == "normalize-space" {
    return n == 0 || n == 1
  }
  if name == "local-name" || name == "name" || name == "namespace-uri" || name == "number" {
    return n == 0 || n == 1
  }
  true
}

fn parse_string_lit(p : XP) -> String raise Refused {
  let q = p.peek()
  p.pos = p.pos + 1
  let sb = StringBuilder()
  while p.pos < p.n && p.s[p.pos] != q {
    sb.write_char(p.s[p.pos])
    p.pos = p.pos + 1
  }
  if p.pos >= p.n {
    raise Refused::BadQuery(at=p.pos, why="unterminated string")
  }
  p.pos = p.pos + 1
  sb.to_string()
}

fn parse_number_lit(p : XP) -> Double raise Refused {
  let sb = StringBuilder()
  while p.pos < p.n && p.s[p.pos] >= '0' && p.s[p.pos] <= '9' {
    sb.write_char(p.s[p.pos])
    p.pos = p.pos + 1
  }
  if p.pos < p.n && p.s[p.pos] == '.' {
    sb.write_char('.')
    p.pos = p.pos + 1
    while p.pos < p.n && p.s[p.pos] >= '0' && p.s[p.pos] <= '9' {
      sb.write_char(p.s[p.pos])
      p.pos = p.pos + 1
    }
  }
  str_to_number(sb.to_string())
}

// ---------------------------------------------------------------------------
// Value conversion
// ---------------------------------------------------------------------------

fn is_nan(d : Double) -> Bool {
  d != d
}

fn nan() -> Double {
  0.0 / 0.0
}

fn round_half_up(d : Double) -> Double {
  (d + 0.5).floor()
}

fn i2d(i : Int) -> Double {
  i.to_double()
}

fn str_to_number(s : String) -> Double {
  let t = trim_xp(s)
  let cs = t.to_array()
  let n = cs.length()
  if n == 0 {
    return nan()
  }
  let mut i = 0
  let mut sign = 1.0
  if i < n && (cs[i] == '+' || cs[i] == '-') {
    if cs[i] == '-' {
      sign = -1.0
    }
    i = i + 1
  }
  let mut v = 0.0
  let mut any = false
  while i < n && cs[i] >= '0' && cs[i] <= '9' {
    v = v * 10.0 + i2d(Char::to_int(cs[i]) - Char::to_int('0'))
    i = i + 1
    any = true
  }
  if i < n && cs[i] == '.' {
    i = i + 1
    let mut f = 0.1
    while i < n && cs[i] >= '0' && cs[i] <= '9' {
      v = v + i2d(Char::to_int(cs[i]) - Char::to_int('0')) * f
      f = f * 0.1
      i = i + 1
      any = true
    }
  }
  if any == false {
    return nan()
  }
  if i < n && (cs[i] == 'e' || cs[i] == 'E') {
    i = i + 1
    let mut esign = 1
    if i < n && (cs[i] == '+' || cs[i] == '-') {
      if cs[i] == '-' {
        esign = -1
      }
      i = i + 1
    }
    let mut ev = 0
    while i < n && cs[i] >= '0' && cs[i] <= '9' {
      ev = ev * 10 + (Char::to_int(cs[i]) - Char::to_int('0'))
      i = i + 1
    }
    let mut k = 0
    while k < ev {
      if esign > 0 {
        v = v * 10.0
      } else {
        v = v / 10.0
      }
      k = k + 1
    }
  }
  if i != n {
    return nan()
  }
  sign * v
}

fn trim_xp(s : String) -> String {
  let cs = s.to_array()
  let n = cs.length()
  let mut a = 0
  while a < n && xp_ws(cs[a]) {
    a = a + 1
  }
  let mut b = n
  while b > a && xp_ws(cs[b - 1]) {
    b = b - 1
  }
  s.substring(start=a, end=b)
}

fn num_str(d : Double) -> String {
  if is_nan(d) {
    "NaN"
  } else if d == 0.0 {
    "0"
  } else {
    d.to_string()
  }
}

/// The XPath string-value of a node. It is the concatenated descendant text
/// for an element or the document, the data for a comment or a processing
/// instruction, and the value for an attribute.
fn node_string_value(n : Node) -> String {
  match n {
    CommentNode(s) => s
    ProcessingInstructionNode(pi) => pi.data
    _ => n.text_content()
  }
}

fn xval_to_string(v : XVal) -> String {
  match v {
    VNodes(ns) => if ns.length() == 0 {
      ""
    } else {
      node_string_value(ns[0])
    }
    VStr(s) => s
    VNum(d) => num_str(d)
    VBool(b) => if b {
      "true"
    } else {
      "false"
    }
  }
}

fn xval_to_number(v : XVal) -> Double {
  match v {
    VNum(d) => d
    VStr(s) => str_to_number(s)
    VBool(b) => if b {
      1.0
    } else {
      0.0
    }
    VNodes(ns) => if ns.length() == 0 {
      nan()
    } else {
      str_to_number(node_string_value(ns[0]))
    }
  }
}

fn xval_to_bool(v : XVal) -> Bool {
  match v {
    VBool(b) => b
    VStr(s) => s.length() > 0
    VNum(d) => d != 0.0 && is_nan(d) == false
    VNodes(ns) => ns.length() > 0
  }
}

fn xval_to_nodes(v : XVal) -> Array[Node] {
  match v {
    VNodes(ns) => ns
    _ => []
  }
}

// ---------------------------------------------------------------------------
// Axes
// ---------------------------------------------------------------------------

fn all_nodes(root : Element) -> Array[Node] {
  let out : Array[Node] = []
  for c in root.children {
    out.push(c)
    collect_all(c, out)
  }
  out
}

fn collect_all(n : Node, out : Array[Node]) -> Unit {
  match n {
    ElementNode(e) => for c in e.children {
      out.push(c)
      collect_all(c, out)
    }
    _ => ()
  }
}

fn index_of_node(arr : Array[Node], target : Node) -> Int {
  let mut i = 0
  for n in arr {
    let same = match (n, target) {
      (ElementNode(a), ElementNode(b)) => physical_equal(a, b)
      (TextNode(a), TextNode(b)) => a == b
      (CDataNode(a), CDataNode(b)) => a == b
      (CommentNode(a), CommentNode(b)) => a == b
      (DoctypeNode(a), DoctypeNode(b)) => a == b
      (ProcessingInstructionNode(a), ProcessingInstructionNode(b)) => a == b
      _ => false
    }
    if same {
      return i
    }
    i = i + 1
  }
  -1
}

fn sibling_nodes(el : Element, forward : Bool) -> Array[Node] {
  let out : Array[Node] = []
  match el.parent {
    None => ()
    Some(p) => {
      let idx = el.index_in_parent()
      if forward {
        let mut i = idx + 1
        while i < p.children.length() {
          out.push(p.children[i])
          i = i + 1
        }
      } else {
        let mut i = idx - 1
        while i >= 0 {
          out.push(p.children[i])
          i = i - 1
        }
      }
    }
  }
  out
}

fn axis_nodes(node : Node, axis : Axis, root : Element) -> Array[Node] {
  match axis {
    AxChild => node.node_children()
    AxDescendant => match node {
      ElementNode(e) => e.descendants()
      _ => []
    }
    AxParent => match node {
      ElementNode(e) => match e.parent {
        Some(p) => [ElementNode(p)]
        None => []
      }
      _ => []
    }
    AxAncestor => match node {
      ElementNode(e) => {
        let out : Array[Node] = []
        for a in e.ancestors() {
          out.push(ElementNode(a))
        }
        out
      }
      _ => []
    }
    AxFollowingSibling => match node {
      ElementNode(e) => sibling_nodes(e, true)
      _ => []
    }
    AxPrecedingSibling => match node {
      ElementNode(e) => sibling_nodes(e, false)
      _ => []
    }
    AxSelf => [node]
    AxDescendantOrSelf => match node {
      ElementNode(e) => {
        let out : Array[Node] = [node]
        for d in e.descendants() {
          out.push(d)
        }
        out
      }
      _ => [node]
    }
    AxAncestorOrSelf => match node {
      ElementNode(e) => {
        let out : Array[Node] = [node]
        for a in e.ancestors() {
          out.push(ElementNode(a))
        }
        out
      }
      _ => [node]
    }
    AxAttribute => match node {
      ElementNode(e) => {
        let out : Array[Node] = []
        for pair in e.attrs {
          let (k, v) = pair
          out.push(AttributeNode(k, v))
        }
        out
      }
      _ => []
    }
    AxNamespace => []
    AxFollowing => following_nodes(node, root)
    AxPreceding => preceding_nodes(node, root)
  }
}

fn following_nodes(node : Node, root : Element) -> Array[Node] {
  match node {
    ElementNode(e) => {
      let all = all_nodes(root)
      let idx = index_of_node(all, node)
      if idx < 0 {
        return []
      }
      let desc = desc_elements(e.descendants())
      let out : Array[Node] = []
      let mut i = idx + 1
      while i < all.length() {
        let cand = all[i]
        let is_desc = match cand {
          ElementNode(ce) => array_has_element(desc, ce)
          _ => false
        }
        if is_desc == false {
          out.push(cand)
        }
        i = i + 1
      }
      out
    }
    _ => []
  }
}

fn desc_elements(nodes : Array[Node]) -> Array[Element] {
  let out : Array[Element] = []
  for n in nodes {
    match n {
      ElementNode(e) => out.push(e)
      _ => ()
    }
  }
  out
}

fn preceding_nodes(node : Node, root : Element) -> Array[Node] {
  match node {
    ElementNode(e) => {
      let all = all_nodes(root)
      let idx = index_of_node(all, node)
      if idx < 0 {
        return []
      }
      let anc : Array[Element] = [e]
      for a in e.ancestors() {
        anc.push(a)
      }
      let out : Array[Node] = []
      let mut i = idx - 1
      while i >= 0 {
        let cand = all[i]
        let is_anc = match cand {
          ElementNode(ce) => array_has_element(anc, ce)
          _ => false
        }
        if is_anc == false {
          out.push(cand)
        }
        i = i - 1
      }
      out
    }
    _ => []
  }
}

/// Whether this element is the synthetic root of a `Document`. XPath calls it
/// the root node: it is the parent of the document element, but it is not an
/// element, so no name test matches it and it has no name.
fn is_document_node(e : Element) -> Bool {
  e.name == "#document"
}

fn test_node(node : Node, nt : NodeTest) -> Bool {
  match nt {
    NameTest(nm) => match node {
      ElementNode(e) => not(is_document_node(e)) && name_matches(e, nm)
      AttributeNode(an, _) => {
        if nm == "*" {
          true
        } else if an == nm {
          true
        } else if nm.contains("{") == false {
          local_of_qname(an) == nm
        } else {
          false
        }
      }
      _ => false
    }
    TextTest => match node {
      TextNode(_) | CDataNode(_) => true
      _ => false
    }
    CommentTest => match node {
      CommentNode(_) => true
      _ => false
    }
    AnyTest => true
    PITest(target) => match node {
      ProcessingInstructionNode(pi) => match target {
        Some(t) => pi.target == t
        None => true
      }
      _ => false
    }
  }
}

fn predicate_ok(v : XVal, pos : Int) -> Bool {
  match v {
    VNum(d) => d == i2d(pos)
    _ => xval_to_bool(v)
  }
}

fn apply_predicates(nodes : Array[Node], preds : Array[Expr], root : Element) -> Array[Node] raise Refused {
  let mut cur = nodes
  for pred in preds {
    let out : Array[Node] = []
    let size = cur.length()
    let mut i = 0
    for node in cur {
      let c = XC::{ node, position: i + 1, size, root }
      let v = eval_expr(pred, c)
      if predicate_ok(v, i + 1) {
        out.push(node)
      }
      i = i + 1
    }
    cur = out
  }
  cur
}

fn eval_step(node : Node, step : Step, root : Element) -> Array[Node] raise Refused {
  let base = axis_nodes(node, step.axis, root)
  let filtered : Array[Node] = []
  for b in base {
    if test_node(b, step.test_kind) {
      filtered.push(b)
    }
  }
  if step.predicates.length() > 0 {
    apply_predicates(filtered, step.predicates, root)
  } else {
    filtered
  }
}

fn fold_steps(start : Array[Node], steps : Array[Step], root : Element) -> Array[Node] raise Refused {
  let mut cur = start
  for step in steps {
    let out : Array[Node] = []
    for node in cur {
      for r in eval_step(node, step, root) {
        out.push(r)
      }
    }
    cur = dedup_nodes(out)
  }
  cur
}

// ---------------------------------------------------------------------------
// Evaluation
// ---------------------------------------------------------------------------

/// The position of `n` in a preorder walk of the tree, or -1 for a node the
/// walk does not visit (an attribute, or a node detached from the tree).
fn preorder_index(all : Array[Node], n : Node) -> Int {
  let mut i = 0
  while i < all.length() {
    if physical_equal(all[i], n) {
      return i
    }
    i = i + 1
  }
  -1
}

/// A union of two node-sets. XPath returns a node-set in document order, and a
/// union is the operation that can produce one out of order, so the result is
/// re-sorted by preorder position. Duplicates are removed by position, which is
/// what makes them duplicates in the first place. Attribute nodes have no
/// preorder position; they keep their relative order and sort after elements,
/// which is as far as this tree model can place them.
fn union_nodes(a : Array[Node], b : Array[Node], root : Element) -> Array[Node] {
  let all = all_nodes(root)
  let keys : Array[Int] = []
  let kept : Array[Node] = []
  let groups : Array[Array[Node]] = [a, b]
  for g in groups {
    for n in g {
      let k = preorder_index(all, n)
      let mut dup = false
      let mut i = 0
      while i < keys.length() {
        if keys[i] == k {
          if k >= 0 || node_string_value(kept[i]) == node_string_value(n) {
            dup = true
          }
        }
        i = i + 1
      }
      if not(dup) {
        keys.push(k)
        kept.push(n)
      }
    }
  }
  let out : Array[Node] = []
  let outk : Array[Int] = []
  let mut i = 0
  while i < kept.length() {
    let k = keys[i]
    let sort_key = if k < 0 {
      1 << 30
    } else {
      k
    }
    let mut pos = out.length()
    while pos > 0 && outk[pos - 1] > sort_key {
      pos = pos - 1
    }
    out.insert(pos, kept[i])
    outk.insert(pos, sort_key)
    i = i + 1
  }
  out
}

fn eval_expr(e : Expr, c : XC) -> XVal raise Refused {
  match e {
    StrLit(s) => XVal::VStr(s)
    NumLit(d) => XVal::VNum(d)
    PathExpr(abs, steps) => {
      let start : Array[Node] = if abs {
        [ElementNode(c.root)]
      } else {
        [c.node]
      }
      XVal::VNodes(fold_steps(start, steps, c.root))
    }
    PathFrom(base, steps) => {
      let base_val = eval_expr(base, c)
      let start = xval_to_nodes(base_val)
      XVal::VNodes(fold_steps(start, steps, c.root))
    }
    FilterExpr(base, preds) => {
      let base_val = eval_expr(base, c)
      let start = xval_to_nodes(base_val)
      XVal::VNodes(apply_predicates(start, preds, c.root))
    }
    UnionExpr(l, r) => {
      let ln = xval_to_nodes(eval_expr(l, c))
      let rn = xval_to_nodes(eval_expr(r, c))
      XVal::VNodes(union_nodes(ln, rn, c.root))
    }
    NegExpr(inner) => {
      let v = eval_expr(inner, c)
      XVal::VNum(-xval_to_number(v))
    }
    BinExpr(op, l, r) => {
      let lv = eval_expr(l, c)
      let rv = eval_expr(r, c)
      eval_bin(op, lv, rv)
    }
    FunExpr(name, args) => {
      eval_fun(name, args, c)
    }
  }
}

fn eval_bin(op : String, l : XVal, r : XVal) -> XVal raise Refused {
  if op == "and" {
    XVal::VBool(xval_to_bool(l) && xval_to_bool(r))
  } else if op == "or" {
    XVal::VBool(xval_to_bool(l) || xval_to_bool(r))
  } else if op == "=" {
    XVal::VBool(cmp_eq(l, r))
  } else if op == "!=" {
    XVal::VBool(cmp_ne(l, r))
  } else if op == "<" || op == ">" || op == "<=" || op == ">=" {
    XVal::VBool(cmp_rel(op, l, r))
  } else if op == "+" {
    XVal::VNum(xval_to_number(l) + xval_to_number(r))
  } else if op == "-" {
    XVal::VNum(xval_to_number(l) - xval_to_number(r))
  } else if op == "*" {
    XVal::VNum(xval_to_number(l) * xval_to_number(r))
  } else if op == "div" {
    XVal::VNum(xval_to_number(l) / xval_to_number(r))
  } else if op == "mod" {
    let a = xval_to_number(l)
    let b = xval_to_number(r)
    XVal::VNum(a - i2d((a / b).to_int()) * b)
  } else {
    raise Refused::Unsupported(what="operator " + op)
  }
}

fn scalar_eq(l : XVal, r : XVal) -> Bool {
  if is_num_like(l) || is_num_like(r) {
    xval_to_number(l) == xval_to_number(r)
  } else {
    xval_to_string(l) == xval_to_string(r)
  }
}

fn is_num_like(v : XVal) -> Bool {
  match v {
    VNum(_) => true
    _ => false
  }
}

fn scalar_eq_node(node : Node, s : XVal) -> Bool {
  match s {
    VNum(d) => str_to_number(node_string_value(node)) == d
    _ => node_string_value(node) == xval_to_string(s)
  }
}

fn cmp_eq(l : XVal, r : XVal) -> Bool {
  match (l, r) {
    (VBool(_), _) => xval_to_bool(l) == xval_to_bool(r)
    (_, VBool(_)) => xval_to_bool(l) == xval_to_bool(r)
    (VNodes(x), VNodes(y)) => {
      let mut found = false
      for a in x {
        for b in y {
          if node_string_value(a) == node_string_value(b) {
            found = true
          }
        }
      }
      found
    }
    (VNodes(x), _) => {
      let mut found = false
      for a in x {
        if scalar_eq_node(a, r) {
          found = true
        }
      }
      found
    }
    (_, VNodes(y)) => {
      let mut found = false
      for b in y {
        if scalar_eq_node(b, l) {
          found = true
        }
      }
      found
    }
    _ => scalar_eq(l, r)
  }
}

fn cmp_ne(l : XVal, r : XVal) -> Bool {
  match (l, r) {
    (VBool(_), _) => xval_to_bool(l) != xval_to_bool(r)
    (_, VBool(_)) => xval_to_bool(l) != xval_to_bool(r)
    (VNodes(x), VNodes(y)) => {
      let mut found = false
      for a in x {
        for b in y {
          if node_string_value(a) != node_string_value(b) {
            found = true
          }
        }
      }
      found
    }
    (VNodes(x), _) => {
      let mut found = false
      for a in x {
        if scalar_eq_node(a, r) == false {
          found = true
        }
      }
      found
    }
    (_, VNodes(y)) => {
      let mut found = false
      for b in y {
        if scalar_eq_node(b, l) == false {
          found = true
        }
      }
      found
    }
    _ => scalar_eq(l, r) == false
  }
}

fn num_rel(op : String, a : Double, b : Double) -> Bool {
  if op == "<" {
    a < b
  } else if op == ">" {
    a > b
  } else if op == "<=" {
    a <= b
  } else {
    a >= b
  }
}

fn cmp_rel(op : String, l : XVal, r : XVal) -> Bool {
  match (l, r) {
    (VNodes(x), VNodes(y)) => {
      let mut found = false
      for a in x {
        for b in y {
          if num_rel(op, str_to_number(node_string_value(a)), str_to_number(node_string_value(b))) {
            found = true
          }
        }
      }
      found
    }
    (VNodes(x), _) => {
      let rn = xval_to_number(r)
      let mut found = false
      for a in x {
        if num_rel(op, str_to_number(node_string_value(a)), rn) {
          found = true
        }
      }
      found
    }
    (_, VNodes(y)) => {
      let ln = xval_to_number(l)
      let mut found = false
      for b in y {
        if num_rel(op, ln, str_to_number(node_string_value(b))) {
          found = true
        }
      }
      found
    }
    _ => num_rel(op, xval_to_number(l), xval_to_number(r))
  }
}

// ---------------------------------------------------------------------------
// Core function library
// ---------------------------------------------------------------------------

fn context_string(c : XC) -> String {
  node_string_value(c.node)
}

fn eval_fun(name : String, args : Array[Expr], c : XC) -> XVal raise Refused {
  if name == "last" {
    XVal::VNum(i2d(c.size))
  } else if name == "position" {
    XVal::VNum(i2d(c.position))
  } else if name == "count" {
    XVal::VNum(i2d(xval_to_nodes(eval_expr(args[0], c)).length()))
  } else if name == "id" {
    let v = eval_expr(args[0], c)
    let wanted = xval_to_string(v)
    let ids = split_ws(wanted)
    let out : Array[Node] = []
    for e in c.root.descendant_elements() {
      match e.attr("id") {
        Some(id) => if ids.contains(id) {
          out.push(ElementNode(e))
        }
        None => ()
      }
    }
    XVal::VNodes(out)
  } else if name == "local-name" {
    XVal::VStr(node_local_name(fun_node(args, c)))
  } else if name == "name" {
    XVal::VStr(node_name(fun_node(args, c)))
  } else if name == "namespace-uri" {
    XVal::VStr(node_namespace_uri(fun_node(args, c)))
  } else if name == "string" {
    XVal::VStr(if args.length() == 0 {
      context_string(c)
    } else {
      xval_to_string(eval_expr(args[0], c))
    })
  } else if name == "concat" {
    let sb = StringBuilder()
    for a in args {
      sb.write_string(xval_to_string(eval_expr(a, c)))
    }
    XVal::VStr(sb.to_string())
  } else if name == "starts-with" {
    XVal::VBool(xval_to_string(eval_expr(args[0], c)).has_prefix(xval_to_string(eval_expr(args[1], c))))
  } else if name == "contains" {
    XVal::VBool(xval_to_string(eval_expr(args[0], c)).contains(xval_to_string(eval_expr(args[1], c))))
  } else if name == "substring-before" {
    let s = xval_to_string(eval_expr(args[0], c))
    let sep = xval_to_string(eval_expr(args[1], c))
    XVal::VStr(substring_before(s, sep))
  } else if name == "substring-after" {
    let s = xval_to_string(eval_expr(args[0], c))
    let sep = xval_to_string(eval_expr(args[1], c))
    XVal::VStr(substring_after(s, sep))
  } else if name == "substring" {
    let s = xval_to_string(eval_expr(args[0], c))
    let start = round_half_up(xval_to_number(eval_expr(args[1], c)))
    let len = if args.length() >= 3 {
      round_half_up(xval_to_number(eval_expr(args[2], c)))
    } else {
      1.0e18
    }
    XVal::VStr(xpath_substring(s, start, len))
  } else if name == "string-length" {
    let s = if args.length() == 0 {
      context_string(c)
    } else {
      xval_to_string(eval_expr(args[0], c))
    }
    XVal::VNum(i2d(s.length()))
  } else if name == "normalize-space" {
    let s = if args.length() == 0 {
      context_string(c)
    } else {
      xval_to_string(eval_expr(args[0], c))
    }
    XVal::VStr(normalize_space(s))
  } else if name == "translate" {
    let s = xval_to_string(eval_expr(args[0], c))
    let from = xval_to_string(eval_expr(args[1], c))
    let to = xval_to_string(eval_expr(args[2], c))
    XVal::VStr(translate(s, from, to))
  } else if name == "boolean" {
    XVal::VBool(xval_to_bool(eval_expr(args[0], c)))
  } else if name == "not" {
    XVal::VBool(xval_to_bool(eval_expr(args[0], c)) == false)
  } else if name == "true" {
    XVal::VBool(true)
  } else if name == "false" {
    XVal::VBool(false)
  } else if name == "lang" {
    XVal::VBool(false)
  } else if name == "number" {
    let v = if args.length() == 0 {
      XVal::VStr(context_string(c))
    } else {
      eval_expr(args[0], c)
    }
    XVal::VNum(xval_to_number(v))
  } else if name == "sum" {
    let ns = xval_to_nodes(eval_expr(args[0], c))
    let mut total = 0.0
    for n in ns {
      total = total + str_to_number(node_string_value(n))
    }
    XVal::VNum(total)
  } else if name == "floor" {
    XVal::VNum(xval_to_number(eval_expr(args[0], c)).floor())
  } else if name == "ceiling" {
    XVal::VNum(xval_to_number(eval_expr(args[0], c)).ceil())
  } else if name == "round" {
    XVal::VNum(round_half_up(xval_to_number(eval_expr(args[0], c))))
  } else {
    raise Refused::Unsupported(what="XPath function " + name + "()")
  }
}

fn fun_node(args : Array[Expr], c : XC) -> Node raise Refused {
  if args.length() == 0 {
    c.node
  } else {
    let ns = xval_to_nodes(eval_expr(args[0], c))
    if ns.length() == 0 {
      c.node
    } else {
      ns[0]
    }
  }
}

fn node_local_name(n : Node) -> String {
  match n {
    ElementNode(e) => if is_document_node(e) {
      ""
    } else {
      e.local_name()
    }
    AttributeNode(nm, _) => local_of_qname(nm)
    ProcessingInstructionNode(pi) => pi.target
    _ => ""
  }
}

fn node_name(n : Node) -> String {
  match n {
    ElementNode(e) => if is_document_node(e) {
      ""
    } else {
      e.name
    }
    AttributeNode(nm, _) => nm
    ProcessingInstructionNode(pi) => pi.target
    _ => ""
  }
}

fn node_namespace_uri(n : Node) -> String {
  match n {
    ElementNode(e) => if is_document_node(e) {
      ""
    } else {
      e.namespace_uri()
    }
    _ => ""
  }
}

fn local_of_qname(s : String) -> String {
  let mut idx = -1
  let mut i = 0
  for c in s {
    if c == ':' {
      idx = i
    }
    i = i + 1
  }
  if idx >= 0 {
    s.substring(start=idx + 1, end=s.length())
  } else {
    s
  }
}

fn substring_before(s : String, sep : String) -> String {
  if sep.length() == 0 {
    return ""
  }
  let idx = index_of_sub(s, sep)
  if idx < 0 {
    ""
  } else {
    s.substring(start=0, end=idx)
  }
}

fn substring_after(s : String, sep : String) -> String {
  if sep.length() == 0 {
    return s
  }
  let idx = index_of_sub(s, sep)
  if idx < 0 {
    ""
  } else {
    s.substring(start=idx + sep.length(), end=s.length())
  }
}

fn index_of_sub(s : String, sub : String) -> Int {
  let n = s.length()
  let m = sub.length()
  if m == 0 {
    return 0
  }
  if m > n {
    return -1
  }
  let cs = s.to_array()
  let cp = sub.to_array()
  let mut i = 0
  while i + m <= n {
    let mut j = 0
    let mut ok = true
    while j < m {
      if cs[i + j] != cp[j] {
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

fn xpath_substring(s : String, start : Double, len : Double) -> String {
  let cs = s.to_array()
  let n = cs.length()
  let sb = StringBuilder()
  let mut i = 0
  while i < n {
    let pos = i2d(i + 1)
    if pos >= start && pos < start + len {
      sb.write_char(cs[i])
    }
    i = i + 1
  }
  sb.to_string()
}

fn normalize_space(s : String) -> String {
  let toks = split_ws(s)
  join_with_space(toks)
}

fn translate(s : String, from : String, to : String) -> String {
  let froms = from.to_array()
  let tos = to.to_array()
  let sb = StringBuilder()
  for c in s {
    let mut idx = -1
    let mut i = 0
    while i < froms.length() {
      if froms[i] == c {
        idx = i
        break
      }
      i = i + 1
    }
    if idx < 0 {
      sb.write_char(c)
    } else if idx < tos.length() {
      sb.write_char(tos[idx])
    }
  }
  sb.to_string()
}

// ---------------------------------------------------------------------------
// Public entry points
// ---------------------------------------------------------------------------

fn root_of_selection(sel : Selection) -> Element {
  match sel.doc {
    Some(d) => d.root
    None => {
      if sel.items.length() == 0 {
        Element::new("#document")
      } else {
        match sel.items[0].as_element() {
          Some(e) => {
            let mut cur = e
            let mut hops = 0
            while true {
              match cur.parent {
                Some(p) => {
                  cur = p
                  hops = hops + 1
                  if hops > 100000 {
                    break
                  }
                }
                None => break
              }
            }
            cur
          }
          None => Element::new("#document")
        }
      }
    }
  }
}

fn eval_to_xval(expr : Expr, ctx : Selection) -> XVal raise Refused {
  if ctx.items.length() == 0 {
    return XVal::VNodes([])
  }
  let root = root_of_selection(ctx)
  let out : Array[Node] = []
  let mut scalar : XVal? = None
  let mut i = 0
  let size = ctx.items.length()
  for item in ctx.items {
    let c = XC::{ node: item, position: i + 1, size, root }
    let v = eval_expr(expr, c)
    match v {
      VNodes(ns) => for n in ns {
        out.push(n)
      }
      other => if scalar.is_none() {
        scalar = Some(other)
      }
    }
    i = i + 1
  }
  if out.length() > 0 || scalar.is_none() {
    XVal::VNodes(dedup_nodes(out))
  } else {
    match scalar {
      Some(v) => v
      None => XVal::VNodes([])
    }
  }
}

/// Evaluate `query` against `ctx` and return the node-set (a non-node-set
/// answer becomes its XPath string value as one text node).
pub fn xpath_select(ctx : Selection, query : String) -> Selection raise Refused {
  if ctx.items.length() == 0 {
    return ctx
  }
  let expr = parse_xpath(query)
  let v = eval_to_xval(expr, ctx)
  match v {
    VNodes(ns) => Selection::with_doc(ctx.doc, dedup_nodes(ns))
    other => Selection::with_doc(ctx.doc, [TextNode(xval_to_string(other))])
  }
}

/// Evaluate `query` against `ctx` and return the typed answer.
pub fn xpath_value_of(ctx : Selection, query : String) -> XPathValue raise Refused {
  if ctx.items.length() == 0 {
    return XPathValue::Nodes(ctx)
  }
  let expr = parse_xpath(query)
  let v = eval_to_xval(expr, ctx)
  match v {
    VNodes(ns) => XPathValue::Nodes(Selection::with_doc(ctx.doc, dedup_nodes(ns)))
    VStr(s) => XPathValue::Str(s)
    VNum(d) => XPathValue::Num(d)
    VBool(b) => XPathValue::Flag(b)
  }
}
