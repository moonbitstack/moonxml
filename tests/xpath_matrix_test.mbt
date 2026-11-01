/// XPath 1.0, expression by expression.
///
/// `tests/xpath_css_test.mbt` pins a handful of representative queries; this
/// file walks the grammar instead: every axis, every node test, every operator
/// precedence level, and the whole core function library. Each case states the
/// result the specification requires, so a regression says which construct
/// broke rather than only that a query changed.

fn xp_doc() -> @moonxml.Document {
  try {
    @xml.loads(
      "<root xmlns:p=\"urn:p\"><a id=\"1\" class=\"x\">one</a><a id=\"2\" class=\"y\">two</a><b><c>3</c><c>4</c></b><!--note--><?pi data?><e/><p:q>seven</p:q></root>",
    )
  } catch {
    _ => abort("the fixture document must parse")
  }
}

fn xp_len(doc : @moonxml.Document, q : String) -> Int32 {
  try {
    doc.xpath(q).length()
  } catch {
    _ => abort("query must parse: " + q)
  }
}

fn xp_txt(doc : @moonxml.Document, q : String) -> String {
  try {
    doc.xpath(q).text()
  } catch {
    _ => abort("query must parse: " + q)
  }
}

fn xp_sub(doc : @moonxml.Document, base : String, rel : String) -> Int32 {
  try {
    doc.xpath(base).xpath(rel).length()
  } catch {
    _ => abort("query must parse: " + base + " then " + rel)
  }
}

test "xpath: location paths, absolute and relative" {
  let doc = xp_doc()
  assert_eq(xp_len(doc, "/root"), 1)
  assert_eq(xp_len(doc, "/root/a"), 2)
  assert_eq(xp_len(doc, "/root/b/c"), 2)
  // `//` is `/descendant-or-self::node()/`.
  assert_eq(xp_len(doc, "//c"), 2)
  assert_eq(xp_len(doc, "//b//c"), 2)
  assert_eq(xp_len(doc, "//root//e"), 1)
  assert_eq(xp_txt(doc, "/root/b/c[2]"), "4")
  // A relative path is evaluated from the context node.
  assert_eq(xp_sub(doc, "/root", "b/c"), 2)
  assert_eq(xp_len(doc, "//missing"), 0)
}

test "xpath: child axis and node tests" {
  let doc = xp_doc()
  assert_eq(xp_len(doc, "/root/child::a"), 2)
  assert_eq(xp_len(doc, "/root/*"), 5)
  // `node()` counts text and comment nodes too; this document has no
  // whitespace between the children, so only the named nodes appear.
  assert_eq(xp_len(doc, "/root/node()"), 7)
  assert_eq(xp_len(doc, "//text()"), 5)
  assert_eq(xp_len(doc, "//comment()"), 1)
  assert_eq(xp_txt(doc, "//comment()"), "note")
  assert_eq(xp_len(doc, "//processing-instruction()"), 1)
  assert_eq(xp_len(doc, "//processing-instruction(\"pi\")"), 1)
  assert_eq(xp_len(doc, "//processing-instruction(\"other\")"), 0)
  // `//self::root` is `/descendant-or-self::node()/self::root`, so it finds the
  // document element; `/self::root` from the root node finds nothing.
  assert_eq(xp_len(doc, "//self::root"), 1)
  assert_eq(xp_len(doc, "/root/self::root"), 1)
}

test "xpath: the thirteen axes" {
  let doc = xp_doc()
  assert_eq(xp_len(doc, "//c[1]/parent::b"), 1)
  assert_eq(xp_len(doc, "//c[1]/ancestor::*"), 2)
  assert_eq(xp_len(doc, "//c[1]/ancestor-or-self::*"), 3)
  assert_eq(xp_len(doc, "//c[1]/descendant::*"), 0)
  assert_eq(xp_len(doc, "//b/descendant::*"), 2)
  assert_eq(xp_len(doc, "//b/descendant-or-self::*"), 3)
  assert_eq(xp_len(doc, "//a[1]/following-sibling::*"), 4)
  assert_eq(xp_len(doc, "//a[2]/preceding-sibling::*"), 1)
  // `following` skips the subtree of the context node; `preceding` mirrors it.
  assert_eq(xp_len(doc, "//a[1]/following::c"), 2)
  assert_eq(xp_len(doc, "//c[2]/preceding::a"), 2)
  assert_eq(xp_len(doc, "//a[1]/attribute::id"), 1)
  assert_eq(xp_txt(doc, "//a/@id"), "12")
  assert_eq(xp_txt(doc, "//a[2]/@class"), "y")
  // The namespace axis is not materialised by this tree model.
  assert_eq(xp_len(doc, "//a[1]/namespace::*"), 0)
}

test "xpath: predicates" {
  let doc = xp_doc()
  // A numeric predicate selects by position, in document order.
  assert_eq(xp_txt(doc, "//a[1]"), "one")
  assert_eq(xp_txt(doc, "//a[2]"), "two")
  assert_eq(xp_txt(doc, "//a[last()]"), "two")
  assert_eq(xp_len(doc, "//a[position() < 2]"), 1)
  assert_eq(xp_len(doc, "//a[position() = last()]"), 1)
  assert_eq(xp_len(doc, "//c[position() mod 2 = 0]"), 1)
  // Predicates chain, each applied to the result of the previous one.
  assert_eq(xp_txt(doc, "//a[@class][2]"), "two")
  assert_eq(xp_len(doc, "//a[@id=\"1\" or @id=\"2\"]"), 2)
  assert_eq(xp_len(doc, "//a[@id and @class]"), 2)
  assert_eq(xp_txt(doc, "//*[self::b]/c[1]"), "3")
  assert_eq(xp_len(doc, "//b[c = 4]"), 1)
  assert_eq(xp_len(doc, "//b[c > 3]"), 1)
  assert_eq(xp_len(doc, "//b[not(c = 5)]"), 1)
}

test "xpath: operators and precedence" {
  let doc = xp_doc()
  // Multiplicative binds tighter than additive, additive than relational.
  assert_eq(xp_txt(doc, "1 + 2 * 3"), "7")
  assert_eq(xp_txt(doc, "(1 + 2) * 3"), "9")
  assert_eq(xp_txt(doc, "7 div 2"), "3.5")
  assert_eq(xp_txt(doc, "7 mod 2"), "1")
  assert_eq(xp_txt(doc, "-3 + 1"), "-2")
  assert_eq(xp_txt(doc, "1 < 2"), "true")
  assert_eq(xp_txt(doc, "1 <= 1"), "true")
  assert_eq(xp_txt(doc, "2 > 3"), "false")
  assert_eq(xp_txt(doc, "2 >= 2"), "true")
  assert_eq(xp_txt(doc, "1 = 1 and 2 = 2"), "true")
  assert_eq(xp_txt(doc, "1 = 2 or 2 = 2"), "true")
  assert_eq(xp_txt(doc, "not(1 = 2)"), "true")
  // A node-set compared with a number compares its string values.
  assert_eq(xp_txt(doc, "//c = 4"), "true")
  assert_eq(xp_txt(doc, "//c != 4"), "true")
  assert_eq(xp_txt(doc, "//c < 4"), "true")
  // A node-set in a boolean context tests for emptiness.
  assert_eq(xp_txt(doc, "//a and //b"), "true")
  assert_eq(xp_txt(doc, "//missing or //a"), "true")
  // Union keeps document order and drops duplicates.
  assert_eq(xp_len(doc, "//a | //a"), 2)
  assert_eq(xp_txt(doc, "//c | //a"), "onetwo34")
}

test "xpath: node-set functions" {
  let doc = xp_doc()
  assert_eq(xp_txt(doc, "count(//a)"), "2")
  assert_eq(xp_txt(doc, "count(//*)"), "8")
  assert_eq(xp_txt(doc, "sum(//c)"), "7")
  assert_eq(xp_txt(doc, "sum(//missing)"), "0")
  assert_eq(xp_txt(doc, "count(id(\"1\"))"), "1")
  assert_eq(xp_txt(doc, "name(//c[1])"), "c")
  assert_eq(xp_txt(doc, "local-name(//c[1])"), "c")
  assert_eq(xp_txt(doc, "local-name(//*[local-name()=\"q\"])"), "q")
  assert_eq(xp_txt(doc, "local-name(//a[1]/@id)"), "id")
  assert_eq(xp_txt(doc, "name(//a[1]/@id)"), "id")
}

test "xpath: string functions" {
  let doc = xp_doc()
  assert_eq(xp_txt(doc, "string(123)"), "123")
  assert_eq(xp_txt(doc, "string(true())"), "true")
  assert_eq(xp_txt(doc, "concat(\"a\", \"b\", \"c\")"), "abc")
  assert_eq(xp_txt(doc, "starts-with(\"hello\", \"he\")"), "true")
  assert_eq(xp_txt(doc, "contains(\"hello\", \"ell\")"), "true")
  assert_eq(xp_txt(doc, "substring(\"12345\", 2, 3)"), "234")
  assert_eq(xp_txt(doc, "substring(\"12345\", 2)"), "2345")
  // Rounding of the start position follows the specification: it rounds up.
  assert_eq(xp_txt(doc, "substring(\"12345\", 1.5, 2.6)"), "234")
  assert_eq(xp_txt(doc, "substring-before(\"1999/04\", \"/\")"), "1999")
  assert_eq(xp_txt(doc, "substring-after(\"1999/04\", \"/\")"), "04")
  assert_eq(xp_txt(doc, "string-length(\"abc\")"), "3")
  // The query text contains a real tab, which normalize-space must collapse
  // together with the spaces.
  assert_eq(xp_txt(doc, "normalize-space(\"  a \t b  \")"), "a b")
  assert_eq(xp_txt(doc, "translate(\"bar\", \"abc\", \"ABC\")"), "BAr")
  // A character whose position is past the end of the third argument is
  // deleted; `b` and `a` are not, so only `c` would go.
  assert_eq(xp_txt(doc, "translate(\"abc\", \"abc\", \"AB\")"), "AB")
  assert_eq(xp_txt(doc, "string(//a[1])"), "one")
  assert_eq(xp_txt(doc, "string(//missing)"), "")
}

test "xpath: number functions" {
  let doc = xp_doc()
  assert_eq(xp_txt(doc, "number(\"12\")"), "12")
  assert_eq(xp_txt(doc, "number(\" 7 \")"), "7")
  assert_eq(xp_txt(doc, "number(true())"), "1")
  assert_eq(xp_txt(doc, "floor(2.9)"), "2")
  assert_eq(xp_txt(doc, "ceiling(2.1)"), "3")
  assert_eq(xp_txt(doc, "round(2.5)"), "3")
  assert_eq(xp_txt(doc, "round(-2.5)"), "-2")
  assert_eq(xp_txt(doc, "number(//c[1])"), "3")
  // NaN is written `NaN`, and comparing it is always false.
  assert_eq(xp_txt(doc, "number(\"x\")"), "NaN")
  assert_eq(xp_txt(doc, "number(\"x\") = number(\"x\")"), "false")
}

test "xpath: boolean functions" {
  let doc = xp_doc()
  assert_eq(xp_txt(doc, "true()"), "true")
  assert_eq(xp_txt(doc, "false()"), "false")
  assert_eq(xp_txt(doc, "boolean(1)"), "true")
  assert_eq(xp_txt(doc, "boolean(0)"), "false")
  assert_eq(xp_txt(doc, "boolean(\"\")"), "false")
  assert_eq(xp_txt(doc, "boolean(\"x\")"), "true")
  assert_eq(xp_txt(doc, "boolean(//missing)"), "false")
  assert_eq(xp_txt(doc, "not(false())"), "true")
  // `lang()` looks for an ancestor `xml:lang`; this tree has none.
  assert_eq(xp_txt(doc, "lang(\"en\")"), "false")
}

fn xp_ns(doc : @moonxml.Document, q : String) -> String {
  try {
    doc.xpath(q).items[0].as_element().unwrap().namespace_uri()
  } catch {
    _ => abort("query must parse: " + q)
  }
}

test "xpath: a bare name matches the local name, whatever the namespace" {
  let doc = xp_doc()
  assert_eq(xp_len(doc, "//q"), 1)
  assert_eq(xp_ns(doc, "//q"), "urn:p")
  // An unprefixed name matches an element in any namespace only when it is the
  // local name; `p:q` in the source is a Clark name in the tree.
  assert_eq(xp_txt(doc, "//q"), "seven")
}

test "xpath: whitespace between tokens is insignificant" {
  let doc = xp_doc()
  assert_eq(xp_len(doc, "  //a [ @id = \"1\" ]  "), 1)
  assert_eq(xp_txt(doc, "count ( //c )"), "2")
}

fn xp_value(doc : @moonxml.Document, q : String) -> @moonxml.XPathValue {
  try {
    doc.xpath_value(q)
  } catch {
    _ => abort("query must parse: " + q)
  }
}

test "xpath: value types" {
  let doc = xp_doc()
  match xp_value(doc, "//missing") {
    @moonxml.XPathValue::Nodes(s) => assert_eq(s.length(), 0)
    _ => abort("expected an empty node-set")
  }
  match xp_value(doc, "true()") {
    @moonxml.XPathValue::Flag(b) => assert_eq(b, true)
    _ => abort("expected a boolean")
  }
  match xp_value(doc, "1 div 0") {
    @moonxml.XPathValue::Num(d) => assert_eq(d > 1.0e308, true)
    _ => abort("expected a number")
  }
}
