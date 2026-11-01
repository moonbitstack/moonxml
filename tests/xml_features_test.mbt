test "xml attribute default from ATTLIST" {
  let doc = @xml.loads("<!DOCTYPE r [<!ATTLIST r a CDATA \"d\">]><r/>")
  let root = doc.document_element().unwrap()
  assert_eq(root.attr("a"), Some("d"))
}

test "xml parameter entity in subset" {
  let text = "<!DOCTYPE r [<!ENTITY % e \"<!ENTITY hi 'X'>\"> %e;]><r>&hi;</r>"
  let doc = @xml.loads(text)
  assert_eq(doc.text(), "X")
}

test "xml depth limit" {
  let ok = try {
    ignore(@xml.loads_config("<a><b><c></c></b></a>", 2, 1000000))
    false
  } catch {
    _ => true
  }
  assert_eq(ok, true)
}

test "xml expansion limit" {
  let text = "<!DOCTYPE r [<!ENTITY a \"xxxx\"><!ENTITY b \"&a;&a;&a;&a;\"><!ENTITY c \"&b;&b;&b;&b;\">]><r>&c;</r>"
  let ok = try {
    ignore(@xml.loads_config(text, 512, 10))
    false
  } catch {
    _ => true
  }
  assert_eq(ok, true)
}
