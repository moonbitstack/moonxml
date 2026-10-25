// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The tree's shape and the editing verbs, each tested on both sides:
/// applied, and the tree still consistent afterwards.
fn sample() -> Document {
  let doc = Document::new(flavour=Html)
  let html = Element::new("html")
  let head = Element::new("head")
  let body = Element::new("body")
  let main = Element::new("div", attrs=[("id", "main"), ("class", "wrap box")])
  let first = Element::new("p", childrens=[TextNode("one")])
  let second = Element::new("p", childrens=[TextNode("two")])
  let span = Element::new("span", attrs=[("class", "tag")], childrens=[
    TextNode("x"),
  ])
  let tail = Element::new("p", childrens=[
    CommentNode("note"),
    TextNode("three"),
  ])
  doc.root.append(ElementNode(html))
  html.append(ElementNode(head))
  html.append(ElementNode(body))
  body.append(ElementNode(main))
  main.append(ElementNode(first))
  main.append(ElementNode(second))
  main.append(ElementNode(span))
  main.append(ElementNode(tail))
  doc
}

///|
/// The one element a selection holds, for tests that know their data.
fn only(sel : Selection) -> Element {
  match sel.items[0] {
    ElementNode(data) => data
    _ => Element::new("")
  }
}

///|
fn parent_name(el : Element) -> String {
  match el.parent {
    Some(above) => above.name
    None => ""
  }
}

///|
test "a fresh element claims the parentage of its children" {
  let inner = Element::new("b")
  let outer = Element::new("p", childrens=[ElementNode(inner)])
  assert_eq(parent_name(inner), "p")
  assert_eq(outer.childrens.length(), 1)
}

///|
test "the constructor detaches a child that already sits in a tree" {
  let doc = sample()
  let moved = only(doc.by_id("main"))
  let other = Element::new("div", childrens=[ElementNode(moved)])
  assert_eq(other.childrens.length(), 1)
  assert_eq(doc.root.childrens.length(), 1)
}

///|
test "append keeps the parent pointer" {
  let doc = sample()
  let main = only(doc.by_id("main"))
  let late = Element::new("em")
  main.append(ElementNode(late))
  assert_eq(main.childrens.length(), 5)
  assert_eq(parent_name(late), "div")
}

///|
test "a node has one parent: appending moves it" {
  let doc = sample()
  let main = only(doc.by_id("main"))
  let body = only(doc.by_tag("body"))
  let span = only(doc.by_tag("span"))
  body.append(ElementNode(span))
  assert_eq(body.childrens.length(), 2)
  assert_eq(main.childrens.length(), 3)
  assert_eq(parent_name(span), "body")
}

///|
test "insert clamps out of range" {
  let el = Element::new("p")
  el.insert(9, TextNode("a"))
  el.insert(-3, TextNode("b"))
  assert_eq(el.childrens.length(), 2)
  assert_eq(el.childrens[0].text(), "b")
}

///|
test "remove detaches and answers" {
  let doc = sample()
  let main = only(doc.by_id("main"))
  let span = only(doc.by_tag("span"))
  assert_eq(span.remove(), true)
  assert_eq(main.childrens.length(), 3)
  assert_eq(span.parent is None, true)
  assert_eq(span.remove(), false)
}

///|
test "replace_with takes the old node's place" {
  let doc = sample()
  let main = only(doc.by_id("main"))
  let first = only(doc.css("p"))
  let fresh = Element::new("h2")
  assert_eq(first.replace_with(ElementNode(fresh)), true)
  assert_eq(main.childrens[0].name(), "h2")
  assert_eq(parent_name(fresh), "div")
}

///|
test "unwrap lifts the children into the parent's place" {
  let doc = sample()
  let main = only(doc.by_id("main"))
  let wrap = Element::new("section", childrens=[TextNode("kept")])
  main.append(ElementNode(wrap))
  assert_eq(wrap.unwrap(), true)
  assert_eq(main.childrens.length(), 5)
  assert_eq(main.childrens[4].text(), "kept")
  assert_eq(wrap.parent is None, true)
  assert_eq(wrap.childrens.length(), 0)
}

///|
test "wrap puts the element inside a fresh one" {
  let doc = sample()
  let main = only(doc.by_id("main"))
  let span = only(doc.by_tag("span"))
  let wrapper = span.wrap("a").unwrap()
  assert_eq(wrapper.name, "a")
  assert_eq(parent_name(wrapper), "div")
  assert_eq(parent_name(span), "a")
  assert_eq(main.childrens[2].name(), "a")
}

///|
test "insert_before and insert_after place among siblings" {
  let doc = sample()
  let main = only(doc.by_id("main"))
  let span = only(doc.by_tag("span"))
  let before = Element::new("i")
  let after = Element::new("u")
  assert_eq(span.insert_before(ElementNode(before)), true)
  assert_eq(span.insert_after(ElementNode(after)), true)
  assert_eq(main.childrens[2].name(), "i")
  assert_eq(main.childrens[4].name(), "u")
}

///|
test "smooth fuses adjacent text and leaves CDATA alone" {
  let el = Element::new("p", childrens=[
    TextNode("a"),
    TextNode("b"),
    CDataNode("<c>"),
    TextNode("d"),
    TextNode("e"),
  ])
  el.smooth()
  assert_eq(el.childrens.length(), 3)
  assert_eq(el.childrens[0].text(), "ab")
  assert_eq(el.childrens[2].text(), "de")
}

///|
test "attributes keep their order and their place" {
  let el = Element::new("a", attrs=[("href", "/x"), ("rel", "nofollow")])
  assert_eq(el.attr("rel"), Some("nofollow"))
  el.set_attr("href", "/y")
  assert_eq(el.attrs.length(), 2)
  assert_eq(el.attrs[0].0, "href")
  assert_eq(el.remove_attr("rel"), true)
  assert_eq(el.remove_attr("rel"), false)
  assert_eq(el.attrs.length(), 1)
}

///|
test "classes add and remove without surprise" {
  let el = Element::new("p", attrs=[("class", "a b")])
  assert_eq(el.classes(), ["a", "b"])
  assert_eq(el.has_class("b"), true)
  el.add_class("c")
  el.add_class("a")
  assert_eq(el.attr("class"), Some("a b c"))
  el.remove_class("b")
  assert_eq(el.attr("class"), Some("a c"))
  el.remove_class("a")
  el.remove_class("c")
  assert_eq(el.attr("class"), Some(""))
}

///|
test "text content is the DOM's textContent" {
  let doc = sample()
  let main = only(doc.by_id("main"))
  assert_eq(main.text(), "onetwoxthree")
}

///|
test "walk is pre-order" {
  let doc = sample()
  let names : Array[String] = []
  only(doc.by_id("main")).walk(fn(node) {
    if node is ElementNode(data) {
      names.push(data.name)
    }
  })
  assert_eq(names, ["p", "p", "span", "p"])
}

///|
test "document walks up to the virtual root" {
  let doc = sample()
  let span = only(doc.by_tag("span"))
  match span.document() {
    Some(home) => assert_eq(home.root.childrens.length(), 1)
    None => assert_eq(true, false)
  }
  let loose = Element::new("div")
  assert_eq(loose.document() is None, true)
  assert_eq(only(doc.by_tag("html")).name, "html")
}

///|
test "the document element is the root's first element child" {
  let doc = Document::new()
  doc.root.append(CommentNode("hi"))
  doc.root.append(ElementNode(Element::new("rss")))
  match doc.document_element() {
    Some(root) => assert_eq(root.name, "rss")
    None => assert_eq(true, false)
  }
}

///|
test "repairs start empty and are answerable" {
  let doc = sample()
  assert_eq(doc.repairs().any(), false)
  assert_eq(doc.repairs().total(), 0)
}

///|
test "the flavour decides how a document writes back" {
  let doc = sample()
  assert_eq(doc.flavour(), Html)
  assert_eq(Document::new().flavour(), Xml)
}
