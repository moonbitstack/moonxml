/// The token dispatch and every insertion mode except "in body" and foreign
/// content, which live in `body.mbt`.
///
/// A handler returns `true` when the token must be reprocessed in the (new)
/// current insertion mode, exactly like the specification's "reprocess the
/// token" steps. That is how a mode hands a token to its successor without
/// duplicating rules.

fn H::dispatch(self : H, tok : Tok) -> Unit {
  let mut again = true
  let mut hops = 0
  while again && hops < 40 {
    again = false
    hops = hops + 1
    if self.use_foreign(tok) {
      if self.step_foreign(tok) {
        continue
      }
    }
    if self.step_mode(tok) {
      again = true
    }
  }
}

fn H::step_mode(self : H, tok : Tok) -> Bool {
  match self.mode {
    MInitial => self.step_initial(tok)
    MBeforeHtml => self.step_before_html(tok)
    MBeforeHead => self.step_before_head(tok)
    MInHead => self.step_in_head(tok)
    MInHeadNoscript => self.step_in_head_noscript(tok)
    MAfterHead => self.step_after_head(tok)
    MInBody => self.step_in_body(tok)
    MText => self.step_text(tok)
    MInTable => self.step_in_table(tok)
    MInTableText => self.step_in_table_text(tok)
    MInCaption => self.step_in_caption(tok)
    MInColumnGroup => self.step_in_column_group(tok)
    MInTableBody => self.step_in_table_body(tok)
    MInRow => self.step_in_row(tok)
    MInCell => self.step_in_cell(tok)
    MInSelect => self.step_in_select(tok)
    MInSelectInTable => self.step_in_select_in_table(tok)
    MInTemplate => self.step_in_template(tok)
    MAfterBody => self.step_after_body(tok)
    MInFrameset => self.step_in_frameset(tok)
    MAfterFrameset => self.step_after_frameset(tok)
    MAfterAfterBody => self.step_after_after_body(tok)
    MAfterAfterFrameset => self.step_after_after_frameset(tok)
  }
}

fn is_end_tag_in(tag : String, names : Array[String]) -> Bool {
  for n in names {
    if tag == n {
      return true
    }
  }
  false
}

fn H::create_html(self : H, attrs : Array[(String, String)]) -> @moonxml.Element {
  let el = @moonxml.Element::with_attrs("html", attrs)
  self.doc.append(@moonxml.Node::ElementNode(el))
  self.stack.push(el)
  el
}

// ---------------------------------------------------------------------------
// Initial, before html, before head
// ---------------------------------------------------------------------------

fn H::step_initial(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => if @text.is_blank(s) {
      false
    } else {
      self.quirks = true
      self.mode = MBeforeHtml
      true
    }
    Comment(s) => {
      self.doc.append(@moonxml.Node::CommentNode(s))
      false
    }
    Doctype(info) => {
      let low = info.to_lower()
      self.quirks = not(low == "html" || low.has_prefix("html "))
      self.doc.append(@moonxml.Node::DoctypeNode(info))
      self.mode = MBeforeHtml
      false
    }
    Eof => {
      self.quirks = true
      self.mode = MBeforeHtml
      true
    }
    _ => {
      self.quirks = true
      self.mode = MBeforeHtml
      true
    }
  }
}

fn H::step_before_html(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => if @text.is_blank(s) {
      false
    } else {
      let (_, rest) = split_lead_ws(s)
      let _ = self.create_html([])
      self.mode = MBeforeHead
      if rest != s {
        self.dispatch(Chars(rest))
        false
      } else {
        true
      }
    }
    Comment(s) => {
      self.doc.append(@moonxml.Node::CommentNode(s))
      false
    }
    Doctype(_) => false
    Start("html", attrs, _) => {
      let _ = self.create_html(attrs)
      self.mode = MBeforeHead
      false
    }
    End(t) => if t == "head" || t == "body" || t == "html" || t == "br" {
      let _ = self.create_html([])
      self.mode = MBeforeHead
      true
    } else {
      false
    }
    Eof => {
      let _ = self.create_html([])
      self.mode = MBeforeHead
      true
    }
    _ => {
      let _ = self.create_html([])
      self.mode = MBeforeHead
      true
    }
  }
}

fn H::step_before_head(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => if @text.is_blank(s) {
      false
    } else {
      let (_, rest) = split_lead_ws(s)
      self.make_head()
      if rest != s {
        self.dispatch(Chars(rest))
        false
      } else {
        true
      }
    }
    Comment(s) => {
      self.insert_comment(s)
      false
    }
    Doctype(_) => false
    Start("html", attrs, _) => self.step_in_body(Start("html", attrs, false))
    Start("head", attrs, _) => {
      let el = self.insert_el("head", attrs)
      self.head = Some(el)
      self.mode = MInHead
      false
    }
    End(t) => if t == "head" || t == "body" || t == "html" || t == "br" {
      self.make_head()
      true
    } else {
      false
    }
    Eof => {
      self.make_head()
      true
    }
    Start(_, _, _) => {
      self.make_head()
      true
    }
  }
}

fn H::make_head(self : H) -> Unit {
  let el = self.insert_el("head", [])
  self.head = Some(el)
  self.mode = MInHead
}

// ---------------------------------------------------------------------------
// In head
// ---------------------------------------------------------------------------

fn is_head_void(t : String) -> Bool {
  t == "base" || t == "basefont" || t == "bgsound" || t == "link" || t == "meta"
}

fn H::insert_template(self : H, attrs : Array[(String, String)]) -> Unit {
  let _ = self.insert_el("template", attrs)
  self.afe_marker()
  self.frameset_ok = false
  self.template_modes.push(MInTemplate)
  self.mode = MInTemplate
}

fn H::close_template(self : H) -> Unit {
  self.generate_implied_end_thoroughly()
  self.pop_until("template")
  self.afe_clear_to_marker()
  if self.template_modes.length() > 0 {
    let _ = self.template_modes.pop()
  }
  self.reset_mode()
}

fn H::step_in_head(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => if @text.is_blank(strip_nul(s)) {
      self.insert_text(s)
      false
    } else {
      // Whitespace that starts the run still belongs to head.
      let (ws, rest) = split_lead_ws(s)
      if ws.length() > 0 {
        self.insert_text(ws)
      }
      self.pop()
      self.mode = MAfterHead
      if rest.length() > 0 {
        self.dispatch(Chars(rest))
      }
      false
    }
    Comment(s) => {
      self.insert_comment(s)
      false
    }
    Doctype(_) => false
    Start("html", attrs, _) => self.step_in_body(Start("html", attrs, false))
    Start(t, attrs, _) => {
      if is_head_void(t) {
        let _ = self.insert_void(t, attrs)
        false
      } else if t == "title" {
        let _ = self.raw_element(t, attrs, TsRcdata)
        false
      } else if t == "noframes" || t == "style" {
        let _ = self.raw_element(t, attrs, TsRawtext)
        false
      } else if t == "noscript" {
        if self.scripting {
          let _ = self.raw_element(t, attrs, TsRawtext)
        } else {
          let _ = self.insert_el("noscript", attrs)
          self.mode = MInHeadNoscript
        }
        false
      } else if t == "script" {
        let _ = self.raw_element(t, attrs, TsScript)
        false
      } else if t == "template" {
        self.insert_template(attrs)
        false
      } else if t == "head" {
        false
      } else {
        self.leave_head(tok)
      }
    }
    End(t) => {
      if t == "head" {
        self.pop()
        self.mode = MAfterHead
        false
      } else if t == "body" || t == "html" || t == "br" {
        self.leave_head(tok)
      } else if t == "template" {
        if self.has_open("template") {
          self.close_template()
        }
        false
      } else {
        false
      }
    }
    Eof => self.leave_head(tok)
  }
}

/// Insert a raw-text element and hand the tokenizer its content model.
fn H::raw_element(
  self : H,
  tag : String,
  attrs : Array[(String, String)],
  ts : TokState
) -> @moonxml.Element {
  let el = self.insert_el(tag, attrs)
  self.raw_tag = tag
  self.tstate = ts
  self.orig_mode = self.mode
  self.mode = MText
  el
}

fn H::leave_head(self : H, tok : Tok) -> Bool {
  let _ = tok
  self.pop()
  self.mode = MAfterHead
  true
}

// ---------------------------------------------------------------------------
// In head noscript
// ---------------------------------------------------------------------------

fn H::step_in_head_noscript(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => if @text.is_blank(s) {
      let _ = self.step_in_head(Chars(s))
      false
    } else {
      self.leave_head_noscript()
      true
    }
    Comment(s) => {
      let _ = self.step_in_head(Comment(s))
      false
    }
    Doctype(_) => false
    Start("html", a, _) => self.step_in_body(Start("html", a, false))
    Start(t, a, _) => {
      if t == "basefont" || t == "bgsound" || t == "link" || t == "meta" || t == "noframes" || t == "style" {
        let _ = self.step_in_head(Start(t, a, false))
        false
      } else if t == "head" || t == "noscript" {
        false
      } else {
        self.leave_head_noscript()
        true
      }
    }
    End("noscript") => {
      self.pop()
      self.mode = MInHead
      false
    }
    End("br") => {
      self.leave_head_noscript()
      true
    }
    End(_) => false
    Eof => {
      self.leave_head_noscript()
      true
    }
  }
}

fn H::leave_head_noscript(self : H) -> Unit {
  self.pop()
  self.mode = MInHead
}

// ---------------------------------------------------------------------------
// After head
// ---------------------------------------------------------------------------

fn is_head_content(t : String) -> Bool {
  if t == "base" || t == "basefont" || t == "bgsound" || t == "link" || t == "meta" {
    return true
  }
  if t == "noframes" || t == "script" || t == "style" || t == "template" {
    return true
  }
  t == "title"
}

fn H::step_after_head(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => if @text.is_blank(strip_nul(s)) {
      self.insert_text(s)
      false
    } else {
      // Whitespace stays between head and body; the rest starts the body.
      let (ws, rest) = split_lead_ws(s)
      if ws.length() > 0 {
        self.insert_text(ws)
      }
      self.make_body()
      if rest.length() > 0 {
        self.dispatch(Chars(rest))
      }
      false
    }
    Comment(s) => {
      self.insert_comment(s)
      false
    }
    Doctype(_) => false
    Start("html", a, _) => self.step_in_body(Start("html", a, false))
    Start("body", a, _) => {
      let _ = self.insert_el("body", a)
      self.frameset_ok = false
      self.mode = MInBody
      false
    }
    Start("frameset", a, _) => {
      let _ = self.insert_el("frameset", a)
      self.mode = MInFrameset
      false
    }
    Start(t, a, _) => {
      if is_head_content(t) {
        // Head content met after head still belongs to head: parse it with the
        // head element temporarily back on the stack.
        match self.head {
          Some(h) => {
            self.stack.push(h)
            let _ = self.step_in_head(Start(t, a, false))
            self.remove_from_stack(h)
          }
          None => {
            let _ = self.step_in_head(Start(t, a, false))
          }
        }
        false
      } else if t == "head" {
        false
      } else {
        self.make_body()
        true
      }
    }
    End("template") => {
      let _ = self.step_in_head(tok)
      false
    }
    End(t) => if t == "body" || t == "html" || t == "br" {
      self.make_body()
      true
    } else {
      false
    }
    Eof => {
      self.make_body()
      true
    }
  }
}

fn H::make_body(self : H) -> Unit {
  let _ = self.insert_el("body", [])
  self.mode = MInBody
}

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

fn H::step_text(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => {
      self.insert_text(s)
      false
    }
    End(_) => {
      self.pop()
      self.mode = self.orig_mode
      false
    }
    Eof => {
      self.pop()
      self.mode = self.orig_mode
      true
    }
    _ => false
  }
}

// ---------------------------------------------------------------------------
// Table
// ---------------------------------------------------------------------------

fn is_table_scope_tag(l : String) -> Bool {
  l == "table" || l == "tbody" || l == "thead" || l == "tfoot" || l == "tr"
}

fn H::step_in_table(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => {
      let s = strip_nul(s)
      let l = self.cur_local()
      if is_table_scope_tag(l) {
        self.pending_text = s
        self.pending_nonws = not(@text.is_blank(s))
        self.orig_mode = self.mode
        self.mode = MInTableText
        false
      } else {
        self.anything_else_in_table(tok)
      }
    }
    Comment(s) => {
      self.insert_comment(s)
      false
    }
    Doctype(_) => false
    Start("caption", a, _) => {
      self.clear_back_to_table_context()
      self.afe_marker()
      let _ = self.insert_el("caption", a)
      self.mode = MInCaption
      false
    }
    Start("colgroup", a, _) => {
      self.clear_back_to_table_context()
      let _ = self.insert_el("colgroup", a)
      self.mode = MInColumnGroup
      false
    }
    Start("col", a, sc) => {
      self.clear_back_to_table_context()
      let _ = self.insert_el("colgroup", [])
      self.mode = MInColumnGroup
      self.dispatch(Start("col", a, sc))
      false
    }
    Start(t, a, _) => {
      if t == "tbody" || t == "tfoot" || t == "thead" {
        self.clear_back_to_table_context()
        let _ = self.insert_el(t, a)
        self.mode = MInTableBody
        false
      } else if t == "td" || t == "th" || t == "tr" {
        self.clear_back_to_table_context()
        let _ = self.insert_el("tbody", [])
        self.mode = MInTableBody
        true
      } else if t == "table" {
        if self.has_in_scope("table", ScTable) {
          self.pop_until("table")
          self.reset_mode()
          true
        } else {
          false
        }
      } else if t == "style" || t == "script" || t == "template" {
        let _ = self.step_in_head(Start(t, a, false))
        false
      } else if t == "input" {
        let mut hidden = false
        for pair in a {
          let (k, v) = pair
          if k == "type" && v.to_lower() == "hidden" {
            hidden = true
          }
        }
        if hidden {
          let _ = self.insert_void("input", a)
          false
        } else {
          self.anything_else_in_table(tok)
        }
      } else if t == "form" {
        if self.has_open("template") || self.form.is_some() {
          false
        } else {
          let el = self.insert_void("form", a)
          self.form = Some(el)
          false
        }
      } else {
        self.anything_else_in_table(tok)
      }
    }
    End("table") => {
      if self.has_in_scope("table", ScTable) {
        self.pop_until("table")
        self.reset_mode()
      }
      false
    }
    End(t) => {
      if t == "body" || t == "caption" || t == "col" || t == "colgroup" || t == "html" || t == "tbody" || t == "td" || t == "tfoot" || t == "th" || t == "thead" || t == "tr" {
        false
      } else if t == "template" {
        let _ = self.step_in_head(tok)
        false
      } else {
        self.anything_else_in_table(tok)
      }
    }
    Eof => self.step_in_body(tok)
  }
}

/// Table content that is not table content: foster-parent it into the body.
fn H::anything_else_in_table(self : H, tok : Tok) -> Bool {
  self.foster = true
  let r = self.step_in_body(tok)
  self.foster = false
  r
}

fn H::step_in_table_text(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => {
      self.pending_text = self.pending_text + s
      if not(@text.is_blank(s)) {
        self.pending_nonws = true
      }
      false
    }
    _ => {
      self.flush_table_text()
      self.mode = self.orig_mode
      true
    }
  }
}

fn H::flush_table_text(self : H) -> Unit {
  let s = self.pending_text
  self.pending_text = ""
  let nonws = self.pending_nonws
  self.pending_nonws = false
  if s.length() == 0 {
    return
  }
  if nonws {
    // Non-whitespace table text is reprocessed by the in-body rules, which is
    // what reconstructs formatting elements around it.
    self.foster = true
    let _ = self.step_in_body(Chars(s))
    self.foster = false
  } else {
    self.insert_text(s)
  }
}

// ---------------------------------------------------------------------------
// Caption, column group, table body, row, cell
// ---------------------------------------------------------------------------

fn is_table_part(t : String) -> Bool {
  if t == "caption" || t == "col" || t == "colgroup" || t == "tbody" {
    return true
  }
  t == "td" || t == "tfoot" || t == "th" || t == "thead" || t == "tr"
}

fn H::close_caption(self : H) -> Unit {
  self.generate_implied_end("caption")
  self.pop_until("caption")
  self.afe_clear_to_marker()
  self.mode = MInTable
}

fn H::step_in_caption(self : H, tok : Tok) -> Bool {
  match tok {
    End("caption") => {
      if self.has_in_scope("caption", ScTable) {
        self.close_caption()
      }
      false
    }
    Start(t, _, _) => if is_table_part(t) {
      if self.has_in_scope("caption", ScTable) {
        self.close_caption()
        true
      } else {
        false
      }
    } else {
      self.step_in_body(tok)
    }
    End("table") => {
      if self.has_in_scope("caption", ScTable) {
        self.close_caption()
        true
      } else {
        false
      }
    }
    End(t) => if t == "body" || t == "col" || t == "colgroup" || t == "html" || t == "tbody" || t == "td" || t == "tfoot" || t == "th" || t == "thead" || t == "tr" {
      false
    } else {
      self.step_in_body(tok)
    }
    _ => self.step_in_body(tok)
  }
}

fn H::step_in_column_group(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => if @text.is_blank(s) {
      self.insert_text(s)
      false
    } else {
      self.column_group_anything(tok)
    }
    Comment(s) => {
      self.insert_comment(s)
      false
    }
    Doctype(_) => false
    Start("html", a, _) => self.step_in_body(Start("html", a, false))
    Start("col", a, _) => {
      let _ = self.insert_void("col", a)
      false
    }
    Start(t, a, _) => if t == "template" {
      let _ = self.step_in_head(Start(t, a, false))
      false
    } else {
      self.column_group_anything(tok)
    }
    End("colgroup") => {
      if self.cur_local() == "colgroup" {
        self.pop()
        self.mode = MInTable
      }
      false
    }
    End("col") => false
    End("template") => {
      let _ = self.step_in_head(tok)
      false
    }
    End(_) => self.column_group_anything(tok)
    Eof => if self.cur_local() == "colgroup" {
      self.column_group_anything(tok)
    } else {
      self.step_in_body(tok)
    }
  }
}

fn H::column_group_anything(self : H, tok : Tok) -> Bool {
  if self.cur_local() != "colgroup" {
    return false
  }
  match tok {
    Chars(s) => {
      let (ws, rest) = split_lead_ws(s)
      if ws.length() > 0 {
        self.insert_text(ws)
      }
      self.pop()
      self.mode = MInTable
      if rest.length() > 0 {
        self.dispatch(Chars(rest))
      }
      false
    }
    _ => {
      self.pop()
      self.mode = MInTable
      true
    }
  }
}

fn H::step_in_table_body(self : H, tok : Tok) -> Bool {
  match tok {
    Start("tr", a, _) => {
      self.clear_back_to_table_body_context()
      let _ = self.insert_el("tr", a)
      self.mode = MInRow
      false
    }
    Start(t, a, _) => {
      if t == "th" || t == "td" {
        self.clear_back_to_table_body_context()
        let _ = self.insert_el("tr", [])
        self.mode = MInRow
        true
      } else if t == "caption" || t == "col" || t == "colgroup" || t == "tbody" || t == "tfoot" || t == "thead" {
        if self.table_body_in_scope() {
          self.clear_back_to_table_body_context()
          self.pop()
          self.mode = MInTable
          true
        } else {
          false
        }
      } else {
        self.step_in_table(tok)
      }
    }
    End(t) => {
      if t == "tbody" || t == "tfoot" || t == "thead" {
        if self.has_in_scope(t, ScTable) {
          self.clear_back_to_table_body_context()
          self.pop()
          self.mode = MInTable
        }
        false
      } else if t == "table" {
        if self.table_body_in_scope() {
          self.clear_back_to_table_body_context()
          self.pop()
          self.mode = MInTable
          true
        } else {
          false
        }
      } else if t == "body" || t == "caption" || t == "col" || t == "colgroup" || t == "html" || t == "td" || t == "th" || t == "tr" {
        false
      } else {
        self.step_in_table(tok)
      }
    }
    _ => self.step_in_table(tok)
  }
}

fn H::table_body_in_scope(self : H) -> Bool {
  self.has_in_scope("tbody", ScTable) || self.has_in_scope("thead", ScTable) || self.has_in_scope("tfoot", ScTable)
}

fn H::step_in_row(self : H, tok : Tok) -> Bool {
  match tok {
    Start(t, a, _) => {
      if t == "th" || t == "td" {
        self.clear_back_to_row_context()
        let _ = self.insert_el(t, a)
        self.mode = MInCell
        self.afe_marker()
        false
      } else if is_table_part(t) {
        if self.has_in_scope("tr", ScTable) {
          self.clear_back_to_row_context()
          self.pop()
          self.mode = MInTableBody
          true
        } else {
          false
        }
      } else {
        self.step_in_table(tok)
      }
    }
    End("tr") => {
      if self.has_in_scope("tr", ScTable) {
        self.clear_back_to_row_context()
        self.pop()
        self.mode = MInTableBody
      }
      false
    }
    End(t) => {
      if t == "table" {
        if self.has_in_scope("tr", ScTable) {
          self.clear_back_to_row_context()
          self.pop()
          self.mode = MInTableBody
          true
        } else {
          false
        }
      } else if t == "tbody" || t == "tfoot" || t == "thead" {
        if self.has_in_scope(t, ScTable) && self.has_in_scope("tr", ScTable) {
          self.clear_back_to_row_context()
          self.pop()
          self.mode = MInTableBody
          true
        } else {
          false
        }
      } else if t == "body" || t == "caption" || t == "col" || t == "colgroup" || t == "html" || t == "td" || t == "th" {
        false
      } else {
        self.step_in_table(tok)
      }
    }
    _ => self.step_in_table(tok)
  }
}

fn H::close_cell(self : H, tok : Tok) -> Unit {
  let _ = tok
  self.generate_implied_end_thoroughly()
  self.pop_until_any(["td", "th"])
  self.afe_clear_to_marker()
  self.mode = MInRow
}

fn H::step_in_cell(self : H, tok : Tok) -> Bool {
  match tok {
    End(t) => {
      if t == "td" || t == "th" {
        if self.has_in_scope(t, ScTable) {
          self.generate_implied_end_thoroughly()
          self.pop_until(t)
          self.afe_clear_to_marker()
          self.mode = MInRow
        }
        false
      } else if t == "body" || t == "caption" || t == "col" || t == "colgroup" || t == "html" {
        false
      } else if t == "table" || t == "tbody" || t == "tfoot" || t == "thead" || t == "tr" {
        if self.has_in_scope(t, ScTable) {
          self.close_cell(tok)
          true
        } else {
          false
        }
      } else {
        self.step_in_body(tok)
      }
    }
    Start(t, _, _) => if is_table_part(t) {
      if self.has_in_scope("td", ScTable) || self.has_in_scope("th", ScTable) {
        self.close_cell(tok)
        true
      } else {
        false
      }
    } else {
      self.step_in_body(tok)
    }
    _ => self.step_in_body(tok)
  }
}

// ---------------------------------------------------------------------------
// Select
// ---------------------------------------------------------------------------

fn H::step_in_select(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => {
      let kept = strip_nul(s)
      self.insert_text(kept)
      false
    }
    Comment(s) => {
      self.insert_comment(s)
      false
    }
    Doctype(_) => false
    Start("html", a, _) => self.step_in_body(Start("html", a, false))
    Start("option", a, _) => {
      if self.cur_local() == "option" {
        self.pop()
      }
      let _ = self.insert_el("option", a)
      false
    }
    Start("optgroup", a, _) => {
      if self.cur_local() == "option" {
        self.pop()
      }
      if self.cur_local() == "optgroup" {
        self.pop()
      }
      let _ = self.insert_el("optgroup", a)
      false
    }
    Start("hr", a, _) => {
      if self.cur_local() == "option" {
        self.pop()
      }
      if self.cur_local() == "optgroup" {
        self.pop()
      }
      let _ = self.insert_void("hr", a)
      false
    }
    Start("select", a, sc) => {
      if self.has_in_scope("select", ScSelect) {
        self.pop_until("select")
        self.reset_mode()
        let _ = (a, sc)
      }
      false
    }
    Start(t, a, sc) => {
      if t == "input" || t == "keygen" || t == "textarea" {
        if self.has_in_scope("select", ScSelect) {
          self.pop_until("select")
          self.reset_mode()
          true
        } else {
          false
        }
      } else if t == "script" || t == "template" {
        let _ = self.step_in_head(Start(t, a, sc))
        false
      } else {
        false
      }
    }
    End("optgroup") => {
      if self.cur_local() == "option" && self.stack.length() >= 2 {
        if local_of(self.stack[self.stack.length() - 2].name).to_lower() == "optgroup" {
          self.pop()
        }
      }
      if self.cur_local() == "optgroup" {
        self.pop()
      }
      false
    }
    End("option") => {
      if self.cur_local() == "option" {
        self.pop()
      }
      false
    }
    End("select") => {
      if self.has_in_scope("select", ScSelect) {
        self.pop_until("select")
        self.reset_mode()
      }
      false
    }
    End("template") => {
      let _ = self.step_in_head(tok)
      false
    }
    End(_) => false
    Eof => self.step_in_body(tok)
  }
}

fn is_select_table_tag(t : String) -> Bool {
  if t == "table" || t == "caption" || t == "tbody" || t == "tfoot" || t == "thead" {
    return true
  }
  t == "tr" || t == "td" || t == "th"
}

fn H::step_in_select_in_table(self : H, tok : Tok) -> Bool {
  match tok {
    Start(t, _, _) => if is_select_table_tag(t) {
      self.pop_until("select")
      self.reset_mode()
      true
    } else {
      self.step_in_select(tok)
    }
    End(t) => if is_select_table_tag(t) {
      self.pop_until("select")
      self.reset_mode()
      true
    } else {
      self.step_in_select(tok)
    }
    _ => self.step_in_select(tok)
  }
}

// ---------------------------------------------------------------------------
// Template
// ---------------------------------------------------------------------------

fn H::step_in_template(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(_) | Comment(_) | Doctype(_) => self.step_in_body(tok)
    Start(t, a, sc) => {
      if is_head_content(t) {
        let _ = self.step_in_head(Start(t, a, sc))
        false
      } else if t == "caption" || t == "colgroup" || t == "tbody" || t == "tfoot" || t == "thead" {
        self.switch_template_mode(MInTable)
        true
      } else if t == "col" {
        self.switch_template_mode(MInColumnGroup)
        true
      } else if t == "tr" {
        self.switch_template_mode(MInTableBody)
        true
      } else if t == "td" || t == "th" {
        self.switch_template_mode(MInRow)
        true
      } else {
        self.switch_template_mode(MInBody)
        true
      }
    }
    End("template") => {
      let _ = self.step_in_head(tok)
      false
    }
    End(_) => false
    Eof => {
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

fn H::switch_template_mode(self : H, m : Mode) -> Unit {
  if self.template_modes.length() > 0 {
    let _ = self.template_modes.pop()
  }
  self.template_modes.push(m)
  self.mode = m
}

// ---------------------------------------------------------------------------
// After body, frameset
// ---------------------------------------------------------------------------

fn H::step_after_body(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => if @text.is_blank(s) {
      let _ = self.step_in_body(Chars(s))
      false
    } else {
      self.mode = MInBody
      true
    }
    Comment(s) => {
      match self.html_element() {
        Some(h) => h.append(@moonxml.Node::CommentNode(s))
        None => self.doc.append(@moonxml.Node::CommentNode(s))
      }
      false
    }
    Doctype(_) => false
    Start("html", a, _) => self.step_in_body(Start("html", a, false))
    End("html") => {
      if not(self.fragment) {
        self.mode = MAfterAfterBody
      }
      false
    }
    End(_) => {
      self.mode = MInBody
      true
    }
    Start(_, _, _) => {
      self.mode = MInBody
      true
    }
    Eof => false
  }
}

fn H::step_after_after_body(self : H, tok : Tok) -> Bool {
  match tok {
    Comment(s) => {
      self.doc.append(@moonxml.Node::CommentNode(s))
      false
    }
    Doctype(_) => {
      let _ = self.step_in_body(tok)
      false
    }
    Chars(s) => if @text.is_blank(s) {
      let _ = self.step_in_body(Chars(s))
      false
    } else {
      self.mode = MInBody
      true
    }
    Start("html", a, _) => self.step_in_body(Start("html", a, false))
    Eof => false
    _ => {
      self.mode = MInBody
      true
    }
  }
}

fn H::step_in_frameset(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => {
      let ws = keep_ws(s)
      self.insert_text(ws)
      false
    }
    Comment(s) => {
      self.insert_comment(s)
      false
    }
    Doctype(_) => false
    Start("html", a, _) => self.step_in_body(Start("html", a, false))
    Start("frameset", a, _) => {
      let _ = self.insert_el("frameset", a)
      false
    }
    Start("frame", a, _) => {
      let _ = self.insert_void("frame", a)
      false
    }
    Start("noframes", a, _) => {
      let _ = self.step_in_head(Start("noframes", a, false))
      false
    }
    Start(_) => false
    End("frameset") => {
      if self.stack.length() <= 1 {
        false
      } else {
        self.pop()
        if not(self.fragment) && self.cur_local() != "frameset" {
          self.mode = MAfterFrameset
        }
        false
      }
    }
    End(_) => false
    Eof => false
  }
}

fn H::step_after_frameset(self : H, tok : Tok) -> Bool {
  match tok {
    Chars(s) => {
      let ws = keep_ws(s)
      self.insert_text(ws)
      false
    }
    Comment(s) => {
      self.insert_comment(s)
      false
    }
    Doctype(_) => false
    Start("html", a, _) => self.step_in_body(Start("html", a, false))
    Start("noframes", a, _) => {
      let _ = self.step_in_head(Start("noframes", a, false))
      false
    }
    End("html") => {
      self.mode = MAfterAfterFrameset
      false
    }
    _ => false
  }
}

fn H::step_after_after_frameset(self : H, tok : Tok) -> Bool {
  match tok {
    Comment(s) => {
      self.doc.append(@moonxml.Node::CommentNode(s))
      false
    }
    Doctype(_) => {
      let _ = self.step_in_body(tok)
      false
    }
    Chars(s) => if @text.is_blank(s) {
      let _ = self.step_in_body(Chars(s))
      false
    } else {
      false
    }
    Start("html", a, _) => self.step_in_body(Start("html", a, false))
    Start("noframes", a, _) => {
      let _ = self.step_in_head(Start("noframes", a, false))
      false
    }
    _ => false
  }
}
