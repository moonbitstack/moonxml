/// Active formatting elements and the adoption agency algorithm.
///
/// This is the real algorithm, not a heuristic: a list of active formatting
/// elements with the Noah's Ark clause, reconstruction of that list before
/// inserting characters, and the eight-step adoption agency for misnested
/// formatting tags (with the inner loop's three-iteration limit, the bookmark,
/// cloning, reparenting and insertion of the clone).
///
/// It is integrated into the simplified insertion model rather than a full set
/// of insertion modes; see `tasks/html-full-conformance.md` for the remaining
/// work. The parts implemented here match the spec's examples.

enum AFEItem {
  AFElement(@moonxml.Element)
  AFMarker
}

fn formatting_tag(t : String) -> Bool {
  if t == "a" || t == "b" || t == "big" || t == "code" {
    return true
  }
  if t == "em" || t == "font" || t == "i" || t == "nobr" {
    return true
  }
  t == "s" || t == "small" || t == "strike" || t == "strong" || t == "tt" || t == "u"
}

fn is_special_local(l : String) -> Bool {
  match l {
    "address" | "applet" | "area" | "article" | "aside" | "base" | "basefont" | "bgsound" |
    "blockquote" | "body" | "br" | "button" | "caption" | "center" | "col" | "colgroup" |
    "dd" | "details" | "dir" | "div" | "dl" | "dt" | "embed" | "fieldset" | "figcaption" |
    "figure" | "footer" | "form" | "frame" | "frameset" | "h1" | "h2" | "h3" | "h4" | "h5" |
    "h6" | "head" | "header" | "hgroup" | "hr" | "html" | "iframe" | "img" | "input" |
    "keygen" | "li" | "link" | "listing" | "main" | "marquee" | "menu" | "meta" | "nav" |
    "noembed" | "noframes" | "noscript" | "object" | "ol" | "p" | "param" | "plaintext" |
    "pre" | "script" | "section" | "select" | "source" | "style" | "summary" | "table" |
    "tbody" | "td" | "template" | "textarea" | "tfoot" | "th" | "thead" | "title" | "tr" |
    "track" | "ul" | "wbr" | "xmp" => true
    _ => false
  }
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

fn H::stack_index(self : H, el : @moonxml.Element) -> Int {
  let mut i = 0
  for s in self.stack {
    if physical_equal(s, el) {
      return i
    }
    i = i + 1
  }
  -1
}

fn H::in_scope(self : H, el : @moonxml.Element) -> Bool {
  let mut i = self.stack.length() - 1
  while i >= 0 {
    let cur = self.stack[i]
    if physical_equal(cur, el) {
      return true
    }
    let l = local_of(cur.name).to_lower()
    if l == "applet" || l == "caption" || l == "html" || l == "table" || l == "td" || l == "th" || l == "marquee" || l == "object" || l == "template" {
      return false
    }
    i = i - 1
  }
  false
}

fn H::afe_index(self : H, el : @moonxml.Element) -> Int {
  let mut i = 0
  for item in self.afe {
    match item {
      AFElement(e) => if physical_equal(e, el) {
        return i
      }
      AFMarker => ()
    }
    i = i + 1
  }
  -1
}

fn H::afe_has(self : H, el : @moonxml.Element) -> Bool {
  self.afe_index(el) >= 0
}

fn H::afe_remove(self : H, el : @moonxml.Element) -> Unit {
  let i = self.afe_index(el)
  if i >= 0 {
    let _ = self.afe.remove(i)
  }
}

fn H::afe_add(self : H, el : @moonxml.Element) -> Unit {
  // Noah's Ark: drop the earliest of four equal entries since the last marker.
  let equals : Array[Int] = []
  let mut i = self.afe.length() - 1
  let mut stop = false
  while i >= 0 && not(stop) {
    match self.afe[i] {
      AFMarker => stop = true
      AFElement(e) => if same_fmt(e, el) {
        equals.push(i)
      }
    }
    i = i - 1
  }
  if equals.length() >= 3 {
    let earliest = equals[equals.length() - 1]
    let _ = self.afe.remove(earliest)
  }
  self.afe.push(AFElement(el))
}

fn H::afe_find_last(self : H, subject : String) -> Int {
  let mut i = self.afe.length() - 1
  while i >= 0 {
    match self.afe[i] {
      AFMarker => return -1
      AFElement(e) => if local_of(e.name).to_lower() == subject {
        return i
      }
    }
    i = i - 1
  }
  -1
}

fn H::reconstruct(self : H) -> Unit {
  if self.afe.length() == 0 {
    return
  }
  let last_item = self.afe[self.afe.length() - 1]
  match last_item {
    AFMarker => return
    AFElement(e) => if self.stack_index(e) >= 0 {
      return
    }
  }
  let mut start = self.afe.length() - 1
  let mut j = start
  let mut stop = false
  while j > 0 && not(stop) {
    match self.afe[j - 1] {
      AFMarker => stop = true
      AFElement(e) => if self.stack_index(e) >= 0 {
        stop = true
      } else {
        start = j - 1
        j = j - 1
      }
    }
  }
  let mut k = start
  while k < self.afe.length() {
    match self.afe[k] {
      AFElement(e) => {
        let c = clone_shallow(e)
        self.current().append(@moonxml.Node::ElementNode(c))
        self.push(c)
        self.afe[k] = AFElement(c)
      }
      AFMarker => ()
    }
    k = k + 1
  }
}

fn H::any_other_end_tag(self : H, name : String) -> Unit {
  let mut i = self.stack.length() - 1
  while i >= 0 {
    let l = local_of(self.stack[i].name).to_lower()
    if l == name {
      let mut n = self.stack.length()
      while n > i {
        let top = self.current()
        self.pop()
        self.afe_remove(top)
        n = n - 1
      }
      return
    }
    i = i - 1
  }
}

fn H::insert_into_common(self : H, common : @moonxml.Element, el : @moonxml.Element) -> Unit {
  let l = local_of(common.name).to_lower()
  if is_table_scope(l) {
    match self.find_table_for(common) {
      Some(t) => {
        let _ = t.insert_before(@moonxml.Node::ElementNode(el))
        return
      }
      None => ()
    }
  }
  common.append(@moonxml.Node::ElementNode(el))
}

fn H::find_table_for(self : H, common : @moonxml.Element) -> @moonxml.Element? {
  let ci = self.stack_index(common)
  let mut i = if ci < 0 { self.stack.length() - 1 } else { ci }
  while i >= 0 {
    if local_of(self.stack[i].name).to_lower() == "table" {
      return Some(self.stack[i])
    }
    i = i - 1
  }
  None
}

fn H::adoption(self : H, subject : String) -> Unit {
  let cur = self.current()
  if local_of(cur.name).to_lower() == subject && not(self.afe_has(cur)) {
    self.pop()
    return
  }
  let mut outer = 0
  while outer < 8 {
    outer = outer + 1
    let fi = self.afe_find_last(subject)
    if fi < 0 {
      self.any_other_end_tag(subject)
      return
    }
    let fmt = match self.afe[fi] {
      AFElement(e) => e
      AFMarker => return
    }
    let si = self.stack_index(fmt)
    if si < 0 {
      let _ = self.afe.remove(fi)
      return
    }
    if not(self.in_scope(fmt)) {
      return
    }
    // Furthest block: the last special element below the formatting element.
    let mut fb = -1
    let mut k = si + 1
    while k < self.stack.length() {
      if is_special_local(local_of(self.stack[k].name).to_lower()) {
        fb = k
      }
      k = k + 1
    }
    if fb < 0 {
      let mut n = self.stack.length()
      while n > si {
        self.pop()
        n = n - 1
      }
      self.afe_remove(fmt)
      return
    }
    let common = self.stack[si - 1]
    let mut bookmark = fi
    let mut node = fb
    let mut last = fb
    let mut inner = 0
    while node > si {
      inner = inner + 1
      node = node - 1
      if node <= si {
        break
      }
      let node_el = self.stack[node]
      let ai = self.afe_index(node_el)
      if inner > 3 && ai >= 0 {
        let _ = self.afe.remove(ai)
        if ai < bookmark {
          bookmark = bookmark - 1
        }
      }
      let ai2 = self.afe_index(node_el)
      if ai2 < 0 {
        let _ = self.stack.remove(node)
        if node < fb {
          fb = fb - 1
        }
        if node < last {
          last = last - 1
        }
      } else {
        let cl = clone_shallow(node_el)
        self.stack[node] = cl
        self.afe[ai2] = AFElement(cl)
        if last == fb {
          bookmark = ai2 + 1
        }
        let last_el = self.stack[last]
        let _ = last_el.remove()
        cl.append(@moonxml.Node::ElementNode(last_el))
        last = node
      }
    }
    // Insert the last node into the common ancestor.
    let last_el = self.stack[last]
    let _ = last_el.remove()
    self.insert_into_common(common, last_el)
    // Clone the formatting element around the furthest block's children.
    let fb_el = self.stack[fb]
    let cl2 = clone_shallow(fmt)
    let kids = fb_el.children.copy()
    fb_el.set_children([])
    for c in kids {
      cl2.append(c)
    }
    fb_el.append(@moonxml.Node::ElementNode(cl2))
    // Replace the formatting element in the list and the stack.
    let fmi = self.afe_index(fmt)
    if fmi >= 0 {
      let _ = self.afe.remove(fmi)
    }
    let bm = if bookmark > self.afe.length() {
      self.afe.length()
    } else {
      bookmark
    }
    self.afe.insert(bm, AFElement(cl2))
    let si2 = self.stack_index(fmt)
    if si2 >= 0 {
      let _ = self.stack.remove(si2)
    }
    let fb2 = self.stack_index(fb_el)
    let pos = if fb2 < 0 {
      self.stack.length()
    } else {
      fb2 + 1
    }
    self.stack.insert(pos, cl2)
  }
}
