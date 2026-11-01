/// Active formatting elements and the adoption agency algorithm.
///
/// This is the real algorithm: a list with markers and the Noah's Ark clause,
/// reconstruction before inserting character data, and the eight-step adoption
/// agency for misnested formatting tags, including the inner loop's
/// three-iteration limit, the bookmark, the shallow clones and the reparenting.

enum AFEItem {
  AFElement(@moonxml.Element)
  AFMarker
}

fn clone_shallow(e : @moonxml.Element) -> @moonxml.Element {
  let c = @moonxml.Element::with_attrs(e.name, e.attrs.copy())
  c.set_closed(e.closed)
  c
}

fn same_fmt(a : @moonxml.Element, b : @moonxml.Element) -> Bool {
  if a.name != b.name || a.attrs.length() != b.attrs.length() {
    return false
  }
  let mut i = 0
  while i < a.attrs.length() {
    let (ak, av) = a.attrs[i]
    let (bk, bv) = b.attrs[i]
    if ak != bk || av != bv {
      return false
    }
    i = i + 1
  }
  true
}

/// The "any other end tag" step: close the nearest matching element, but never
/// look past a special element.
fn H::any_other_end_tag(self : H, name : String) -> Unit {
  let mut i = self.stack.length() - 1
  while i >= 0 {
    let node = self.stack[i]
    let l = local_of(node.name).to_lower()
    if l == name {
      self.generate_implied_end(name)
      self.pop_until(name)
      return
    }
    if is_special_node(l, ns_of(node.name)) {
      return
    }
    i = i - 1
  }
}

/// Insert an element into a common ancestor, honouring foster parenting when
/// that ancestor is a table part.
fn H::append_at(self : H, common : @moonxml.Element, el : @moonxml.Element) -> Unit {
  let l = local_of(common.name).to_lower()
  if is_table_scope(l) {
    let ci = self.index_of(common)
    let mut i = if ci < 0 { self.stack.length() - 1 } else { ci }
    while i >= 0 {
      if local_of(self.stack[i].name).to_lower() == "table" {
        let t = self.stack[i]
        t.insert_before(@moonxml.Node::ElementNode(el))
        return
      }
      i = i - 1
    }
  }
  common.append(@moonxml.Node::ElementNode(el))
}

fn H::adoption(self : H, subject : String) -> Unit {
  let cur = self.cur()
  if local_of(cur.name).to_lower() == subject && not(self.afe_has(cur)) && not(self.has_open("template")) {
    self.pop()
    return
  }
  let mut outer = 0
  while outer < 8 {
    outer = outer + 1
    let fi = self.afe_last_named(subject)
    if fi < 0 {
      self.any_other_end_tag(subject)
      return
    }
    let fmt = match self.afe[fi] {
      AFElement(e) => e
      AFMarker => return
    }
    let si = self.index_of(fmt)
    if si < 0 {
      let _ = self.afe.remove(fi)
      return
    }
    if not(self.el_in_scope(fmt, ScDefault)) {
      return
    }
    // The furthest block is the first special element above the formatting
    // element: the deepest block the misnested tag reaches into.
    let mut fb_el : @moonxml.Element? = None
    let mut k = si + 1
    while k < self.stack.length() {
      let node = self.stack[k]
      if is_special_node(local_of(node.name).to_lower(), ns_of(node.name)) {
        fb_el = Some(node)
        break
      }
      k = k + 1
    }
    let fb = match fb_el {
      None => {
        // No block: pop up to and including the formatting element.
        self.pop_until_index(si)
        self.afe_remove(fmt)
        return
      }
      Some(f) => f
    }
    let common = self.stack[si - 1]
    let mut bookmark = self.afe_index(fmt)
    let mut node = fb
    let mut last = fb
    let mut inner = 0
    while true {
      inner = inner + 1
      let ni = self.index_of(node) - 1
      if ni < 0 {
        break
      }
      node = self.stack[ni]
      if physical_equal(node, fmt) {
        break
      }
      let ai = self.afe_index(node)
      if inner > 3 && ai >= 0 {
        let _ = self.afe.remove(ai)
        if ai < bookmark {
          bookmark = bookmark - 1
        }
        continue
      }
      if ai < 0 {
        self.remove_from_stack(node)
        continue
      }
      // Clone the node, keeping its place in both lists.
      let cl = clone_shallow(node)
      let ai2 = self.afe_index(node)
      self.afe[ai2] = AFElement(cl)
      let ni2 = self.index_of(node)
      self.stack[ni2] = cl
      node = cl
      if physical_equal(last, fb) {
        bookmark = ai2 + 1
      }
      let _ = last.remove()
      node.append(@moonxml.Node::ElementNode(last))
      last = node
    }
    let _ = last.remove()
    self.append_at(common, last)
    // Rebuild the formatting element around the block's children.
    let clone_fmt = clone_shallow(fmt)
    let kids = fb.children.copy()
    fb.set_children([])
    for c in kids {
      clone_fmt.append(c)
    }
    fb.append(@moonxml.Node::ElementNode(clone_fmt))
    let fmi = self.afe_index(fmt)
    if fmi >= 0 {
      let _ = self.afe.remove(fmi)
      if fmi < bookmark {
        bookmark = bookmark - 1
      }
    }
    let bm = if bookmark < 0 {
      0
    } else if bookmark > self.afe.length() {
      self.afe.length()
    } else {
      bookmark
    }
    self.afe.insert(bm, AFElement(clone_fmt))
    self.remove_from_stack(fmt)
    let fi2 = self.index_of(fb)
    let pos = if fi2 < 0 { self.stack.length() } else { fi2 + 1 }
    self.stack.insert(pos, clone_fmt)
  }
}
