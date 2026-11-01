test "xpath string functions" {
  let doc = sample()
  assert_eq(doc.xpath("substring(\"hello\",2,3)").text(), "ell")
  assert_eq(doc.xpath("translate(\"abc\",\"abc\",\"xyz\")").text(), "xyz")
  assert_eq(doc.xpath("string-length(\"abc\")").text(), "3")
  assert_eq(doc.xpath("round(2.5)").text(), "3")
  assert_eq(doc.xpath("floor(2.9)").text(), "2")
  assert_eq(doc.xpath("ceiling(2.1)").text(), "3")
  assert_eq(doc.xpath("substring-before(\"a-b\",\"-\")").text(), "a")
  assert_eq(doc.xpath("substring-after(\"a-b\",\"-\")").text(), "b")
}

test "css structural" {
  let doc = @html.loads("<div><p>a</p><span>b</span><p>c</p><i></i></div>")
  assert_eq(doc.css("p:first-of-type").text(), "a")
  assert_eq(doc.css("p:last-of-type").text(), "c")
  assert_eq(doc.css("p:nth-of-type(2)").text(), "c")
  assert_eq(doc.css("i:empty").length(), 1)
  assert_eq(doc.css("span:only-child").length(), 0)
  assert_eq(doc.css("p:only-of-type").length(), 0)
}

test "html comment and doctype" {
  let doc = @html.loads("<!DOCTYPE html><html><body><!--c--><p>x</p></body></html>")
  assert_eq(doc.dumps_html().contains("<!--c-->"), true)
  assert_eq(doc.document_element().unwrap().name, "html")
}

test "html template and frameset parse" {
  let doc = @html.loads("<template><p>t</p></template><frameset><frame></frameset>")
  assert_eq(doc.css("template p").length(), 1)
  assert_eq(doc.css("frameset").length(), 1)
}
