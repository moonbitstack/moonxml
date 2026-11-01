test "chain narrows" {
  let doc = sample()
  assert_eq(doc.css("ul").css("li").length(), 3)
  assert_eq(doc.xpath("//ul").css("li").length(), 3)
  assert_eq(doc.css("li").xpath("@class").text(), "last")
  assert_eq(doc.selector("tag", "li").length(), 3)
}

test "by_ helpers" {
  let doc = sample()
  assert_eq(doc.by_id("a").length(), 1)
  assert_eq(doc.by_class("last").length(), 1)
  assert_eq(doc.by_tag("li").length(), 3)
  assert_eq(doc.by_tag("*").length(), 8)
}

test "traversal" {
  let doc = sample()
  assert_eq(doc.css("li").first().text(), "1")
  assert_eq(doc.css("li").last().text(), "3")
  assert_eq(doc.css("li").eq(1).text(), "2")
  assert_eq(doc.css("li").eq(-1).text(), "3")
  assert_eq(doc.css("li").parent().length(), 1)
  assert_eq(doc.css("ul").children().length(), 3)
  assert_eq(doc.css("div").descendants().length() > 0, true)
}

test "read" {
  let doc = sample()
  assert_eq(doc.css("div").text(), "123x")
  assert_eq(doc.css("ul").html(), "<li>1</li><li>2</li><li class=\"last\">3</li>")
  assert_eq(doc.css("div").attr("id"), Some("a"))
  assert_eq(doc.css("nope").html(), "")
  assert_eq(doc.css("nope").text(), "")
}

test "filter and closest" {
  let doc = sample()
  assert_eq(doc.css("li").filter(fn(n) { n.is_element() }).length(), 3)
  assert_eq(doc.css("li").closest("div").length(), 1)
  assert_eq(doc.css("li").closest("ul").length(), 1)
}

test "selection edit verbs" {
  let doc = sample()
  doc.css("li").set_attr("data-x", "1")
  assert_eq(doc.css("li").attr("data-x"), Some("1"))
  doc.css("li").add_class("row")
  assert_eq(doc.css("li.row").length(), 3)
  doc.css("p").set_text("changed")
  assert_eq(doc.css("p").text(), "changed")
}
