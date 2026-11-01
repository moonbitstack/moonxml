test "svg camelcase and integration point" {
  let doc = @html.loads("<svg viewBox=\"0 0 1 1\"><foreignObject><div>x</div></foreignObject></svg>")
  let svg = doc.css("svg").items[0].as_element().unwrap()
  assert_eq(svg.attr("viewBox"), Some("0 0 1 1"))
  let fo = doc.css("foreignObject").items[0].as_element().unwrap()
  assert_eq(fo.name, "{http://www.w3.org/2000/svg}foreignObject")
  let d = doc.css("div").items[0].as_element().unwrap()
  assert_eq(d.namespace_uri(), "")
}

test "table foster parenting" {
  let doc = @html.loads("<table>stray<tr><td>x</td></tr></table>")
  let h = doc.dumps_html()
  assert_eq(h.contains("stray<table>"), true)
}

test "head routing" {
  let doc = @html.loads("<title>t</title><meta charset=\"utf-8\"><p>x</p>")
  assert_eq(doc.css("head title").length(), 1)
  assert_eq(doc.css("head meta").length(), 1)
  assert_eq(doc.css("body p").length(), 1)
}
