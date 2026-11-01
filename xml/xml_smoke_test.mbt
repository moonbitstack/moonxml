test "xml roundtrip" {
  let text = "<root a=\"1\"><child>text</child></root>"
  let doc = loads(text)
  assert_eq(doc.dumps(), text)
}

test "xml entity internal subset" {
  let text = "<!DOCTYPE r [<!ENTITY hi \"Hello\">]><r>&hi; world</r>"
  let doc = loads(text)
  assert_eq(doc.text(), "Hello world")
}

test "xml namespaces" {
  let text = "<a xmlns=\"u\"><b/></a>"
  let doc = loads(text)
  let root = doc.document_element().unwrap()
  assert_eq(root.name, "{u}a")
  let b = root.children_elements()[0]
  assert_eq(b.name, "{u}b")
}

test "xml malformed" {
  let r = try { ignore(loads("<a><b></a>")) ; false } catch { _ => true }
  assert_eq(r, true)
}
