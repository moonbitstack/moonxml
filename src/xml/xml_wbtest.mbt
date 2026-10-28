// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A sink that counts what it sees, for the streaming read.
struct Counter {
  mut starts : Int32
  mut texts : Int32
}

///|
impl @event.Sink for Counter with fn push(self, event) {
  match event {
    StartTag(_) => self.starts = self.starts + 1
    Text(_) => self.texts = self.texts + 1
    _ => ()
  }
}

///|
fn refused(text : String) -> Bool {
  try {
    ignore(loads(text))
    false
  } catch {
    _ => true
  }
}

///|
test "a document becomes a tree" {
  let doc = loads("<a><b x='1'>t</b><c/></a>")
  assert_eq(doc.document_element().unwrap().name, "a")
  assert_eq(doc.css("b").text(), "t")
  assert_eq(doc.css("b").attr("x"), Some("1"))
  assert_eq(doc.css("c").length(), 1)
  match doc.css("c").items[0] {
    ElementNode(el) => assert_eq(el.closed, true)
    _ => assert_eq(true, false)
  }
}

///|
test "a well-formed document writes back byte for byte" {
  // Attribute values are written double-quoted: a document that used single
  // quotes normalizes on the first write and is byte-stable from then on.
  let cases = [
    "<a/>", "<a></a>", "<a b=\"1\" c=\"2\"/>", "<a c=\"2\" b=\"1\"></a>", "<?xml version=\"1.0\"?><r><x/></r>",
    "<!DOCTYPE html><html><body><p>hi</p></body></html>", "<r><![CDATA[x < y & z]]></r>",
    "<r><!-- a comment --><b/></r>", "<r><?php echo 1; ?></r>", "<r>text &amp; more &lt;</r>",
    "<r><a>1</a><a>2</a><a>3</a></r>",
  ]
  for source in cases {
    let doc = loads(source)
    assert_eq(doc.dumps(), source)
  }
}

///|
test "character references decode, and that is the one deviation" {
  // The DOM means them decoded; a document written with them normalizes on
  // the first write and is byte-stable from then on.
  let doc = loads("<r>&#65;&#x42;</r>")
  assert_eq(doc.css("r").text(), "AB")
  assert_eq(doc.dumps(), "<r>AB</r>")
}

///|
test "namespaces resolve to Clark names" {
  let doc = loads(
    "<r xmlns='urn:x' xmlns:p='urn:y'><p:a p:b='1' c='2'/><d/></r>",
  )
  assert_eq(doc.css("r").items[0].name(), "{urn:x}r")
  assert_eq(doc.css("a").length(), 1)
  assert_eq(doc.css("a").items[0].name(), "{urn:y}a")
  assert_eq(doc.css("a").attr("{urn:y}b"), Some("1"))
  assert_eq(doc.css("a").attr("c"), Some("2"))
  assert_eq(doc.css("d").items[0].name(), "{urn:x}d")
}

///|
test "the xml prefix is predefined and a prefix nobody declared is refused" {
  let doc = loads("<r xml:lang='en'/>")
  assert_eq(
    doc.css("r").attr("{http://www.w3.org/XML/1998/namespace}lang"),
    Some("en"),
  )
  assert_eq(refused("<r><p:a/></r>"), true)
  assert_eq(refused("<r xmlns:p='u'><p:a/></r>"), false)
}

///|
test "mixed content, comments, CDATA and instructions all survive" {
  let doc = loads("<r>a<!--c--><![CDATA[<b>]]><?pi data?>b</r>")
  let children = doc.css("r").items[0].children()
  assert_eq(children.length(), 5)
  assert_eq(children[1] is CommentNode(_), true)
  assert_eq(children[2] is CDataNode(_), true)
  assert_eq(children[3] is ProcessingInstructionNode(_), true)
  assert_eq(doc.css("r").text(), "a<b>b")
}

///|
test "a doctype keeps its internal subset" {
  let source = "<!DOCTYPE r [ <!ELEMENT r (#PCDATA)> ]><r>x</r>"
  let doc = loads(source)
  assert_eq(doc.dumps(), source)
  match doc.root.children[0] {
    DoctypeNode(text) => assert_eq(text, "r [ <!ELEMENT r (#PCDATA)> ]")
    _ => assert_eq(true, false)
  }
}

///|
test "a broken document names the fault" {
  let cases = [
    "<a>", "<a></b>", "<a b=1/>", "<a b='1' b='2'/>", "<a/><b/>", "text only", "<a><!-- x -- y --></a>",
    "<a>&nope;</a>", "<a><![CDATA[x</a>", "<a b='<'/>",
  ]
  for source in cases {
    assert_eq(refused(source), true)
  }
  assert_eq(refused(""), true)
  assert_eq(refused("<a/>"), false)
}

///|
test "nesting past the bound is refused" {
  let mut source = ""
  for _k = 0; _k < 513; _k = _k + 1 {
    source = source + "<a>"
  }
  for _k = 0; _k < 513; _k = _k + 1 {
    source = source + "</a>"
  }
  assert_eq(refused(source), true)
}

///|
test "the streaming read sees events without a tree" {
  let counter : Counter = { starts: 0, texts: 0, }
  scan("<a><b>1</b><c>2</c></a>", counter)
  assert_eq(counter.starts, 3)
  assert_eq(counter.texts, 2)
  let doc = loads("<a><b>1</b></a>")
  let events = doc.events()
  assert_eq(events.length(), 5)
}

///|
test "bytes, the byte-order mark and fragments" {
  let doc = load(b"\xEF\xBB\xBF<a>x</a>")
  assert_eq(doc.css("a").text(), "x")
  let fragment = loads_fragment("<a/>text<b/>")
  assert_eq(fragment.root.children.length(), 3)
  assert_eq(fragment.dumps(), "<a/>text<b/>")
}

///|
test "the chain reads an XML document like any other" {
  let doc = loads(
    "<feed><entry id='1'><title>One</title></entry><entry id='2'><title>Two</title></entry></feed>",
  )
  assert_eq(doc.css("entry").length(), 2)
  assert_eq(doc.xpath("//entry[@id='2']/title").text(), "Two")
  assert_eq(doc.css("entry").xpath("@id").text(), "12")
  assert_eq(doc.flavour(), @moonxml.Xml)
}

///|
test "the depth bound is stated, not buried" {
  assert_eq(limit, 512)
  let deep = "<a>".repeat(4) + "</a>".repeat(4)
  assert_eq(loads(deep).css("a").length(), 4)
  let refused = try {
    ignore(loads(deep, limit=3))
    false
  } catch {
    @moonxml.Exceeded(limit~, got~, ..) => limit == 3 && got == 4
    _ => false
  }
  assert_eq(refused, true)
}

///|
test "bytes that are not UTF-8 are refused at the fault" {
  let refused = try {
    ignore(load(b"<a>\xFF</a>"))
    false
  } catch {
    @moonxml.Malformed(at~, ..) => at == 3
    _ => false
  }
  assert_eq(refused, true)
}

///|
test "an internal entity stands for its text" {
  let doc = loads(
    "<!DOCTYPE r [<!ENTITY who \"the reader\">]><r>hello &who;</r>",
  )
  assert_eq(doc.css("r").text(), "hello the reader")
}

///|
test "an entity may stand for markup, and it is read as markup" {
  let doc = loads("<!DOCTYPE r [<!ENTITY e \"<b>bold</b>\">]><r>&e;</r>")
  assert_eq(doc.css("b").length(), 1)
  assert_eq(doc.css("b").text(), "bold")
}

///|
test "entities nest, and the inner one is expanded too" {
  let doc = loads(
    "<!DOCTYPE r [<!ENTITY inner \"deep\"><!ENTITY outer \"very &inner;\">]><r>&outer;</r>",
  )
  assert_eq(doc.css("r").text(), "very deep")
}

///|
test "an entity that contains itself is refused" {
  assert_eq(
    refused("<!DOCTYPE r [<!ENTITY a \"&b;\"><!ENTITY b \"&a;\">]><r>&a;</r>"),
    true,
  )
}

///|
test "a character reference stays a character, not markup" {
  let doc = loads("<!DOCTYPE r [<!ENTITY e \"&lt;b&gt;\">]><r>&e;</r>")
  assert_eq(doc.css("b").length(), 0)
  assert_eq(doc.css("r").text(), "<b>")
}

///|
test "expansion is bounded, and going past the bound is refused" {
  let fifty = "A".repeat(50)
  let source = "<!DOCTYPE r [<!ENTITY e \"" + fifty + "\">]><r>&e;</r>"
  assert_eq(entity_limit, 1048576)
  assert_eq(loads(source).css("r").text().length(), 50)
  let refused = try {
    ignore(loads(source, entity_limit=10))
    false
  } catch {
    @moonxml.Exceeded(limit~, ..) => limit == 10
    _ => false
  }
  assert_eq(refused, true)
}

///|
test "a declaration gives an element an attribute it did not write" {
  let doc = loads(
    "<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r kind CDATA \"plain\">]><r/>",
  )
  assert_eq(doc.css("r").attr("kind"), Some("plain"))
}

///|
test "a default fills in what the start tag left out, and only that" {
  let doc = loads(
    "<!DOCTYPE r [<!ATTLIST r a CDATA \"one\" b CDATA \"two\">]><r b=\"own\"/>",
  )
  assert_eq(doc.css("r").attr("a"), Some("one"))
  assert_eq(doc.css("r").attr("b"), Some("own"))
}

///|
test "a typed attribute has its whitespace collapsed" {
  let doc = loads(
    "<!DOCTYPE r [<!ATTLIST r list NMTOKENS #IMPLIED>]><r list=\"  a   b  \"/>",
  )
  assert_eq(doc.css("r").attr("list"), Some("a b"))
}

///|
test "a parameter entity stands for declarations" {
  let doc = loads(
    "<!DOCTYPE r [<!ENTITY % decl \"<!ENTITY who 'the reader'>\">%decl;]><r>&who;</r>",
  )
  assert_eq(doc.css("r").text(), "the reader")
}

///|
test "an external entity is not fetched, and is named" {
  let doc = loads(
    "<!DOCTYPE r [<!ENTITY e SYSTEM \"elsewhere.txt\">]><r>a&e;b</r>",
  )
  assert_eq(doc.css("r").text(), "ab")
  assert_eq(doc.unresolved(), ["e"])
}

///|
test "a document that says standalone reads nothing from outside" {
  assert_eq(
    refused(
      "<?xml version=\"1.0\" standalone=\"yes\"?><!DOCTYPE r SYSTEM \"r.dtd\"><r>&e;</r>",
    ),
    true,
  )
}

///|
test "a doctype with an internal subset writes back as it was read" {
  let source = "<!DOCTYPE r [<!ELEMENT r (#PCDATA)><!ATTLIST r a CDATA #IMPLIED>]><r/>"
  assert_eq(loads(source).dumps(), source)
}

///|
test "a bare ampersand is not a reference" {
  assert_eq(refused("<r>a & b</r>"), true)
}

///|
test "an entity cannot be closed by what follows it" {
  assert_eq(refused("<!DOCTYPE r [<!ENTITY e \"<b>\">]><r>&e;</r></b>"), true)
}
