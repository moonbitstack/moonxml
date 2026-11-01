/// Runs the vendored libxml2 XPath corpus and reports a pass rate.
///
/// The corpus pairs expressions with the value libxml2 produced: a boolean, a
/// number, a string, or a node-set described by its size and by the kind and
/// name of each top-level node. Numbers are compared to five significant digits
/// because libxml2 prints six, and a node-set is compared on its shape rather
/// than on libxml2's full serialisation of it.
///
/// The floor is a ratchet: raise it as the engine improves, never lower it. The
/// report separates "unsupported" (a construct this engine does not implement)
/// from "wrong answer", because those are different kinds of debt.
///
/// Fifteen cases are known not to pass, and they are not all the same thing:
///
/// - five use the namespace axis, which this tree does not keep (the parser
///   consumes `xmlns` declarations instead of storing them);
/// - two walk up from an attribute, which needs an owner pointer the synthetic
///   attribute node does not carry;
/// - six are in `mixedpat`, where libxml2 evaluates a relative path from the
///   document element; a standard XPath context node is the root node, and this
///   engine follows the standard;
/// - two compare `string()` of a huge number: libxml2 prints `1.2345e+19`, while
///   XPath 1.0 asks for the integer in decimal form, which is what this engine
///   prints.

enum XpActual {
  AFlag(Bool)
  ANum(Double)
  AStr(String)
  ANodes(Int, String)
  AFailed(String)
}

/// The preorder-stable description of a node-set that the corpus records:
/// the kind and name of each top-level node, joined with `|`.
fn xp_node_label(node : @moonxml.Node) -> String {
  match node {
    // The synthetic #document element is XPath's root node, which the corpus
    // writes as `/`.
    @moonxml.ElementNode(e) => if e.name == "#document" {
      "/"
    } else {
      "ELEMENT " + e.local_name()
    }
    @moonxml.TextNode(_) => "TEXT"
    @moonxml.CDataNode(_) => "CDATA"
    @moonxml.CommentNode(_) => "COMMENT"
    @moonxml.ProcessingInstructionNode(pi) => "PI " + pi.target
    @moonxml.AttributeNode(name, _) => "ATTRIBUTE " + xp_local(name)
    @moonxml.DoctypeNode(_) => "DOCTYPE"
  }
}

fn xp_local(name : String) -> String {
  let cs = name.to_array()
  let mut close = -1
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '}' {
      close = i
    }
    i = i + 1
  }
  if close < 0 {
    return name
  }
  let sb = StringBuilder()
  let mut k = close + 1
  while k < cs.length() {
    sb.write_char(cs[k])
    k = k + 1
  }
  sb.to_string()
}

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

fn xp_eval(doc : @moonxml.Document, expr : String) -> XpActual {
  let v = try {
    doc.xpath_value(expr)
  } catch {
    @moonxml.Refused::Unsupported(what~) => return AFailed("unsupported: " + what)
    @moonxml.Refused::BadQuery(why~, ..) => return AFailed("bad-query: " + why)
    @moonxml.Refused::Malformed(why~, ..) => return AFailed("malformed: " + why)
    @moonxml.Refused::UnknownSelector(name~) => return AFailed("unknown-selector: " + name)
  }
  match v {
    @moonxml.XPathValue::Flag(b) => AFlag(b)
    @moonxml.XPathValue::Num(d) => ANum(d)
    @moonxml.XPathValue::Str(s) => AStr(s)
    @moonxml.XPathValue::Nodes(sel) => ANodes(sel.length(), xp_join_labels(sel.items))
  }
}

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

fn xp_abs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

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
  let scale = if xp_abs(want) > 1.0 {
    xp_abs(want)
  } else {
    1.0
  }
  xp_abs(actual - want) / scale <= 5.0e-6
}

fn xp_matches(actual : XpActual, kind : String, value : String, nodes : String) -> Bool {
  match (actual, kind) {
    (AFailed(_), _) => false
    (AFlag(b), "bool") => (if b { "true" } else { "false" }) == value
    (ANum(d), "num") => xp_number_matches(d, value)
    (AStr(s), "str") => s == value
    (ANodes(n, labels), "nodes") => n.to_string() == value && labels == nodes
    _ => false
  }
}

test "libxml2 xpath conformance" {
  let docs = xpath_docs()
  let cases = xpath_cases()
  let parsed : Array[(@moonxml.Document, String)] = []
  for pair in docs {
    let (name, text) = pair
    let doc = try {
      @xml.loads(text)
    } catch {
      _ => abort("corpus document must parse: " + name)
    }
    parsed.push((doc, name))
  }
  // The expression-only files were evaluated by libxml2 with no document; an
  // empty root gives the same answers for everything they contain.
  let empty = try {
    @xml.loads("<r/>")
  } catch {
    _ => abort("the empty document must parse")
  }
  let mut pass = 0
  let mut shown = 0
  let mut unsupported = 0
  let mut wrong = 0
  let files : Array[String] = []
  let fpass : Array[Int] = []
  let ftotal : Array[Int] = []
  for c in cases {
    let mut doc = empty
    if c.doc != "" {
      for p in parsed {
        let (d, name) = p
        if name == c.doc {
          doc = d
        }
      }
    }
    let actual = xp_eval(doc, c.expr)
    let ok = xp_matches(actual, c.kind, c.value, c.nodes)
    if ok {
      pass = pass + 1
    } else {
      match actual {
        AFailed(_) => unsupported = unsupported + 1
        _ => wrong = wrong + 1
      }
      if shown < 5 {
        shown = shown + 1
        println("FAIL " + c.file + " expr=" + c.expr)
        println("  want " + c.kind + " " + c.value + " " + c.nodes)
        match actual {
          AFlag(b) => println("  got  bool " + b.to_string())
          ANum(d) => println("  got  num " + d.to_string())
          AStr(s) => println("  got  str " + s)
          ANodes(n, labels) => println("  got  nodes " + n.to_string() + " " + labels)
          AFailed(why) => println("  got  " + why)
        }
      }
    }
    // Per-file totals, in first-seen order.
    let mut idx = -1
    let mut i = 0
    while i < files.length() {
      if files[i] == c.file {
        idx = i
      }
      i = i + 1
    }
    if idx < 0 {
      files.push(c.file)
      fpass.push(if ok { 1 } else { 0 })
      ftotal.push(1)
    } else {
      ftotal[idx] = ftotal[idx] + 1
      if ok {
        fpass[idx] = fpass[idx] + 1
      }
    }
  }
  let total = cases.length()
  println(
    "libxml2 xpath: " +
    pass.to_string() +
    "/" +
    total.to_string() +
    " (unsupported " +
    unsupported.to_string() +
    ", wrong " +
    wrong.to_string() +
    ")",
  )
  let mut i = 0
  while i < files.length() {
    println("  " + files[i] + " " + fpass[i].to_string() + "/" + ftotal[i].to_string())
    i = i + 1
  }
  assert_eq(pass >= 311, true)
}
