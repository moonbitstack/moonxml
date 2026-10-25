// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A page to select against: three lists, nested boxes, a table, a form.
fn page() -> Document {
  let doc = Document::new(flavor=Html)
  let html = Element::new("html")
  let body = Element::new("body")
  let nav = Element::new("ul", attrs=[("id", "nav"), ("class", "menu wide")])
  let one = Element::new("li", attrs=[("class", "item first")])
  let two = Element::new("li", attrs=[("class", "item")])
  let three = Element::new("li", attrs=[("class", "item last")])
  let box = Element::new("div", attrs=[("class", "box")])
  let inner = Element::new("p", attrs=[("class", "note"), ("data-x", "a b")])
  let deep = Element::new("span", attrs=[("class", "tag")])
  let table = Element::new("table")
  let row = Element::new("tr")
  let cell = Element::new("td", attrs=[("colspan", "2")])
  let form = Element::new("form")
  let input = Element::new("input", attrs=[
    ("type", "text"),
    ("name", "q"),
    ("required", ""),
  ])
  let link = Element::new("a", attrs=[("href", "https://example.com/x")])
  let mail = Element::new("a", attrs=[("href", "/local")])
  doc.root.append(ElementNode(html))
  html.append(ElementNode(body))
  body.append(ElementNode(nav))
  nav.append(ElementNode(one))
  nav.append(ElementNode(two))
  nav.append(ElementNode(three))
  body.append(ElementNode(box))
  box.append(ElementNode(inner))
  inner.append(ElementNode(deep))
  body.append(ElementNode(table))
  table.append(ElementNode(row))
  row.append(ElementNode(cell))
  body.append(ElementNode(form))
  form.append(ElementNode(input))
  form.append(ElementNode(link))
  form.append(ElementNode(mail))
  doc
}

///|
/// The names the selector answers, in document order.
fn hits(doc : Document, query : String) -> Array[String] raise Refused {
  let names : Array[String] = []
  for node in doc.css(query).items {
    if node is ElementNode(data) {
      names.push(data.name)
    }
  }
  names
}

///|
test "type, universal, id and class selectors" {
  let doc = page()
  assert_eq(hits(doc, "li"), ["li", "li", "li"])
  assert_eq(hits(doc, "*"), [
    "html", "body", "ul", "li", "li", "li", "div", "p", "span", "table", "tr", "td",
    "form", "input", "a", "a",
  ])
  assert_eq(hits(doc, "#nav"), ["ul"])
  assert_eq(hits(doc, ".item"), ["li", "li", "li"])
  assert_eq(hits(doc, "li.first"), ["li"])
  assert_eq(hits(doc, "ul.menu.wide"), ["ul"])
  assert_eq(hits(doc, "div#nav"), [])
}

///|
test "attribute selectors, every operator" {
  let doc = page()
  assert_eq(hits(doc, "[data-x]"), ["p"])
  assert_eq(hits(doc, "[data-x=a b]"), ["p"])
  assert_eq(hits(doc, "[data-x=\"a b\"]"), ["p"])
  assert_eq(hits(doc, "[data-x~=b]"), ["p"])
  assert_eq(hits(doc, "[data-x~=c]"), [])
  assert_eq(hits(doc, "[colspan=2]"), ["td"])
  assert_eq(hits(doc, "[href^=https]"), ["a"])
  assert_eq(hits(doc, "[href$=/x]"), ["a"])
  assert_eq(hits(doc, "[href*=example]"), ["a"])
  assert_eq(hits(doc, "[href|=https]"), [])
  assert_eq(hits(doc, "[required]"), ["input"])
  assert_eq(hits(doc, "[required=\"\"]"), ["input"])
}

///|
test "the case flag is ASCII and opt-in" {
  let doc = page()
  assert_eq(hits(doc, "[href^=HTTPS i]"), ["a"])
  assert_eq(hits(doc, "[href^=HTTPS]"), [])
  assert_eq(hits(doc, "[href^=https s]"), ["a"])
}

///|
test "combinators" {
  let doc = page()
  assert_eq(hits(doc, "ul li"), ["li", "li", "li"])
  assert_eq(hits(doc, "body > ul"), ["ul"])
  assert_eq(hits(doc, "li + li"), ["li", "li"])
  assert_eq(hits(doc, "li.first ~ li"), ["li", "li"])
  assert_eq(hits(doc, "div span"), ["span"])
  assert_eq(hits(doc, "div > span"), [])
  assert_eq(hits(doc, "table tr td"), ["td"])
  assert_eq(hits(doc, "html body table tr"), ["tr"])
}

///|
test "selector lists" {
  let doc = page()
  assert_eq(hits(doc, "table, form"), ["table", "form"])
  assert_eq(hits(doc, "span, a"), ["span", "a", "a"])
}

///|
test "structural pseudo-classes" {
  let doc = page()
  assert_eq(hits(doc, "li:first-child"), ["li"])
  assert_eq(hits(doc, "li:last-child"), ["li"])
  assert_eq(hits(doc, "li:nth-child(2)"), ["li"])
  assert_eq(hits(doc, "li:nth-child(odd)"), ["li", "li"])
  assert_eq(hits(doc, "li:nth-child(even)"), ["li"])
  assert_eq(hits(doc, "li:nth-child(2n)"), ["li"])
  assert_eq(hits(doc, "li:nth-child(-n+2)"), ["li", "li"])
  assert_eq(hits(doc, "li:nth-last-child(1)"), ["li"])
  assert_eq(hits(doc, "li:only-child"), [])
  assert_eq(hits(doc, "ul:only-of-type"), ["ul"])
  assert_eq(hits(doc, "li:first-of-type"), ["li"])
  assert_eq(hits(doc, "li:last-of-type"), ["li"])
  assert_eq(hits(doc, "span:empty"), ["span"])
  assert_eq(hits(doc, "p:empty"), [])
  assert_eq(hits(doc, "html:root"), ["html"])
  assert_eq(hits(doc, "body:root"), [])
}

///|
test "the logical pseudo-classes" {
  let doc = page()
  assert_eq(hits(doc, "li:not(.first)"), ["li", "li"])
  assert_eq(hits(doc, "li:is(.first, .last)"), ["li", "li"])
  assert_eq(hits(doc, "li:where(.last)"), ["li"])
  assert_eq(hits(doc, "p:has(span)"), ["p"])
  assert_eq(hits(doc, "div:has(> p)"), ["div"])
  assert_eq(hits(doc, "div:has(span)"), ["div"])
  assert_eq(hits(doc, "body:has(table tr td)"), ["body"])
  assert_eq(hits(doc, "form:has(+ form)"), [])
  assert_eq(hits(doc, "tr:has(+ tr)"), [])
  assert_eq(hits(doc, "td:has(~ td)"), [])
  assert_eq(hits(doc, "li:not(:has(a))"), ["li", "li", "li"])
  assert_eq(hits(doc, "a:not([href^=https])"), ["a"])
}

///|
test "the state pseudo-classes answer from their attribute" {
  let doc = page()
  assert_eq(hits(doc, "a:any-link"), ["a", "a"])
  assert_eq(hits(doc, "input:required"), ["input"])
  assert_eq(hits(doc, "input:optional"), [])
  assert_eq(hits(doc, "input:disabled"), [])
  assert_eq(hits(doc, "input:enabled"), ["input"])
}

///|
test "a dynamic pseudo-class is a parse error, not a silent miss" {
  let doc = page()
  let failed = try {
    ignore(hits(doc, "a:hover"))
    false
  } catch {
    _ => true
  }
  assert_eq(failed, true)
}

///|
test "a malformed selector names the fault" {
  let doc = page()
  let failed = try {
    ignore(hits(doc, "div..x"))
    false
  } catch {
    _ => true
  }
  assert_eq(failed, true)
}

///|
test "the context is never a candidate" {
  let doc = page()
  let ul = doc.css("#nav").items[0]
  assert_eq(ul.css("ul").length(), 0)
  assert_eq(ul.css("li").length(), 3)
  assert_eq(ul.css("*").length(), 3)
}

///|
test "namespaced names match by local part" {
  let doc = Document::new(flavor=Xml)
  let svg = Element::new("{http://www.w3.org/2000/svg}svg")
  let rect = Element::new("{http://www.w3.org/2000/svg}rect")
  svg.append(ElementNode(rect))
  doc.root.append(ElementNode(svg))
  assert_eq(hits(doc, "rect"), ["{http://www.w3.org/2000/svg}rect"])
  assert_eq(hits(doc, "svg|rect"), ["{http://www.w3.org/2000/svg}rect"])
  assert_eq(hits(doc, "{http://www.w3.org/2000/svg}svg"), [
    "{http://www.w3.org/2000/svg}svg",
  ])
  assert_eq(hits(doc, "svg"), ["{http://www.w3.org/2000/svg}svg"])
}

///|
test "the empty selection stays empty through a chain" {
  let doc = page()
  assert_eq(doc.css("table").css("a").length(), 0)
  assert_eq(doc.css("table").css("a").css("b").length(), 0)
  assert_eq(doc.css("nope").text(), "")
  assert_eq(doc.css("nope").first().length(), 0)
}
