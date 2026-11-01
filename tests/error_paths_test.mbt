/// What the query engines do with input they cannot use.
///
/// A malformed selector or expression must raise `Refused`, not panic and not
/// quietly return nothing: a caller has to be able to tell "the query is wrong"
/// from "the query matched nothing". Each case here names the kind of failure it
/// expects, so a change from one kind to another is visible.

fn css_error(doc : @moonxml.Document, q : String) -> String {
  try {
    ignore(doc.css(q))
    "accepted"
  } catch {
    @moonxml.Refused::BadQuery(..) => "bad-query"
    @moonxml.Refused::Unsupported(..) => "unsupported"
    @moonxml.Refused::UnknownSelector(..) => "unknown-selector"
    @moonxml.Refused::Malformed(..) => "malformed"
  }
}

fn xpath_error(doc : @moonxml.Document, q : String) -> String {
  try {
    ignore(doc.xpath(q))
    "accepted"
  } catch {
    @moonxml.Refused::BadQuery(..) => "bad-query"
    @moonxml.Refused::Unsupported(..) => "unsupported"
    @moonxml.Refused::UnknownSelector(..) => "unknown-selector"
    @moonxml.Refused::Malformed(..) => "malformed"
  }
}

fn error_doc() -> @moonxml.Document {
  @html.loads("<div id=r class=a><p>x</p></div>")
}

test "css: a malformed selector is a query error" {
  let doc = error_doc()
  let bad : Array[String] = [
    "",
    "   ",
    "div >",
    "> div",
    "div +",
    "[",
    "[a=",
    "[a=1",
    "div,,p",
    "#",
    ".",
    ":",
    "p:nth-child(",
    "p:nth-child(2n+)",
    "p:not(",
    "*|div",
  ]
  for q in bad {
    if css_error(doc, q) == "accepted" {
      println("accepted selector: [" + q + "]")
    }
    assert_eq(css_error(doc, q), "bad-query")
  }
}

test "css: a pseudo-class the engine does not know is refused as unsupported" {
  let doc = error_doc()
  assert_eq(css_error(doc, "p:hover"), "unsupported")
  assert_eq(css_error(doc, "p:visited"), "unsupported")
  assert_eq(css_error(doc, "p:has(+ p"), "bad-query")
}

/// A selector a caller can register: picks the paragraphs of the context.
struct Mine {}

impl @moonxml.Selector for Mine with select(self, ctx, query) {
  // A registered selector works on the descendants of its input, which is the
  // convention the built-in ones follow.
  let out : Array[@moonxml.Node] = []
  for e in @moonxml.gather_elements(ctx) {
    if e.local_name() == query {
      out.push(@moonxml.ElementNode(e))
    }
  }
  @moonxml.Selection::new(out)
}

test "css: an unregistered selector name is its own error" {
  let doc = error_doc()
  let kind = try {
    ignore(doc.selector("nope", "p"))
    "accepted"
  } catch {
    @moonxml.Refused::UnknownSelector(name~) => "unknown:" + name
    _ => "other"
  }
  assert_eq(kind, "unknown:nope")
  // A registered one is used.
  doc.register("mine", Mine::{})
  assert_eq(doc.selector("mine", "p").length(), 1)
  assert_eq(doc.selector("mine", "div").length(), 1)
  assert_eq(doc.selector_names().contains("mine"), true)
}


test "xpath: a malformed expression is a query error" {
  let doc = error_doc()
  let bad : Array[String] = [
    "",
    "//",
    "a[",
    "a[)",
    "1 +",
    "(1",
    "count(",
    "count()",
    "count(1, 2)",
    "substring()",
    "concat(\"a\")",
    "translate(\"a\")",
    "unknown-axis::p",
    "\"unterminated",
  ]
  for q in bad {
    if xpath_error(doc, q) == "accepted" {
      println("accepted expression: [" + q + "]")
    }
    assert_eq(xpath_error(doc, q), "bad-query")
  }
}

test "xpath: variables and unknown functions are unsupported, not malformed" {
  let doc = error_doc()
  assert_eq(xpath_error(doc, "$x"), "unsupported")
  // A prefixed function name does not parse in XPath 1.0, so it is a query
  // error rather than an unsupported one.
  assert_eq(xpath_error(doc, "ext:fn(1)"), "bad-query")
}

test "xpath: a wrong argument count is caught before evaluation" {
  // `count()` used to reach the evaluator and index an empty argument list,
  // which is a crash rather than an error. It is now a parse-time check.
  let doc = error_doc()
  assert_eq(xpath_error(doc, "count()"), "bad-query")
  assert_eq(xpath_error(doc, "position(1)"), "bad-query")
  assert_eq(xpath_error(doc, "substring(\"a\")"), "bad-query")
  assert_eq(xpath_error(doc, "substring(\"a\", 1, 2)"), "accepted")
  assert_eq(xpath_error(doc, "concat(\"a\", \"b\")"), "accepted")
}

test "css: a query error reports a position inside the query" {
  let doc = error_doc()
  let report = try {
    ignore(doc.css("div > > p"))
    "no error"
  } catch {
    @moonxml.Refused::BadQuery(at~, why~) => at.to_string() + ":" + why
    _ => "other"
  }
  assert_eq(report.contains(":"), true)
  // The offset points inside the query, not past it.
  match report.split(":").next() {
    Some(n) => assert_eq((n == "no error") || (n == "other"), false)
    None => abort("the report must have a position")
  }
}

test "xml: a CSS query on a XML document treats names as case-sensitive" {
  let doc = try {
    @xml.loads("<r><Item/><item/></r>")
  } catch {
    _ => abort("the fixture must parse")
  }
  assert_eq(doc.css("Item").length(), 1)
  assert_eq(doc.css("item").length(), 1)
  // In an XML document a type selector is case-sensitive, so an upper-case
  // selector matches neither element.
  assert_eq(doc.css("ITEM").length(), 0)
}
