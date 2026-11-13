// The corpus the differential run replays: one document per line, read and
// written again by this library, then handed to a mature implementation in
// `scripts/check_interop.py` to see whether the two agree.
//
// Both directions are covered by one exchange. What this program prints is
// what the library wrote; the checker parses it with lxml or html5lib and
// compares the result against the same implementation's reading of the source,
// so a document that survives means each can read what the other wrote.

///|
/// The cases, in the order the checker reports them. `xml` cases must be
/// well-formed; `html` cases are whatever a browser accepts, which is
/// everything.
fn cases() -> Array[(String, String, String)] {
  [
    // XML: the parts a byte-faithful writer has to keep
    ("xml-elements", "xml", "<a><b>1</b><b>2</b><c/></a>"),
    ("xml-attribute-order", "xml", "<a z=\"1\" a=\"2\" m=\"3\"/>"),
    ("xml-closing-styles", "xml", "<a><b/><c></c></a>"),
    ("xml-cdata", "xml", "<a><![CDATA[x < y & z]]></a>"),
    ("xml-comment", "xml", "<a><!-- note --><b/></a>"),
    (
      "xml-declaration-and-instruction", "xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><?target data here?><a/>",
    ),
    (
      "xml-doctype-internal-subset", "xml", "<!DOCTYPE a [<!ENTITY greet \"hello\">]><a>&greet; world</a>",
    ),
    ("xml-doctype-system", "xml", "<!DOCTYPE a SYSTEM \"a.dtd\"><a/>"),
    ("xml-mixed-content", "xml", "<p>text <b>bold</b> tail <i>it</i>.</p>"),
    ("xml-namespace-default", "xml", "<a xmlns=\"urn:x\"><b/></a>"),
    (
      "xml-namespace-prefixed", "xml", "<x:a xmlns:x=\"urn:x\"><x:b y=\"1\"/></x:a>",
    ),
    (
      "xml-namespace-on-attribute", "xml", "<a xmlns:p=\"urn:p\" p:x=\"1\" y=\"2\"/>",
    ),
    (
      "xml-character-references", "xml", "<a>&amp;&lt;&gt;&quot;&apos;&#65;&#x42;</a>",
    ),
    ("xml-unicode", "xml", "<a title=\"日本語\">中文 ✓</a>"),
    ("xml-whitespace", "xml", "<a>  <b> x </b>  </a>"),
    ("xml-deep-nesting", "xml", "<a><b><c><d>x</d></c></b></a>"),
    ("xml-empty-element", "xml", "<a></a>"),
    ("xml-quote-styles", "xml", "<a b='single' c=\"double\"/>"),
    ("xml-language", "xml", "<a xml:lang=\"en\"><b xml:lang=\"fr\"/></a>"),
    ("xml-instruction-in-content", "xml", "<a><?php echo 1; ?><b/></a>"),
    ("xml-lines", "xml", "<a>\n  <b/>\n  <c/>\n</a>"),
    ("xml-attribute-whitespace", "xml", "<a b=\"  two  spaces  \"/>"),
    ("xml-empty-attribute", "xml", "<a b=\"\"/>"),
    (
      "xml-nested-namespaces", "xml", "<a xmlns=\"urn:a\"><b xmlns=\"urn:b\"><c/></b></a>",
    ),
    // HTML: the repairs a browser makes, and the writer that has to survive them
    ("html-minimal", "html", "<p>hi"),
    ("html-list-closes-itself", "html", "<ul><li>a<li>b</ul>"),
    (
      "html-foster-parenting", "html", "<table><tr><td>a</td></tr> stray</table>",
    ),
    ("html-adoption-agency", "html", "<b>1<p>2</b>3</p>"),
    ("html-void-elements", "html", "<br><img src=x><hr>"),
    (
      "html-character-references", "html", "<p>&amp; &nbsp; &copy; &#x1F600;</p>",
    ),
    ("html-comment", "html", "<!-- c --><p>x</p>"),
    (
      "html-doctype", "html", "<!DOCTYPE html><html><body><p>x</p></body></html>",
    ),
    ("html-unquoted-attributes", "html", "<a href=/x class=y>z</a>"),
    ("html-duplicate-attribute", "html", "<a x=1 x=2>d</a>"),
    (
      "html-svg", "html", "<svg viewBox=\"0 0 1 1\"><rect/><foreignObject><div>x</div></foreignObject></svg>",
    ),
    (
      "html-mathml", "html", "<math><mi>x</mi><annotation-xml encoding=\"text/html\"><div>y</div></annotation-xml></math>",
    ),
    ("html-template", "html", "<template><li>x</li></template>"),
    ("html-textarea", "html", "<textarea>a<b>c</textarea>"),
    ("html-pre", "html", "<pre>\n a\n  b</pre>"),
    ("html-script", "html", "<script>if (a < b && c > d) x();</script>"),
    ("html-noscript", "html", "<noscript><p>x</p></noscript>"),
    ("html-bogus-comment", "html", "<?php x ?><p>y"),
    ("html-formatting-nested", "html", "<p><b><i>x</b></i></p>"),
    ("html-implied-tbody", "html", "<table><tr><td>1<td>2</table>"),
    ("html-select", "html", "<select><option>a<option>b</select>"),
    ("html-nested-anchor", "html", "<a href=1>x<a href=2>y</a>"),
    ("html-caption", "html", "<table><caption>c<tr><td>x</table>"),
    ("html-frameset", "html", "<frameset><frame src=a></frameset>"),
    ("html-dl", "html", "<dl><dt>a<dd>b<dt>c</dl>"),
    ("html-headings", "html", "<h1>a<h2>b</h2>"),
    (
      "html-foreign-xml-lang", "html", "<body xml:lang=en><svg><g xml:lang=fr xlink:href=foo></g></svg>",
    ),
  ]
}

///|
/// The characters the checker's format gives meaning to, escaped so one
/// document stays one line.
fn escaped(text : String) -> String {
  let out = StringBuilder()
  for ch in text {
    match ch {
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\t' => out.write_string("\\t")
      '\r' => out.write_string("\\r")
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

///|
fn main {
  for item in cases() {
    let (id, flavour, source) = item
    let written = if flavour == "xml" {
      @xml.loads(source).dumps() catch {
        error => "refused: \{error}"
      }
    } else {
      @html.loads(source).dumps()
    }
    println("\{id}\t\{flavour}\t\{escaped(source)}\t\{escaped(written)}")
  }
}
