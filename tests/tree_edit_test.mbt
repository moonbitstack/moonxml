test "append and parent pointer" {
  let doc = @xml.loads("<root><a>1</a></root>")
  let root = doc.document_element().unwrap()
  let b = @moonxml.Element::new("b")
  b.set_text("2")
  root.append(@moonxml.Node::ElementNode(b))
  assert_eq(doc.dumps(), "<root><a>1</a><b>2</b></root>")
  match b.parent {
    Some(p) => assert_eq(p.name, "root")
    None => assert_eq(false, true)
  }
}

test "prepend and insert" {
  let doc = @xml.loads("<root><a></a></root>")
  let root = doc.document_element().unwrap()
  let z = @moonxml.Element::new("z")
  root.prepend(@moonxml.Node::ElementNode(z))
  let y = @moonxml.Element::new("y")
  root.insert(1, @moonxml.Node::ElementNode(y))
  assert_eq(doc.dumps(), "<root><z></z><y></y><a></a></root>")
}

test "insert_before and insert_after" {
  let doc = @xml.loads("<root><a></a></root>")
  let a = doc.css("a").items[0].as_element().unwrap()
  a.insert_before(@moonxml.Node::ElementNode(@moonxml.Element::new("q")))
  a.insert_after(@moonxml.Node::ElementNode(@moonxml.Element::new("r")))
  assert_eq(doc.dumps(), "<root><q></q><a></a><r></r></root>")
}

test "replace_with" {
  let doc = @xml.loads("<root><a>1</a></root>")
  let a = doc.css("a").items[0].as_element().unwrap()
  let s = @moonxml.Element::new("s")
  s.set_text("2")
  a.replace_with(@moonxml.Node::ElementNode(s))
  assert_eq(doc.dumps(), "<root><s>2</s></root>")
}

test "remove" {
  let doc = @xml.loads("<root><a>1</a><b>2</b></root>")
  let a = doc.css("a").items[0].as_element().unwrap()
  let _ = a.remove()
  assert_eq(doc.dumps(), "<root><b>2</b></root>")
}

test "unwrap" {
  let doc = @xml.loads("<root><a><b>1</b><c>2</c></a></root>")
  let a = doc.css("a").items[0].as_element().unwrap()
  a.unwrap()
  assert_eq(doc.dumps(), "<root><b>1</b><c>2</c></root>")
  let b = doc.css("b").items[0].as_element().unwrap()
  match b.parent {
    Some(p) => assert_eq(p.name, "root")
    None => assert_eq(false, true)
  }
}

test "wrap" {
  let doc = @xml.loads("<root><a>1</a></root>")
  let a = doc.css("a").items[0].as_element().unwrap()
  let _ = a.wrap("w")
  assert_eq(doc.dumps(), "<root><w><a>1</a></w></root>")
}

test "clear and set_text" {
  let doc = @xml.loads("<root><a>1<b>2</b></a></root>")
  let a = doc.css("a").items[0].as_element().unwrap()
  a.clear()
  assert_eq(doc.dumps(), "<root><a></a></root>")
  a.set_text("z")
  assert_eq(doc.dumps(), "<root><a>z</a></root>")
}

test "smooth fuses text" {
  let doc = @xml.loads("<root><a></a></root>")
  let a = doc.css("a").items[0].as_element().unwrap()
  a.append(@moonxml.Node::TextNode("x"))
  a.append(@moonxml.Node::TextNode("y"))
  a.smooth()
  assert_eq(doc.dumps(), "<root><a>xy</a></root>")
}

test "attributes and classes" {
  let doc = @xml.loads("<root><a class=\"one\"></a></root>")
  let a = doc.css("a").items[0].as_element().unwrap()
  assert_eq(a.has_class("one"), true)
  a.add_class("two")
  assert_eq(a.attr("class"), Some("one two"))
  a.remove_class("one")
  assert_eq(a.attr("class"), Some("two"))
  a.set_attr("id", "x")
  assert_eq(a.attr("id"), Some("x"))
  a.remove_attr("id")
  assert_eq(a.attr("id"), None)
}
