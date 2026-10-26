// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The surface a caller can reach but the feature tests never touch: the byte
// writers, the namespace helpers, the error and flavour pretty-printing, and
// the few verbs the editing tests did not need. Everything public is named
// here at least once.

///|
test "names: the Clark spelling and its two halves" {
  assert_eq(local_of("{urn:a}entry"), "entry")
  assert_eq(local_of("entry"), "entry")
  assert_eq(namespace_of("{urn:a}entry"), Some("urn:a"))
  assert_eq(namespace_of("entry"), None)
  // a brace that never closes is just a name
  assert_eq(namespace_of("{urn:a"), None)
  assert_eq(local_of("{urn:a"), "{urn:a")
}

///|
test "the byte writers answer the same text as the string writers" {
  let doc = Document::new(flavour=Html)
  let p = Element::new("p", childrens=[TextNode("a & b")])
  doc.root.append(ElementNode(p))
  assert_eq(dumps(ElementNode(p)), "<p>a &amp; b</p>")
  assert_eq(dumps_html(ElementNode(p)), "<p>a &amp; b</p>")
  assert_eq(dump(ElementNode(p)), @utf8.encode(dumps(ElementNode(p))))
  assert_eq(dump_html(ElementNode(p)), @utf8.encode(dumps_html(ElementNode(p))))
  assert_eq(doc.dumps(), "<p>a &amp; b</p>")
  assert_eq(doc.dumps_html(), "<p>a &amp; b</p>")
  assert_eq(doc.dump(), @utf8.encode(doc.dumps()))
  assert_eq(doc.dump_html(), @utf8.encode(doc.dumps_html()))
}

///|
test "clearing empties what it is called on and nothing else" {
  let doc = Document::new(flavour=Html)
  let parent = Element::new("div", childrens=[TextNode("x")])
  let kept = Element::new("span", childrens=[TextNode("y")])
  doc.root.append(ElementNode(parent))
  doc.root.append(ElementNode(kept))
  parent.clear()
  assert_eq(parent.childrens.length(), 0)
  assert_eq(kept.text(), "y")
  doc.clear()
  assert_eq(doc.root.childrens.length(), 0)
}

///|
test "a selection's clear reaches every matched node" {
  let doc = Document::new(flavour=Html)
  let first = Element::new("a", childrens=[TextNode("x")])
  let second = Element::new("b", childrens=[TextNode("y")])
  doc.root.append(ElementNode(first))
  doc.root.append(ElementNode(second))
  doc.css("*").clear()
  assert_eq(first.childrens.length(), 0)
  assert_eq(second.childrens.length(), 0)
}

///|
test "attributes: present, absent, and the class list" {
  let el = Element::new("a", attrs=[("href", "/x"), ("class", "one two")])
  assert_eq(el.has_attr("href"), true)
  assert_eq(el.has_attr("title"), false)
  assert_eq(el.classes(), ["one", "two"])
  el.remove_class("one")
  assert_eq(el.classes(), ["two"])
  assert_eq(el.has_attr("class"), true)
}

///|
test "a node knows whether it is an element" {
  let el = Element::new("p")
  assert_eq(ElementNode(el).is_element(), true)
  assert_eq(TextNode("x").is_element(), false)
  assert_eq(ElementNode(el).is_text(), false)
  assert_eq(TextNode("x").is_text(), true)
}

///|
test "the error prints what it knows" {
  let bad = Malformed(at=7, why="an unterminated tag")
  assert_eq(bad.to_string(), "malformed at 7: an unterminated tag")
  assert_eq(
    BadQuery(at=2, why="an empty selector").to_string(),
    "bad query at 2: an empty selector",
  )
  assert_eq(
    UnknownSelector(name="mine").to_string(),
    "no selector registered as mine",
  )
  assert_eq(
    Unsupported(what="a variable").to_string(),
    "unsupported: a variable",
  )
  // and compares by value, which is what a test wants to do
  assert_eq(Malformed(at=1, why="x") == Malformed(at=1, why="x"), true)
  assert_eq(Malformed(at=1, why="x") == Malformed(at=2, why="x"), false)
}

///|
test "a flavour prints and compares" {
  assert_eq(Xml.to_string(), "xml")
  assert_eq(Html.to_string(), "html")
  assert_eq(Xml == Xml, true)
  assert_eq(Xml == Html, false)
}

///|
test "repairs: their sum, and whether anything happened" {
  let none = Repairs::new()
  assert_eq(none.total(), 0)
  assert_eq(none.any(), false)
  let some = Repairs::new()
  some.implied = 2
  some.closed_at_eof = 1
  assert_eq(some.total(), 3)
  assert_eq(some.any(), true)
  let doc = Document::new(flavour=Html)
  doc.set_repairs(some)
  assert_eq(doc.repairs().total(), 3)
}

///|
test "an xpath value prints as the thing it is" {
  let doc = Document::new(flavour=Html)
  doc.root.append(ElementNode(Element::new("p", childrens=[TextNode("x")])))
  assert_eq(doc.xpath_value("count(//p)").to_string(), "1")
  assert_eq(doc.xpath_value("//p = 'x'").to_string(), "true")
  assert_eq(doc.xpath_value("'text'").to_string(), "text")
  assert_eq(doc.xpath_value("//p").to_string(), "1 nodes")
}

///|
test "the derived trait members work when called directly" {
  // `==` and `to_string` go through these; naming them keeps the interface
  // honest about what it promises.
  assert_eq(Xml.equal(Xml), true)
  assert_eq(Xml.not_equal(Html), true)
  let bad = Malformed(at=3, why="x")
  assert_eq(bad.equal(Malformed(at=3, why="x")), true)
  assert_eq(bad.not_equal(Malformed(at=4, why="x")), true)
}
