/// XML well-formedness: what `loads` accepts, what it refuses, and how it says
/// so.
///
/// The parser's tolerance is the interesting part of a parser's behaviour, and
/// it is the part that ordinary round-trip tests never reach: a document that
/// is rejected by accident and one that is accepted by accident both look fine
/// until a caller depends on them.

fn xml_ok(text : String) -> Bool {
  try {
    ignore(@xml.loads(text))
    true
  } catch {
    _ => false
  }
}

/// The kind of failure: `malformed`, `unsupported`, or `none`.
fn xml_error(text : String) -> String {
  try {
    ignore(@xml.loads(text))
    "none"
  } catch {
    @moonxml.Refused::Malformed(..) => "malformed"
    @moonxml.Refused::Unsupported(..) => "unsupported"
    @moonxml.Refused::BadQuery(..) => "bad-query"
    @moonxml.Refused::UnknownSelector(..) => "unknown-selector"
  }
}

test "xml: well-formed documents are accepted" {
  let good : Array[String] = [
    "<a/>",
    "<a></a>",
    "<a>text</a>",
    "<a b=\"1\" c='2'/>",
    "<?xml version=\"1.0\"?><a/>",
    "<!--c--><a/>",
    "<?pi data?><a/>",
    "<a><![CDATA[x<y]]></a>",
    "<a>&amp;&lt;&gt;&quot;&apos;</a>",
    "<a>&#65;&#x41;</a>",
    "<a xmlns:p=\"urn:p\"><p:b/></a>",
    "<a xmlns=\"urn:d\"><b/></a>",
    "<a><!--x--><?y?></a>",
    "<!DOCTYPE a><a/>",
    "<!DOCTYPE a [<!ENTITY e \"v\">]><a>&e;</a>",
    "<a b=\"a&#10;b\"/>",
  ]
  for text in good {
    if !xml_ok(text) {
      println("refused: " + text + " (" + xml_error(text) + ")")
    }
    assert_eq(xml_ok(text), true)
  }
}

test "xml: malformed documents are refused" {
  let bad : Array[String] = [
    "",
    "<a>",
    "<a></b>",
    "<a><b></a></b>",
    "<a b=1/>",
    "<a b/>",
    "text<a/>",
    "<a/>text",
    "<a/><b/>",
    "<a>&undefined;</a>",
    "<a>&#xD800;</a>",
    "<a b=\"<\"/>",
    "<a><!--a--b--></a>",
    "<a></a",
    "<a><![CDATA[x</a>",
    "<p:a/>",
    "<a xmlns:p=\"urn:p\"><q:b/></a>",
    "<?xml version=\"1.0\"?><a/><?xml version=\"1.0\"?>",
    "<a xmlns:p=\"urn:p\" xmlns:q=\"urn:p\" p:b=\"1\" q:b=\"2\"/>",
  ]
  for text in bad {
    if xml_ok(text) {
      println("accepted: [" + text + "]")
    }
    assert_eq(xml_ok(text), false)
  }
}

test "xml: a malformed document says where and why" {
  let message = try {
    ignore(@xml.loads("<a><b></a>"))
    ""
  } catch {
    @moonxml.Refused::Malformed(at~, why~) => at.to_string() + ":" + why
    _ => "wrong error kind"
  }
  assert_eq(message.contains(":"), true)
  assert_eq(message.has_prefix("wrong"), false)

  // An unbound prefix is a well-formedness error, and the message names it.
  let unbound = try {
    ignore(@xml.loads("<p:a/>"))
    ""
  } catch {
    @moonxml.Refused::Malformed(why~, ..) => why
    _ => "wrong error kind"
  }
  assert_eq(unbound.contains("p"), true)
}

test "xml: an external entity is refused as unsupported, not as malformed" {
  // The library does not read external subsets, and says so rather than
  // pretending the document is broken.
  let text = "<!DOCTYPE a [<!ENTITY e SYSTEM \"e.xml\">]><a>&e;</a>"
  assert_eq(xml_error(text), "unsupported")
}

test "xml: a fragment may have several roots and text" {
  let doc = try {
    @xml.loads_fragment("<a/><b/>text")
  } catch {
    _ => abort("a fragment with several roots must parse")
  }
  assert_eq(doc.css("a").length(), 1)
  assert_eq(doc.css("b").length(), 1)
  assert_eq(doc.text(), "text")
}

test "xml: entity recursion and expansion are bounded" {
  let recursive = "<!DOCTYPE a [<!ENTITY e \"&e;\">]><a>&e;</a>"
  assert_eq(xml_error(recursive), "malformed")
  // Two levels are fine; the same entity twice in one value is fine too.
  let ok = "<!DOCTYPE a [<!ENTITY e \"x\"><!ENTITY f \"&e;&e;\">]><a>&f;</a>"
  let doc = try {
    @xml.loads(ok)
  } catch {
    _ => abort("a two-level entity must expand")
  }
  assert_eq(doc.text(), "xx")
}

test "xml: the default depth limit is generous but present" {
  let sb = StringBuilder()
  let mut i = 0
  while i < 1200 {
    sb.write_string("<a>")
    i = i + 1
  }
  i = 0
  while i < 1200 {
    sb.write_string("</a>")
    i = i + 1
  }
  assert_eq(xml_error(sb.to_string()), "malformed")
  assert_eq(xml_ok("<a><b><c/></b></a>"), true)
}

test "xml: a comment or PI inside the prolog and the element is kept" {
  let doc = try {
    @xml.loads("<!--a--><?p d?><r><!--b--><?q e?></r>")
  } catch {
    _ => abort("the fixture must parse")
  }
  assert_eq(doc.dumps(), "<!--a--><?p d?><r><!--b--><?q e?></r>")
}
