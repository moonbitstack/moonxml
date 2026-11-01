test "html basic" {
  let doc = loads("<p>Hello <b>world</b></p>")
  assert_eq(doc.css("p").length(), 1)
  assert_eq(doc.css("b").text(), "world")
  assert_eq(doc.css("body").length(), 1)
}

test "html entities" {
  let doc = loads("<p>&amp; &lt; &#65; &nbsp;</p>")
  assert_eq(doc.css("p").text(), "& < A \u{A0}")
}

test "html void" {
  let doc = loads("<div><br><img src=\"x\"></div>")
  let h = doc.dumps_html()
  assert_eq(h.contains("<br>"), true)
  assert_eq(h.contains("</br>"), false)
  assert_eq(doc.css("img").attr("src"), Some("x"))
}

test "html script rawtext" {
  let doc = loads("<script>if (a < b) { x(); }</script>")
  assert_eq(doc.css("script").text(), "if (a < b) { x(); }")
}

test "html foreign" {
  let doc = loads("<svg><circle/></svg>")
  let c = doc.css("circle").items[0].as_element().unwrap()
  assert_eq(c.namespace_uri(), "http://www.w3.org/2000/svg")
}

test "html auto close li" {
  let doc = loads("<ul><li>a<li>b</ul>")
  assert_eq(doc.css("li").length(), 2)
  assert_eq(doc.css("li").eq(1).text(), "b")
}
