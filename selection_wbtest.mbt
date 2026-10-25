// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The chain: heterogeneous narrowing, the registry, the caller's own
/// selector, and the node-level forms that keep a chain from stopping.
fn doc() -> Document {
  let page = Document::new(flavour=Html)
  let html = Element::new("html")
  let body = Element::new("body")
  let nav = Element::new("ul", attrs=[("id", "nav")])
  let one = Element::new("li")
  let link = Element::new("a", attrs=[("href", "https://example.com/a")])
  let two = Element::new("li")
  let inner = Element::new("a", attrs=[("href", "/local")])
  let span = Element::new("span", childrens=[TextNode("deep")])
  let form = Element::new("form")
  let field = Element::new("input", attrs=[("name", "q")])
  page.root.append(ElementNode(html))
  html.append(ElementNode(body))
  body.append(ElementNode(nav))
  nav.append(ElementNode(one))
  one.append(ElementNode(link))
  nav.append(ElementNode(two))
  two.append(ElementNode(inner))
  inner.append(ElementNode(span))
  body.append(ElementNode(form))
  form.append(ElementNode(field))
  page
}

///|
/// A caller's own selector, the closure shape: the links whose href leaves
/// the site.
fn deep_links(ctx : Selection, _query : String) -> Selection raise Refused {
  ctx
  .css("a[href]")
  .filter(fn(node) {
    match node {
      ElementNode(data) =>
        match data.attr("href") {
          Some(href) => href.has_prefix("https://")
          None => false
        }
      _ => false
    }
  })
}

///|
/// A caller's own selector with configuration of its own.
struct MinLinks {
  floor : Int32
}

///|
fn MinLinks::new(floor : Int32) -> MinLinks {
  { floor, }
}

///|
impl Selector for MinLinks with fn select(
  self,
  ctx : Selection,
  _query : String,
) -> Selection raise Refused {
  ctx
  .css("a")
  .filter(fn(node) {
    match node {
      ElementNode(data) =>
        match data.attr("href") {
          Some(href) => href.length() > self.floor
          None => false
        }
      _ => false
    }
  })
}

///|
test "css narrows, then xpath-shaped narrowing would follow" {
  let page = doc()
  assert_eq(page.css("ul").length(), 1)
  assert_eq(page.css("ul li").length(), 2)
  assert_eq(page.css("ul").css("li").length(), 2)
  assert_eq(page.css("body").css("a").length(), 2)
}

///|
test "the chain the library exists for" {
  let page = doc()
  let sel = page.css("#nav").css("li").items[1].childrens()[0].css("span")
  assert_eq(sel.length(), 1)
  assert_eq(sel.text(), "deep")
}

///|
test "by_id, by_class, by_tag and by_name" {
  let page = doc()
  assert_eq(page.by_id("nav").length(), 1)
  assert_eq(page.by_tag("li").length(), 2)
  assert_eq(page.by_tag("*").length(), 10)
  assert_eq(page.by_name("q").length(), 1)
  assert_eq(page.by_class("none").length(), 0)
  assert_eq(page.by_id("nav").by_tag("a").length(), 2)
}

///|
test "selector dispatches by registered name" {
  let page = doc()
  assert_eq(page.selector("css", "a").length(), 2)
  assert_eq(page.selector("tag", "li").length(), 2)
  assert_eq(page.selector("id", "nav").length(), 1)
  let missed = try {
    ignore(page.selector("nope", "x"))
    false
  } catch {
    _ => true
  }
  assert_eq(missed, true)
}

///|
test "a registered selector replaces, and the method still works" {
  let page = doc()
  page.register("outer", SelectorFn::new(deep_links))
  assert_eq(page.selector("outer", "").length(), 1)
  page.register("css", SelectorFn::new(deep_links))
  assert_eq(page.selector("css", "").length(), 1)
  assert_eq(page.css("a").length(), 2)
}

///|
test "custom runs a selector that was never registered" {
  let page = doc()
  assert_eq(page.custom(SelectorFn::new(deep_links)).length(), 1)
  // a custom selector searches the context's descendants, like css does
  assert_eq(page.css("a").custom(SelectorFn::new(deep_links)).length(), 0)
  assert_eq(page.css("body").custom(SelectorFn::new(deep_links)).length(), 1)
  assert_eq(page.css("form").custom(SelectorFn::new(deep_links)).length(), 0)
}

///|
test "a selector with configuration of its own" {
  let page = doc()
  page.register("long", MinLinks::new(10))
  assert_eq(page.selector("long", "").length(), 1)
  assert_eq(
    page.selector("long", "").attr("href"),
    Some("https://example.com/a"),
  )
}

///|
test "filter, first, last and eq" {
  let page = doc()
  assert_eq(
    page.by_tag("li").filter(fn(node) { node is ElementNode(_) }).length(),
    2,
  )
  assert_eq(page.by_tag("a").first().length(), 1)
  assert_eq(
    page.by_tag("a").first().attr("href"),
    Some("https://example.com/a"),
  )
  assert_eq(page.by_tag("a").last().attr("href"), Some("/local"))
  assert_eq(page.by_tag("a").eq(1).attr("href"), Some("/local"))
  assert_eq(page.by_tag("a").eq(-1).attr("href"), Some("/local"))
  assert_eq(page.by_tag("a").eq(9).length(), 0)
  assert_eq(page.by_tag("li").eq(0).text(), "")
}

///|
test "childrens, parent and descendants" {
  let page = doc()
  let li = page.by_tag("li")
  assert_eq(li.length(), 2)
  assert_eq(li.items[0].name(), "li")
  assert_eq(li.items[1].name(), "li")
  assert_eq(li.items[0].childrens().length(), 1)
  assert_eq(li.childrens().length(), 2)
  assert_eq(li.childrens().items[0].name(), "a")
  assert_eq(page.by_id("nav").parent().length(), 1)
  assert_eq(page.by_id("nav").parent().items[0].name(), "body")
  assert_eq(page.by_id("nav").descendants().length(), 6)
}

///|
test "closest walks up, self included" {
  let page = doc()
  assert_eq(page.css("span").closest("li").length(), 1)
  assert_eq(page.css("span").closest("li").attr("href") is None, true)
  assert_eq(page.css("span").closest("a").length(), 1)
  assert_eq(page.css("span").closest("body").length(), 1)
  assert_eq(page.css("span").closest("table").length(), 0)
}

///|
test "text, html and attr read the selection" {
  let page = doc()
  assert_eq(page.by_id("nav").text(), "deep")
  assert_eq(page.by_tag("li").text(), "deep")
  assert_eq(page.css("a").length(), 2)
  assert_eq(page.css("a").attr("href"), Some("https://example.com/a"))
  assert_eq(page.css("a[href=/local]").attr("href"), Some("/local"))
  assert_eq(
    page.by_id("nav").html(),
    "<li><a href=\"https://example.com/a\"></a></li><li><a href=\"/local\"><span>deep</span></a></li>",
  )
  assert_eq(page.css("form").html(), "<input name=\"q\">")
}

///|
test "editing verbs apply to every selected element" {
  let page = doc()
  page.by_tag("a").set_attr("rel", "nofollow")
  assert_eq(page.css("a[rel=nofollow]").length(), 2)
  page.by_tag("a").add_class("external")
  assert_eq(page.by_class("external").length(), 2)
  page.by_tag("a").remove_class("external")
  assert_eq(page.by_class("external").length(), 0)
  page.by_tag("li").set_text("gone")
  assert_eq(page.by_id("nav").text(), "gonegone")
  page.by_tag("span").remove()
  assert_eq(page.by_tag("span").length(), 0)
  assert_eq(page.by_id("nav").text(), "gonegone")
}

///|
test "append and prepend on a selection" {
  let page = doc()
  page.by_id("nav").append(TextNode("!"))
  page.by_tag("form").prepend(ElementNode(Element::new("label")))
  assert_eq(page.by_id("nav").text(), "deep!")
  assert_eq(page.by_tag("label").length(), 1)
  assert_eq(page.by_tag("form").childrens().length(), 2)
}

///|
test "wrap and unwrap through a selection" {
  let page = doc()
  page.by_tag("span").wrap("em")
  assert_eq(page.by_tag("em").length(), 1)
  assert_eq(page.by_tag("span").length(), 1)
  page.by_tag("em").unwrap()
  assert_eq(page.by_tag("em").length(), 0)
  assert_eq(page.by_tag("span").length(), 1)
}

///|
test "a node keeps the chain going" {
  let page = doc()
  let li = page.by_tag("li").items[1]
  assert_eq(li.css("a").length(), 1)
  assert_eq(li.by_tag("span").length(), 1)
  assert_eq(li.childrens()[0].css("span").text(), "deep")
  assert_eq(li.closest("ul").length(), 1)
  assert_eq(li.selector("tag", "span").length(), 1)
  let text = page.css("span").items[0]
  assert_eq(text.css("a").length(), 0)
}

///|
test "a text node answers an empty selection" {
  let page = doc()
  let node = page.css("span").descendants().items[0]
  assert_eq(node.is_text(), true)
  assert_eq(node.css("a").length(), 0)
  assert_eq(node.by_tag("li").length(), 0)
}

///|
test "the document itself is a context" {
  let page = doc()
  assert_eq(page.css("html").length(), 1)
  assert_eq(page.css("a").length(), 2)
  assert_eq(page.length(), 1)
  assert_eq(page.descendants().length(), 11)
}

///|
test "a selection can be indexed" {
  let page = doc()
  assert_eq(page.by_tag("li").length(), 2)
  assert_eq(page.by_tag("li")[1].name(), "li")
  // out of range is a detached empty element, not a panic
  assert_eq(page.by_tag("li")[9].name(), "")
}
