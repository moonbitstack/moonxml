/// Character references, script data, and comment edge cases.
///
/// These pin the tokenizer details the html5lib corpus is sensitive to, so a
/// regression shows up as a small unit failure rather than a moved pass rate.

fn body_text(input : String) -> String raise @moonxml.Refused {
  @html.loads(input).css("body").text()
}

test "named references resolve through the full table" {
  assert_eq(body_text("<p>&Alpha;&Beta;</p>"), "\u{391}\u{392}")
  assert_eq(body_text("<p>&nbsp;x</p>"), "\u{A0}x")
  // Two code points, one reference.
  assert_eq(body_text("<p>&NotEqualTilde;</p>"), "\u{2242}\u{338}")
}

test "longest match wins" {
  // `&not` is a legacy alias for negation; `&notin;` must win over it.
  assert_eq(body_text("<p>&notin;</p>"), "\u{2209}")
  assert_eq(body_text("<p>&not;</p>"), "\u{AC}")
  assert_eq(body_text("<p>&not</p>"), "\u{AC}")
}

test "legacy references without a semicolon" {
  assert_eq(body_text("<p>a&amp b</p>"), "a& b")
  assert_eq(body_text("<p>x&copy y</p>"), "x\u{A9} y")
}

test "attribute values keep a legacy reference that would change a query" {
  let doc = @html.loads("<a href=\"?a=1&notc=2&copy=3\"></a>")
  assert_eq(doc.css("a").attr("href"), Some("?a=1&notc=2&copy=3"))
  let doc2 = @html.loads("<a href=\"?a=1&amp;b=2\"></a>")
  assert_eq(doc2.css("a").attr("href"), Some("?a=1&b=2"))
}

test "numeric references" {
  assert_eq(body_text("<p>&#65;&#x42;</p>"), "AB")
  // A missing semicolon still decodes.
  assert_eq(body_text("<p>&#41BAR</p>"), ")BAR")
  // C1 range maps through Windows-1252.
  assert_eq(body_text("<p>&#x80;</p>"), "\u{20AC}")
  // Out of range, surrogate and NUL become the replacement character.
  assert_eq(body_text("<p>&#111111111111</p>"), "\u{FFFD}")
  assert_eq(body_text("<p>&#xD800;</p>"), "\u{FFFD}")
  assert_eq(body_text("<p>&#0;</p>"), "\u{FFFD}")
}

test "an unknown reference stays literal" {
  assert_eq(body_text("<p>&nosuchname; </p>"), "&nosuchname; ")
  assert_eq(body_text("<p>a & b</p>"), "a & b")
}

test "script data: escaped and double-escaped states" {
  // A `</script>` after `<!--` closes the element.
  let doc = @html.loads("<script><!--</script>")
  assert_eq(doc.css("script").text(), "<!--")
  // After `<!--<script>`, a `</script>` is text until the escaped state is
  // entered again.
  let doc2 = @html.loads("<script><!--<script></script>X</script>")
  assert_eq(doc2.css("script").text(), "<!--<script></script>X")
  // `</script` needs a delimiter to close.
  let doc3 = @html.loads("<script>a</scriptb</script>")
  assert_eq(doc3.css("script").text(), "a</scriptb")
}

test "comments: abrupt closes and bogus markup" {
  let doc = @html.loads("<div><!--></div>")
  assert_eq(doc.dumps_html().contains("<!---->"), true)
  let doc2 = @html.loads("<div><!---></div>")
  assert_eq(doc2.dumps_html().contains("<!---->"), true)
  // `<?` is a bogus comment, not markup.
  let doc3 = @html.loads("<?xml version=\"1.0\"><p>x</p>")
  assert_eq(doc3.dumps_html().contains("<!--?xml version=\"1.0\"-->"), true)
  assert_eq(doc3.css("p").text(), "x")
}

test "a block start tag closes a paragraph through formatting elements" {
  assert_eq(@html.loads("<p><b>x<p>y").css("p").length(), 2)
  assert_eq(@html.loads("<p><b>x<p>y").css("p").eq(1).text(), "y")
}
