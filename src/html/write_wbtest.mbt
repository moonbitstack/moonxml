// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The HTML writer's promises: a void element has no closing tag, a foreign
/// element keeps its own spelling, a template's contents stay inside it, and
/// the characters WHATWG asks to escape are escaped.

///|
test "void elements have no closing tag, in framesets too" {
  let plain = loads("<br><img src=x><hr>")
  assert_eq(
    plain.dumps(),
    "<html><head></head><body><br><img src=\"x\"><hr></body></html>",
  )
  let framed = loads("<frameset><frame src=a></frameset>")
  assert_eq(
    framed.dumps(),
    "<html><head></head><frameset><frame src=\"a\"></frameset></html>",
  )
}

///|
test "xml:lang keeps its prefix in foreign content" {
  let doc = loads(
    "<body xml:lang=en><svg><g xml:lang=fr xlink:href=foo></g></svg>",
  )
  assert_eq(
    doc.dumps(),
    "<html><head></head><body xml:lang=\"en\"><svg><g xml:lang=\"fr\" xlink:href=\"foo\"></g></svg></body></html>",
  )
}

///|
test "a template's contents are written inside the template" {
  let doc = loads("<template><li>x</li></template>")
  assert_eq(
    doc.dumps(),
    "<html><head><template><li>x</li></template></head><body></body></html>",
  )
}

///|
test "a non-breaking space is written as its reference" {
  let doc = loads("<p>&nbsp; &copy; &#x1F600;</p>")
  assert_eq(
    doc.dumps(),
    "<html><head></head><body><p>&nbsp; © 😀</p></body></html>",
  )
}

///|
test "raw text elements keep the characters they held" {
  let doc = loads("<script>if (a < b && c > d) x();</script>")
  assert_eq(
    doc.dumps(),
    "<html><head><script>if (a < b && c > d) x();</script></head><body></body></html>",
  )
}

///|
test "a script-free noscript's content is markup" {
  let doc = loads("<noscript><p>x</p></noscript>")
  assert_eq(
    doc.dumps(),
    "<html><head><noscript></noscript></head><body><p>x</p></body></html>",
  )
}
