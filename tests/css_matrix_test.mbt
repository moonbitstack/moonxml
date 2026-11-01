/// CSS selectors, construct by construct.
///
/// The point is coverage rather than a demonstration: every attribute operator,
/// every combinator, every structural pseudo-class, and the four functional
/// ones. A failure names the construct, which is what a selector engine needs
/// in order to be maintained.

fn css_doc() -> @moonxml.Document {
  @html.loads(
    "<div id=\"root\" class=\"box wide\" data-role=\"panel\"><p class=\"x\">1</p><p class=\"x y\" data-v=\"a1\">2</p><p>3</p><span></span><a href=\"https://example.com/a.html\" hreflang=\"en-US\">link</a><ul><li>a</li><li>b</li><li>c</li></ul></div>",
  )
}

fn css_n(doc : @moonxml.Document, q : String) -> Int32 {
  try {
    doc.css(q).length()
  } catch {
    _ => abort("selector must parse: " + q)
  }
}

fn css_t(doc : @moonxml.Document, q : String) -> String {
  try {
    doc.css(q).text()
  } catch {
    _ => abort("selector must parse: " + q)
  }
}

test "css: simple selectors" {
  let doc = css_doc()
  assert_eq(css_n(doc, "p"), 3)
  assert_eq(css_n(doc, "*") > 0, true)
  assert_eq(css_n(doc, "#root"), 1)
  assert_eq(css_n(doc, ".x"), 2)
  assert_eq(css_n(doc, ".x.y"), 1)
  assert_eq(css_n(doc, "p.x"), 2)
  assert_eq(css_n(doc, "p.y"), 1)
  assert_eq(css_n(doc, "div.box.wide"), 1)
  assert_eq(css_n(doc, "#root.box[data-role=\"panel\"]"), 1)
  assert_eq(css_n(doc, "p#root"), 0)
  // Class names are case-sensitive; tag names in a HTML tree are not.
  assert_eq(css_n(doc, ".X"), 0)
  assert_eq(css_n(doc, "P"), 3)
}

test "css: attribute operators" {
  let doc = css_doc()
  assert_eq(css_n(doc, "[data-role]"), 1)
  assert_eq(css_n(doc, "[data-role=\"panel\"]"), 1)
  assert_eq(css_n(doc, "[data-role='panel']"), 1)
  assert_eq(css_n(doc, "[data-role=\"other\"]"), 0)
  // `~=` is a word in a whitespace-separated list.
  assert_eq(css_n(doc, "[data-v~=\"a1\"]"), 1)
  assert_eq(css_n(doc, "[class~=\"y\"]"), 1)
  assert_eq(css_n(doc, "[class~=\"y z\"]"), 0)
  // `|=` matches the value or a value that starts with it plus a dash.
  assert_eq(css_n(doc, "[hreflang|=\"en\"]"), 1)
  assert_eq(css_n(doc, "[hreflang|=\"en-US\"]"), 1)
  assert_eq(css_n(doc, "[hreflang|=\"e\"]"), 0)
  assert_eq(css_n(doc, "[href^=\"https:\"]"), 1)
  assert_eq(css_n(doc, "[href$=\".html\"]"), 1)
  assert_eq(css_n(doc, "[href*=\"example\"]"), 1)
  assert_eq(css_n(doc, "[href^=\"http:\"]"), 0)
  // Whitespace around the operator and the value does not matter.
  assert_eq(css_n(doc, "[ data-role = \"panel\" ]"), 1)
}

test "css: combinators" {
  let doc = css_doc()
  assert_eq(css_n(doc, "div p"), 3)
  assert_eq(css_n(doc, "div > p"), 3)
  assert_eq(css_n(doc, "body p"), 3)
  assert_eq(css_n(doc, "ul > li"), 3)
  assert_eq(css_n(doc, "p + p"), 2)
  assert_eq(css_n(doc, "p + span"), 1)
  assert_eq(css_n(doc, "p ~ span"), 1)
  assert_eq(css_n(doc, "p ~ li"), 0)
  assert_eq(css_n(doc, "div > p + p.y"), 1)
  assert_eq(css_n(doc, "div p ~ ul"), 1)
  assert_eq(css_n(doc, "div > ul > li"), 3)
  // A child combinator does not match a grandchild.
  assert_eq(css_n(doc, "div > li"), 0)
}

test "css: structural pseudo-classes" {
  let doc = css_doc()
  assert_eq(css_t(doc, "p:first-child"), "1")
  assert_eq(css_t(doc, "p:last-child"), "")
  assert_eq(css_n(doc, "p:first-of-type"), 1)
  assert_eq(css_n(doc, "p:last-of-type"), 1)
  assert_eq(css_n(doc, "p:only-of-type"), 0)
  assert_eq(css_n(doc, "span:only-of-type"), 1)
  assert_eq(css_n(doc, "p:only-child"), 0)
  assert_eq(css_n(doc, "span:empty"), 1)
  assert_eq(css_n(doc, "p:empty"), 0)
  // `:root` is the document element, not the synthetic root node.
  assert_eq(css_n(doc, ":root"), 1)
  assert_eq(css_n(doc, ":root > body"), 1)
}

test "css: nth formulas" {
  let doc = css_doc()
  assert_eq(css_t(doc, "li:nth-child(1)"), "a")
  assert_eq(css_t(doc, "li:nth-child(2)"), "b")
  assert_eq(css_t(doc, "li:nth-child(odd)"), "ac")
  assert_eq(css_t(doc, "li:nth-child(even)"), "b")
  assert_eq(css_t(doc, "li:nth-child(2n+1)"), "ac")
  assert_eq(css_t(doc, "li:nth-child(3n)"), "c")
  assert_eq(css_t(doc, "li:nth-child(n+2)"), "bc")
  assert_eq(css_t(doc, "li:nth-last-child(1)"), "c")
  assert_eq(css_t(doc, "li:nth-last-child(2)"), "b")
  assert_eq(css_n(doc, "li:nth-of-type(2)"), 1)
  assert_eq(css_n(doc, "li:nth-last-of-type(1)"), 1)
  // `of S` filters the siblings the formula counts.
  assert_eq(css_n(doc, "p:nth-child(1 of .x)"), 1)
  assert_eq(css_n(doc, "p:nth-child(2 of .x)"), 1)
  assert_eq(css_n(doc, "p:nth-child(3 of .x)"), 0)
}

test "css: the functional pseudo-classes" {
  let doc = css_doc()
  assert_eq(css_n(doc, "p:not(.x)"), 1)
  assert_eq(css_n(doc, "p:not(.x):not(.y)"), 1)
  assert_eq(css_n(doc, ":is(p, span)"), 4)
  assert_eq(css_n(doc, ":where(li)"), 3)
  assert_eq(css_n(doc, "div:has(li)"), 1)
  assert_eq(css_n(doc, "div:has(> ul)"), 1)
  assert_eq(css_n(doc, "ul:has(> li)"), 1)
  assert_eq(css_n(doc, "p:has(li)"), 0)
  assert_eq(css_n(doc, "li:not(:first-child)"), 2)
  assert_eq(css_n(doc, "li:is(:first-child, :last-child)"), 2)
}

test "css: selector lists" {
  let doc = css_doc()
  assert_eq(css_n(doc, "p, span"), 4)
  assert_eq(css_n(doc, "p , li"), 6)
  assert_eq(css_n(doc, "p, p"), 3)
  assert_eq(css_n(doc, "#root, .x"), 3)
}

fn css_refused(sel : @moonxml.Selection, q : String) -> Bool {
  try {
    ignore(sel.css(q))
    false
  } catch {
    _ => true
  }
}

test "css: a selector can start from an element, not only from the document" {
  let doc = css_doc()
  let ul = doc.css("ul")
  assert_eq(ul.css("li").length(), 3)
  // A selector cannot begin with a combinator; that is a parse error, not an
  // empty result.
  assert_eq(css_refused(ul, "> li"), true)
  let div = doc.css("div")
  assert_eq(div.css("p.x").length(), 2)
  assert_eq(div.closest(".box").length(), 1)
}

test "css: namespaces match by local name unless written as a Clark name" {
  let doc = @xml.loads("<r xmlns:s=\"urn:s\"><s:circle r=\"1\"/><circle r=\"2\"/></r>") catch {
    _ => abort("the fixture document must parse")
  }
  assert_eq(doc.css("circle").length(), 2)
  assert_eq(doc.css("[r]").length(), 2)
  assert_eq(doc.css("*").length() > 0, true)
}

test "css: matches_one answers about a single element" {
  let doc = css_doc()
  let li = doc.css("li").items[1].as_element().unwrap()
  assert_eq(@moonxml.matches_one(li, "li:nth-child(2)"), true)
  assert_eq(@moonxml.matches_one(li, "li:nth-child(1)"), false)
  assert_eq(@moonxml.name_matches(li, "li"), true)
  assert_eq(@moonxml.name_matches(li, "ul"), false)
}
