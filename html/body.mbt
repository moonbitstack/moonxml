/// "In body", the biggest mode, plus the rules for foreign (`svg`/`math`)
/// content.
///
/// Every rule that inserts an element goes through `insert_el`, so foster
/// parenting, the active formatting list and the namespace adjustments all
/// apply in one place.

fn is_block_start(t : String) -> Bool {
  if t == "address" || t == "article" || t == "aside" || t == "blockquote" || t == "center" {
    return true
  }
  if t == "details" || t == "dialog" || t == "dir" || t == "div" || t == "dl" {
    return true
  }
  if t == "fieldset" || t == "figcaption" || t == "figure" || t == "footer" || t == "header" {
    return true
  }
  if t == "hgroup" || t == "main" || t == "menu" || t == "nav" || t == "ol" {
    return true
  }
  t == "p" || t == "section" || t == "summary" || t == "ul" || t == "search"
}

/// The block elements whose end tag closes them through the generic rule. It
/// differs from the start-tag list: `p`, `form`, `li`, `dd`, `dt` and the
/// headings each have their own end-tag rule.
fn is_block_end(t : String) -> Bool {
  if t == "address" || t == "article" || t == "aside" || t == "blockquote" || t == "button" {
    return true
  }
  if t == "center" || t == "details" || t == "dialog" || t == "dir" || t == "div" {
    return true
  }
  if t == "dl" || t == "fieldset" || t == "figcaption" || t == "figure" || t == "footer" {
    return true
  }
  if t == "header" || t == "hgroup" || t == "listing" || t == "main" || t == "menu" {
    return true
  }
  t == "nav" || t == "ol" || t == "pre" || t == "section" || t == "summary" || t == "ul"
}

fn is_heading_tag(t : String) -> Bool {
  t == "h1" || t == "h2" || t == "h3" || t == "h4" || t == "h5" || t == "h6"
}

fn is_formatting_tag(t : String) -> Bool {
  if t == "b" || t == "big" || t == "code" || t == "em" || t == "font" || t == "i" {
    return true
  }
  if t == "s" || t == "small" || t == "strike" || t == "strong" {
    return true
  }
  t == "tt" || t == "u"
}

fn is_void_body_start(t : String) -> Bool {
  t == "area" || t == "br" || t == "embed" || t == "img" || t == "keygen" || t == "wbr"
}

fn is_table_ignored_start(t : String) -> Bool {
  if t == "caption" || t == "col" || t == "colgroup" || t == "frame" || t == "head" {
    return true
  }
  t == "tbody" || t == "td" || t == "tfoot" || t == "th" || t == "thead" || t == "tr"
}

fn H::merge_attrs_into(self : H, el : @moonxml.Element, attrs : Array[(String, String)]) -> Unit {
  for pair in attrs {
    let (k, v) = pair
    if el.attr(k).is_none() {
      el.set_attr(k, v)
    }
  }
}

fn H::merge_attrs_on_top(self : H, tag : String, attrs : Array[(String, String)]) -> Unit {
  let mut i = 0
  while i < self.stack.length() {
    if local_of(self.stack[i].name).to_lower() == tag {
      self.merge_attrs_into(self.stack[i], attrs)
      return
    }
    i = i + 1
  }
}

fn H::step_in_body(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => {
      let t = strip_nul(s)
      self.reconstruct()
      self.insert_text(t)
      if not(@text.is_blank(t)) {
        self.frameset_ok = false
      }
      false
    }
    Comment(s) => {
      self.insert_comment(s)
      false
    }
    Doctype(_) => false
    Start(t, a, sc) => self.start_in_body(t, a, sc)
    End(t) => self.end_in_body(t)
    Eof => {
      // An open template has to close before the document does, and closing it
      // resumes the mode the template interrupted.
      if self.has_open("template") {
        self.pop_until("template")
        self.afe_clear_to_marker()
        if self.template_modes.length() > 0 {
          let _ = self.template_modes.pop()
        }
        self.reset_mode()
        true
      } else {
        false
      }
    }
  }
}

fn H::start_in_body(
  self : H,
  t : String,
  a : Array[(String, String)],
  sc : Bool
) -> Bool {
  if t == "html" {
    if not(self.has_open("template")) {
      match self.html_element() {
        Some(h) => self.merge_attrs_into(h, a)
        None => ()
      }
    }
    return false
  }
  if is_head_content(t) {
    let _ = self.step_in_head(Start(t, a, false))
    return false
  }
  if t == "body" {
    if self.stack.length() < 2 || self.has_open("template") {
      return false
    }
    if local_of(self.stack[1].name).to_lower() != "body" {
      return false
    }
    self.frameset_ok = false
    self.merge_attrs_into(self.stack[1], a)
    return false
  }
  if t == "frameset" {
    if self.stack.length() < 2 {
      return false
    }
    if local_of(self.stack[1].name).to_lower() != "body" {
      return false
    }
    if not(self.frameset_ok) {
      return false
    }
    let body = self.stack[1]
    let _ = body.remove()
    self.pop_until_index(1)
    let _ = self.insert_el("frameset", a)
    self.mode = MInFrameset
    return false
  }
  if is_block_start(t) {
    self.close_p()
    let _ = self.insert_el(t, a)
    return false
  }
  if is_heading_tag(t) {
    self.close_p()
    let l = self.cur_local()
    if is_heading(t_like(l)) {
      self.pop()
    }
    let _ = self.insert_el(t, a)
    return false
  }
  if t == "pre" || t == "listing" {
    self.close_p()
    let _ = self.insert_el(t, a)
    self.ignore_lf = true
    self.frameset_ok = false
    return false
  }
  if t == "form" {
    if self.form.is_some() && not(self.has_open("template")) {
      return false
    }
    self.close_p()
    let el = self.insert_el("form", a)
    if not(self.has_open("template")) {
      self.form = Some(el)
    }
    return false
  }
  if t == "li" {
    self.frameset_ok = false
    self.close_list_item("li")
    self.close_p()
    let _ = self.insert_el("li", a)
    return false
  }
  if t == "dd" || t == "dt" {
    self.frameset_ok = false
    self.close_list_item(t)
    self.close_p()
    let _ = self.insert_el(t, a)
    return false
  }
  if t == "plaintext" {
    self.close_p()
    let _ = self.insert_el("plaintext", a)
    self.raw_tag = "plaintext"
    self.tstate = TsPlaintext
    return false
  }
  if t == "button" {
    if self.has_in_scope("button", ScDefault) {
      self.generate_implied_end_thoroughly()
      self.pop_until("button")
    }
    self.reconstruct()
    let _ = self.insert_el("button", a)
    self.frameset_ok = false
    return false
  }
  if t == "a" {
    let fi = self.afe_last_named("a")
    if fi >= 0 {
      let old = match self.afe[fi] {
        AFElement(e) => e
        AFMarker => self.cur()
      }
      self.adoption("a")
      self.afe_remove(old)
      self.remove_from_stack(old)
    }
    self.reconstruct()
    let el = self.insert_el("a", a)
    self.afe_push(el)
    return false
  }
  if is_formatting_tag(t) {
    self.reconstruct()
    let el = self.insert_el(t, a)
    self.afe_push(el)
    return false
  }
  if t == "nobr" {
    self.reconstruct()
    if self.has_in_scope("nobr", ScDefault) {
      self.adoption("nobr")
      self.reconstruct()
    }
    let el = self.insert_el("nobr", a)
    self.afe_push(el)
    return false
  }
  if t == "applet" || t == "marquee" || t == "object" {
    self.reconstruct()
    let _ = self.insert_el(t, a)
    self.afe_marker()
    self.frameset_ok = false
    return false
  }
  if t == "table" {
    if not(self.quirks) && self.has_in_scope("p", ScButton) {
      self.close_p()
    }
    let _ = self.insert_el("table", a)
    self.frameset_ok = false
    self.mode = MInTable
    return false
  }
  if is_void_body_start(t) {
    self.reconstruct()
    let _ = self.insert_void(t, a)
    self.frameset_ok = false
    return false
  }
  if t == "input" {
    self.reconstruct()
    let _ = self.insert_void("input", a)
    let mut hidden = false
    for pair in a {
      let (k, v) = pair
      if k == "type" && v.to_lower() == "hidden" {
        hidden = true
      }
    }
    if not(hidden) {
      self.frameset_ok = false
    }
    return false
  }
  if t == "param" || t == "source" || t == "track" {
    let _ = self.insert_void(t, a)
    return false
  }
  if t == "hr" {
    self.close_p()
    let _ = self.insert_void("hr", a)
    self.frameset_ok = false
    return false
  }
  if t == "image" {
    return self.start_in_body("img", a, sc)
  }
  if t == "textarea" {
    let _ = self.raw_element("textarea", a, TsRcdata)
    self.ignore_lf = true
    self.frameset_ok = false
    return false
  }
  if t == "xmp" {
    self.close_p()
    self.reconstruct()
    self.frameset_ok = false
    let _ = self.raw_element("xmp", a, TsRawtext)
    return false
  }
  if t == "iframe" {
    self.frameset_ok = false
    let _ = self.raw_element("iframe", a, TsRawtext)
    return false
  }
  if t == "noembed" {
    let _ = self.raw_element("noembed", a, TsRawtext)
    return false
  }
  if t == "noscript" && self.scripting {
    let _ = self.raw_element("noscript", a, TsRawtext)
    return false
  }
  if t == "select" {
    self.reconstruct()
    let _ = self.insert_el("select", a)
    self.frameset_ok = false
    match self.mode {
      MInTable | MInCaption | MInTableBody | MInRow | MInCell => self.mode = MInSelectInTable
      _ => self.mode = MInSelect
    }
    return false
  }
  if t == "optgroup" || t == "option" {
    if self.cur_local() == "option" {
      self.pop()
    }
    self.reconstruct()
    let _ = self.insert_el(t, a)
    return false
  }
  if t == "rb" || t == "rtc" {
    if self.has_in_scope("ruby", ScDefault) {
      self.generate_implied_end("")
    }
    let _ = self.insert_el(t, a)
    return false
  }
  if t == "rp" || t == "rt" {
    if self.has_in_scope("ruby", ScDefault) {
      self.generate_implied_end("rtc")
    }
    let _ = self.insert_el(t, a)
    return false
  }
  if t == "math" {
    self.reconstruct()
    let attrs = adjust_attrs_foreign(adjust_attrs_math(a))
    let el = self.insert_foreign(math_ns, "math", attrs)
    if sc {
      self.pop()
      let _ = el
    }
    return false
  }
  if t == "svg" {
    self.reconstruct()
    let attrs = adjust_attrs_foreign(adjust_attrs_svg(a))
    let el = self.insert_foreign(svg_ns, "svg", attrs)
    if sc {
      self.pop()
      let _ = el
    }
    return false
  }
  if t == "mglyph" || t == "malignmark" {
    if self.cur_local() == "annotation-xml" && self.cur_ns() == math_ns {
      let attrs = adjust_attrs_foreign(adjust_attrs_math(a))
      let el = self.insert_foreign(math_ns, t, attrs)
      if sc {
        self.pop()
        let _ = el
      }
      return false
    }
  }
  if is_table_ignored_start(t) {
    return false
  }
  // A self-closing flag on a non-void HTML element is a parse error and is
  // otherwise ignored: the element stays open.
  let _ = sc
  self.reconstruct()
  let _ = self.insert_el(t, a)
  false
}

/// `is_heading` takes a lowercased name; keep one spelling for both callers.
fn t_like(l : String) -> String {
  l
}

fn H::close_list_item(self : H, t : String) -> Unit {
  let mut i = self.stack.length() - 1
  while i >= 0 {
    let node = self.stack[i]
    let l = local_of(node.name).to_lower()
    if l == t {
      self.generate_implied_end(t)
      self.pop_until(t)
      return
    }
    if is_special_el(l) && l != "address" && l != "div" && l != "p" {
      return
    }
    i = i - 1
  }
}

fn H::end_in_body(self : H, t : String) -> Bool {
  if t == "template" {
    let _ = self.step_in_head(End("template"))
    return false
  }
  if t == "body" {
    if not(self.has_in_scope("body", ScDefault)) {
      return false
    }
    self.mode = MAfterBody
    return false
  }
  if t == "html" {
    if not(self.has_in_scope("body", ScDefault)) {
      return false
    }
    self.mode = MAfterBody
    return true
  }
  if is_block_end(t) {
    if not(self.has_in_scope(t, ScDefault)) {
      return false
    }
    self.generate_implied_end(t)
    self.pop_until(t)
    return false
  }
  if t == "form" {
    if not(self.has_open("template")) {
      let node = self.form
      self.form = None
      match node {
        Some(n) => {
          if not(self.el_in_scope(n, ScDefault)) {
            return false
          }
          self.generate_implied_end("")
          self.remove_from_stack(n)
        }
        None => ()
      }
      return false
    }
    if not(self.has_in_scope("form", ScDefault)) {
      return false
    }
    self.generate_implied_end("")
    self.pop_until("form")
    return false
  }
  if t == "p" {
    if not(self.has_in_scope("p", ScButton)) {
      let _ = self.insert_void("p", [])
      return false
    }
    self.close_p()
    return false
  }
  if t == "li" {
    if not(self.has_in_scope("li", ScList)) {
      return false
    }
    self.generate_implied_end("li")
    self.pop_until("li")
    return false
  }
  if t == "dd" || t == "dt" {
    if not(self.has_in_scope(t, ScDefault)) {
      return false
    }
    self.generate_implied_end(t)
    self.pop_until(t)
    return false
  }
  if is_heading_tag(t) {
    if not(self.heading_in_scope()) {
      return false
    }
    self.generate_implied_end("")
    self.pop_until_any(["h1", "h2", "h3", "h4", "h5", "h6"])
    return false
  }
  if t == "a" || is_formatting_tag(t) {
    self.adoption(t)
    return false
  }
  if t == "applet" || t == "marquee" || t == "object" {
    if not(self.has_in_scope(t, ScDefault)) {
      return false
    }
    self.generate_implied_end("")
    self.pop_until(t)
    self.afe_clear_to_marker()
    return false
  }
  if t == "br" {
    self.reconstruct()
    let _ = self.insert_void("br", [])
    self.frameset_ok = false
    return false
  }
  // Any other end tag.
  let mut i = self.stack.length() - 1
  while i >= 0 {
    let node = self.stack[i]
    let l = local_of(node.name).to_lower()
    let ns = ns_of(node.name)
    if l == t && ns == "" {
      self.generate_implied_end(t)
      self.pop_until(t)
      return false
    }
    if is_special_node(l, ns) {
      return false
    }
    i = i - 1
  }
  false
}

fn H::heading_in_scope(self : H) -> Bool {
  self.has_in_scope("h1", ScDefault) || self.has_in_scope("h2", ScDefault) || self.has_in_scope("h3", ScDefault) || self.has_in_scope("h4", ScDefault) || self.has_in_scope("h5", ScDefault) || self.has_in_scope("h6", ScDefault)
}

/// The spec's special category, including the foreign integration points.
fn is_special_node(l : String, ns : String) -> Bool {
  if ns == "" {
    return is_special_el(l)
  }
  if ns == math_ns {
    return l == "mi" || l == "mo" || l == "mn" || l == "ms" || l == "mtext" || l == "annotation-xml"
  }
  l == "foreignobject" || l == "desc" || l == "title"
}

// ---------------------------------------------------------------------------
// Foreign content
// ---------------------------------------------------------------------------

fn is_mathml_text_ip(l : String) -> Bool {
  l == "mi" || l == "mo" || l == "mn" || l == "ms" || l == "mtext"
}

/// Whether the current node takes HTML content (a MathML text integration
/// point, or an SVG/HTML integration point).
fn H::at_integration_point(self : H) -> Bool {
  let cur = self.cur()
  let ns = ns_of(cur.name)
  if ns == "" {
    return false
  }
  let l = local_of(cur.name).to_lower()
  if ns == math_ns && is_mathml_text_ip(l) {
    return true
  }
  self.is_html_ip(cur)
}

fn H::is_html_ip(self : H, el : @moonxml.Element) -> Bool {
  let ns = ns_of(el.name)
  let l = local_of(el.name).to_lower()
  if ns == svg_ns {
    return l == "foreignobject" || l == "desc" || l == "title"
  }
  if ns == math_ns {
    if l == "annotation-xml" {
      match el.attr("encoding") {
        Some(v) => {
          let e = v.to_lower()
          e == "text/html" || e == "application/xhtml+xml"
        }
        None => false
      }
    } else {
      false
    }
  } else {
    false
  }
}

/// Whether the token belongs to the foreign-content rules rather than the
/// insertion mode. This is the spec's dispatch condition.
fn H::use_foreign(self : H, tok : Tok) -> Bool {
  if self.stack.length() == 0 {
    return false
  }
  let cur = self.adjusted()
  let ns = ns_of(cur.name)
  if ns == "" {
    return false
  }
  let l = local_of(cur.name).to_lower()
  match tok {
    Eof => false
    Start(t, _, _) => {
      if is_mathml_text_ip(l) && t != "mglyph" && t != "malignmark" {
        return false
      }
      if self.is_html_ip(cur) {
        return false
      }
      if l == "annotation-xml" && t == "svg" {
        return false
      }
      true
    }
    _ => true
  }
}

fn has_any_attr(a : Array[(String, String)], names : Array[String]) -> Bool {
  for pair in a {
    let (k, _) = pair
    for n in names {
      if k == n {
        return true
      }
    }
  }
  false
}

/// Pop out of foreign content back to HTML content. Returns false when the
/// content could not be left, which happens in a fragment whose context is a
/// plain foreign element: that context cannot be popped, so the tag stays
/// foreign.
fn H::break_out_foreign(self : H) -> Bool {
  // In a fragment whose context is a plain foreign element there is no HTML
  // content to break out to: the whole fragment is foreign.
  if self.fragment {
    match self.context {
      Some(c) => {
        if ns_of(c.name) != "" {
          let cl = local_of(c.name).to_lower()
          if not(is_mathml_text_ip(cl)) && not(self.is_html_ip(c)) {
            return false
          }
        }
      }
      None => ()
    }
  }
  while self.stack.length() > 1 {
    let cur = self.cur()
    let ns = ns_of(cur.name)
    if ns == "" {
      return true
    }
    let l = local_of(cur.name).to_lower()
    if is_mathml_text_ip(l) || self.is_html_ip(cur) {
      return true
    }
    self.pop()
  }
  if self.fragment {
    let a = self.adjusted()
    if ns_of(a.name) != "" {
      let l = local_of(a.name).to_lower()
      if not(is_mathml_text_ip(l)) && not(self.is_html_ip(a)) {
        return false
      }
    }
  }
  true
}

fn H::step_foreign(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => {
      // In foreign content NUL becomes U+FFFD rather than disappearing, but an
      // integration point still holds HTML, where it just goes away.
      let t = if self.at_integration_point() { strip_nul(s) } else { nul_to_fffd(s) }
      if self.at_integration_point() {
        // An integration point holds HTML, so formatting elements reconstruct
        // here the way they do in body content.
        self.reconstruct()
      }
      self.insert_text(t)
      if not(@text.is_blank(t)) {
        self.frameset_ok = false
      }
      true
    }
    Comment(s) => {
      self.insert_comment(s)
      true
    }
    Doctype(_) => true
    Start(t, a, sc) => {
      let breakout = is_html_breakout(t) || (t == "font" && has_any_attr(a, ["color", "face", "size"]))
      if breakout {
        if self.break_out_foreign() {
          return false
        }
      }
      let ns = self.adjusted_ns()
      if ns == svg_ns {
        let attrs = adjust_attrs_foreign(adjust_attrs_svg(a))
        let el = self.insert_foreign(svg_ns, svg_adjust_tag(t), attrs)
        if sc {
          self.pop()
          let _ = el
        }
      } else if ns == math_ns {
        let attrs = adjust_attrs_foreign(adjust_attrs_math(a))
        let el = self.insert_foreign(math_ns, t, attrs)
        if sc {
          self.pop()
          let _ = el
        }
      } else {
        let el = self.insert_el(t, a)
        if sc {
          self.pop()
          let _ = el
        }
      }
      true
    }
    End(t) => {
      if t == "br" || t == "p" {
        return if self.break_out_foreign() { false } else { true }
      }
      let mut i = self.stack.length() - 1
      while i >= 0 {
        let node = self.stack[i]
        let l = local_of(node.name).to_lower()
        if l == t {
          self.pop_until_index(i)
          return true
        }
        if ns_of(node.name) == "" {
          return false
        }
        i = i - 1
      }
      true
    }
    Eof => false
  }
}
