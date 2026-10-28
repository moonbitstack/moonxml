// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The insertion modes, in the standard's order. A mode handles one token and
// either answers or hands it on — `dispatch` again with the mode it has moved
// to, which is the standard's "reprocess the token".

///|
fn process(lexer : Lexer, token : Token) -> Unit {
  dispatch(lexer.builder, lexer, token, 0)
}

///|
/// How many times one token may be handed on before the parser stops handing
/// it on. Every hand-on changes the mode, so a document that means something
/// needs a handful.
fn reprocess_bound() -> Int32 {
  64
}

///|
fn dispatch(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  if depth > reprocess_bound() {
    return
  }
  if in_foreign_content(b, token) {
    foreign_content(b, lx, token, depth)
    return
  }
  dispatch_html(b, lx, token, depth)
}

///|
/// The modes, without the foreign content check in front of them: what a token
/// that broke out of an SVG subtree is read by.
fn dispatch_html(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  if depth > reprocess_bound() {
    return
  }
  match b.mode {
    Initial => initial(b, lx, token, depth)
    BeforeHtml => before_html(b, lx, token, depth)
    BeforeHead => before_head(b, lx, token, depth)
    InHead => in_head(b, lx, token, depth)
    InHeadNoscript => in_head_noscript(b, lx, token, depth)
    AfterHead => after_head(b, lx, token, depth)
    InBody => in_body(b, lx, token, depth)
    Text => in_text(b, lx, token, depth)
    InTable => in_table(b, lx, token, depth)
    InTableText => in_table_text(b, lx, token, depth)
    InCaption => in_caption(b, lx, token, depth)
    InColumnGroup => in_column_group(b, lx, token, depth)
    InTableBody => in_table_body(b, lx, token, depth)
    InRow => in_row(b, lx, token, depth)
    InCell => in_cell(b, lx, token, depth)
    InSelect => in_select(b, lx, token, depth)
    InSelectInTable => in_select_in_table(b, lx, token, depth)
    InTemplate => in_template(b, lx, token, depth)
    AfterBody => after_body(b, lx, token, depth)
    InFrameset => in_frameset(b, lx, token, depth)
    AfterFrameset => after_frameset(b, lx, token, depth)
    AfterAfterBody => after_after_body(b, lx, token, depth)
    AfterAfterFrameset => after_after_frameset(b, lx, token, depth)
  }
}

///|
/// Whether the token is read by the foreign content rules rather than by the
/// mode's own: the standard's tree construction dispatcher.
fn in_foreign_content(b : Builder, token : Token) -> Bool {
  if b.stack.is_empty() {
    return false
  }
  let node = match adjusted_current(b) {
    Some(el) => el
    None => return false
  }
  if namespace_of_element(node) == html_namespace {
    return false
  }
  if is_mathml_text_integration_point(node) {
    match token {
      StartTag(name~, ..) =>
        if name != "mglyph" && name != "malignmark" {
          return false
        }
      Characters(_) => return false
      _ => ()
    }
  }
  if namespace_of_element(node) == mathml_namespace &&
    @moonxml.local_of(node.name) == "annotation-xml" {
    match token {
      StartTag(name~, ..) => if name == "svg" { return false }
      _ => ()
    }
  }
  if is_html_integration_point(node) {
    match token {
      StartTag(..) => return false
      Characters(_) => return false
      _ => ()
    }
  }
  match token {
    Eof => false
    _ => true
  }
}

// ------------------------------------------------------------- the prologue

///|
fn initial(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    Characters(text~) =>
      if is_space_text(text) {
        return
      } else {
        b.quirks = true
        b.mode = BeforeHtml
        dispatch(b, lx, token, depth + 1)
      }
    CommentToken(text~) => insert_comment_into(b.root, text)
    DoctypeToken(name~, public_id~, system_id~, force_quirks~) => {
      b.quirks = match quirks_of(name, public_id, system_id, force_quirks) {
        Quirks => true
        NoQuirks | LimitedQuirks => false
      }
      let raw = doctype_text(name, public_id, system_id)
      b.root.append(@moonxml.DoctypeNode(raw))
      b.mode = BeforeHtml
    }
    _ => {
      b.quirks = true
      b.mode = BeforeHtml
      dispatch(b, lx, token, depth + 1)
    }
  }
}

///|
/// How a document's doctype sets the parser's quirks flag. Limited quirks is
/// the middle state: it changes the box model in a browser, but not how a
/// table closes a paragraph.
priv enum QuirkState {
  NoQuirks
  LimitedQuirks
  Quirks
}

///|
/// The standard's quirks rules, from the doctype's three parts.
fn quirks_of(
  name : String,
  public_id : String,
  system_id : String,
  force_quirks : Bool,
) -> QuirkState {
  if force_quirks || name != "html" {
    return Quirks
  }
  let public = public_id.to_lower()
  let system = system_id.to_lower()
  if public.has_prefix("-//w3c//dtd xhtml 1.0 frameset//") ||
    public.has_prefix("-//w3c//dtd xhtml 1.0 transitional//") {
    return LimitedQuirks
  }
  if !system_id.is_empty() &&
    (
      public.has_prefix("-//w3c//dtd html 4.01 frameset//") ||
      public.has_prefix("-//w3c//dtd html 4.01 transitional//")
    ) {
    return LimitedQuirks
  }
  for
    prefix in [
      "+//silmaril//dtd html pro v0r11 19970101//", "-//advasoft ltd//dtd html 3.0 aswedit + extensions//",
      "-//as//dtd html 3.0 aswedit + extensions//", "-//ietf//dtd html 2.0 level 1//",
      "-//ietf//dtd html 2.0 level 2//", "-//ietf//dtd html 2.0 strict level 1//",
      "-//ietf//dtd html 2.0 strict level 2//", "-//ietf//dtd html 2.0 strict//",
      "-//ietf//dtd html 2.0//", "-//ietf//dtd html 2.1e//", "-//ietf//dtd html 3.0//",
      "-//ietf//dtd html 3.2 final//", "-//ietf//dtd html 3.2//", "-//ietf//dtd html 3//",
      "-//ietf//dtd html level 0//", "-//ietf//dtd html level 1//", "-//ietf//dtd html level 2//",
      "-//ietf//dtd html level 3//", "-//ietf//dtd html strict level 0//", "-//ietf//dtd html strict level 1//",
      "-//ietf//dtd html strict level 2//", "-//ietf//dtd html strict level 3//",
      "-//ietf//dtd html strict//", "-//ietf//dtd html//", "-//metrius//dtd metrius presentational//",
      "-//microsoft//dtd internet explorer 2.0 html strict//", "-//microsoft//dtd internet explorer 2.0 html//",
      "-//microsoft//dtd internet explorer 2.0 tables//", "-//microsoft//dtd internet explorer 3.0 html strict//",
      "-//microsoft//dtd internet explorer 3.0 html//", "-//microsoft//dtd internet explorer 3.0 tables//",
      "-//netscape comm. corp.//dtd html//", "-//netscape comm. corp.//dtd strict html//",
      "-//o'reilly and associates//dtd html 2.0//", "-//o'reilly and associates//dtd html extended 1.0//",
      "-//o'reilly and associates//dtd html extended relaxed 1.0//", "-//sq//dtd html 2.0 hotmetal + extensions//",
      "-//softquad software//dtd hotmetal pro 6.0::19990601::extensions to html 4.0//",
      "-//softquad//dtd hotmetal pro 4.0::19971010::extensions to html 4.0//", "-//spyglass//dtd html 2.0 extended//",
      "-//sun microsystems corp.//dtd hotjava html//", "-//sun microsystems corp.//dtd hotjava strict html//",
      "-//w3c//dtd html 3 1995-03-24//", "-//w3c//dtd html 3.2 draft//", "-//w3c//dtd html 3.2 final//",
      "-//w3c//dtd html 3.2//", "-//w3c//dtd html 3.2s draft//", "-//w3c//dtd html 4.0 frameset//",
      "-//w3c//dtd html 4.0 transitional//", "-//w3c//dtd html experimental 19960712//",
      "-//w3c//dtd html experimental 970421//", "-//w3c//dtd w3 html//", "-//w3o//dtd w3 html 3.0//",
      "-//webtechs//dtd mozilla html 2.0//", "-//webtechs//dtd mozilla html//",
    ] {
    if public.has_prefix(prefix) {
      return Quirks
    }
  }
  if system == "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd" {
    return Quirks
  }
  if system_id.is_empty() &&
    (
      public.has_prefix("-//w3c//dtd html 4.01 frameset//") ||
      public.has_prefix("-//w3c//dtd html 4.01 transitional//")
    ) {
    return Quirks
  }
  NoQuirks
}

///|
/// A doctype as the writer spells it back: its name, and its identifiers when
/// it has them.
fn doctype_text(
  name : String,
  public_id : String,
  system_id : String,
) -> String {
  if public_id.is_empty() && system_id.is_empty() {
    return name
  }
  // Both identifiers are written when either is there, quoted, in the order
  // the declaration gives them.
  name + " \"" + public_id + "\" \"" + system_id + "\""
}

///|
fn is_space_text(text : String) -> Bool {
  if text.is_empty() {
    return false
  }
  let unit = text.at(0)
  unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0C || unit == 0x0D
}

///|
fn before_html(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    DoctypeToken(_) => ()
    CommentToken(text~) => insert_comment_into(b.root, text)
    Characters(text~) =>
      if !is_space_text(text) {
        note_implied(b)
        let element = insert_element(b, "html", [])
        push(b, element)
        b.mode = BeforeHead
        dispatch(b, lx, token, depth + 1)
      }
    StartTag(name~, attrs~, ..) =>
      if name == "html" {
        let element = insert_element(b, "html", attrs)
        push(b, element)
        b.mode = BeforeHead
      } else {
        note_implied(b)
        let element = insert_element(b, "html", [])
        push(b, element)
        b.mode = BeforeHead
        dispatch(b, lx, token, depth + 1)
      }
    EndTag(name~) =>
      if name == "head" || name == "body" || name == "html" || name == "br" {
        note_implied(b)
        let element = insert_element(b, "html", [])
        push(b, element)
        b.mode = BeforeHead
        dispatch(b, lx, token, depth + 1)
      }
    _ => {
      note_implied(b)
      let element = insert_element(b, "html", [])
      push(b, element)
      b.mode = BeforeHead
      dispatch(b, lx, token, depth + 1)
    }
  }
}

///|
fn before_head(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    Characters(text~) =>
      if !is_space_text(text) {
        note_implied(b)
        let head = insert_element(b, "head", [])
        push(b, head)
        b.head = Some(head)
        b.mode = InHead
        dispatch(b, lx, token, depth + 1)
      }
    CommentToken(text~) => insert_comment(b, text)
    DoctypeToken(_) => ()
    StartTag(name~, attrs~, ..) =>
      if name == "html" {
        in_body(b, lx, token, depth + 1)
      } else if name == "head" {
        let head = insert_element(b, "head", attrs)
        push(b, head)
        b.head = Some(head)
        b.mode = InHead
      } else {
        note_implied(b)
        let head = insert_element(b, "head", [])
        push(b, head)
        b.head = Some(head)
        b.mode = InHead
        dispatch(b, lx, token, depth + 1)
      }
    EndTag(name~) =>
      if name == "head" || name == "body" || name == "html" || name == "br" {
        note_implied(b)
        let head = insert_element(b, "head", [])
        push(b, head)
        b.head = Some(head)
        b.mode = InHead
        dispatch(b, lx, token, depth + 1)
      }
    _ => {
      note_implied(b)
      let head = insert_element(b, "head", [])
      push(b, head)
      b.head = Some(head)
      b.mode = InHead
      dispatch(b, lx, token, depth + 1)
    }
  }
}

///|
fn in_head(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    Characters(text~) =>
      if is_space_text(text) {
        insert_text(b, text)
      } else {
        ignore(pop(b))
        b.mode = AfterHead
        dispatch(b, lx, token, depth + 1)
      }
    CommentToken(text~) => insert_comment(b, text)
    DoctypeToken(_) => ()
    StartTag(name~, attrs~, self_closing~) =>
      match name {
        "html" => in_body(b, lx, token, depth + 1)
        "base" | "basefont" | "bgsound" | "link" | "meta" => {
          ignore(insert_element_open(b, name, attrs))
          ignore(pop(b))
          ignore(self_closing)
        }
        "title" => {
          let element = insert_element(b, "title", attrs)
          push(b, element)
          lx.raw_name = "title"
          lx.state = Rcdata
          b.text_mode = b.mode
          b.mode = Text
        }
        "noscript" => {
          let element = insert_element(b, "noscript", attrs)
          push(b, element)
          b.mode = InHeadNoscript
        }
        "noframes" | "style" => {
          let element = insert_element(b, name, attrs)
          push(b, element)
          lx.raw_name = name
          lx.state = Rawtext
          b.text_mode = b.mode
          b.mode = Text
        }
        "script" => {
          let element = insert_element(b, "script", attrs)
          push(b, element)
          lx.raw_name = "script"
          lx.state = ScriptData
          b.text_mode = b.mode
          b.mode = Text
        }
        "template" => {
          let element = insert_template(b, attrs)
          push(b, element)
          push_marker(b)
          b.frameset_ok = false
          b.mode = InTemplate
          b.templates.push(InTemplate)
        }
        "head" => ()
        _ => {
          ignore(pop(b))
          b.mode = AfterHead
          dispatch(b, lx, token, depth + 1)
        }
      }
    EndTag(name~) =>
      match name {
        "head" => {
          ignore(pop(b))
          b.mode = AfterHead
        }
        "body" | "html" | "br" => {
          ignore(pop(b))
          b.mode = AfterHead
          dispatch(b, lx, token, depth + 1)
        }
        "template" => end_template(b, lx, depth)
        _ => ()
      }
    _ => {
      ignore(pop(b))
      b.mode = AfterHead
      dispatch(b, lx, token, depth + 1)
    }
  }
}

///|
fn in_head_noscript(
  b : Builder,
  lx : Lexer,
  token : Token,
  depth : Int32,
) -> Unit {
  match token {
    DoctypeToken(_) => ()
    StartTag(name~, ..) =>
      if name == "html" {
        in_body(b, lx, token, depth + 1)
      } else if name == "basefont" ||
        name == "bgsound" ||
        name == "link" ||
        name == "meta" ||
        name == "noframes" ||
        name == "style" {
        in_head(b, lx, token, depth + 1)
      } else if name == "head" || name == "noscript" {
        ()
      } else {
        ignore(pop(b))
        b.mode = InHead
        dispatch(b, lx, token, depth + 1)
      }
    EndTag(name~) =>
      if name == "noscript" {
        ignore(pop(b))
        b.mode = InHead
      } else if name == "br" {
        ignore(pop(b))
        b.mode = InHead
        dispatch(b, lx, token, depth + 1)
      }
    Characters(text~) =>
      if is_space_text(text) {
        in_head(b, lx, token, depth + 1)
      } else {
        ignore(pop(b))
        b.mode = InHead
        dispatch(b, lx, token, depth + 1)
      }
    CommentToken(_) => in_head(b, lx, token, depth + 1)
    _ => {
      ignore(pop(b))
      b.mode = InHead
      dispatch(b, lx, token, depth + 1)
    }
  }
}

///|
fn after_head(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    Characters(text~) =>
      if is_space_text(text) {
        insert_text(b, text)
      } else {
        note_implied(b)
        let body = insert_element(b, "body", [])
        push(b, body)
        b.mode = InBody
        dispatch(b, lx, token, depth + 1)
      }
    CommentToken(text~) => insert_comment(b, text)
    DoctypeToken(_) => ()
    StartTag(name~, attrs~, self_closing~) =>
      match name {
        "html" => in_body(b, lx, token, depth + 1)
        "body" => {
          let body = insert_element(b, "body", attrs)
          push(b, body)
          b.frameset_ok = false
          b.mode = InBody
        }
        "frameset" => {
          let frameset = insert_element(b, "frameset", attrs)
          push(b, frameset)
          b.mode = InFrameset
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
          match b.head {
            Some(head) => push(b, head)
            None => ()
          }
          in_head(b, lx, token, depth + 1)
          // The head goes back off the stack once the element it took has
          // been dealt with.
          match b.head {
            Some(head) => ignore(remove_from_stack(b, head))
            None => ()
          }
          ignore(self_closing)
        }
        "head" => ()
        _ => {
          note_implied(b)
          let body = insert_element(b, "body", [])
          push(b, body)
          b.mode = InBody
          dispatch(b, lx, token, depth + 1)
        }
      }
    EndTag(name~) =>
      if name == "template" {
        in_head(b, lx, token, depth + 1)
      } else if name == "body" || name == "html" || name == "br" {
        note_implied(b)
        let body = insert_element(b, "body", [])
        push(b, body)
        b.mode = InBody
        dispatch(b, lx, token, depth + 1)
      }
    _ => {
      note_implied(b)
      let body = insert_element(b, "body", [])
      push(b, body)
      b.mode = InBody
      dispatch(b, lx, token, depth + 1)
    }
  }
}

///|
fn remove_from_stack(b : Builder, element : @moonxml.Element) -> Bool {
  match index_on_stack(b, element) {
    Some(at) => {
      ignore(b.stack.remove(at))
      true
    }
    None => false
  }
}

///|
/// `</template>`: close the template, its formatting elements, and go back to
/// whatever the stack says the parser was in.
fn end_template(b : Builder, lx : Lexer, depth : Int32) -> Unit {
  ignore(lx)
  ignore(depth)
  if !has_on_stack(b, "template") {
    return
  }
  generate_implied_end(b, "")
  pop_until_name(b, "template")
  clear_afe_to_marker(b)
  if !b.templates.is_empty() {
    ignore(b.templates.pop())
  }
  reset_mode(b)
}

// ------------------------------------------------------------------ in body

///|
fn in_body(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    Characters(text~) => {
      let cleaned = text_for(b, text)
      if cleaned.is_empty() {
        return
      }
      reconstruct_afe(b)
      insert_text(b, cleaned)
      if !is_space_text(cleaned) {
        b.frameset_ok = false
      }
    }
    CommentToken(text~) => insert_comment(b, text)
    DoctypeToken(_) => ()
    StartTag(name~, attrs~, self_closing~) =>
      start_in_body(b, lx, name, attrs, self_closing, depth)
    EndTag(name~) => end_in_body(b, lx, name, depth)
    Eof =>
      if !b.templates.is_empty() {
        in_template(b, lx, token, depth + 1)
        return
      }
  }
}

///|
fn text_for(b : Builder, text : String) -> String {
  let mut cleaned = strip_nulls(text)
  if b.skip_lf {
    b.skip_lf = false
    if cleaned.has_prefix("\n") {
      cleaned = cleaned[1:cleaned.length()].to_owned()
    }
  }
  cleaned
}

///|
fn strip_nulls(text : String) -> String {
  if !text.contains("\u{0}") {
    return text
  }
  let out = StringBuilder()
  for ch in text {
    if ch != '\u{0}' {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
fn start_in_body(
  b : Builder,
  lx : Lexer,
  name : String,
  attrs : Array[(String, String)],
  self_closing : Bool,
  depth : Int32,
) -> Unit {
  match name {
    "html" => {
      if has_on_stack(b, "template") {
        return
      }
      match html_element(b) {
        Some(html) => merge_attrs(html, attrs)
        None => ()
      }
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
    | "title" =>
      in_head(b, lx, StartTag(name~, attrs~, self_closing~), depth + 1)
    "body" =>
      match body_element(b) {
        Some(body) =>
          if b.stack.length() > 1 && !has_on_stack(b, "template") {
            b.frameset_ok = false
            merge_attrs(body, attrs)
          }
        None => ()
      }
    "frameset" => {
      if b.stack.length() < 2 {
        return
      }
      if b.stack[1].name != "body" && b.stack[1].name != "frameset" {
        return
      }
      if !b.frameset_ok {
        return
      }
      match body_element(b) {
        Some(body) => ignore(body.remove())
        None => ()
      }
      while b.stack.length() > 1 {
        ignore(pop(b))
      }
      let frameset = insert_element(b, "frameset", attrs)
      push(b, frameset)
      b.mode = InFrameset
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
    | "search"
    | "section"
    | "summary"
    | "ul" => {
      if has_in_scope(b, "p", Button) {
        close_p(b)
      }
      ignore(insert_element_open(b, name, attrs))
    }
    "h1" | "h2" | "h3" | "h4" | "h5" | "h6" => {
      if has_in_scope(b, "p", Button) {
        close_p(b)
      }
      if is_heading(current(b).name) {
        ignore(pop(b))
      }
      ignore(insert_element_open(b, name, attrs))
    }
    "pre" | "listing" => {
      if has_in_scope(b, "p", Button) {
        close_p(b)
      }
      ignore(insert_element_open(b, name, attrs))
      b.frameset_ok = false
      b.skip_lf = true
    }
    "form" => {
      let in_template = has_on_stack(b, "template")
      if b.form is Some(_) && !in_template {
        return
      }
      if has_in_scope(b, "p", Button) {
        close_p(b)
      }
      let element = insert_element_open(b, "form", attrs)
      if !in_template {
        b.form = Some(element)
      }
    }
    "li" => {
      b.frameset_ok = false
      let mut k = b.stack.length() - 1
      while k >= 0 {
        let node = b.stack[k]
        if node.name == "li" {
          generate_implied_end(b, "li")
          pop_until_name(b, "li")
          break
        }
        if is_special(node.name) &&
          node.name != "address" &&
          node.name != "div" &&
          node.name != "p" {
          break
        }
        k = k - 1
      }
      if has_in_scope(b, "p", Button) {
        close_p(b)
      }
      ignore(insert_element_open(b, "li", attrs))
    }
    "dd" | "dt" => {
      b.frameset_ok = false
      let mut k = b.stack.length() - 1
      while k >= 0 {
        let node = b.stack[k]
        if node.name == "dd" || node.name == "dt" {
          generate_implied_end(b, node.name)
          pop_until_name(b, node.name)
          break
        }
        if is_special(node.name) &&
          node.name != "address" &&
          node.name != "div" &&
          node.name != "p" {
          break
        }
        k = k - 1
      }
      if has_in_scope(b, "p", Button) {
        close_p(b)
      }
      ignore(insert_element_open(b, name, attrs))
    }
    "plaintext" => {
      if has_in_scope(b, "p", Button) {
        close_p(b)
      }
      ignore(insert_element_open(b, "plaintext", attrs))
      lx.state = Plaintext
    }
    "button" => {
      if has_in_scope(b, "button", Default) {
        generate_implied_end(b, "")
        pop_until_name(b, "button")
      }
      reconstruct_afe(b)
      ignore(insert_element_open(b, "button", attrs))
      b.frameset_ok = false
    }
    "a" => {
      match find_afe(b, "a") {
        Some(existing) => {
          adoption_agency(b, "a")
          match afe_index(b, existing) {
            Some(at) => ignore(b.afe.remove(at))
            None => ()
          }
          ignore(remove_from_stack(b, existing))
        }
        None => ()
      }
      reconstruct_afe(b)
      let element = insert_element_open(b, "a", attrs)
      push_afe(b, element)
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
      reconstruct_afe(b)
      let element = insert_element_open(b, name, attrs)
      push_afe(b, element)
    }
    "nobr" => {
      reconstruct_afe(b)
      if has_in_scope(b, "nobr", Default) {
        adoption_agency(b, "nobr")
        reconstruct_afe(b)
      }
      let element = insert_element_open(b, "nobr", attrs)
      push_afe(b, element)
    }
    "applet" | "marquee" | "object" => {
      reconstruct_afe(b)
      ignore(insert_element_open(b, name, attrs))
      push_marker(b)
      b.frameset_ok = false
    }
    "table" => {
      if !b.quirks && has_in_scope(b, "p", Button) {
        close_p(b)
      }
      ignore(insert_element_open(b, "table", attrs))
      b.frameset_ok = false
      b.mode = InTable
    }
    "area" | "br" | "embed" | "img" | "keygen" | "wbr" => {
      reconstruct_afe(b)
      ignore(insert_element_open(b, name, attrs))
      ignore(pop(b))
      b.frameset_ok = false
      ignore(self_closing)
    }
    "input" => {
      reconstruct_afe(b)
      ignore(insert_element_open(b, "input", attrs))
      ignore(pop(b))
      let mut hidden = false
      for pair in attrs {
        if pair.0 == "type" && pair.1.to_lower() == "hidden" {
          hidden = true
        }
      }
      if !hidden {
        b.frameset_ok = false
      }
      ignore(self_closing)
    }
    "param" | "source" | "track" => {
      ignore(insert_element_open(b, name, attrs))
      ignore(pop(b))
      ignore(self_closing)
    }
    "hr" => {
      if has_in_scope(b, "p", Button) {
        close_p(b)
      }
      ignore(insert_element_open(b, "hr", attrs))
      ignore(pop(b))
      b.frameset_ok = false
      ignore(self_closing)
    }
    "image" => start_in_body(b, lx, "img", attrs, self_closing, depth)
    "textarea" => {
      ignore(insert_element_open(b, "textarea", attrs))
      b.skip_lf = true
      lx.raw_name = "textarea"
      lx.state = Rcdata
      b.text_mode = b.mode
      b.frameset_ok = false
      b.mode = Text
    }
    "xmp" => {
      if has_in_scope(b, "p", Button) {
        close_p(b)
      }
      reconstruct_afe(b)
      b.frameset_ok = false
      ignore(insert_element_open(b, "xmp", attrs))
      lx.raw_name = "xmp"
      lx.state = Rawtext
      b.text_mode = b.mode
      b.mode = Text
    }
    "iframe" => {
      b.frameset_ok = false
      ignore(insert_element_open(b, "iframe", attrs))
      lx.raw_name = "iframe"
      lx.state = Rawtext
      b.text_mode = b.mode
      b.mode = Text
    }
    "noembed" => {
      ignore(insert_element_open(b, "noembed", attrs))
      lx.raw_name = "noembed"
      lx.state = Rawtext
      b.text_mode = b.mode
      b.mode = Text
    }
    "select" => {
      reconstruct_afe(b)
      ignore(insert_element_open(b, "select", attrs))
      b.frameset_ok = false
      b.mode = match b.mode {
        InTable | InCaption | InTableBody | InRow | InCell => InSelectInTable
        _ => InSelect
      }
    }
    "optgroup" | "option" => {
      if current_is(b, "option") {
        ignore(pop(b))
      }
      reconstruct_afe(b)
      ignore(insert_element_open(b, name, attrs))
    }
    "rb" | "rtc" => {
      if has_in_scope(b, "ruby", Default) {
        generate_implied_end(b, "")
      }
      ignore(insert_element_open(b, name, attrs))
    }
    "rp" | "rt" => {
      if has_in_scope(b, "ruby", Default) {
        generate_implied_end(b, "rtc")
      }
      ignore(insert_element_open(b, name, attrs))
    }
    "math" => {
      reconstruct_afe(b)
      let element = insert_foreign(b, "math", attrs, mathml_namespace)
      push(b, element)
      if self_closing {
        ignore(pop(b))
      }
    }
    "svg" => {
      reconstruct_afe(b)
      let element = insert_foreign(b, "svg", attrs, svg_namespace)
      push(b, element)
      if self_closing {
        ignore(pop(b))
      }
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
    | "tr" => note_dropped(b)
    _ => {
      reconstruct_afe(b)
      ignore(insert_element_open(b, name, attrs))
    }
  }
}

///|
fn merge_attrs(
  element : @moonxml.Element,
  attrs : Array[(String, String)],
) -> Unit {
  for pair in attrs {
    if !element.has_attr(pair.0) {
      element.set_attr(pair.0, pair.1)
    }
  }
}

///|
fn end_in_body(b : Builder, lx : Lexer, name : String, depth : Int32) -> Unit {
  ignore(lx)
  ignore(depth)
  match name {
    "template" => end_template(b, lx, depth)
    "body" => if has_in_scope(b, "body", Default) { b.mode = AfterBody }
    "html" =>
      if has_in_scope(b, "body", Default) {
        b.mode = AfterBody
        dispatch(b, lx, EndTag(name~), depth + 1)
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
    | "search"
    | "section"
    | "summary"
    | "ul" =>
      if has_in_scope(b, name, Default) {
        generate_implied_end(b, "")
        pop_until_name(b, name)
      }
    "form" => {
      if has_on_stack(b, "template") {
        if has_in_scope(b, "form", Default) {
          generate_implied_end(b, "")
          pop_until_name(b, "form")
        }
        return
      }
      let target = b.form
      b.form = None
      match target {
        Some(node) =>
          if element_in_scope(b, node, Default) {
            generate_implied_end(b, "")
            ignore(remove_from_stack(b, node))
          }
        None => ()
      }
    }
    "p" => {
      if !has_in_scope(b, "p", Button) {
        note_implied(b)
        ignore(insert_element_open(b, "p", []))
      }
      close_p(b)
    }
    "li" =>
      if has_in_scope(b, "li", ListItem) {
        generate_implied_end(b, "li")
        pop_until_name(b, "li")
      }
    "dd" | "dt" =>
      if has_in_scope(b, name, Default) {
        generate_implied_end(b, name)
        pop_until_name(b, name)
      }
    "h1" | "h2" | "h3" | "h4" | "h5" | "h6" =>
      if has_any_in_scope(b, ["h1", "h2", "h3", "h4", "h5", "h6"], Default) {
        generate_implied_end(b, "")
        pop_until_any(b, ["h1", "h2", "h3", "h4", "h5", "h6"])
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
    | "u" => adoption_agency(b, name)
    "applet" | "marquee" | "object" =>
      if has_in_scope(b, name, Default) {
        generate_implied_end(b, "")
        pop_until_name(b, name)
        clear_afe_to_marker(b)
      }
    "br" => {
      // A closing br is a br.
      reconstruct_afe(b)
      ignore(insert_element_open(b, "br", []))
      ignore(pop(b))
      b.frameset_ok = false
    }
    _ => any_other_end_tag(b, name)
  }
}

///|
/// The standard's "any other end tag": walk outward for a matching element and
/// stop at the first special one.
fn any_other_end_tag(b : Builder, name : String) -> Unit {
  let mut k = b.stack.length() - 1
  while k >= 0 {
    let node = b.stack[k]
    if node.name == name {
      generate_implied_end(b, name)
      while b.stack.length() > k {
        ignore(pop(b))
      }
      return
    }
    if is_special(node.name) {
      note_dropped(b)
      return
    }
    k = k - 1
  }
  note_dropped(b)
}

// ------------------------------------------------------------------- text

///|
fn in_text(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    Characters(text~) => insert_text(b, text_for(b, replace_nulls(text)))
    Eof => {
      ignore(pop(b))
      b.mode = b.text_mode
      dispatch(b, lx, token, depth + 1)
    }
    EndTag(_) => {
      ignore(pop(b))
      b.mode = b.text_mode
    }
    _ => ()
  }
}

// ------------------------------------------------------------------ tables

///|
fn in_table(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    Characters(_) =>
      if is_table_part(current(b).name) {
        b.pending = StringBuilder()
        b.pending_space = true
        b.prior_mode = b.mode
        b.mode = InTableText
        dispatch(b, lx, token, depth + 1)
      } else {
        fostered(b, lx, token, depth)
      }
    CommentToken(text~) => insert_comment(b, text)
    DoctypeToken(_) => ()
    StartTag(name~, attrs~, self_closing~) =>
      match name {
        "caption" => {
          clear_to_table(b)
          push_marker(b)
          ignore(insert_element_open(b, "caption", attrs))
          b.mode = InCaption
        }
        "colgroup" => {
          clear_to_table(b)
          ignore(insert_element_open(b, "colgroup", attrs))
          b.mode = InColumnGroup
        }
        "col" => {
          clear_to_table(b)
          ignore(insert_element_open(b, "colgroup", []))
          b.mode = InColumnGroup
          dispatch(b, lx, token, depth + 1)
        }
        "tbody" | "tfoot" | "thead" => {
          clear_to_table(b)
          ignore(insert_element_open(b, name, attrs))
          b.mode = InTableBody
        }
        "td" | "th" | "tr" => {
          clear_to_table(b)
          note_implied(b)
          ignore(insert_element_open(b, "tbody", []))
          b.mode = InTableBody
          dispatch(b, lx, token, depth + 1)
        }
        "table" =>
          if has_in_scope(b, "table", Table) {
            pop_until_name(b, "table")
            reset_mode(b)
            dispatch(b, lx, token, depth + 1)
          }
        "style" | "script" | "template" =>
          in_head(b, lx, StartTag(name~, attrs~, self_closing~), depth + 1)
        "input" => {
          let mut hidden = false
          for pair in attrs {
            if pair.0 == "type" && pair.1.to_lower() == "hidden" {
              hidden = true
            }
          }
          if hidden {
            ignore(insert_element_open(b, "input", attrs))
            ignore(pop(b))
          } else {
            fostered(b, lx, token, depth)
          }
        }
        "form" =>
          if b.form is None && !has_on_stack(b, "template") {
            let element = insert_element_open(b, "form", attrs)
            b.form = Some(element)
            ignore(pop(b))
          }
        _ => fostered(b, lx, token, depth)
      }
    EndTag(name~) =>
      match name {
        "table" =>
          if has_in_scope(b, "table", Table) {
            pop_until_name(b, "table")
            reset_mode(b)
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
        | "tr" => ()
        "template" => end_template(b, lx, depth)
        _ => fostered(b, lx, token, depth)
      }
    Eof => in_body(b, lx, token, depth + 1)
  }
}

///|
/// Read the token with foster parenting on: what a table cannot hold goes in
/// front of it.
fn fostered(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  ignore(depth)
  note_reparented(b)
  b.foster = true
  in_body(b, lx, token, depth + 1)
  b.foster = false
}

///|
fn in_table_text(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    Characters(text~) => {
      b.pending.write_string(text)
      if !is_space_text(text) {
        b.pending_space = false
      }
    }
    _ => {
      let held = strip_nulls(b.pending.to_string())
      b.pending = StringBuilder()
      let was_space = b.pending_space
      b.pending_space = true
      b.mode = b.prior_mode
      if !held.is_empty() {
        if was_space {
          insert_text(b, held)
        } else {
          b.foster = true
          reconstruct_afe(b)
          insert_text(b, held)
          b.foster = false
        }
      }
      dispatch(b, lx, token, depth + 1)
    }
  }
}

///|
fn in_caption(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    EndTag(name~) =>
      if name == "caption" {
        if has_in_scope(b, "caption", Table) {
          generate_implied_end(b, "")
          pop_until_name(b, "caption")
          clear_afe_to_marker(b)
          b.mode = InTable
        }
      } else if name == "table" {
        if has_in_scope(b, "caption", Table) {
          generate_implied_end(b, "")
          pop_until_name(b, "caption")
          clear_afe_to_marker(b)
          b.mode = InTable
          dispatch(b, lx, token, depth + 1)
        }
      } else if name == "body" ||
        name == "col" ||
        name == "colgroup" ||
        name == "html" ||
        name == "tbody" ||
        name == "td" ||
        name == "tfoot" ||
        name == "th" ||
        name == "thead" ||
        name == "tr" {
        ()
      } else {
        in_body(b, lx, token, depth + 1)
      }
    StartTag(name~, ..) =>
      if name == "caption" ||
        name == "col" ||
        name == "colgroup" ||
        name == "tbody" ||
        name == "td" ||
        name == "tfoot" ||
        name == "th" ||
        name == "thead" ||
        name == "tr" {
        if has_in_scope(b, "caption", Table) {
          generate_implied_end(b, "")
          pop_until_name(b, "caption")
          clear_afe_to_marker(b)
          b.mode = InTable
          dispatch(b, lx, token, depth + 1)
        }
      } else {
        in_body(b, lx, token, depth + 1)
      }
    _ => in_body(b, lx, token, depth + 1)
  }
}

///|
fn in_column_group(
  b : Builder,
  lx : Lexer,
  token : Token,
  depth : Int32,
) -> Unit {
  match token {
    Characters(text~) =>
      if is_space_text(text) {
        insert_text(b, text)
      } else if current_is(b, "colgroup") {
        ignore(pop(b))
        b.mode = InTable
        dispatch(b, lx, token, depth + 1)
      }
    CommentToken(text~) => insert_comment(b, text)
    DoctypeToken(_) => ()
    StartTag(name~, attrs~, self_closing~) =>
      if name == "html" {
        in_body(b, lx, token, depth + 1)
      } else if name == "col" {
        ignore(insert_element_open(b, "col", attrs))
        ignore(pop(b))
        ignore(self_closing)
      } else if name == "template" {
        in_head(b, lx, token, depth + 1)
      } else if current_is(b, "colgroup") {
        ignore(pop(b))
        b.mode = InTable
        dispatch(b, lx, token, depth + 1)
      }
    EndTag(name~) =>
      if name == "colgroup" {
        if current_is(b, "colgroup") {
          ignore(pop(b))
          b.mode = InTable
        }
      } else if name == "col" {
        ()
      } else if name == "template" {
        in_head(b, lx, token, depth + 1)
      } else if current_is(b, "colgroup") {
        ignore(pop(b))
        b.mode = InTable
        dispatch(b, lx, token, depth + 1)
      }
    Eof => in_body(b, lx, token, depth + 1)
  }
}

///|
fn in_table_body(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    StartTag(name~, attrs~, self_closing~) =>
      match name {
        "tr" => {
          clear_to_table_body(b)
          ignore(insert_element_open(b, "tr", attrs))
          b.mode = InRow
        }
        "th" | "td" => {
          clear_to_table_body(b)
          ignore(insert_element_open(b, "tr", []))
          b.mode = InRow
          dispatch(b, lx, token, depth + 1)
        }
        "caption" | "col" | "colgroup" | "tbody" | "tfoot" | "thead" =>
          if has_any_in_scope(b, ["tbody", "thead", "tfoot"], Table) {
            clear_to_table_body(b)
            ignore(pop(b))
            b.mode = InTable
            dispatch(b, lx, token, depth + 1)
          }
        _ => in_table(b, lx, StartTag(name~, attrs~, self_closing~), depth + 1)
      }
    EndTag(name~) =>
      match name {
        "tbody" | "tfoot" | "thead" =>
          if has_in_scope(b, name, Table) {
            clear_to_table_body(b)
            ignore(pop(b))
            b.mode = InTable
          }
        "table" =>
          if has_any_in_scope(b, ["tbody", "thead", "tfoot"], Table) {
            clear_to_table_body(b)
            ignore(pop(b))
            b.mode = InTable
            dispatch(b, lx, token, depth + 1)
          }
        "body" | "caption" | "col" | "colgroup" | "html" | "td" | "th" | "tr" =>
          ()
        _ => in_table(b, lx, token, depth + 1)
      }
    _ => in_table(b, lx, token, depth + 1)
  }
}

///|
fn in_row(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    StartTag(name~, attrs~, self_closing~) =>
      match name {
        "th" | "td" => {
          clear_to_row(b)
          ignore(insert_element_open(b, name, attrs))
          b.mode = InCell
          push_marker(b)
        }
        "caption" | "col" | "colgroup" | "tbody" | "tfoot" | "thead" | "tr" =>
          if has_in_scope(b, "tr", Table) {
            clear_to_row(b)
            ignore(pop(b))
            b.mode = InTableBody
            dispatch(b, lx, token, depth + 1)
          }
        _ => in_table(b, lx, StartTag(name~, attrs~, self_closing~), depth + 1)
      }
    EndTag(name~) =>
      match name {
        "tr" =>
          if has_in_scope(b, "tr", Table) {
            clear_to_row(b)
            ignore(pop(b))
            b.mode = InTableBody
          }
        "table" =>
          if has_in_scope(b, "tr", Table) {
            clear_to_row(b)
            ignore(pop(b))
            b.mode = InTableBody
            dispatch(b, lx, token, depth + 1)
          }
        "tbody" | "tfoot" | "thead" =>
          if has_in_scope(b, name, Table) && has_in_scope(b, "tr", Table) {
            clear_to_row(b)
            ignore(pop(b))
            b.mode = InTableBody
            dispatch(b, lx, token, depth + 1)
          }
        "body" | "caption" | "col" | "colgroup" | "html" | "td" | "th" => ()
        _ => in_table(b, lx, token, depth + 1)
      }
    _ => in_table(b, lx, token, depth + 1)
  }
}

///|
fn close_cell(b : Builder) -> Unit {
  generate_implied_end(b, "")
  pop_until_any(b, ["td", "th"])
  clear_afe_to_marker(b)
  b.mode = InRow
}

///|
fn in_cell(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    EndTag(name~) =>
      if name == "td" || name == "th" {
        if has_in_scope(b, name, Table) {
          generate_implied_end(b, "")
          pop_until_name(b, name)
          clear_afe_to_marker(b)
          b.mode = InRow
        }
      } else if name == "body" ||
        name == "caption" ||
        name == "col" ||
        name == "colgroup" ||
        name == "html" {
        ()
      } else if name == "table" ||
        name == "tbody" ||
        name == "tfoot" ||
        name == "thead" ||
        name == "tr" {
        if has_in_scope(b, name, Table) {
          close_cell(b)
          dispatch(b, lx, token, depth + 1)
        }
      } else {
        in_body(b, lx, token, depth + 1)
      }
    StartTag(name~, ..) =>
      if name == "caption" ||
        name == "col" ||
        name == "colgroup" ||
        name == "tbody" ||
        name == "td" ||
        name == "tfoot" ||
        name == "th" ||
        name == "thead" ||
        name == "tr" {
        if has_any_in_scope(b, ["td", "th"], Table) {
          close_cell(b)
          dispatch(b, lx, token, depth + 1)
        }
      } else {
        in_body(b, lx, token, depth + 1)
      }
    _ => in_body(b, lx, token, depth + 1)
  }
}

///|
fn in_select(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    Characters(text~) => {
      let cleaned = strip_nulls(text)
      if !cleaned.is_empty() {
        insert_text(b, cleaned)
      }
    }
    CommentToken(text~) => insert_comment(b, text)
    DoctypeToken(_) => ()
    StartTag(name~, attrs~, self_closing~) =>
      match name {
        "html" => in_body(b, lx, token, depth + 1)
        "option" => {
          if current_is(b, "option") {
            ignore(pop(b))
          }
          reconstruct_afe(b)
          ignore(insert_element_open(b, "option", attrs))
        }
        "optgroup" => {
          if current_is(b, "option") {
            ignore(pop(b))
          }
          if current_is(b, "optgroup") {
            ignore(pop(b))
          }
          ignore(insert_element_open(b, "optgroup", attrs))
        }
        "hr" => {
          if current_is(b, "option") {
            ignore(pop(b))
          }
          if current_is(b, "optgroup") {
            ignore(pop(b))
          }
          ignore(insert_element_open(b, "hr", attrs))
          ignore(pop(b))
          ignore(self_closing)
        }
        "select" =>
          if has_in_scope(b, "select", Select) {
            pop_until_name(b, "select")
            reset_mode(b)
          }
        "input" =>
          if has_in_scope(b, "select", Select) {
            pop_until_name(b, "select")
            reset_mode(b)
            dispatch(b, lx, token, depth + 1)
          }
        "keygen" | "textarea" => in_body(b, lx, token, depth + 1)
        "script" | "template" =>
          in_head(b, lx, StartTag(name~, attrs~, self_closing~), depth + 1)
        _ => in_body(b, lx, StartTag(name~, attrs~, self_closing~), depth + 1)
      }
    EndTag(name~) =>
      match name {
        "optgroup" => {
          if current_is(b, "option") &&
            b.stack.length() >= 2 &&
            b.stack[b.stack.length() - 2].name == "optgroup" {
            ignore(pop(b))
          }
          if current_is(b, "optgroup") {
            ignore(pop(b))
          }
        }
        "option" => if current_is(b, "option") { ignore(pop(b)) }
        "select" =>
          if has_in_scope(b, "select", Select) {
            pop_until_name(b, "select")
            reset_mode(b)
          }
        "template" => in_head(b, lx, token, depth + 1)
        _ => in_body(b, lx, token, depth + 1)
      }
    Eof => in_body(b, lx, token, depth + 1)
  }
}

///|
fn in_select_in_table(
  b : Builder,
  lx : Lexer,
  token : Token,
  depth : Int32,
) -> Unit {
  match token {
    StartTag(name~, ..) =>
      if name == "caption" ||
        name == "table" ||
        name == "tbody" ||
        name == "tfoot" ||
        name == "thead" ||
        name == "tr" ||
        name == "td" ||
        name == "th" {
        pop_until_name(b, "select")
        reset_mode(b)
        dispatch(b, lx, token, depth + 1)
      } else {
        in_select(b, lx, token, depth + 1)
      }
    EndTag(name~) =>
      if name == "caption" ||
        name == "table" ||
        name == "tbody" ||
        name == "tfoot" ||
        name == "thead" ||
        name == "tr" ||
        name == "td" ||
        name == "th" {
        if has_in_scope(b, name, Table) {
          pop_until_name(b, "select")
          reset_mode(b)
          dispatch(b, lx, token, depth + 1)
        }
      } else {
        in_select(b, lx, token, depth + 1)
      }
    _ => in_select(b, lx, token, depth + 1)
  }
}

///|
fn in_template(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    Characters(_) | CommentToken(_) | DoctypeToken(_) =>
      in_body(b, lx, token, depth + 1)
    StartTag(name~, ..) =>
      match name {
        "base"
        | "basefont"
        | "bgsound"
        | "link"
        | "meta"
        | "noframes"
        | "script"
        | "style"
        | "template"
        | "title" => in_head(b, lx, token, depth + 1)
        "caption" | "colgroup" | "tbody" | "tfoot" | "thead" => {
          pop_template_mode(b)
          b.templates.push(InTable)
          b.mode = InTable
          dispatch(b, lx, token, depth + 1)
        }
        "col" => {
          pop_template_mode(b)
          b.templates.push(InColumnGroup)
          b.mode = InColumnGroup
          dispatch(b, lx, token, depth + 1)
        }
        "tr" => {
          pop_template_mode(b)
          b.templates.push(InTableBody)
          b.mode = InTableBody
          dispatch(b, lx, token, depth + 1)
        }
        "td" | "th" => {
          pop_template_mode(b)
          b.templates.push(InRow)
          b.mode = InRow
          dispatch(b, lx, token, depth + 1)
        }
        _ => {
          pop_template_mode(b)
          b.templates.push(InBody)
          b.mode = InBody
          dispatch(b, lx, token, depth + 1)
        }
      }
    EndTag(name~) => if name == "template" { in_head(b, lx, token, depth + 1) }
    Eof => {
      if !has_on_stack(b, "template") {
        return
      }
      pop_until_name(b, "template")
      clear_afe_to_marker(b)
      pop_template_mode(b)
      reset_mode(b)
      dispatch(b, lx, token, depth + 1)
    }
  }
}

///|
fn pop_template_mode(b : Builder) -> Unit {
  if !b.templates.is_empty() {
    ignore(b.templates.pop())
  }
}

// -------------------------------------------------------------- after body

///|
fn after_body(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    Characters(text~) =>
      if is_space_text(text) {
        in_body(b, lx, token, depth + 1)
      } else {
        b.mode = InBody
        dispatch(b, lx, token, depth + 1)
      }
    CommentToken(text~) =>
      match html_element(b) {
        Some(html) => insert_comment_into(html, text)
        None => insert_comment_into(b.root, text)
      }
    DoctypeToken(_) => ()
    StartTag(name~, ..) =>
      if name == "html" {
        in_body(b, lx, token, depth + 1)
      } else {
        b.mode = InBody
        dispatch(b, lx, token, depth + 1)
      }
    EndTag(name~) =>
      if name == "html" {
        if b.context is None {
          b.mode = AfterAfterBody
        }
      } else {
        b.mode = InBody
        dispatch(b, lx, token, depth + 1)
      }
    Eof => ()
  }
}

///|
fn in_frameset(b : Builder, lx : Lexer, token : Token, depth : Int32) -> Unit {
  match token {
    Characters(text~) => if is_space_text(text) { insert_text(b, text) }
    CommentToken(text~) => insert_comment(b, text)
    DoctypeToken(_) => ()
    StartTag(name~, attrs~, self_closing~) =>
      match name {
        "html" => in_body(b, lx, token, depth + 1)
        "frameset" => ignore(insert_element_open(b, "frameset", attrs))
        "frame" => {
          ignore(insert_element_open(b, "frame", attrs))
          ignore(pop(b))
          ignore(self_closing)
        }
        "noframes" =>
          in_head(b, lx, StartTag(name~, attrs~, self_closing~), depth + 1)
        _ => ()
      }
    EndTag(name~) =>
      if name == "frameset" {
        if current_is(b, "html") {
          return
        }
        ignore(pop(b))
        if b.context is None && !current_is(b, "frameset") {
          b.mode = AfterFrameset
        }
      }
    Eof => ()
  }
}

///|
fn after_frameset(
  b : Builder,
  lx : Lexer,
  token : Token,
  depth : Int32,
) -> Unit {
  match token {
    Characters(text~) => if is_space_text(text) { insert_text(b, text) }
    CommentToken(text~) => insert_comment(b, text)
    DoctypeToken(_) => ()
    StartTag(name~, attrs~, self_closing~) =>
      match name {
        "html" => in_body(b, lx, token, depth + 1)
        "noframes" =>
          in_head(b, lx, StartTag(name~, attrs~, self_closing~), depth + 1)
        _ => ()
      }
    EndTag(name~) => if name == "html" { b.mode = AfterAfterFrameset }
    Eof => ()
  }
}

///|
fn after_after_body(
  b : Builder,
  lx : Lexer,
  token : Token,
  depth : Int32,
) -> Unit {
  match token {
    CommentToken(text~) => insert_comment_into(b.root, text)
    DoctypeToken(_) => in_body(b, lx, token, depth + 1)
    Characters(text~) =>
      if is_space_text(text) {
        in_body(b, lx, token, depth + 1)
      } else {
        b.mode = InBody
        dispatch(b, lx, token, depth + 1)
      }
    StartTag(name~, ..) =>
      if name == "html" {
        in_body(b, lx, token, depth + 1)
      } else {
        b.mode = InBody
        dispatch(b, lx, token, depth + 1)
      }
    Eof => ()
    _ => {
      b.mode = InBody
      dispatch(b, lx, token, depth + 1)
    }
  }
}

///|
fn after_after_frameset(
  b : Builder,
  lx : Lexer,
  token : Token,
  depth : Int32,
) -> Unit {
  match token {
    CommentToken(text~) => insert_comment_into(b.root, text)
    DoctypeToken(_) => in_body(b, lx, token, depth + 1)
    Characters(text~) =>
      if is_space_text(text) {
        in_body(b, lx, token, depth + 1)
      }
    StartTag(name~, attrs~, self_closing~) =>
      match name {
        "html" => in_body(b, lx, token, depth + 1)
        "noframes" =>
          in_head(b, lx, StartTag(name~, attrs~, self_closing~), depth + 1)
        _ => ()
      }
    EndTag(_) => ()
    Eof => ()
  }
}

// -------------------------------------------------------- resetting a mode

///|
/// Work out the mode from the stack, the standard's "reset the insertion mode
/// appropriately".
fn reset_mode(b : Builder) -> Unit {
  // The bottom of the stack is the root, and in a fragment that root stands
  // for the context element: the body's rules are the ones to go back to.
  if b.stack.length() <= 1 {
    b.mode = match b.context {
      Some(_) => InBody
      None => if b.head is None { BeforeHead } else { AfterHead }
    }
    return
  }
  let mut k = b.stack.length() - 1
  while k >= 0 {
    let node = b.stack[k]
    let last = k == 0
    match node.name {
      "select" => {
        let mut in_table = false
        let mut j = k - 1
        while j >= 0 {
          let above = b.stack[j].name
          if above == "template" {
            break
          }
          if above == "table" {
            in_table = true
            break
          }
          j = j - 1
        }
        b.mode = if in_table { InSelectInTable } else { InSelect }
        return
      }
      "td" | "th" =>
        if !last {
          b.mode = InCell
          return
        }
      "tr" => {
        b.mode = InRow
        return
      }
      "tbody" | "thead" | "tfoot" => {
        b.mode = InTableBody
        return
      }
      "caption" => {
        b.mode = InCaption
        return
      }
      "colgroup" => {
        b.mode = InColumnGroup
        return
      }
      "table" => {
        b.mode = InTable
        return
      }
      "template" => {
        b.mode = match b.templates.last() {
          Some(mode) => mode
          None => InBody
        }
        return
      }
      "head" =>
        if !last {
          b.mode = InHead
          return
        }
      "body" => {
        b.mode = InBody
        return
      }
      "frameset" => {
        b.mode = InFrameset
        return
      }
      "html" => {
        b.mode = match b.head {
          Some(_) => AfterHead
          None => BeforeHead
        }
        return
      }
      _ => ()
    }
    k = k - 1
  }
  b.mode = InBody
}

// --------------------------------------------------------- foreign content

///|
/// The rules for parsing tokens in foreign content: SVG and MathML keep their
/// own namespaces and their own spelling, and a handful of HTML tags break out.
fn foreign_content(
  b : Builder,
  lx : Lexer,
  token : Token,
  depth : Int32,
) -> Unit {
  match token {
    Characters(text~) => {
      insert_text(b, replace_nulls(text))
      if !is_space_text(text) && !only_nulls(text) {
        b.frameset_ok = false
      }
    }
    CommentToken(text~) => insert_comment(b, text)
    DoctypeToken(_) => ()
    StartTag(name~, attrs~, self_closing~) => {
      let mut breakout = is_breakout(name)
      if name == "font" {
        for pair in attrs {
          if pair.0 == "color" || pair.0 == "face" || pair.0 == "size" {
            breakout = true
          }
        }
      }
      if breakout {
        // Out of the foreign subtree, and the token is read again as HTML.
        while b.stack.length() > 0 {
          let node = current(b)
          if namespace_of_element(node) == html_namespace ||
            is_mathml_text_integration_point(node) ||
            is_html_integration_point(node) {
            break
          }
          ignore(pop(b))
        }
        dispatch_html(b, lx, token, depth + 1)
        return
      }
      let node = match adjusted_current(b) {
        Some(el) => el
        None => return
      }
      let space = if namespace_of_element(node) == svg_namespace {
        svg_namespace
      } else {
        mathml_namespace
      }
      let element = insert_foreign(b, name, attrs, space)
      push(b, element)
      if self_closing {
        ignore(pop(b))
      }
    }
    EndTag(name~) => {
      if name == "br" || name == "p" {
        while b.stack.length() > 0 {
          let node = current(b)
          if namespace_of_element(node) == html_namespace ||
            is_mathml_text_integration_point(node) ||
            is_html_integration_point(node) {
            break
          }
          ignore(pop(b))
        }
        dispatch_html(b, lx, token, depth + 1)
        return
      }
      let mut k = b.stack.length() - 1
      let mut node = b.stack[k]
      if @moonxml.local_of(node.name).to_lower() != name {
        // Walk outward for the element this closes, and stop at the top.
        while k > 0 {
          if @moonxml.local_of(node.name).to_lower() == name {
            break
          }
          k = k - 1
          node = b.stack[k]
        }
        if @moonxml.local_of(node.name).to_lower() != name {
          return
        }
      }
      while b.stack.length() > k {
        ignore(pop(b))
      }
    }
    Eof => in_body(b, lx, token, depth + 1)
  }
}

///|
/// Whether every character in the run is U+0000, which foreign content reads as
/// a replacement character and does not count as content.
fn only_nulls(text : String) -> Bool {
  for ch in text {
    if ch != '\u{0}' {
      return false
    }
  }
  true
}

///|
fn replace_nulls(text : String) -> String {
  if !text.contains("\u{0}") {
    return text
  }
  let out = StringBuilder()
  for ch in text {
    if ch == '\u{0}' {
      out.write_char('\u{FFFD}')
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

// ----------------------------------------------------------- the adoption

///|
/// The adoption agency algorithm: the standard's answer to misnested formatting,
/// `<b><p></b>` included. At most eight passes, because the standard says eight.
fn adoption_agency(b : Builder, subject : String) -> Unit {
  let top = current(b)
  if top.name == subject && find_afe(b, subject) is None {
    ignore(pop(b))
    return
  }
  let mut outer = 0
  while outer < 8 {
    outer = outer + 1
    let formatting = match find_afe(b, subject) {
      Some(el) => el
      None => {
        any_other_end_tag(b, subject)
        return
      }
    }
    if !on_stack(b, formatting) {
      match afe_index(b, formatting) {
        Some(at) => ignore(b.afe.remove(at))
        None => ()
      }
      return
    }
    if !element_in_scope(b, formatting, Default) {
      return
    }
    let fmt_at = match index_on_stack(b, formatting) {
      Some(at) => at
      None => return
    }
    let mut furthest : @moonxml.Element? = None
    let mut k = fmt_at + 1
    while k < b.stack.length() {
      if is_special(b.stack[k].name) {
        furthest = Some(b.stack[k])
        break
      }
      k = k + 1
    }
    let block = match furthest {
      Some(el) => el
      None => {
        generate_implied_end(b, subject)
        pop_until_name(b, subject)
        match afe_index(b, formatting) {
          Some(at) => ignore(b.afe.remove(at))
          None => ()
        }
        return
      }
    }
    let common = if fmt_at >= 1 { b.stack[fmt_at - 1] } else { b.root }
    let mut bookmark = match afe_index(b, formatting) {
      Some(at) => at
      None => return
    }
    // The inner loop walks up the stack from the furthest block to the
    // formatting element, re-creating every formatting element it passes and
    // gathering what it holds into the node above it.
    let mut last = block
    let mut inner = 0
    let mut at = match index_on_stack(b, block) {
      Some(found) => found - 1
      None => -1
    }
    while at >= 0 {
      let node = b.stack[at]
      if physical_equal(node, formatting) {
        break
      }
      inner = inner + 1
      let mut node_afe = afe_index(b, node)
      if inner > 3 {
        match node_afe {
          Some(found) => {
            ignore(b.afe.remove(found))
            node_afe = None
          }
          None => ()
        }
      }
      match node_afe {
        None => ignore(b.stack.remove(at))
        Some(found) => {
          let fresh = @moonxml.Element::new(node.name, attrs=node.attrs.copy())
          b.afe[found] = Some(fresh)
          b.stack[at] = fresh
          if physical_equal(last, block) {
            bookmark = found + 1
          }
          fresh.append(@moonxml.ElementNode(last))
          last = fresh
        }
      }
      at = at - 1
    }
    // The last node takes the place of the block in the common ancestor.
    match index_of(common, block) {
      Some(at) => {
        ignore(block.remove())
        common.insert(at, @moonxml.ElementNode(last))
      }
      None => append_into(common, @moonxml.ElementNode(last))
    }
    let fresh = @moonxml.Element::new(
      formatting.name,
      attrs=formatting.attrs.copy(),
    )
    let kids = block.children.copy()
    block.clear()
    for kid in kids {
      fresh.append(kid)
    }
    block.append(@moonxml.ElementNode(fresh))
    match afe_index(b, formatting) {
      Some(at) => {
        ignore(b.afe.remove(at))
        if at < bookmark {
          bookmark = bookmark - 1
        }
      }
      None => ()
    }
    let slot = if bookmark > b.afe.length() {
      b.afe.length()
    } else if bookmark < 0 {
      0
    } else {
      bookmark
    }
    b.afe.insert(slot, Some(fresh))
    ignore(remove_from_stack(b, formatting))
    match index_on_stack(b, block) {
      Some(at) => b.stack.insert(at + 1, fresh)
      None => ()
    }
  }
}
