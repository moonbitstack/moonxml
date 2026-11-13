// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Writing XML back is where a tree proves it kept what it read: attribute
/// order, quoting, CDATA, comments, instructions, the doctype, and the two
/// ways of closing an element.

///|
test "an xml:lang keeps its prefix and needs no declaration" {
  let doc = loads("<a xml:lang=\"en\"><b xml:lang=\"fr\"/></a>")
  assert_eq(doc.dumps(), "<a xml:lang=\"en\"><b xml:lang=\"fr\"/></a>")
}

///|
test "a name in a space nothing declares is declared before it is used" {
  // A tree built by hand can carry an attribute in a space the document never
  // declared; the writer earns the declaration and puts it on the element it
  // covers rather than after the attribute that needs it.
  let element = @moonxml.Element::new(
    "a",
    attrs=[("{urn:x}k", "v"), ("plain", "1")],
    closed=true,
  )
  assert_eq(
    @moonxml.dumps(ElementNode(element)),
    "<a xmlns:ns1=\"urn:x\" ns1:k=\"v\" plain=\"1\"/>",
  )
}

///|
test "attribute order is the document's order" {
  let doc = loads("<a z=\"1\" a=\"2\" m=\"3\"/>")
  assert_eq(doc.dumps(), "<a z=\"1\" a=\"2\" m=\"3\"/>")
}

///|
test "a character reference is decoded, as a DOM means it" {
  let doc = loads("<a>&amp;&#65;&#x42;</a>")
  assert_eq(doc.dumps(), "<a>&amp;AB</a>")
}

///|
test "an attribute's quoting is normalized, not preserved" {
  // The tree holds the value, not the syntax that spelled it: single quotes
  // come back as double, which is why the writer's byte-for-byte promise is
  // about the document's meaning as well as its bytes.
  let doc = loads("<a b='single'/>")
  assert_eq(doc.dumps(), "<a b=\"single\"/>")
}

///|
test "a declared entity is expanded, and its declaration stays" {
  let doc = loads(
    "<!DOCTYPE a [<!ENTITY greet \"hello\">]><a>&greet; world</a>",
  )
  assert_eq(
    doc.dumps(),
    "<!DOCTYPE a [<!ENTITY greet \"hello\">]><a>hello world</a>",
  )
}

///|
test "cdata, comments, instructions and the doctype survive" {
  let text = "<?xml version=\"1.0\"?><!DOCTYPE a><a><![CDATA[x < y]]><!-- note --><?go now?></a>"
  let doc = loads(text)
  assert_eq(doc.dumps(), text)
}

///|
test "the two ways of closing stay the two ways" {
  let text = "<a><b/><c></c></a>"
  let doc = loads(text)
  assert_eq(doc.dumps(), text)
}

///|
test "whitespace between elements is content, and stays" {
  let text = "<a>\n  <b/>\n</a>"
  let doc = loads(text)
  assert_eq(doc.dumps(), text)
}

///|
test "a namespace prefix the document chose is the one written back" {
  let text = "<x:a xmlns:x=\"urn:x\"><x:b y=\"1\"/></x:a>"
  let doc = loads(text)
  assert_eq(doc.dumps(), text)
}
