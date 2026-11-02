// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The editing verbs are each small, and each one has to leave the tree
// consistent: every child knows its parent, every parent lists the child at the
// position the child reports, and a node that moves is no longer in two places.
// These tests check the invariant rather than one expected output per verb, so a
// change in one verb is caught by every test that touches it.

///|
/// Walk the subtree and report the first inconsistency, or `""`.
fn tree_problem(element : Element) -> String {
  let mut i = 0
  while i < element.children.length() {
    match element.children[i] {
      ElementNode(child) => {
        match child.parent {
          Some(parent) =>
            if !physical_equal(parent, element) {
              return "child " + child.name + " does not point at its parent"
            }
          None => return "child " + child.name + " has no parent"
        }
        if child.index_in_parent() != i {
          return "child " +
            child.name +
            " reports index " +
            child.index_in_parent().to_string()
        }
        let inner = tree_problem(child)
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

///|
/// `<div id=r><p>a</p><p>b</p><span></span></div>`, built by hand so that this
/// file needs no parser.
fn invariants_doc() -> Document {
  let doc = Document::new()
  let root = Element::new("div", attrs=[("id", "r")])
  root.append(ElementNode(Element::new("p", children=[TextNode("a")])))
  root.append(ElementNode(Element::new("p", children=[TextNode("b")])))
  root.append(ElementNode(Element::new("span")))
  doc.root.append(ElementNode(root))
  doc
}

///|
fn only_id(doc : Document, id : String) -> Element {
  match doc.by_id(id).items {
    [ElementNode(element), ..] => element
    _ => abort("no element with id \{id}")
  }
}

///|
test "edit: a moved node has one parent" {
  let doc = invariants_doc()
  let root = only_id(doc, "r")
  let second = match doc.css("p").items[1] {
    ElementNode(element) => element
    _ => abort("the second paragraph is not an element")
  }
  // Appending an element that already sits in the tree moves it.
  root.append(ElementNode(second))
  assert_eq(tree_problem(root), "")
  // It moved rather than being copied: three children, not four.
  assert_eq(root.child_elements().length(), 3)
  assert_eq(
    root.child_elements().map(fn(element) { element.name }).join(","),
    "p,span,p",
  )
}

///|
test "edit: prepend, insert and the index they report" {
  let doc = invariants_doc()
  let root = only_id(doc, "r")
  root.prepend(ElementNode(Element::new("i")))
  assert_eq(tree_problem(root), "")
  assert_eq(root.child_elements()[0].name, "i")
  // An index past either end clamps to it instead of failing.
  root.insert(99, ElementNode(Element::new("b")))
  root.insert(-5, ElementNode(Element::new("u")))
  assert_eq(tree_problem(root), "")
  assert_eq(root.child_elements()[0].name, "u")
  assert_eq(root.child_elements()[root.children.length() - 1].name, "b")
}

///|
test "edit: insert_before and insert_after on a detached element do nothing" {
  let lonely = Element::new("p")
  assert_eq(lonely.insert_before(ElementNode(Element::new("a"))), false)
  assert_eq(lonely.insert_after(ElementNode(Element::new("b"))), false)
  assert_eq(lonely.replace_with(ElementNode(Element::new("c"))), false)
  assert_eq(lonely.children.length(), 0)
  assert_eq(lonely.parent is None, true)
}

///|
test "edit: replace_with keeps the position and clears the old parent" {
  let doc = invariants_doc()
  let root = only_id(doc, "r")
  let first = root.child_elements()[0]
  assert_eq(first.replace_with(ElementNode(Element::new("h1"))), true)
  assert_eq(tree_problem(root), "")
  assert_eq(root.child_elements()[0].name, "h1")
  assert_eq(first.parent is None, true)
  assert_eq(doc.css("h1").length(), 1)
}

///|
test "edit: remove detaches the subtree and answers true" {
  let doc = invariants_doc()
  let first = match doc.css("p").items[0] {
    ElementNode(element) => element
    _ => abort("not an element")
  }
  assert_eq(first.remove(), true)
  assert_eq(first.parent is None, true)
  assert_eq(doc.css("p").length(), 1)
  // The subtree it was is still whole, and removing twice is harmless.
  assert_eq(first.text(), "a")
  assert_eq(first.remove(), false)
  assert_eq(first.parent is None, true)
}

///|
test "edit: unwrap splices the children in place" {
  let doc = Document::new()
  let div = Element::new("div")
  let bold = Element::new("b", children=[TextNode("1")])
  bold.append(ElementNode(Element::new("i", children=[TextNode("2")])))
  bold.append(TextNode("3"))
  div.append(ElementNode(bold))
  div.append(TextNode("4"))
  doc.root.append(ElementNode(div))
  assert_eq(bold.unwrap(), true)
  assert_eq(tree_problem(doc.root), "")
  assert_eq(div.text(), "1234")
  assert_eq(div.child_elements()[0].name, "i")
  assert_eq(bold.parent is None, true)
  assert_eq(bold.children.length(), 0)
}

///|
test "edit: wrap gives the wrapper the old position" {
  let doc = invariants_doc()
  let root = only_id(doc, "r")
  let first = root.child_elements()[0]
  let wrapper = first.wrap("section").unwrap()
  assert_eq(tree_problem(doc.root), "")
  assert_eq(wrapper.name, "section")
  assert_eq(wrapper.child_elements()[0].name, "p")
  assert_eq(root.child_elements()[0].name, "section")
}

///|
test "edit: set_children repairs every parent pointer" {
  let doc = invariants_doc()
  let root = only_id(doc, "r")
  let old = root.child_elements()[0]
  let a = Element::new("a")
  let b = Element::new("b")
  root.set_children([ElementNode(a), TextNode("t"), ElementNode(b)])
  assert_eq(tree_problem(root), "")
  assert_eq(root.children.length(), 3)
  assert_eq(root.text(), "t")
  // What the element held is let go, and what came in is claimed.
  assert_eq(old.parent is None, true)
  assert_eq(a.parent is Some(_), true)
  assert_eq(b.index_in_parent(), 2)
}

///|
test "edit: clear and set_text let the old children go" {
  let doc = invariants_doc()
  let root = only_id(doc, "r")
  let first = root.child_elements()[0]
  root.clear()
  assert_eq(root.children.length(), 0)
  assert_eq(root.text(), "")
  assert_eq(first.parent is None, true)
  root.set_text("x")
  assert_eq(root.children.length(), 1)
  assert_eq(root.text(), "x")
  assert_eq(tree_problem(root), "")
}

///|
test "edit: smooth fuses adjacent text and drops empty text" {
  let doc = Document::new()
  let div = Element::new("div")
  doc.root.append(ElementNode(div))
  div.append(TextNode("a"))
  div.append(TextNode(""))
  div.append(TextNode("b"))
  div.append(ElementNode(Element::new("i")))
  div.append(TextNode("c"))
  div.append(TextNode(""))
  div.smooth()
  assert_eq(div.text(), "abc")
  assert_eq(div.children.length(), 3)
  // Smoothing twice changes nothing.
  div.smooth()
  assert_eq(div.children.length(), 3)
}

///|
test "edit: clone_deep is independent of the original" {
  let doc = invariants_doc()
  let root = only_id(doc, "r")
  let copy = match ElementNode(root).clone_deep() {
    ElementNode(element) => element
    _ => abort("a copy of an element is an element")
  }
  assert_eq(copy.text(), "ab")
  copy.set_text("changed")
  assert_eq(copy.text(), "changed")
  assert_eq(root.text(), "ab")
  assert_eq(copy.parent is None, true)
  assert_eq(tree_problem(copy), "")
  // The attributes travel with the copy.
  assert_eq(copy.attr("id"), Some("r"))
}

///|
test "edit: classes are a set, not a list" {
  let doc = invariants_doc()
  let root = only_id(doc, "r")
  root.add_class("x")
  root.add_class("x")
  assert_eq(root.attr("class"), Some("x"))
  root.add_class("y")
  assert_eq(root.attr("class"), Some("x y"))
  assert_eq(root.has_class("y"), true)
  assert_eq(root.has_class("z"), false)
  root.remove_class("x")
  assert_eq(root.attr("class"), Some("y"))
  root.remove_class("y")
  // The attribute stays, empty: it was written by the caller, and emptying a
  // list is not the same edit as deleting the attribute.
  assert_eq(root.classes().is_empty(), true)
  assert_eq(root.attr("class"), Some(""))
}

///|
test "edit: selection verbs apply to every selected node" {
  let doc = invariants_doc()
  doc.css("p").set_text("z")
  assert_eq(doc.css("p").text(), "zz")
  doc.css("p").add_class("k")
  assert_eq(doc.css("p.k").length(), 2)
  doc.css("p").wrap("div")
  assert_eq(doc.css("div > p").length(), 2)
  doc.css("p").unwrap()
  assert_eq(doc.css("div > p").length(), 0)
  doc.css("p").remove()
  assert_eq(doc.css("p").length(), 0)
  assert_eq(tree_problem(doc.root), "")
}

///|
test "edit: siblings and index_in_parent agree" {
  let doc = Document::new()
  let div = Element::new("div")
  let a = Element::new("a")
  let b = Element::new("b")
  let c = Element::new("c")
  div.append(ElementNode(a))
  div.append(ElementNode(b))
  div.append(ElementNode(c))
  doc.root.append(ElementNode(div))
  assert_eq(b.index_in_parent(), 1)
  assert_eq(b.previous_element_sibling().unwrap().name, "a")
  assert_eq(b.next_element_sibling().unwrap().name, "c")
  assert_eq(a.previous_element_sibling() is None, true)
  assert_eq(c.next_element_sibling() is None, true)
  // A text node between two elements is skipped, and a detached element has no
  // position at all.
  div.insert(1, TextNode(" "))
  assert_eq(b.index_in_parent(), 2)
  assert_eq(b.previous_element_sibling().unwrap().name, "a")
  assert_eq(Element::new("d").index_in_parent(), -1)
}
