/// Editing invariants.
///
/// The editing verbs are individually simple, but each one has to leave the tree
/// consistent: every child knows its parent, every parent lists the child at the
/// position the child reports, and a node that moves is no longer in two places.
/// These tests check the invariants rather than one expected output per verb, so
/// a change in one verb is caught by every test that touches it.

/// Walk the subtree and report the first inconsistency, or `""`.
fn tree_problem(el : @moonxml.Element) -> String {
  let mut i = 0
  while i < el.children.length() {
    match el.children[i] {
      @moonxml.ElementNode(c) => {
        match c.parent {
          Some(p) => if not(physical_equal(p, el)) {
            return "child " + c.name + " does not point at its parent"
          }
          None => return "child " + c.name + " has no parent"
        }
        if c.index_in_parent() != i {
          return "child " + c.name + " reports index " + c.index_in_parent().to_string()
        }
        let inner = tree_problem(c)
        if inner != "" {
          return inner
        }
      }
      _ => ()
    }
    i = i + 1
  }
  ""
}

fn edited_doc() -> @moonxml.Document {
  @html.loads("<div id=r><p>a</p><p>b</p><span></span></div>")
}

test "edit: a moved node has one parent" {
  let doc = edited_doc()
  let r = doc.css("#r").items[0].as_element().unwrap()
  let ps = doc.css("p")
  let second = ps.items[1].as_element().unwrap()
  // Appending an element that already has a parent moves it.
  r.append(@moonxml.Node::ElementNode(second))
  assert_eq(tree_problem(r), "")
  let names = r.children_elements().map(fn(e) { e.name })
  assert_eq(names.length(), 3)
}

test "edit: prepend, insert and the index they report" {
  let doc = edited_doc()
  let r = doc.css("#r").items[0].as_element().unwrap()
  r.prepend(@moonxml.Node::ElementNode(@moonxml.Element::new("i")))
  assert_eq(tree_problem(r), "")
  assert_eq(r.children_elements()[0].name, "i")
  // Out-of-range indices clamp instead of failing.
  r.insert(99, @moonxml.Node::ElementNode(@moonxml.Element::new("b")))
  r.insert(-5, @moonxml.Node::ElementNode(@moonxml.Element::new("u")))
  assert_eq(tree_problem(r), "")
  assert_eq(r.children_elements()[0].name, "u")
  assert_eq(r.children_elements()[r.children_elements().length() - 1].name, "b")
}

test "edit: insert_before and insert_after on a detached element do nothing" {
  let lonely = @moonxml.Element::new("p")
  lonely.insert_before(@moonxml.Node::ElementNode(@moonxml.Element::new("a")))
  lonely.insert_after(@moonxml.Node::ElementNode(@moonxml.Element::new("b")))
  lonely.replace_with(@moonxml.Node::ElementNode(@moonxml.Element::new("c")))
  assert_eq(lonely.children.length(), 0)
  assert_eq(lonely.parent.is_none(), true)
}

test "edit: replace_with keeps the position and clears the old parent" {
  let doc = edited_doc()
  let r = doc.css("#r").items[0].as_element().unwrap()
  let first = r.children_elements()[0]
  first.replace_with(@moonxml.Node::ElementNode(@moonxml.Element::new("h1")))
  assert_eq(tree_problem(r), "")
  assert_eq(r.children_elements()[0].name, "h1")
  assert_eq(first.parent.is_none(), true)
  assert_eq(doc.css("h1").length(), 1)
}

test "edit: remove returns the subtree and detaches it" {
  let doc = edited_doc()
  let first = doc.css("p").items[0].as_element().unwrap()
  let got = first.remove()
  assert_eq(got.is_element(), true)
  assert_eq(first.parent.is_none(), true)
  assert_eq(doc.css("p").length(), 1)
  // Removing twice is harmless.
  let _ = first.remove()
  assert_eq(first.parent.is_none(), true)
}

test "edit: unwrap splices children in place" {
  let doc = @html.loads("<div><b>1<i>2</i>3</b>4</div>")
  let b = doc.css("b").items[0].as_element().unwrap()
  b.unwrap()
  assert_eq(tree_problem(doc.root), "")
  let div = doc.css("div").items[0].as_element().unwrap()
  assert_eq(div.text(), "1234")
  assert_eq(div.children_elements()[0].name, "i")
  assert_eq(b.parent.is_none(), true)
  assert_eq(b.children.length(), 0)
}

test "edit: wrap gives the wrapper the old position" {
  let doc = edited_doc()
  let first = doc.css("p").items[0].as_element().unwrap()
  let wrapper = first.wrap("section")
  assert_eq(tree_problem(doc.root), "")
  assert_eq(wrapper.name, "section")
  assert_eq(wrapper.children_elements()[0].name, "p")
  assert_eq(doc.css("#r").items[0].as_element().unwrap().children_elements()[0].name, "section")
}

test "edit: set_children repairs every parent pointer" {
  let doc = edited_doc()
  let r = doc.css("#r").items[0].as_element().unwrap()
  let a = @moonxml.Element::new("a")
  let b = @moonxml.Element::new("b")
  r.set_children([
    @moonxml.Node::ElementNode(a),
    @moonxml.Node::TextNode("t"),
    @moonxml.Node::ElementNode(b),
  ])
  assert_eq(tree_problem(r), "")
  assert_eq(r.children.length(), 3)
  assert_eq(r.text(), "t")
}

test "edit: clear and set_text" {
  let doc = edited_doc()
  let r = doc.css("#r").items[0].as_element().unwrap()
  r.clear()
  assert_eq(r.children.length(), 0)
  assert_eq(r.text(), "")
  r.set_text("x")
  assert_eq(r.children.length(), 1)
  assert_eq(r.text(), "x")
  assert_eq(tree_problem(r), "")
}

test "edit: smooth fuses adjacent text and drops empty text" {
  let doc = @html.loads("<div></div>")
  let div = doc.css("div").items[0].as_element().unwrap()
  div.append(@moonxml.Node::TextNode("a"))
  div.append(@moonxml.Node::TextNode(""))
  div.append(@moonxml.Node::TextNode("b"))
  div.append(@moonxml.Node::ElementNode(@moonxml.Element::new("i")))
  div.append(@moonxml.Node::TextNode("c"))
  div.smooth()
  assert_eq(div.children.length(), 3)
  assert_eq(div.text(), "abc")
  // Smoothing twice changes nothing.
  div.smooth()
  assert_eq(div.children.length(), 3)
}

test "edit: clone_deep is independent of the original" {
  let doc = edited_doc()
  let r = doc.css("#r").items[0].as_element().unwrap()
  let copy = @moonxml.Node::ElementNode(r).clone_deep()
  let c = copy.as_element().unwrap()
  assert_eq(c.text(), "ab")
  c.set_text("changed")
  assert_eq(c.text(), "changed")
  assert_eq(r.text(), "ab")
  assert_eq(c.parent.is_none(), true)
  assert_eq(tree_problem(c), "")
}

test "edit: classes are a set, not a list" {
  let doc = edited_doc()
  let r = doc.css("#r").items[0].as_element().unwrap()
  r.add_class("x")
  r.add_class("x")
  assert_eq(r.attr("class"), Some("x"))
  r.add_class("y")
  assert_eq(r.attr("class"), Some("x y"))
  assert_eq(r.has_class("y"), true)
  assert_eq(r.has_class("z"), false)
  r.remove_class("x")
  assert_eq(r.attr("class"), Some("y"))
  r.remove_class("y")
  // The attribute goes away with its last class.
  assert_eq(r.attr("class"), None)
}

test "edit: selection verbs apply to every selected node" {
  let doc = edited_doc()
  doc.css("p").set_text("z")
  assert_eq(doc.css("p").text(), "zz")
  doc.css("p").add_class("k")
  assert_eq(doc.css("p.k").length(), 2)
  doc.css("p").wrap("div")
  assert_eq(doc.css("div > p").length(), 2)
  doc.css("p").unwrap()
  assert_eq(doc.css("div > p").length(), 0)
  let _ = doc.css("p").remove()
  assert_eq(doc.css("p").length(), 0)
  assert_eq(tree_problem(doc.root), "")
}

test "edit: siblings and index_in_parent agree" {
  let doc = @html.loads("<div><a></a><b></b><c></c></div>")
  let b = doc.css("b").items[0].as_element().unwrap()
  assert_eq(b.index_in_parent(), 1)
  assert_eq(b.previous_element_sibling().unwrap().name, "a")
  assert_eq(b.next_element_sibling().unwrap().name, "c")
  let a = doc.css("a").items[0].as_element().unwrap()
  assert_eq(a.previous_element_sibling().is_none(), true)
  let c = doc.css("c").items[0].as_element().unwrap()
  assert_eq(c.next_element_sibling().is_none(), true)
  assert_eq(b.parent.unwrap().name, "div")
}

test "edit: repairs are recorded, not hidden" {
  // The HTML parser repairs what it has to; the count is how a caller finds out
  // that the document it read is not the document that was written.
  let clean = @html.loads("<div><p>x</p></div>")
  assert_eq(clean.repairs().count(), 0)
  assert_eq(clean.repairs().log().length(), 0)
  // A stray end tag, a `</br>`, and an end tag that names nothing all count.
  let stray = @html.loads("<div></span></div>")
  assert_eq(stray.repairs().count() > 0, true)
  let br = @html.loads("<div></br></div>")
  assert_eq(br.repairs().count() > 0, true)
  let orphan_p = @html.loads("<div></p></div>")
  assert_eq(orphan_p.repairs().count() > 0, true)
  // The log says how many, and only exists when something happened.
  assert_eq(stray.repairs().log().length(), 1)
  assert_eq(stray.repairs().log()[0].contains("repaired"), true)
}
