/// Foreign content, the scripting flag, and the small input rules around them.

test "scripting on makes noscript raw text" {
  let doc = @html.loads_with_scripting("<body><noscript><b>x</b></noscript>", true)
  assert_eq(doc.css("noscript").text(), "<b>x</b>")
  assert_eq(doc.css("noscript b").length(), 0)
}

test "scripting off parses noscript content" {
  let doc = @html.loads("<body><noscript><b>x</b></noscript>")
  assert_eq(doc.css("noscript b").length(), 1)
  assert_eq(doc.css("noscript").text(), "x")
}

test "foreign attributes keep their namespace" {
  let doc = @html.loads("<svg xlink:href=\"a\" xml:lang=\"en\"></svg>")
  let svg = doc.css("svg").items[0].as_element().unwrap()
  assert_eq(svg.attr("{http://www.w3.org/1999/xlink}href"), Some("a"))
  assert_eq(svg.attr("{http://www.w3.org/XML/1998/namespace}lang"), Some("en"))
}

test "html attributes are left alone" {
  let doc = @html.loads("<a xlink:href=\"a\">x</a>")
  assert_eq(doc.css("a").attr("xlink:href"), Some("a"))
}

test "pre drops one leading newline" {
  let doc = @html.loads("<pre>\nfoo</pre>")
  assert_eq(doc.css("pre").text(), "foo")
  let doc2 = @html.loads("<pre>\n\nfoo</pre>")
  assert_eq(doc2.css("pre").text(), "\nfoo")
}

test "a fostered title stays in the body" {
  let doc = @html.loads("<table><title>X</title></table>")
  assert_eq(doc.css("body title").length(), 1)
  assert_eq(doc.css("head title").length(), 0)
}

test "head and body attributes survive" {
  let doc = @html.loads("<html lang=\"en\"><body class=\"b\"><p>x</p></body></html>")
  assert_eq(doc.css("html").attr("lang"), Some("en"))
  assert_eq(doc.css("body").attr("class"), Some("b"))
}
