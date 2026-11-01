// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// libxml2's XPath corpus: expressions with the value libxml2 produced, a boolean, a
// number, a string, or a node-set by its size and the kind and name of each top-level
// node. Numbers are compared to five significant digits because libxml2 prints six.

///|
enum XpActual {
  AFlag(Bool)
  ANum(Double)
  AStr(String)
  ANodes(Int32, String)
  AFailed
}

///|
/// The preorder-stable description of a node-set that the corpus records:
/// the kind and name of each top-level node, joined with `|`.
fn xp_node_label(node : @moonxml.Node) -> String {
  match node {
    // The synthetic #document element is XPath's root node, which the corpus
    // writes as `/`.
    @moonxml.ElementNode(e) =>
      if e.name == "#document" {
        "/"
      } else {
        "ELEMENT " + @moonxml.local_of(e.name)
      }
    @moonxml.TextNode(_) => "TEXT"
    @moonxml.CDataNode(_) => "CDATA"
    @moonxml.CommentNode(_) => "COMMENT"
    @moonxml.ProcessingInstructionNode(pi) => "PI " + pi.target
    @moonxml.DoctypeNode(_) => "DOCTYPE"
  }
}

///|
fn xp_join_labels(nodes : Array[@moonxml.Node]) -> String {
  let sb = StringBuilder()
  let mut first = true
  for n in nodes {
    if !first {
      sb.write_string("|")
    }
    first = false
    sb.write_string(xp_node_label(n))
  }
  sb.to_string()
}

///|
fn xp_eval(doc : @moonxml.Document, expr : String) -> XpActual {
  xp_actual(() => doc.xpath_value(expr))
}

///|
fn xp_eval_at(root : @moonxml.Element, expr : String) -> XpActual {
  xp_actual(() => root.xpath_value(expr))
}

///|
fn xp_actual(
  run : () -> @moonxml.XPathValue raise @moonxml.Refused,
) -> XpActual {
  let v = run() catch { _ => return AFailed }
  match v {
    @moonxml.XPathValue::Flag(b) => AFlag(b)
    @moonxml.XPathValue::Num(d) => ANum(d)
    @moonxml.XPathValue::Str(s) => AStr(s)
    @moonxml.XPathValue::Nodes(sel) =>
      ANodes(sel.length(), xp_join_labels(sel.items))
  }
}

///|
/// Parse the corpus's number syntax: an optional sign, digits with an optional
/// fraction, and an optional decimal exponent.
fn xp_parse_number(s : String) -> Double {
  let cs = s.to_array()
  let n = cs.length()
  let mut i = 0
  let mut sign = 1.0
  if i < n && (cs[i] == '+' || cs[i] == '-') {
    if cs[i] == '-' {
      sign = -1.0
    }
    i = i + 1
  }
  let mut v = 0.0
  while i < n && cs[i] >= '0' && cs[i] <= '9' {
    v = v * 10.0 + (Char::to_int(cs[i]) - 48).to_double()
    i = i + 1
  }
  if i < n && cs[i] == '.' {
    i = i + 1
    let mut scale = 0.1
    while i < n && cs[i] >= '0' && cs[i] <= '9' {
      v = v + (Char::to_int(cs[i]) - 48).to_double() * scale
      scale = scale * 0.1
      i = i + 1
    }
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
    let mut e = 0
    while i < n && cs[i] >= '0' && cs[i] <= '9' {
      e = e * 10 + (Char::to_int(cs[i]) - 48)
      i = i + 1
    }
    let mut k = 0
    while k < e {
      if esign > 0 {
        v = v * 10.0
      } else {
        v = v / 10.0
      }
      k = k + 1
    }
  }
  sign * v
}

///|
fn xp_abs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
/// libxml2 prints a double with six significant digits, so agreement is asserted
/// to five. Infinity and NaN have to be recognised before any arithmetic.
fn xp_number_matches(actual : Double, expected : String) -> Bool {
  if expected == "NaN" {
    return actual != actual
  }
  if expected == "Infinity" {
    return actual > 1.0e308
  }
  if expected == "-Infinity" {
    return actual < -1.0e308
  }
  let want = xp_parse_number(expected)
  if actual != actual || want != want {
    return false
  }
  let scale = if xp_abs(want) > 1.0 { xp_abs(want) } else { 1.0 }
  xp_abs(actual - want) / scale <= 5.0e-6
}

///|
fn xp_matches(
  actual : XpActual,
  kind : String,
  value : String,
  nodes : String,
) -> Bool {
  match (actual, kind) {
    (AFailed, _) => false
    (AFlag(b), "bool") => (if b { "true" } else { "false" }) == value
    (ANum(d), "num") => xp_number_matches(d, value)
    (AStr(s), "str") => s == value
    (ANodes(n, labels), "nodes") => n.to_string() == value && labels == nodes
    _ => false
  }
}

///|
/// Files whose expressions libxml2 ran with the document element as the context
/// node, where a standard XPath context is the root.
let from_element : Array[String] = ["tests/mixedpat"]

///|
/// Where XPath 1.0 and libxml2 part company and this library keeps to the
/// specification: `string()` of a huge number is its decimal form.
let specified : Array[String] = [
  "string(12345678901234567890)", "string(-12345678901234567890)",
]

///|
/// What does not pass yet, each a gap in the engine. A case leaving this list has
/// to be taken off it, so the list can only shrink.
let known : Array[String] = [
  "expr/base 1e2147483648", "expr/base 1e4294967296", "expr/base 1e9223372036854775808",
  "expr/base 1e18446744073709551616", "expr/base 1e-2147483649", "expr/base 1e-4294967296",
  "expr/base 1e-9223372036854775809", "expr/base 1e-18446744073709551616", "expr/compare 'b' > 'a'",
  "expr/compare 'a' < 'b'", "expr/compare 'a' >= 'a'", "expr/compare 'b' >= 'a'",
  "expr/compare 'a' <= 'a'", "expr/compare 'a' <= 'b'", "expr/compare 'a' > '0.0'",
  "expr/floats 1.23e3", "expr/floats 1.23e-3", "expr/floats 1 div -0", "expr/floats (1 div -0) > 0",
  "expr/floats (1 div -0) < 0", "expr/floats 1 div floor(-0)", "expr/floats 1 div ceiling(-0)",
  "expr/floats 1 div round(-0.1)", "expr/floats 1 div round(-0)", "expr/strings substring(\"12345\",0 div 0, 3)",
  "expr/strings substring(\"12345\",-5000000000,5000000004)", "tests/chaptersprefol /preceding::*",
  "tests/langsimple //*[lang('en')]", "tests/langsimple //*[lang('en-us')]", "tests/nodespat //.",
  "tests/nodespat /root//.", "tests/nodespat //.//./././/.", "tests/nodespat /root//././/bar//.",
  "tests/nssimple /doc/elem/namespace::node()/..", "tests/nssimple /doc/elem/namespace::*/self::node()[true()]",
  "tests/nssimple //*[namespace::ns1]", "tests/nssimple /doc/elem/namespace::ns2/following::*",
  "tests/nssimple /doc/elem/namespace::ns2/preceding::*", "tests/simplebase /child::EXAMPLE/attribute::prop1/self::node()",
  "tests/simplebase /child::EXAMPLE/attribute::prop1/descendant-or-self::node()",
  "tests/simplebase /child::EXAMPLE/attribute::prop1/ancestor-or-self::node()", "tests/simplebase /child::EXAMPLE/attribute::prop1/ancestor-or-self::*",
]

///|
fn xp_run(doc : @moonxml.Document, c : XPathCase) -> XpActual {
  if from_element.contains(c.file) && doc.document_element() is Some(root) {
    return xp_eval_at(root, c.expr)
  }
  xp_eval(doc, c.expr)
}

///|
test "libxml2 xpath: everything passes but the known gaps" {
  let parsed : Map[String, @moonxml.Document] = Map([])
  for pair in xpath_docs() {
    let (name, text) = pair
    parsed[name] = @xml.loads(text)
  }
  let empty = @xml.loads("<r/>")
  let surprises = []
  for c in xpath_cases() {
    if specified.contains(c.expr) {
      continue
    }
    let doc = parsed.get(c.doc).unwrap_or(empty)
    let ok = xp_matches(xp_run(doc, c), c.kind, c.value, c.nodes)
    let id = c.file + " " + c.expr
    if ok == known.contains(id) {
      surprises.push(if ok { "passes now: " + id } else { "fails: " + id })
    }
  }
  assert_eq(surprises.join("\n"), "")
}
