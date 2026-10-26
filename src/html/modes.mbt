// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The insertion modes, in the order the spec lists them. A function that
// answers `true` is asking to see the same token again in whatever mode it is
// now in — the spec's "reprocess the token", and the reason `<td>` in a table
// ends up creating the row it needs.

///|
fn remove_from_stack(builder : Builder, element : @moonxml.Element) -> Bool {
  match builder.stack.length() {
    0 => false
    _ => {
      let mut k = builder.stack.length() - 1
      while k >= 1 {
        if physical_equal(builder.stack[k], element) {
          ignore(builder.stack.remove(k))
          return true
        }
        k = k - 1
      }
      false
    }
  }
}

///|
/// An implied end tag closes the innermost elements of the implied set, but not
/// the one the token names — `<li><li>` closes the first list item, and
/// `<li>` inside it stays open.
fn generate_implied_except(builder : Builder, name : String) -> Unit {
  while builder.stack.length() > 1 &&
        is_implied_end(current(builder).name) &&
        current(builder).name != name {
    ignore(pop_stack(builder))
  }
}

///|
/// Merge a repeated `<html>` or `<body>` start tag's attributes onto the
/// element already there, as the spec says to.
fn merge_attrs_into(
  builder : Builder,
  element : @moonxml.Element,
  attrs : Array[(String, String)],
) -> Unit {
  ignore(builder)
  for pair in attrs {
    if !element.has_attr(pair.0) {
      element.set_attr(pair.0, pair.1)
    }
  }
}

///|
/// The body element, which is whatever `body` sits directly under `html`.
fn body_element(builder : Builder) -> @moonxml.Element? {
  for node in builder.doc.root.childrens {
    match node {
      ElementNode(html) =>
        for child in html.childrens {
          match child {
            ElementNode(el) => if el.name == "body" { return Some(el) }
            _ => ()
          }
        }
      _ => ()
    }
  }
  None
}

///|
/// The HTML element: the document's one element child.
fn html_element(builder : Builder) -> @moonxml.Element? {
  for node in builder.doc.root.childrens {
    match node {
      ElementNode(el) => return Some(el)
      _ => ()
    }
  }
  None
}

///|
/// The stack stops holding a head once the head is done; `head` stays for the
/// elements the spec sends back to it.
fn close_head(builder : Builder) -> Unit {
  while builder.stack.length() > 1 {
    let top = pop_stack(builder)
    if top.name == "head" {
      return
    }
  }
}

///|
fn implied(builder : Builder) -> Unit {
  builder.repairs.implied = builder.repairs.implied + 1
}

// ------------------------------------------------------------- the prologue

///|
fn doctype_in(builder : Builder, name : String, quirks~ : Bool) -> Bool {
  ignore(name)
  match builder.mode {
    Initial => {
      builder.quirks = quirks
      builder.doc.root.append(@moonxml.DoctypeNode(name))
      builder.mode = BeforeHtml
      false
    }
    InBody
    | InTable
    | InTableText
    | InCaption
    | InColumnGroup
    | InTableBody
    | InRow
    | InCell
    | InSelect
    | InSelectInTable
    | AfterBody
    | AfterAfterBody => false
    _ => false
  }
}

///|
fn comment_in(builder : Builder, text : String) -> Bool {
  if builder.mode is InTableText {
    // The text a table was holding belongs before the comment, not after it.
    flush_table_text(builder)
    builder.mode = InTable
  }
  match builder.mode {
    Initial | BeforeHtml => {
      insert_comment_into(builder.doc.root, text)
      false
    }
    AfterBody => {
      match html_element(builder) {
        Some(html) => insert_comment_into(html, text)
        None => insert_comment_into(builder.doc.root, text)
      }
      false
    }
    AfterAfterBody => {
      insert_comment_into(builder.doc.root, text)
      false
    }
    _ => {
      insert_comment(builder, text)
      false
    }
  }
}

///|
/// The elements whose content the tokenizer reads as one run: their end tag is
/// the only thing that closes them.
fn is_raw_text_tag(name : String) -> Bool {
  match name {
    "script"
    | "style"
    | "title"
    | "textarea"
    | "xmp"
    | "iframe"
    | "noembed"
    | "noframes"
    | "plaintext" => true
    _ => false
  }
}

///|
fn whitespace_only(text : String) -> Bool {
  for ch in text {
    if !(ch == ' ' || ch == '\t' || ch == '\n' || ch == '\u{0C}' || ch == '\r') {
      return false
    }
  }
  true
}

// ------------------------------------------------------------------ characters

///|
fn chars_in(builder : Builder, text : String) -> Bool {
  if builder.text_only {
    insert_text(builder, text)
    return false
  }
  match builder.mode {
    Initial =>
      if whitespace_only(text) {
        false
      } else {
        builder.quirks = true
        builder.mode = BeforeHtml
        true
      }
    BeforeHtml =>
      if whitespace_only(text) {
        false
      } else {
        imply_html(builder)
        true
      }
    BeforeHead =>
      if whitespace_only(text) {
        false
      } else {
        imply_head(builder)
        true
      }
    InHead =>
      if whitespace_only(text) {
        insert_text(builder, text)
        false
      } else {
        // Text in the head is the head's own end: the body is next.
        close_head(builder)
        builder.mode = AfterHead
        true
      }
    AfterHead =>
      if whitespace_only(text) {
        insert_text(builder, text)
        false
      } else {
        imply_body(builder)
        true
      }
    InBody => {
      reconstruct_afe(builder)
      insert_text(builder, text)
      false
    }
    InTable =>
      if is_table_like(current(builder).name) {
        builder.pending = ""
        builder.mode = InTableText
        true
      } else {
        builder.foster = true
        reconstruct_afe(builder)
        insert_text(builder, text)
        builder.foster = false
        false
      }
    InTableText => {
      builder.pending = builder.pending + text
      false
    }
    InColumnGroup =>
      if whitespace_only(text) {
        insert_text(builder, text)
        false
      } else if current_is(builder, "colgroup") {
        ignore(pop_stack(builder))
        builder.mode = InTable
        true
      } else {
        builder.mode = InTable
        true
      }
    InSelect | InSelectInTable => {
      insert_text(builder, text)
      false
    }
    InCaption | InTableBody | InRow | InCell => in_body_chars(builder, text)
    AfterBody | AfterAfterBody =>
      if whitespace_only(text) {
        builder.mode = InBody
        reconstruct_afe(builder)
        insert_text(builder, text)
        false
      } else {
        builder.mode = InBody
        true
      }
  }
}

///|
fn in_body_chars(builder : Builder, text : String) -> Bool {
  let saved = builder.mode
  builder.mode = InBody
  reconstruct_afe(builder)
  insert_text(builder, text)
  builder.mode = saved
  false
}

///|
fn flush_table_text(builder : Builder) -> Unit {
  let held = builder.pending
  builder.pending = ""
  if held.is_empty() {
    return
  }
  if whitespace_only(held) {
    insert_text(builder, held)
  } else {
    // Non-space text inside a table belongs before it, not in it.
    builder.foster = true
    reconstruct_afe(builder)
    insert_text(builder, held)
    builder.foster = false
  }
}

// -------------------------------------------------------------- start tags

///|
fn start_in(
  builder : Builder,
  name : String,
  attrs : Array[(String, String)],
  self_closing~ : Bool,
) -> Bool {
  match builder.mode {
    Initial => {
      if builder.mode is Initial {
        builder.quirks = true
      }
      builder.mode = BeforeHtml
      true
    }
    BeforeHtml =>
      if name == "html" {
        let element = insert_element(builder, "html", attrs)
        push_stack(builder, element)
        builder.mode = BeforeHead
        false
      } else {
        imply_html(builder)
        true
      }
    BeforeHead =>
      match name {
        "html" => in_body_start(builder, name, attrs)
        "head" => {
          let element = insert_open(builder, "head", attrs)
          builder.head = Some(element)
          builder.mode = InHead
          false
        }
        _ => {
          imply_head(builder)
          true
        }
      }
    InHead => start_in_head(builder, name, attrs, self_closing~)
    AfterHead => start_in_after_head(builder, name, attrs, self_closing~)
    InBody => in_body_start(builder, name, attrs)
    InTable => start_in_table(builder, name, attrs, self_closing~)
    InTableText => {
      flush_table_text(builder)
      builder.mode = InTable
      true
    }
    InCaption => start_in_caption(builder, name, attrs)
    InColumnGroup =>
      match name {
        "html" => in_body_start(builder, name, attrs)
        "col" => {
          let element = insert_element(builder, "col", attrs)
          ignore(element)
          false
        }
        _ =>
          if current_is(builder, "colgroup") {
            ignore(pop_stack(builder))
            builder.mode = InTable
            true
          } else {
            builder.repairs.dropped = builder.repairs.dropped + 1
            false
          }
      }
    InTableBody => start_in_table_body(builder, name, attrs, self_closing~)
    InRow => start_in_row(builder, name, attrs, self_closing~)
    InCell => start_in_cell(builder, name, attrs)
    InSelect => start_in_select(builder, name, attrs)
    InSelectInTable => start_in_select_in_table(builder, name, attrs)
    AfterBody | AfterAfterBody => {
      builder.mode = InBody
      true
    }
  }
}

///|
fn imply_html(builder : Builder) -> Unit {
  implied(builder)
  let element = insert_element(builder, "html", [])
  push_stack(builder, element)
  builder.mode = BeforeHead
}

///|
/// A `<head>` the document never wrote: implied, empty, and already done with.
fn imply_head(builder : Builder) -> Unit {
  implied(builder)
  let element = insert_open(builder, "head", [])
  builder.head = Some(element)
  builder.mode = InHead
}

///|
fn imply_body(builder : Builder) -> Unit {
  implied(builder)
  let element = insert_open(builder, "body", [])
  ignore(element)
  builder.mode = InBody
}

///|
fn start_in_head(
  builder : Builder,
  name : String,
  attrs : Array[(String, String)],
  self_closing~ : Bool,
) -> Bool {
  match name {
    "html" => in_body_start(builder, name, attrs)
    "base" | "basefont" | "bgsound" | "link" | "meta" => {
      ignore(insert_element(builder, name, attrs))
      false
    }
    "title" | "style" | "noframes" | "script" | "noscript" => {
      ignore(insert_open(builder, name, attrs))
      false
    }
    "template" => {
      ignore(insert_open(builder, "template", attrs))
      builder.afe.push(None)
      builder.mode = InBody
      false
    }
    "head" => {
      builder.repairs.dropped = builder.repairs.dropped + 1
      false
    }
    _ => {
      ignore(self_closing)
      close_head(builder)
      builder.mode = AfterHead
      true
    }
  }
}

///|
fn start_in_after_head(
  builder : Builder,
  name : String,
  attrs : Array[(String, String)],
  self_closing~ : Bool,
) -> Bool {
  match name {
    "html" => in_body_start(builder, name, attrs)
    "body" => {
      let element = insert_open(builder, "body", attrs)
      ignore(element)
      builder.mode = InBody
      false
    }
    "base"
    | "basefont"
    | "bgsound"
    | "link"
    | "meta"
    | "noframes"
    | "script"
    | "style"
    | "template"
    | "title" => {
      // These go back into the head, where the spec sends them.
      let head = match builder.head {
        Some(el) => el
        None => {
          implied(builder)
          let el = insert_open(builder, "head", [])
          builder.head = Some(el)
          el
        }
      }
      let element = @moonxml.Element::new(name, attrs~)
      head.append(@moonxml.ElementNode(element))
      if !is_void(name) {
        // A raw-text element needs to be open so that its content lands in it;
        // its own end tag closes it.
        push_stack(builder, element)
      }
      ignore(self_closing)
      false
    }
    "head" => {
      builder.repairs.dropped = builder.repairs.dropped + 1
      false
    }
    _ => {
      imply_body(builder)
      true
    }
  }
}

///|
fn start_in_table(
  builder : Builder,
  name : String,
  attrs : Array[(String, String)],
  self_closing~ : Bool,
) -> Bool {
  match name {
    "caption" => {
      clear_to_table(builder)
      ignore(insert_open(builder, "caption", attrs))
      builder.afe.push(None)
      builder.mode = InCaption
      false
    }
    "colgroup" => {
      clear_to_table(builder)
      ignore(insert_open(builder, "colgroup", attrs))
      builder.mode = InColumnGroup
      false
    }
    "col" => {
      clear_to_table(builder)
      ignore(insert_open(builder, "colgroup", []))
      builder.mode = InColumnGroup
      true
    }
    "tbody" | "tfoot" | "thead" => {
      clear_to_table(builder)
      ignore(insert_open(builder, name, attrs))
      builder.mode = InTableBody
      false
    }
    "td" | "th" | "tr" => {
      clear_to_table(builder)
      implied(builder)
      ignore(insert_open(builder, "tbody", []))
      builder.mode = InTableBody
      true
    }
    "table" =>
      if has_in_scope(builder, "table", Table) {
        pop_through(builder, "table")
        reset_mode(builder)
        true
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
        false
      }
    "style" | "script" | "template" =>
      start_in_head(builder, name, attrs, self_closing~)
    "input" => {
      let mut hidden = false
      for pair in attrs {
        if pair.0 == "type" && lower(pair.1) == "hidden" {
          hidden = true
        }
      }
      if hidden {
        let element = insert_element(builder, "input", attrs)
        ignore(element)
        false
      } else {
        builder.foster = true
        let again = in_body_start(builder, name, attrs)
        builder.foster = false
        again
      }
    }
    "form" => {
      if builder.form is None {
        let element = insert_open(builder, "form", attrs)
        builder.form = Some(element)
        ignore(pop_stack(builder))
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
      }
      false
    }
    _ => {
      builder.foster = true
      let again = in_body_start(builder, name, attrs)
      builder.foster = false
      again
    }
  }
}

///|
fn start_in_table_body(
  builder : Builder,
  name : String,
  attrs : Array[(String, String)],
  self_closing~ : Bool,
) -> Bool {
  match name {
    "tr" => {
      clear_to_table_body(builder)
      ignore(insert_open(builder, "tr", attrs))
      builder.mode = InRow
      false
    }
    "th" | "td" => {
      clear_to_table_body(builder)
      implied(builder)
      ignore(insert_open(builder, "tr", []))
      builder.mode = InRow
      true
    }
    "caption" | "col" | "colgroup" | "tbody" | "tfoot" | "thead" =>
      if has_any_in_scope(builder, ["tbody", "thead", "tfoot"], Table) {
        clear_to_table_body(builder)
        ignore(pop_stack(builder))
        builder.mode = InTable
        true
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
        false
      }
    _ => {
      ignore(self_closing)
      start_in_table(builder, name, attrs, self_closing~)
    }
  }
}

///|
fn start_in_row(
  builder : Builder,
  name : String,
  attrs : Array[(String, String)],
  self_closing~ : Bool,
) -> Bool {
  match name {
    "th" | "td" => {
      clear_to_row(builder)
      ignore(insert_open(builder, name, attrs))
      builder.mode = InCell
      builder.afe.push(None)
      false
    }
    "caption" | "col" | "colgroup" | "tbody" | "tfoot" | "thead" | "tr" =>
      if has_in_scope(builder, "tr", Table) {
        clear_to_row(builder)
        ignore(pop_stack(builder))
        builder.mode = InTableBody
        true
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
        false
      }
    _ => {
      ignore(self_closing)
      start_in_table(builder, name, attrs, self_closing~)
    }
  }
}

///|
fn start_in_cell(
  builder : Builder,
  name : String,
  attrs : Array[(String, String)],
) -> Bool {
  match name {
    "caption"
    | "col"
    | "colgroup"
    | "tbody"
    | "td"
    | "tfoot"
    | "th"
    | "thead"
    | "tr" =>
      if has_any_in_scope(builder, ["td", "th"], Table) {
        close_cell(builder)
        true
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
        false
      }
    _ => in_body_start(builder, name, attrs)
  }
}

///|
fn close_cell(builder : Builder) -> Unit {
  generate_implied_end(builder)
  if has_in_scope(builder, "td", Table) {
    pop_through(builder, "td")
  } else if has_in_scope(builder, "th", Table) {
    pop_through(builder, "th")
  }
  clear_afe_to_marker(builder)
  builder.mode = InRow
}

///|
fn start_in_caption(
  builder : Builder,
  name : String,
  attrs : Array[(String, String)],
) -> Bool {
  match name {
    "caption"
    | "col"
    | "colgroup"
    | "tbody"
    | "td"
    | "tfoot"
    | "th"
    | "thead"
    | "tr" =>
      if has_in_scope(builder, "caption", Table) {
        generate_implied_end(builder)
        pop_through(builder, "caption")
        clear_afe_to_marker(builder)
        builder.mode = InTable
        true
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
        false
      }
    _ => in_body_start(builder, name, attrs)
  }
}

///|
fn start_in_select(
  builder : Builder,
  name : String,
  attrs : Array[(String, String)],
) -> Bool {
  match name {
    "html" => in_body_start(builder, name, attrs)
    "option" => {
      if current_is(builder, "option") {
        ignore(pop_stack(builder))
      }
      ignore(insert_open(builder, "option", attrs))
      false
    }
    "optgroup" => {
      if current_is(builder, "option") {
        ignore(pop_stack(builder))
      }
      if current_is(builder, "optgroup") {
        ignore(pop_stack(builder))
      }
      ignore(insert_open(builder, "optgroup", attrs))
      false
    }
    "hr" => {
      if current_is(builder, "option") {
        ignore(pop_stack(builder))
      }
      if current_is(builder, "optgroup") {
        ignore(pop_stack(builder))
      }
      let element = insert_element(builder, "hr", attrs)
      ignore(element)
      false
    }
    "select" => {
      if has_in_scope(builder, "select", Select) {
        pop_through(builder, "select")
        reset_mode(builder)
      }
      false
    }
    "input" | "keygen" | "textarea" =>
      if has_in_scope(builder, "select", Select) {
        pop_through(builder, "select")
        reset_mode(builder)
        true
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
        false
      }
    "script" | "style" | "template" =>
      start_in_head(builder, name, attrs, self_closing=false)
    _ => {
      builder.repairs.dropped = builder.repairs.dropped + 1
      false
    }
  }
}

///|
fn start_in_select_in_table(
  builder : Builder,
  name : String,
  attrs : Array[(String, String)],
) -> Bool {
  match name {
    "caption" | "table" | "tbody" | "tfoot" | "thead" | "tr" | "td" | "th" =>
      if has_any_in_scope(
          builder,
          ["table", "tbody", "tfoot", "thead", "tr"],
          Table,
        ) {
        pop_through(builder, "select")
        reset_mode(builder)
        true
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
        false
      }
    _ => start_in_select(builder, name, attrs)
  }
}

// ------------------------------------------------------------------ in body

///|
fn is_heading(name : String) -> Bool {
  match name {
    "h1" | "h2" | "h3" | "h4" | "h5" | "h6" => true
    _ => false
  }
}

///|
fn in_body_start(
  builder : Builder,
  name : String,
  attrs : Array[(String, String)],
) -> Bool {
  match name {
    "html" => {
      match html_element(builder) {
        Some(html) => merge_attrs_into(builder, html, attrs)
        None => ()
      }
      builder.repairs.dropped = builder.repairs.dropped + 1
      false
    }
    "base"
    | "basefont"
    | "bgsound"
    | "link"
    | "meta"
    | "noframes"
    | "script"
    | "style"
    | "template"
    | "title" => start_in_head(builder, name, attrs, self_closing=false)
    "body" => {
      match body_element(builder) {
        Some(body) =>
          if builder.stack.length() > 1 {
            merge_attrs_into(builder, body, attrs)
          }
        None => ()
      }
      builder.repairs.dropped = builder.repairs.dropped + 1
      false
    }
    "address"
    | "article"
    | "aside"
    | "blockquote"
    | "center"
    | "details"
    | "dialog"
    | "dir"
    | "div"
    | "dl"
    | "fieldset"
    | "figcaption"
    | "figure"
    | "footer"
    | "header"
    | "hgroup"
    | "main"
    | "menu"
    | "nav"
    | "ol"
    | "p"
    | "section"
    | "summary"
    | "ul" => {
      if has_in_scope(builder, "p", Button) {
        close_p(builder)
      }
      ignore(insert_open(builder, name, attrs))
      false
    }
    "h1" | "h2" | "h3" | "h4" | "h5" | "h6" => {
      if has_in_scope(builder, "p", Button) {
        close_p(builder)
      }
      if is_heading(current(builder).name) {
        ignore(pop_stack(builder))
      }
      ignore(insert_open(builder, name, attrs))
      false
    }
    "pre" | "listing" => {
      if has_in_scope(builder, "p", Button) {
        close_p(builder)
      }
      ignore(insert_open(builder, name, attrs))
      false
    }
    "form" => {
      let open_form = builder.form
      match open_form {
        Some(_) => builder.repairs.dropped = builder.repairs.dropped + 1
        None => {
          if has_in_scope(builder, "p", Button) {
            close_p(builder)
          }
          let element = insert_open(builder, "form", attrs)
          builder.form = Some(element)
        }
      }
      false
    }
    "li" => {
      if has_in_scope(builder, "li", ListItem) {
        generate_implied_except(builder, "li")
        pop_through(builder, "li")
      }
      if has_in_scope(builder, "p", Button) {
        close_p(builder)
      }
      ignore(insert_open(builder, "li", attrs))
      false
    }
    "dd" | "dt" => {
      if has_any_in_scope(builder, ["dd", "dt"], Default) {
        generate_implied_except(builder, name)
        pop_until(builder, ["dd", "dt"])
      }
      if has_in_scope(builder, "p", Button) {
        close_p(builder)
      }
      ignore(insert_open(builder, name, attrs))
      false
    }
    "plaintext" => {
      if has_in_scope(builder, "p", Button) {
        close_p(builder)
      }
      ignore(insert_open(builder, name, attrs))
      false
    }
    "button" => {
      if has_in_scope(builder, "button", Default) {
        generate_implied_end(builder)
        pop_through(builder, "button")
      }
      reconstruct_afe(builder)
      ignore(insert_open(builder, "button", attrs))
      false
    }
    "a" => {
      match find_afe(builder, "a") {
        Some(existing) => {
          adoption_agency(builder, "a")
          match afe_index(builder, existing) {
            Some(at) => ignore(builder.afe.remove(at))
            None => ()
          }
          ignore(remove_from_stack(builder, existing))
        }
        None => ()
      }
      reconstruct_afe(builder)
      let element = insert_open(builder, "a", attrs)
      push_afe(builder, element)
      false
    }
    "b"
    | "big"
    | "code"
    | "em"
    | "font"
    | "i"
    | "s"
    | "small"
    | "strike"
    | "strong"
    | "tt"
    | "u" => {
      reconstruct_afe(builder)
      let element = insert_open(builder, name, attrs)
      push_afe(builder, element)
      false
    }
    "nobr" => {
      reconstruct_afe(builder)
      if has_in_scope(builder, "nobr", Default) {
        adoption_agency(builder, "nobr")
        reconstruct_afe(builder)
      }
      let element = insert_open(builder, "nobr", attrs)
      push_afe(builder, element)
      false
    }
    "applet" | "marquee" | "object" => {
      reconstruct_afe(builder)
      ignore(insert_open(builder, name, attrs))
      builder.afe.push(None)
      false
    }
    "table" => {
      if !builder.quirks && has_in_scope(builder, "p", Button) {
        close_p(builder)
      }
      ignore(insert_open(builder, "table", attrs))
      builder.mode = InTable
      false
    }
    "area" | "br" | "embed" | "img" | "keygen" | "wbr" => {
      reconstruct_afe(builder)
      ignore(insert_element(builder, name, attrs))
      false
    }
    "input" => {
      reconstruct_afe(builder)
      ignore(insert_element(builder, "input", attrs))
      false
    }
    "param" | "source" | "track" => {
      ignore(insert_element(builder, name, attrs))
      false
    }
    "hr" => {
      if has_in_scope(builder, "p", Button) {
        close_p(builder)
      }
      ignore(insert_element(builder, "hr", attrs))
      false
    }
    "image" => in_body_start(builder, "img", attrs)
    "textarea" => {
      ignore(insert_open(builder, "textarea", attrs))
      false
    }
    "xmp" => {
      if has_in_scope(builder, "p", Button) {
        close_p(builder)
      }
      reconstruct_afe(builder)
      ignore(insert_open(builder, "xmp", attrs))
      false
    }
    "iframe" | "noembed" => {
      ignore(insert_open(builder, name, attrs))
      false
    }
    "select" => {
      reconstruct_afe(builder)
      ignore(insert_open(builder, "select", attrs))
      builder.mode = if builder.mode is InTable ||
        builder.mode is InCaption ||
        builder.mode is InTableBody ||
        builder.mode is InRow ||
        builder.mode is InCell {
        InSelectInTable
      } else {
        InSelect
      }
      false
    }
    "optgroup" | "option" => {
      if current_is(builder, "option") {
        ignore(pop_stack(builder))
      }
      reconstruct_afe(builder)
      ignore(insert_open(builder, name, attrs))
      false
    }
    "rb" | "rtc" => {
      if has_in_scope(builder, "ruby", Default) {
        generate_implied_end(builder)
      }
      ignore(insert_open(builder, name, attrs))
      false
    }
    "rp" | "rt" => {
      if has_in_scope(builder, "ruby", Default) {
        generate_implied_except(builder, "rtc")
      }
      ignore(insert_open(builder, name, attrs))
      false
    }
    "math" | "svg" => {
      reconstruct_afe(builder)
      ignore(insert_open(builder, name, attrs))
      false
    }
    "caption"
    | "col"
    | "colgroup"
    | "frame"
    | "head"
    | "tbody"
    | "td"
    | "tfoot"
    | "th"
    | "thead"
    | "tr" => {
      builder.repairs.dropped = builder.repairs.dropped + 1
      false
    }
    _ => {
      reconstruct_afe(builder)
      ignore(insert_open(builder, name, attrs))
      false
    }
  }
}

// ------------------------------------------------------------------ end tags

///|
fn end_in(builder : Builder, name : String) -> Bool {
  match builder.mode {
    Initial | BeforeHtml =>
      match name {
        "head" | "body" | "html" | "br" => {
          if builder.mode is Initial {
            builder.quirks = true
          }
          imply_html(builder)
          true
        }
        _ => {
          builder.repairs.dropped = builder.repairs.dropped + 1
          false
        }
      }
    BeforeHead =>
      match name {
        "head" | "body" | "html" | "br" => {
          imply_head(builder)
          true
        }
        _ => {
          builder.repairs.dropped = builder.repairs.dropped + 1
          false
        }
      }
    InHead =>
      match name {
        "head" => {
          close_head(builder)
          builder.mode = AfterHead
          false
        }
        "body" | "html" | "br" => {
          close_head(builder)
          builder.mode = AfterHead
          true
        }
        "template" => {
          pop_through(builder, "template")
          clear_afe_to_marker(builder)
          reset_mode(builder)
          false
        }
        _ =>
          if current_is(builder, name) {
            ignore(pop_stack(builder))
            false
          } else {
            close_head(builder)
            builder.mode = AfterHead
            true
          }
      }
    AfterHead =>
      match name {
        "body" | "html" | "br" => {
          imply_body(builder)
          true
        }
        _ =>
          // A raw-text element the head took back stays open until its own end
          // tag arrives, which comes here rather than to "in head".
          if is_raw_text_tag(name) && current_is(builder, name) {
            ignore(pop_stack(builder))
            false
          } else {
            builder.repairs.dropped = builder.repairs.dropped + 1
            false
          }
      }
    InBody => in_body_end(builder, name)
    InTable => in_table_end(builder, name)
    InTableText => {
      flush_table_text(builder)
      builder.mode = InTable
      true
    }
    InCaption =>
      match name {
        "caption" => {
          if has_in_scope(builder, "caption", Table) {
            generate_implied_end(builder)
            pop_through(builder, "caption")
            clear_afe_to_marker(builder)
          } else {
            builder.repairs.dropped = builder.repairs.dropped + 1
          }
          builder.mode = InTable
          false
        }
        "table" =>
          if has_in_scope(builder, "caption", Table) {
            generate_implied_end(builder)
            pop_through(builder, "caption")
            clear_afe_to_marker(builder)
            builder.mode = InTable
            true
          } else {
            builder.repairs.dropped = builder.repairs.dropped + 1
            false
          }
        "body"
        | "col"
        | "colgroup"
        | "html"
        | "tbody"
        | "td"
        | "tfoot"
        | "th"
        | "thead"
        | "tr" => {
          builder.repairs.dropped = builder.repairs.dropped + 1
          false
        }
        _ => in_body_end(builder, name)
      }
    InColumnGroup =>
      match name {
        "colgroup" => {
          if current_is(builder, "colgroup") {
            ignore(pop_stack(builder))
            builder.mode = InTable
          } else {
            builder.repairs.dropped = builder.repairs.dropped + 1
          }
          false
        }
        "col" => {
          builder.repairs.dropped = builder.repairs.dropped + 1
          false
        }
        "template" => {
          ignore(in_body_end(builder, name))
          false
        }
        _ =>
          if current_is(builder, "colgroup") {
            ignore(pop_stack(builder))
            builder.mode = InTable
            true
          } else {
            builder.repairs.dropped = builder.repairs.dropped + 1
            false
          }
      }
    InTableBody =>
      match name {
        "tbody" | "tfoot" | "thead" => {
          if has_in_scope(builder, name, Table) {
            clear_to_table_body(builder)
            ignore(pop_stack(builder))
            builder.mode = InTable
          } else {
            builder.repairs.dropped = builder.repairs.dropped + 1
          }
          false
        }
        "table" =>
          if has_any_in_scope(builder, ["tbody", "thead", "tfoot"], Table) {
            clear_to_table_body(builder)
            ignore(pop_stack(builder))
            builder.mode = InTable
            true
          } else {
            builder.repairs.dropped = builder.repairs.dropped + 1
            false
          }
        "body" | "caption" | "col" | "colgroup" | "html" | "td" | "th" | "tr" => {
          builder.repairs.dropped = builder.repairs.dropped + 1
          false
        }
        _ => in_table_end(builder, name)
      }
    InRow =>
      match name {
        "tr" => {
          if has_in_scope(builder, "tr", Table) {
            clear_to_row(builder)
            ignore(pop_stack(builder))
            builder.mode = InTableBody
          } else {
            builder.repairs.dropped = builder.repairs.dropped + 1
          }
          false
        }
        "table" =>
          if has_in_scope(builder, "tr", Table) {
            clear_to_row(builder)
            ignore(pop_stack(builder))
            builder.mode = InTableBody
            true
          } else {
            builder.repairs.dropped = builder.repairs.dropped + 1
            false
          }
        "tbody" | "tfoot" | "thead" =>
          if has_in_scope(builder, name, Table) &&
            has_in_scope(builder, "tr", Table) {
            clear_to_row(builder)
            ignore(pop_stack(builder))
            builder.mode = InTableBody
            true
          } else {
            builder.repairs.dropped = builder.repairs.dropped + 1
            false
          }
        "body" | "caption" | "col" | "colgroup" | "html" | "td" | "th" => {
          builder.repairs.dropped = builder.repairs.dropped + 1
          false
        }
        _ => in_table_end(builder, name)
      }
    InCell =>
      match name {
        "td" | "th" => {
          if has_in_scope(builder, name, Table) {
            generate_implied_end(builder)
            pop_through(builder, name)
            clear_afe_to_marker(builder)
            builder.mode = InRow
          } else {
            builder.repairs.dropped = builder.repairs.dropped + 1
          }
          false
        }
        "body" | "caption" | "col" | "colgroup" | "html" => {
          builder.repairs.dropped = builder.repairs.dropped + 1
          false
        }
        "table" | "tbody" | "tfoot" | "thead" | "tr" =>
          if has_in_scope(builder, name, Table) {
            close_cell(builder)
            true
          } else {
            builder.repairs.dropped = builder.repairs.dropped + 1
            false
          }
        _ => in_body_end(builder, name)
      }
    InSelect | InSelectInTable => {
      let table_context = builder.mode is InSelectInTable
      match name {
        "optgroup" => {
          if current_is(builder, "option") &&
            builder.stack.length() >= 2 &&
            builder.stack[builder.stack.length() - 2].name == "optgroup" {
            ignore(pop_stack(builder))
          }
          if current_is(builder, "optgroup") {
            ignore(pop_stack(builder))
          }
          false
        }
        "option" => {
          if current_is(builder, "option") {
            ignore(pop_stack(builder))
          }
          false
        }
        "select" => {
          if has_in_scope(builder, "select", Select) {
            pop_through(builder, "select")
            reset_mode(builder)
          }
          false
        }
        _ =>
          if table_context &&
            (
              name == "caption" ||
              name == "table" ||
              name == "tbody" ||
              name == "tfoot" ||
              name == "thead" ||
              name == "tr" ||
              name == "td" ||
              name == "th"
            ) {
            if has_any_in_scope(
                builder,
                ["table", "tbody", "tfoot", "thead", "tr"],
                Table,
              ) {
              pop_through(builder, "select")
              reset_mode(builder)
              true
            } else {
              builder.repairs.dropped = builder.repairs.dropped + 1
              false
            }
          } else {
            builder.repairs.dropped = builder.repairs.dropped + 1
            false
          }
      }
    }
    AfterBody =>
      if name == "html" {
        builder.mode = AfterAfterBody
        false
      } else {
        builder.mode = InBody
        true
      }
    AfterAfterBody => {
      builder.mode = InBody
      true
    }
  }
}

///|
fn in_table_end(builder : Builder, name : String) -> Bool {
  match name {
    "table" => {
      if has_in_scope(builder, "table", Table) {
        pop_through(builder, "table")
        reset_mode(builder)
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
      }
      false
    }
    "body"
    | "caption"
    | "col"
    | "colgroup"
    | "html"
    | "tbody"
    | "td"
    | "tfoot"
    | "th"
    | "thead"
    | "tr" => {
      builder.repairs.dropped = builder.repairs.dropped + 1
      false
    }
    _ => {
      builder.foster = true
      let again = in_body_end(builder, name)
      builder.foster = false
      again
    }
  }
}

///|
fn in_body_end(builder : Builder, name : String) -> Bool {
  match name {
    "template" => {
      if has_on_stack(builder, "template") {
        generate_implied_end(builder)
        pop_through(builder, "template")
        clear_afe_to_marker(builder)
        reset_mode(builder)
      }
      false
    }
    "body" => {
      if has_in_scope(builder, "body", Default) {
        builder.mode = AfterBody
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
      }
      false
    }
    "html" =>
      if has_in_scope(builder, "body", Default) {
        builder.mode = AfterBody
        true
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
        false
      }
    "address"
    | "article"
    | "aside"
    | "blockquote"
    | "button"
    | "center"
    | "details"
    | "dialog"
    | "dir"
    | "div"
    | "dl"
    | "fieldset"
    | "figcaption"
    | "figure"
    | "footer"
    | "header"
    | "hgroup"
    | "listing"
    | "main"
    | "menu"
    | "nav"
    | "ol"
    | "pre"
    | "section"
    | "summary"
    | "ul" => {
      if has_in_scope(builder, name, Default) {
        generate_implied_end(builder)
        pop_through(builder, name)
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
      }
      false
    }
    "form" => {
      let target = builder.form
      builder.form = None
      match target {
        Some(node) =>
          if on_stack(builder, node) && has_in_scope(builder, "form", Default) {
            generate_implied_end(builder)
            ignore(remove_from_stack(builder, node))
          }
        None => ()
      }
      false
    }
    "p" => {
      if !has_in_scope(builder, "p", Button) {
        implied(builder)
        ignore(insert_open(builder, "p", []))
      }
      close_p(builder)
      false
    }
    "li" => {
      if has_in_scope(builder, "li", ListItem) {
        generate_implied_except(builder, "li")
        pop_through(builder, "li")
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
      }
      false
    }
    "dd" | "dt" => {
      if has_in_scope(builder, name, Default) {
        generate_implied_except(builder, name)
        pop_through(builder, name)
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
      }
      false
    }
    "h1" | "h2" | "h3" | "h4" | "h5" | "h6" => {
      if has_any_in_scope(
          builder,
          ["h1", "h2", "h3", "h4", "h5", "h6"],
          Default,
        ) {
        generate_implied_end(builder)
        pop_until(builder, ["h1", "h2", "h3", "h4", "h5", "h6"])
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
      }
      false
    }
    "a"
    | "b"
    | "big"
    | "code"
    | "em"
    | "font"
    | "i"
    | "nobr"
    | "s"
    | "small"
    | "strike"
    | "strong"
    | "tt"
    | "u" => {
      adoption_agency(builder, name)
      false
    }
    "applet" | "marquee" | "object" => {
      if has_in_scope(builder, name, Default) {
        generate_implied_end(builder)
        pop_through(builder, name)
        clear_afe_to_marker(builder)
      } else {
        builder.repairs.dropped = builder.repairs.dropped + 1
      }
      false
    }
    "br" => {
      // A closing br is a br: the tokenizer's start-tag path, as the spec says.
      reconstruct_afe(builder)
      ignore(insert_element(builder, "br", []))
      false
    }
    _ => {
      any_other_end_tag(builder, name)
      false
    }
  }
}

// ------------------------------------------------------- the awkward corners

///|
/// The spec's "any other end tag": walk outward for a matching element, and
/// stop at the first special one — which is why `</span>` can do nothing at
/// all.
fn any_other_end_tag(builder : Builder, name : String) -> Unit {
  let mut k = builder.stack.length() - 1
  while k >= 1 {
    let node = builder.stack[k]
    if node.name == name {
      generate_implied_except(builder, name)
      while builder.stack.length() > k {
        ignore(pop_stack(builder))
      }
      return
    }
    if is_special(node.name) {
      builder.repairs.dropped = builder.repairs.dropped + 1
      return
    }
    k = k - 1
  }
  builder.repairs.dropped = builder.repairs.dropped + 1
}

///|
fn index_on_stack(builder : Builder, element : @moonxml.Element) -> Int32? {
  let mut k = 0
  while k < builder.stack.length() {
    if physical_equal(builder.stack[k], element) {
      return Some(k)
    }
    k = k + 1
  }
  None
}

///|
/// Whether a particular element is in the given scope.
fn in_scope_element(
  builder : Builder,
  element : @moonxml.Element,
  scope : Scope,
) -> Bool {
  let mut k = builder.stack.length() - 1
  while k >= 0 {
    let here = builder.stack[k]
    if physical_equal(here, element) {
      return true
    }
    if is_scoped_by(here.name, scope) {
      return false
    }
    k = k - 1
  }
  false
}

///|
fn insert_afe_at(
  builder : Builder,
  at : Int32,
  element : @moonxml.Element,
) -> Unit {
  let pos = if at > builder.afe.length() {
    builder.afe.length()
  } else if at < 0 {
    0
  } else {
    at
  }
  builder.afe.insert(pos, Some(element))
}

///|
/// The adoption agency algorithm: the spec's answer to misnested formatting,
/// `<b><p></b>` included. Eight passes, because the spec says eight.
fn adoption_agency(builder : Builder, subject : String) -> Unit {
  if current(builder).name == subject && find_afe(builder, subject) is None {
    ignore(pop_stack(builder))
    return
  }
  let mut outer = 0
  while outer < 8 {
    outer = outer + 1
    let formatting = match find_afe(builder, subject) {
      Some(el) => el
      None => {
        any_other_end_tag(builder, subject)
        return
      }
    }
    if !on_stack(builder, formatting) {
      match afe_index(builder, formatting) {
        Some(at) => ignore(builder.afe.remove(at))
        None => ()
      }
      return
    }
    if !in_scope_element(builder, formatting, Default) {
      builder.repairs.dropped = builder.repairs.dropped + 1
      return
    }
    let fmt_at = match index_on_stack(builder, formatting) {
      Some(at) => at
      None => return
    }
    let mut furthest : @moonxml.Element? = None
    let mut k = fmt_at + 1
    while k < builder.stack.length() {
      if is_special(builder.stack[k].name) {
        furthest = Some(builder.stack[k])
        break
      }
      k = k + 1
    }
    let block = match furthest {
      Some(el) => el
      None => {
        generate_implied_end(builder)
        pop_through(builder, subject)
        match afe_index(builder, formatting) {
          Some(at) => ignore(builder.afe.remove(at))
          None => ()
        }
        return
      }
    }
    let common = if fmt_at >= 1 {
      builder.stack[fmt_at - 1]
    } else {
      builder.doc.root
    }
    let mut bookmark = match afe_index(builder, formatting) {
      Some(at) => at
      None => return
    }
    let mut node = block
    let mut last = block
    let mut inner = 0
    while true {
      inner = inner + 1
      let node_at = match index_on_stack(builder, node) {
        Some(at) => at
        None => break
      }
      if node_at == 0 {
        break
      }
      node = builder.stack[node_at - 1]
      if physical_equal(node, formatting) {
        break
      }
      let mut node_afe = afe_index(builder, node)
      if inner > 3 {
        match node_afe {
          Some(at) => {
            ignore(builder.afe.remove(at))
            node_afe = None
          }
          None => ()
        }
      }
      match node_afe {
        None => ignore(remove_from_stack(builder, node))
        Some(at) => {
          let fresh = @moonxml.Element::new(node.name, attrs=node.attrs.copy())
          builder.afe[at] = Some(fresh)
          match index_on_stack(builder, node) {
            Some(where_) => builder.stack[where_] = fresh
            None => ()
          }
          node = fresh
          if physical_equal(last, block) {
            bookmark = at + 1
          }
          node.append(@moonxml.ElementNode(last))
          last = node
        }
      }
    }
    common.append(@moonxml.ElementNode(last))
    let fresh = @moonxml.Element::new(
      formatting.name,
      attrs=formatting.attrs.copy(),
    )
    // A node's parent lives on the element, not on a text node, so the move
    // empties the block first rather than appending what is already there.
    let kids = block.childrens.copy()
    block.clear()
    for kid in kids {
      fresh.append(kid)
    }
    block.append(@moonxml.ElementNode(fresh))
    match afe_index(builder, formatting) {
      Some(at) => {
        ignore(builder.afe.remove(at))
        if at < bookmark {
          bookmark = bookmark - 1
        }
      }
      None => ()
    }
    insert_afe_at(builder, bookmark, fresh)
    ignore(remove_from_stack(builder, formatting))
    match index_on_stack(builder, block) {
      Some(at) => builder.stack.insert(at + 1, fresh)
      None => ()
    }
  }
}

///|
/// The spec's "reset the insertion mode appropriately": what the parser is in
/// the middle of, worked out from the stack rather than remembered.
fn reset_mode(builder : Builder) -> Unit {
  let mut k = builder.stack.length() - 1
  while k >= 0 {
    let here = builder.stack[k].name
    let last = k == 0
    match here {
      "select" => {
        let mut in_table = false
        let mut j = k - 1
        while j >= 0 {
          let above = builder.stack[j].name
          if above == "template" {
            break
          }
          if above == "table" {
            in_table = true
            break
          }
          j = j - 1
        }
        builder.mode = if in_table { InSelectInTable } else { InSelect }
        return
      }
      "td" | "th" =>
        if !last {
          builder.mode = InCell
          return
        }
      "tr" => {
        builder.mode = InRow
        return
      }
      "tbody" | "thead" | "tfoot" => {
        builder.mode = InTableBody
        return
      }
      "caption" => {
        builder.mode = InCaption
        return
      }
      "colgroup" => {
        builder.mode = InColumnGroup
        return
      }
      "table" => {
        builder.mode = InTable
        return
      }
      "template" => {
        builder.mode = InBody
        return
      }
      "head" =>
        if !last {
          builder.mode = InHead
          return
        }
      "body" => {
        builder.mode = InBody
        return
      }
      "html" => {
        builder.mode = match builder.head {
          Some(_) => AfterHead
          None => BeforeHead
        }
        return
      }
      "#document" => {
        builder.mode = InBody
        return
      }
      _ => ()
    }
    k = k - 1
  }
  builder.mode = InBody
}
