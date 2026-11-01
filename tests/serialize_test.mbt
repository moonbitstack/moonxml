/// Serialization, both flavours.
///
/// The XML writer aims at byte fidelity for documents written in the canonical
/// style (double quotes, no prefixed names); the HTML writer follows WHATWG §13
/// where the tree no longer remembers the source. The tests pin the rules that
/// are easy to break: escaping, void and raw-text elements, attribute quoting,
/// namespace re-declaration, and the fixpoint property that some of them imply.

fn xml_rt(text : String) -> @moonxml.Document {
  try {
    @xml.loads(text)
  } catch {
    _ => abort("the fixture must parse: " + text)
  }
}

fn html_rt(text : String) -> @moonxml.Document {
  @html.loads(text)
}

test "xml: a canonical document is byte-identical" {
  let text = "<root a=\"1\" b=\"2\"><!--c--><![CDATA[x<y]]><?pi d?><child/></root>"
  let doc = xml_rt(text)
  assert_eq(doc.dumps(), text)
  // Two round trips do not drift.
  assert_eq(xml_rt(doc.dumps()).dumps(), text)
}

test "xml: attribute order is kept and quoting normalises to double quotes" {
  let doc = xml_rt("<r b=\"2\" a=\"1\" c='3'/>")
  assert_eq(doc.dumps(), "<r b=\"2\" a=\"1\" c=\"3\"/>")
}

test "xml: text escaping is minimal" {
  let doc = xml_rt("<r>a &amp; b &lt; c &gt; d</r>")
  assert_eq(doc.dumps(), "<r>a &amp; b &lt; c > d</r>")
  // A `>` needs escaping only where it would close a CDATA section.
  let doc2 = xml_rt("<r><![CDATA[a]]]]><![CDATA[>b]]></r>")
  assert_eq(doc2.dumps(), "<r><![CDATA[a]]]]><![CDATA[>b]]></r>")
}

test "xml: attribute values escape quotes, angle brackets and whitespace" {
  let doc = xml_rt("<r a=\"&amp;&quot;&lt;&#9;&#10;&#13;\"/>")
  assert_eq(doc.dumps(), "<r a=\"&amp;&quot;&lt;&#9;&#10;&#13;\"/>")
}

test "xml: CDATA, comments, processing instructions and the doctype survive" {
  let text = "<!DOCTYPE r SYSTEM \"r.dtd\"><r><!--a--><?t?><![CDATA[<raw>]]></r>"
  let doc = xml_rt(text)
  assert_eq(doc.dumps(), text)
}

test "xml: self-closing syntax is preserved only where the source used it" {
  let doc = xml_rt("<r><a/><b></b></r>")
  assert_eq(doc.dumps(), "<r><a/><b></b></r>")
}

test "xml: an empty element keeps its written form after an edit" {
  let doc = xml_rt("<r><a/></r>")
  let a = doc.css("a").items[0].as_element().unwrap()
  a.append(@moonxml.Node::TextNode("x"))
  assert_eq(doc.dumps(), "<r><a>x</a></r>")
  a.clear()
  // Emptying an element does not change how it was written: the self-closing
  // form the source used is a property of the element, not of its content.
  assert_eq(doc.dumps(), "<r><a/></r>")
}

test "xml: namespaces become default declarations, once per run" {
  let doc = xml_rt("<p:r xmlns:p=\"urn:p\"><p:a/><p:b/></p:r>")
  assert_eq(doc.dumps(), "<r xmlns=\"urn:p\"><a/><b/></r>")
  // Coming back to no namespace has to be declared.
  let doc2 = xml_rt("<r xmlns=\"urn:d\"><a/><b xmlns=\"\"/></r>")
  assert_eq(doc2.dumps(), "<r xmlns=\"urn:d\"><a/><b xmlns=\"\"/></r>")
}

test "xml: a namespaced attribute is given a prefix that is declared" {
  let doc = xml_rt("<r xmlns:x=\"urn:x\" x:a=\"1\" b=\"2\"/>")
  let out = doc.dumps()
  assert_eq(out.contains("xmlns:ns0=\"urn:x\""), true)
  assert_eq(out.contains("ns0:a=\"1\""), true)
  assert_eq(out.contains("b=\"2\""), true)
  // The reparse gives the same names back, which is what matters.
  let again = xml_rt(out)
  assert_eq(again.dumps(), out)
  let r = again.document_element().unwrap()
  assert_eq(r.attr("{urn:x}a"), Some("1"))
}

test "xml: round trips are a fixpoint" {
  let docs : Array[String] = [
    "<r/>",
    "<r>text</r>",
    "<r><a>1</a><a>2</a></r>",
    "<r a=\"1\"><b c=\"2\">t</b></r>",
    "<r><!--c--><![CDATA[x]]><?pi d?></r>",
    "<r><a/><b></b><c> </c></r>",
    "<r>a &amp; b &lt; c</r>",
    "<p:r xmlns:p=\"urn:p\"><p:a b=\"1\"/></p:r>",
  ]
  for text in docs {
    let once = xml_rt(text).dumps()
    let twice = xml_rt(once).dumps()
    assert_eq(twice, once)
  }
}

test "html: void elements carry no end tag" {
  let doc = html_rt("<div><br><img src=a.png><input><hr></div>")
  assert_eq(doc.dumps_html(), "<html><head></head><body><div><br><img src=\"a.png\"><input><hr></div></body></html>")
}

test "html: raw text elements are written without escaping" {
  let doc = html_rt("<div><script>if (a < b && c) { x(); }</script><style>a > b { }</style></div>")
  let out = doc.dumps_html()
  assert_eq(out.contains("<script>if (a < b && c) { x(); }</script>"), true)
  assert_eq(out.contains("<style>a > b { }</style>"), true)
}

test "html: text escapes the five characters the serialiser cares about" {
  let doc = html_rt("<p>a &amp; b &lt; c &gt; d")
  assert_eq(doc.css("p").html(), "a &amp; b &lt; c &gt; d")
  // A non-breaking space is written as an entity, not as itself.
  let doc2 = html_rt("<p>a&#160;b</p>")
  assert_eq(doc2.css("p").html(), "a&nbsp;b")
}

test "html: attributes keep document order and empty values stay bare" {
  let doc = html_rt("<input checked type=\"text\" value=\"a&amp;b\" title='q\"r'>")
  assert_eq(
    doc.dumps_html(),
    "<html><head></head><body><input checked type=\"text\" value=\"a&amp;b\" title=\"q&quot;r\"></body></html>",
  )
}

test "html: comments and the doctype survive" {
  let doc = html_rt("<!DOCTYPE html><html><body><!--x--><p>y</p></body></html>")
  // A head element always exists, even when the source had none.
  assert_eq(
    doc.dumps_html(),
    "<!DOCTYPE html><html><head></head><body><!--x--><p>y</p></body></html>",
  )
}

test "html: the document writes itself in its own flavour" {
  let h = html_rt("<p>x</p>")
  // `dumps` on an HTML document is HTML, not XML.
  assert_eq(h.dumps(), h.dumps_html())
  assert_eq(h.dumps().contains("<p>x</p>"), true)
  // The same tree written as XML would close the void element.
  let x = xml_rt("<p>x</p>")
  assert_eq(x.dumps(), "<p>x</p>")
}

test "html: a selection writes its inner HTML in the document's flavour" {
  let doc = html_rt("<div><br><span>a &amp; b</span></div>")
  assert_eq(doc.css("div").html(), "<br><span>a &amp; b</span>")
  assert_eq(doc.css("span").html(), "a &amp; b")
  assert_eq(doc.css("nope").html(), "")
}

test "xml: a selection writes its inner XML" {
  let doc = xml_rt("<r><a/><b>x</b></r>")
  assert_eq(doc.css("r").html(), "<a/><b>x</b>")
}

test "html: a doctype with identifiers is written so that it reads back" {
  // The tree keeps the corpus's flattened form (name, then the identifiers);
  // the writer puts the PUBLIC or SYSTEM keyword back, because a parser needs
  // it. Without that, a XHTML doctype would be a bogus one after a round trip.
  let text = "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">"
  let doc = html_rt(text)
  assert_eq(doc.dumps_html(), text + "<html><head></head><body></body></html>")
  let sys = html_rt("<!DOCTYPE r SYSTEM \"r.dtd\">")
  assert_eq(sys.dumps_html().has_prefix("<!DOCTYPE r SYSTEM \"r.dtd\">"), true)
}

test "html: a leading newline in pre survives being written" {
  // The parser drops one newline after `pre`, so the writer adds one back; a
  // document written to disk and read again keeps its blank first line.
  let doc = html_rt("<pre>\n\nA</pre>")
  assert_eq(doc.css("pre").html(), "\nA")
  assert_eq(doc.dumps_html().contains("<pre>\n\nA</pre>"), true)
  let same = html_rt(doc.dumps_html())
  assert_eq(same.css("pre").html(), "\nA")
}

test "html: a foreign element that shares an HTML name is not raw text" {
  // `plaintext` and `br` are ordinary SVG elements; only HTML ones are special.
  // So the text inside `svg plaintext` is escaped, and `svg br` gets an end tag.
  let doc = html_rt("<svg><plaintext>a &amp; b</plaintext><br></br></svg>")
  let out = doc.dumps_html()
  assert_eq(out.contains("<svg><plaintext>a &amp; b</plaintext>"), true)
  assert_eq(out.contains("</plaintext></svg>"), true)
  let x = xp_ns_of(doc, "plaintext")
  assert_eq(x, "http://www.w3.org/2000/svg")
}

fn xp_ns_of(doc : @moonxml.Document, tag : String) -> String {
  try {
    doc.css(tag).items[0].as_element().unwrap().namespace_uri()
  } catch {
    _ => abort("the element must exist: " + tag)
  }
}

test "html: noscript holding only text is written the way it was parsed" {
  // With scripting enabled `noscript` is raw text, so its content must not be
  // escaped; the tree cannot record the flag, but a text-only child list can
  // only come from that mode.
  let doc = @html.loads_with_scripting("<noscript>a < b</noscript>", true)
  assert_eq(doc.dumps_html().contains("<noscript>a < b</noscript>"), true)
  // Without scripting the same source is not raw text: the text token leaves
  // `noscript` behind (the "in head noscript" rule pops it), so the element is
  // empty and the text lands in the body.
  let plain = @html.loads_with_scripting("<noscript>a &amp; b</noscript>", false)
  assert_eq(plain.dumps_html().contains("<noscript></noscript>"), true)
  assert_eq(plain.css("noscript").text(), "")
  assert_eq(plain.css("body").text(), "a & b")
}
