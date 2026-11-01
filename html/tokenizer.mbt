/// The tokenizer, as the specification's state machine.
///
/// Every state in "Tokenizing character references" .. "Script data states" of
/// the WHATWG HTML standard has a branch here, including the reconsume steps,
/// which is why the states are an enum that survives between `next_token`
/// calls: the tree builder switches the content model and then reads on.
///
/// Character data is accumulated and flushed as one token when markup starts,
/// so callers see runs rather than one token per character.

/// Every state. The names follow the specification's.
enum TState {
  StData
  StRcdata
  StRawtext
  StScriptData
  StPlaintext
  // Tag open and tag name.
  StTagOpen
  StEndTagOpen
  StTagName
  // End tags inside raw text.
  StRcdataLt
  StRcdataEndTagOpen
  StRcdataEndTagName
  StRawtextLt
  StRawtextEndTagOpen
  StRawtextEndTagName
  StScriptLt
  StScriptEndTagOpen
  StScriptEndTagName
  // Script data escape states.
  StScriptEscapeStart
  StScriptEscapeStartDash
  StScriptEscaped
  StScriptEscapedDash
  StScriptEscapedDashDash
  StScriptEscapedLt
  StScriptEscapedEndTagOpen
  StScriptEscapedEndTagName
  StScriptDoubleEscapeStart
  StScriptDoubleEscaped
  StScriptDoubleEscapedDash
  StScriptDoubleEscapedDashDash
  StScriptDoubleEscapedLt
  StScriptDoubleEscapeEnd
  // Attributes.
  StBeforeAttrName
  StAttrName
  StAfterAttrName
  StBeforeAttrValue
  StAttrValueDq
  StAttrValueSq
  StAttrValueUnq
  StAfterAttrValueQuoted
  StSelfClosing
  // Markup that is not a tag.
  StBogusComment
  StMarkupDeclOpen
  StCommentStart
  StCommentStartDash
  StComment
  StCommentLt
  StCommentLtBang
  StCommentLtBangDash
  StCommentLtBangDashDash
  StCommentEndDash
  StCommentEnd
  StCommentEndBang
  StDoctype
  StBeforeDoctypeName
  StDoctypeName
  StAfterDoctypeName
  StAfterDoctypePublicKeyword
  StBeforeDoctypePublicId
  StDoctypePublicIdDq
  StDoctypePublicIdSq
  StAfterDoctypePublicId
  StBetweenDoctypeIds
  StAfterDoctypeSystemKeyword
  StBeforeDoctypeSystemId
  StDoctypeSystemIdDq
  StDoctypeSystemIdSq
  StAfterDoctypeSystemId
  StBogusDoctype
  StCdataSection
  StCdataSectionBracket
  StCdataSectionEnd
} derive(Eq)

fn is_alpha_ascii(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

fn is_space_h(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\u{0C}'
}

/// Append a character to a token buffer, mapping NUL to U+FFFD.
fn push_repl(sb : Array[Char], c : Char) -> Unit {
  if c == '\u{0}' {
    sb.push('\u{FFFD}')
  } else {
    sb.push(c)
  }
}

fn chars_of(a : Array[Char]) -> String {
  let sb = StringBuilder()
  for c in a {
    sb.write_char(c)
  }
  sb.to_string()
}

fn lower_str(s : String) -> String {
  let sb = StringBuilder()
  for c in s {
    sb.write_char(lower_char(c))
  }
  sb.to_string()
}

/// Flush the accumulated character data, if any.
fn H::flush_data(self : H) -> Tok? {
  if self.data_buf.length() == 0 {
    return None
  }
  let s = self.data_buf
  self.data_buf = ""
  Some(Chars(s))
}

fn H::add_data(self : H, c : Char) -> Unit {
  self.data_buf = self.data_buf + c.to_string()
}

fn H::add_data_str(self : H, s : String) -> Unit {
  self.data_buf = self.data_buf + s
}

/// Start a start or end tag token.
fn H::begin_tag(self : H, is_end : Bool) -> Unit {
  self.tok_is_end = is_end
  self.tok_name = ""
  self.tok_attrs = []
  self.attr_name = ""
  self.attr_val = ""
  self.tok_sc = false
}

fn H::start_attr(self : H) -> Unit {
  self.attr_name = ""
  self.attr_val = ""
}

fn H::finish_attr(self : H) -> Unit {
  if self.attr_name.length() > 0 && not(has_attr(self.tok_attrs, self.attr_name)) {
    self.tok_attrs.push((self.attr_name, self.attr_val))
  }
  self.attr_name = ""
  self.attr_val = ""
}

fn H::emit_tag(self : H) -> Tok {
  self.finish_attr()
  let name = self.tok_name
  if self.tok_is_end {
    End(name)
  } else {
    self.last_start_tag = name
    Start(name, self.tok_attrs, self.tok_sc)
  }
}

/// Read one token, running the state machine until a token is complete.
/// Whether a state is one of the plain content models, where character data
/// keeps accumulating instead of being handed back first.
fn accumulates(st : TState) -> Bool {
  match st {
    StData | StRcdata | StRawtext | StScriptData | StPlaintext | StCdataSection => true
    _ => false
  }
}

fn H::next_token(self : H) -> Tok {
  while true {
    // Character data always precedes the markup that ends it.
    if self.data_buf.length() > 0 && not(accumulates(self.tstate)) {
      match self.flush_data() {
        Some(t) => return t
        None => ()
      }
    }
    // Character data is flushed before any markup is examined.
    if self.at_end() {
      match self.flush_data() {
        Some(t) => return t
        None => ()
      }
      let st = self.tstate
      self.tstate = StData
      match st {
        StPlaintext | StRcdata | StRawtext | StScriptData | StCdataSection | StData => return Eof
        StScriptEscaped | StScriptDoubleEscaped | StScriptEscapedDash | StScriptDoubleEscapedDash | StScriptEscapedDashDash | StScriptDoubleEscapedDashDash => return Eof
        StTagOpen => return Chars("<")
        StEndTagOpen => return Chars("</")
        StRcdataLt | StRawtextLt | StScriptLt | StScriptEscapedLt => return Chars("<")
        StScriptDoubleEscapedLt => return Chars("<")
        StRcdataEndTagOpen | StRawtextEndTagOpen | StScriptEndTagOpen | StScriptEscapedEndTagOpen =>
          return Chars("</")
        StRcdataEndTagName | StRawtextEndTagName | StScriptEndTagName | StScriptEscapedEndTagName =>
          return Chars("</" + self.temp)
        StCommentStart | StCommentStartDash | StComment | StCommentLt | StCommentLtBang | StCommentEndDash | StCommentEnd | StCommentEndBang =>
          return Comment(self.comment_data)
        StBogusComment => return Comment(self.comment_data)
        StDoctype | StBeforeDoctypeName | StDoctypeName | StAfterDoctypeName | StAfterDoctypePublicKeyword | StBeforeDoctypePublicId | StDoctypePublicIdDq | StDoctypePublicIdSq | StAfterDoctypePublicId | StBetweenDoctypeIds | StAfterDoctypeSystemKeyword | StBeforeDoctypeSystemId | StDoctypeSystemIdDq | StDoctypeSystemIdSq | StAfterDoctypeSystemId | StBogusDoctype =>
          return Doctype(
            self.doctype_name,
            self.doctype_pub,
            self.doctype_sys,
            self.doctype_quirks,
          )
        StMarkupDeclOpen => return Comment("")
        StCdataSectionBracket => {
          // The bracket was held back waiting for `]]`; at end of input it is
          // just text.
          self.tstate = StData
          return Chars("]")
        }
        StCdataSectionEnd => {
          self.tstate = StData
          return Chars("]]")
        }
        StTagName | StBeforeAttrName | StAttrName | StAfterAttrName | StBeforeAttrValue | StAttrValueDq | StAttrValueSq | StAttrValueUnq | StAfterAttrValueQuoted | StSelfClosing =>
          return Eof
        _ => return Eof
      }
    }
    let c = self.peek()
    let st = self.tstate
    // ---- content models -------------------------------------------------
    if st == StData {
      if c == '<' {
        // Markup starts here: hand back the text first, then the tag on the
        // next call, so the tokens arrive in document order.
        match self.flush_data() {
          Some(t) => return t
          None => ()
        }
        self.tstate = StTagOpen
        self.pos = self.pos + 1
      } else if c == '&' {
        let (text, next, ok) = self.read_char_ref(self.pos, false)
        if ok {
          self.add_data_str(text)
          self.pos = next
        } else {
          self.add_data('&')
          self.pos = self.pos + 1
        }
      } else {
        self.add_data(c)
        self.pos = self.pos + 1
      }
    } else if st == StRcdata {
      if c == '<' {
        match self.flush_data() {
          Some(t) => return t
          None => ()
        }
        self.tstate = StRcdataLt
        self.pos = self.pos + 1
      } else if c == '&' {
        let (text, next, ok) = self.read_char_ref(self.pos, false)
        if ok {
          self.add_data_str(text)
          self.pos = next
        } else {
          self.add_data('&')
          self.pos = self.pos + 1
        }
      } else {
        push_repl_data(self, c)
        self.pos = self.pos + 1
      }
    } else if st == StRawtext || st == StScriptData {
      if c == '<' {
        match self.flush_data() {
          Some(t) => return t
          None => ()
        }
        if st == StRawtext {
          self.tstate = StRawtextLt
        } else {
          self.tstate = StScriptLt
        }
        self.pos = self.pos + 1
      } else {
        push_repl_data(self, c)
        self.pos = self.pos + 1
      }
    } else if st == StPlaintext {
      push_repl_data(self, c)
      self.pos = self.pos + 1
    } else if st == StCdataSection {
      if c == ']' {
        match self.flush_data() {
          Some(t) => return t
          None => ()
        }
        self.tstate = StCdataSectionBracket
        self.pos = self.pos + 1
      } else {
        self.add_data(c)
        self.pos = self.pos + 1
      }
    } else if st == StCdataSectionBracket {
      if c == ']' {
        self.tstate = StCdataSectionEnd
        self.pos = self.pos + 1
      } else {
        self.add_data(']')
        self.tstate = StCdataSection
      }
    } else if st == StCdataSectionEnd {
      if c == ']' {
        self.add_data(']')
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
      } else {
        self.add_data_str("]]")
        self.tstate = StCdataSection
      }
    } else if st == StTagOpen {
      if c == '!' {
        self.tstate = StMarkupDeclOpen
        self.pos = self.pos + 1
      } else if c == '/' {
        self.tstate = StEndTagOpen
        self.pos = self.pos + 1
      } else if is_alpha_ascii(c) {
        self.begin_tag(false)
        self.tstate = StTagName
      } else if c == '?' {
        self.comment_data = ""
        self.tstate = StBogusComment
      } else {
        self.tstate = StData
        return Chars("<")
      }
    } else if st == StEndTagOpen {
      if is_alpha_ascii(c) {
        self.begin_tag(true)
        self.tstate = StTagName
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
      } else {
        self.comment_data = ""
        self.tstate = StBogusComment
      }
    } else if st == StTagName {
      if is_space_h(c) {
        self.tstate = StBeforeAttrName
        self.pos = self.pos + 1
      } else if c == '/' {
        self.tstate = StSelfClosing
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return self.emit_tag()
      } else {
        self.tok_name = self.tok_name + lower_char(repl_char(c)).to_string()
        self.pos = self.pos + 1
      }
    } else if st == StBeforeAttrName {
      if is_space_h(c) {
        self.pos = self.pos + 1
      } else if c == '/' || c == '>' {
        self.tstate = StAfterAttrName
      } else if c == '=' {
        self.finish_attr()
        self.start_attr()
        self.attr_name = "="
        self.tstate = StAttrName
        self.pos = self.pos + 1
      } else {
        // The attribute before this one is complete.
        self.finish_attr()
        self.start_attr()
        self.tstate = StAttrName
      }
    } else if st == StAttrName {
      if is_space_h(c) || c == '/' || c == '>' {
        self.tstate = StAfterAttrName
      } else if c == '=' {
        self.tstate = StBeforeAttrValue
        self.pos = self.pos + 1
      } else {
        let ch = repl_char(c)
        self.attr_name = self.attr_name + lower_char(ch).to_string()
        self.pos = self.pos + 1
      }
    } else if st == StAfterAttrName {
      if is_space_h(c) {
        self.pos = self.pos + 1
      } else if c == '/' {
        self.tstate = StSelfClosing
        self.pos = self.pos + 1
      } else if c == '=' {
        self.tstate = StBeforeAttrValue
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return self.emit_tag()
      } else {
        self.finish_attr()
        self.start_attr()
        self.tstate = StAttrName
      }
    } else if st == StBeforeAttrValue {
      if is_space_h(c) {
        self.pos = self.pos + 1
      } else if c == '"' {
        self.tstate = StAttrValueDq
        self.pos = self.pos + 1
      } else if c == '\'' {
        self.tstate = StAttrValueSq
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return self.emit_tag()
      } else {
        self.tstate = StAttrValueUnq
      }
    } else if st == StAttrValueDq || st == StAttrValueSq {
      let q = if st == StAttrValueDq { '"' } else { '\'' }
      if c == q {
        self.tstate = StAfterAttrValueQuoted
        self.pos = self.pos + 1
      } else if c == '&' {
        let (text, next, ok) = self.read_char_ref(self.pos, true)
        if ok {
          self.attr_val = self.attr_val + text
          self.pos = next
        } else {
          self.attr_val = self.attr_val + "&"
          self.pos = self.pos + 1
        }
      } else {
        self.attr_val = self.attr_val + repl_char(c).to_string()
        self.pos = self.pos + 1
      }
    } else if st == StAttrValueUnq {
      if is_space_h(c) {
        self.tstate = StBeforeAttrName
        self.pos = self.pos + 1
      } else if c == '&' {
        let (text, next, ok) = self.read_char_ref(self.pos, true)
        if ok {
          self.attr_val = self.attr_val + text
          self.pos = next
        } else {
          self.attr_val = self.attr_val + "&"
          self.pos = self.pos + 1
        }
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return self.emit_tag()
      } else {
        self.attr_val = self.attr_val + repl_char(c).to_string()
        self.pos = self.pos + 1
      }
    } else if st == StAfterAttrValueQuoted {
      if is_space_h(c) {
        self.tstate = StBeforeAttrName
        self.pos = self.pos + 1
      } else if c == '/' {
        self.tstate = StSelfClosing
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return self.emit_tag()
      } else {
        self.tstate = StBeforeAttrName
      }
    } else if st == StSelfClosing {
      if c == '>' {
        self.tok_sc = true
        self.tstate = StData
        self.pos = self.pos + 1
        return self.emit_tag()
      } else {
        self.tstate = StBeforeAttrName
      }
    } else if st == StBogusComment {
      if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Comment(self.comment_data)
      } else {
        self.comment_data = self.comment_data + repl_char(c).to_string()
        self.pos = self.pos + 1
      }
    } else if st == StMarkupDeclOpen {
      if self.starts_with("--") {
        self.pos = self.pos + 2
        self.comment_data = ""
        self.tstate = StCommentStart
      } else if self.starts_with_ci("doctype") {
        self.pos = self.pos + 7
        self.doctype_name = None
        self.doctype_pub = None
        self.doctype_sys = None
        self.doctype_quirks = false
        self.tstate = StDoctype
      } else if self.starts_with("[CDATA[") && self.adjusted_foreign() {
        self.pos = self.pos + 7
        self.tstate = StCdataSection
      } else {
        self.comment_data = ""
        self.tstate = StBogusComment
      }
    } else if st == StCommentStart {
      if c == '-' {
        self.tstate = StCommentStartDash
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Comment(self.comment_data)
      } else {
        self.tstate = StComment
      }
    } else if st == StCommentStartDash {
      if c == '-' {
        self.tstate = StCommentEnd
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Comment(self.comment_data)
      } else {
        self.comment_data = self.comment_data + "-"
        self.tstate = StComment
      }
    } else if st == StComment {
      if c == '<' {
        self.comment_data = self.comment_data + "<"
        self.tstate = StCommentLt
        self.pos = self.pos + 1
      } else if c == '-' {
        self.tstate = StCommentEndDash
        self.pos = self.pos + 1
      } else {
        self.comment_data = self.comment_data + repl_char(c).to_string()
        self.pos = self.pos + 1
      }
    } else if st == StCommentLt {
      if c == '!' {
        self.comment_data = self.comment_data + "!"
        self.tstate = StCommentLtBang
        self.pos = self.pos + 1
      } else if c == '<' {
        self.comment_data = self.comment_data + "<"
        self.pos = self.pos + 1
      } else {
        self.tstate = StComment
      }
    } else if st == StCommentLtBang {
      if c == '-' {
        self.tstate = StCommentLtBangDash
        self.pos = self.pos + 1
      } else {
        self.tstate = StComment
      }
    } else if st == StCommentLtBangDash {
      if c == '-' {
        self.tstate = StCommentLtBangDashDash
        self.pos = self.pos + 1
      } else {
        self.tstate = StCommentEndDash
      }
    } else if st == StCommentLtBangDashDash {
      // Every character is reconsumed in the comment end state, which is what
      // makes `<!--<!--x-->` keep the nested marker as data.
      self.tstate = StCommentEnd
    } else if st == StCommentEndDash {
      if c == '-' {
        self.tstate = StCommentEnd
        self.pos = self.pos + 1
      } else {
        self.comment_data = self.comment_data + "-"
        self.tstate = StComment
      }
    } else if st == StCommentEnd {
      if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Comment(self.comment_data)
      } else if c == '!' {
        self.tstate = StCommentEndBang
        self.pos = self.pos + 1
      } else if c == '-' {
        self.comment_data = self.comment_data + "-"
        self.pos = self.pos + 1
      } else {
        self.comment_data = self.comment_data + "--"
        self.tstate = StComment
      }
    } else if st == StCommentEndBang {
      if c == '-' {
        self.comment_data = self.comment_data + "--!"
        self.tstate = StCommentEndDash
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Comment(self.comment_data)
      } else {
        self.comment_data = self.comment_data + "--!"
        self.tstate = StComment
      }
    } else if st == StDoctype {
      if is_space_h(c) {
        self.tstate = StBeforeDoctypeName
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        self.doctype_quirks = true
        return Doctype(None, None, None, true)
      } else {
        self.tstate = StBeforeDoctypeName
      }
    } else if st == StBeforeDoctypeName {
      if is_space_h(c) {
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Doctype(None, None, None, true)
      } else {
        self.doctype_name = Some("")
        self.tstate = StDoctypeName
        self.pos = self.pos + 1
        self.doctype_name = Some(repl_char(c).to_string().to_lower())
      }
    } else if st == StDoctypeName {
      if is_space_h(c) {
        self.tstate = StAfterDoctypeName
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Doctype(self.doctype_name, self.doctype_pub, self.doctype_sys, false)
      } else {
        match self.doctype_name {
          Some(v) => self.doctype_name = Some(v + repl_char(c).to_string().to_lower())
          None => self.doctype_name = Some(repl_char(c).to_string().to_lower())
        }
        self.pos = self.pos + 1
      }
    } else if st == StAfterDoctypeName {
      if is_space_h(c) {
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Doctype(self.doctype_name, self.doctype_pub, self.doctype_sys, false)
      } else if self.starts_with_ci("PUBLIC") {
        self.pos = self.pos + 6
        self.tstate = StAfterDoctypePublicKeyword
      } else if self.starts_with_ci("SYSTEM") {
        self.pos = self.pos + 6
        self.tstate = StAfterDoctypeSystemKeyword
      } else {
        self.doctype_quirks = true
        self.tstate = StBogusDoctype
      }
    } else if st == StAfterDoctypePublicKeyword {
      if is_space_h(c) {
        self.tstate = StBeforeDoctypePublicId
        self.pos = self.pos + 1
      } else if c == '"' {
        self.doctype_pub = Some("")
        self.tstate = StDoctypePublicIdDq
        self.pos = self.pos + 1
      } else if c == '\'' {
        self.doctype_pub = Some("")
        self.tstate = StDoctypePublicIdSq
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Doctype(self.doctype_name, self.doctype_pub, self.doctype_sys, true)
      } else {
        self.doctype_quirks = true
        self.tstate = StBogusDoctype
      }
    } else if st == StBeforeDoctypePublicId {
      if is_space_h(c) {
        self.pos = self.pos + 1
      } else if c == '"' {
        self.doctype_pub = Some("")
        self.tstate = StDoctypePublicIdDq
        self.pos = self.pos + 1
      } else if c == '\'' {
        self.doctype_pub = Some("")
        self.tstate = StDoctypePublicIdSq
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Doctype(self.doctype_name, self.doctype_pub, self.doctype_sys, true)
      } else {
        self.doctype_quirks = true
        self.tstate = StBogusDoctype
      }
    } else if st == StDoctypePublicIdDq || st == StDoctypePublicIdSq {
      let q = if st == StDoctypePublicIdDq { '"' } else { '\'' }
      if c == q {
        self.tstate = StAfterDoctypePublicId
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Doctype(self.doctype_name, self.doctype_pub, self.doctype_sys, true)
      } else {
        self.doctype_pub = append_opt(self.doctype_pub, repl_char(c))
        self.pos = self.pos + 1
      }
    } else if st == StAfterDoctypePublicId {
      if is_space_h(c) {
        self.tstate = StBetweenDoctypeIds
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Doctype(self.doctype_name, self.doctype_pub, self.doctype_sys, false)
      } else if c == '"' {
        self.doctype_sys = Some("")
        self.tstate = StDoctypeSystemIdDq
        self.pos = self.pos + 1
      } else if c == '\'' {
        self.doctype_sys = Some("")
        self.tstate = StDoctypeSystemIdSq
        self.pos = self.pos + 1
      } else {
        self.doctype_quirks = true
        self.tstate = StBogusDoctype
      }
    } else if st == StBetweenDoctypeIds {
      if is_space_h(c) {
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Doctype(self.doctype_name, self.doctype_pub, self.doctype_sys, false)
      } else if c == '"' {
        self.doctype_sys = Some("")
        self.tstate = StDoctypeSystemIdDq
        self.pos = self.pos + 1
      } else if c == '\'' {
        self.doctype_sys = Some("")
        self.tstate = StDoctypeSystemIdSq
        self.pos = self.pos + 1
      } else {
        self.doctype_quirks = true
        self.tstate = StBogusDoctype
      }
    } else if st == StAfterDoctypeSystemKeyword {
      if is_space_h(c) {
        self.tstate = StBeforeDoctypeSystemId
        self.pos = self.pos + 1
      } else if c == '"' {
        self.doctype_sys = Some("")
        self.tstate = StDoctypeSystemIdDq
        self.pos = self.pos + 1
      } else if c == '\'' {
        self.doctype_sys = Some("")
        self.tstate = StDoctypeSystemIdSq
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Doctype(self.doctype_name, self.doctype_pub, self.doctype_sys, true)
      } else {
        self.doctype_quirks = true
        self.tstate = StBogusDoctype
      }
    } else if st == StBeforeDoctypeSystemId {
      if is_space_h(c) {
        self.pos = self.pos + 1
      } else if c == '"' {
        self.doctype_sys = Some("")
        self.tstate = StDoctypeSystemIdDq
        self.pos = self.pos + 1
      } else if c == '\'' {
        self.doctype_sys = Some("")
        self.tstate = StDoctypeSystemIdSq
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Doctype(self.doctype_name, self.doctype_pub, self.doctype_sys, true)
      } else {
        self.doctype_quirks = true
        self.tstate = StBogusDoctype
      }
    } else if st == StDoctypeSystemIdDq || st == StDoctypeSystemIdSq {
      let q = if st == StDoctypeSystemIdDq { '"' } else { '\'' }
      if c == q {
        self.tstate = StAfterDoctypeSystemId
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Doctype(self.doctype_name, self.doctype_pub, self.doctype_sys, true)
      } else {
        self.doctype_sys = append_opt(self.doctype_sys, repl_char(c))
        self.pos = self.pos + 1
      }
    } else if st == StAfterDoctypeSystemId {
      if is_space_h(c) {
        self.pos = self.pos + 1
      } else if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Doctype(self.doctype_name, self.doctype_pub, self.doctype_sys, false)
      } else {
        self.tstate = StBogusDoctype
      }
    } else if st == StBogusDoctype {
      if c == '>' {
        self.tstate = StData
        self.pos = self.pos + 1
        return Doctype(self.doctype_name, self.doctype_pub, self.doctype_sys, self.doctype_quirks)
      }
      self.pos = self.pos + 1
    } else if st == StRcdataLt || st == StRawtextLt || st == StScriptLt {
      if c == '!' && st == StScriptLt {
        self.add_data_str("<!")
        self.tstate = StScriptEscapeStart
        self.pos = self.pos + 1
      } else if c == '/' {
        self.temp = ""
        if st == StRcdataLt {
          self.tstate = StRcdataEndTagOpen
        } else if st == StRawtextLt {
          self.tstate = StRawtextEndTagOpen
        } else {
          self.tstate = StScriptEndTagOpen
        }
        self.pos = self.pos + 1
      } else {
        self.tstate = if st == StRcdataLt {
          StRcdata
        } else if st == StRawtextLt {
          StRawtext
        } else {
          StScriptData
        }
        self.add_data('<')
      }
    } else if st == StRcdataEndTagOpen || st == StRawtextEndTagOpen || st == StScriptEndTagOpen {
      if is_alpha_ascii(c) {
        self.begin_tag(true)
        self.temp = ""
        self.tstate = if st == StRcdataEndTagOpen {
          StRcdataEndTagName
        } else if st == StRawtextEndTagOpen {
          StRawtextEndTagName
        } else {
          StScriptEndTagName
        }
      } else {
        self.tstate = if st == StRcdataEndTagOpen {
          StRcdata
        } else if st == StRawtextEndTagOpen {
          StRawtext
        } else {
          StScriptData
        }
        self.add_data_str("</")
      }
    } else if st == StRcdataEndTagName || st == StRawtextEndTagName || st == StScriptEndTagName {
      let back = if st == StRcdataEndTagName {
        StRcdata
      } else if st == StRawtextEndTagName {
        StRawtext
      } else {
        StScriptData
      }
      let matched = lower_str(self.temp) == self.raw_tag
      if is_space_h(c) && matched {
        self.tok_name = lower_str(self.temp)
        self.tstate = StBeforeAttrName
        self.pos = self.pos + 1
      } else if c == '/' && matched {
        self.tok_name = lower_str(self.temp)
        self.tstate = StSelfClosing
        self.pos = self.pos + 1
      } else if c == '>' && matched {
        self.tstate = StData
        self.pos = self.pos + 1
        return End(lower_str(self.temp))
      } else if is_alpha_ascii(c) {
        self.temp = self.temp + c.to_string()
        self.pos = self.pos + 1
      } else {
        self.tstate = back
        self.add_data_str("</")
        self.add_data_str(self.temp)
      }
    } else if st == StScriptEscapeStart {
      if c == '-' {
        self.add_data('-')
        self.tstate = StScriptEscapeStartDash
        self.pos = self.pos + 1
      } else {
        self.tstate = StScriptData
      }
    } else if st == StScriptEscapeStartDash {
      if c == '-' {
        self.add_data('-')
        self.tstate = StScriptEscapedDashDash
        self.pos = self.pos + 1
      } else {
        self.tstate = StScriptData
      }
    } else if st == StScriptEscaped || st == StScriptEscapedDash || st == StScriptEscapedDashDash {
      if c == '-' {
        // escaped -> escaped dash -> escaped dash dash, and stay there.
        self.add_data('-')
        self.tstate = match st {
          StScriptEscaped => StScriptEscapedDash
          StScriptEscapedDash => StScriptEscapedDashDash
          _ => st
        }
        self.pos = self.pos + 1
      } else if c == '<' {
        self.tstate = StScriptEscapedLt
        self.pos = self.pos + 1
      } else if c == '>' && st == StScriptEscapedDashDash {
        self.add_data('>')
        self.tstate = StScriptData
        self.pos = self.pos + 1
      } else if c == '\u{0}' {
        self.add_data('\u{FFFD}')
        self.tstate = StScriptEscaped
        self.pos = self.pos + 1
      } else {
        self.add_data(c)
        self.tstate = StScriptEscaped
        self.pos = self.pos + 1
      }
    } else if st == StScriptEscapedLt {
      if c == '/' {
        self.temp = ""
        self.tstate = StScriptEscapedEndTagOpen
        self.pos = self.pos + 1
      } else if is_alpha_ascii(c) {
        self.temp = ""
        self.add_data('<')
        self.tstate = StScriptDoubleEscapeStart
      } else {
        self.add_data('<')
        self.tstate = StScriptEscaped
      }
    } else if st == StScriptEscapedEndTagOpen {
      if is_alpha_ascii(c) {
        self.begin_tag(true)
        self.temp = ""
        self.tstate = StScriptEscapedEndTagName
      } else {
        self.add_data_str("</")
        self.tstate = StScriptEscaped
      }
    } else if st == StScriptEscapedEndTagName {
      let matched = lower_str(self.temp) == self.raw_tag
      if is_space_h(c) && matched {
        self.tok_name = lower_str(self.temp)
        self.tstate = StBeforeAttrName
        self.pos = self.pos + 1
      } else if c == '/' && matched {
        self.tok_name = lower_str(self.temp)
        self.tstate = StSelfClosing
        self.pos = self.pos + 1
      } else if c == '>' && matched {
        self.tstate = StData
        self.pos = self.pos + 1
        return End(lower_str(self.temp))
      } else if is_alpha_ascii(c) {
        self.temp = self.temp + c.to_string()
        self.pos = self.pos + 1
      } else {
        self.add_data_str("</")
        self.add_data_str(self.temp)
        self.tstate = StScriptEscaped
      }
    } else if st == StScriptDoubleEscapeStart {
      if is_space_h(c) || c == '/' || c == '>' {
        if lower_str(self.temp) == "script" {
          self.tstate = StScriptDoubleEscaped
        } else {
          self.tstate = StScriptEscaped
        }
        self.add_data(c)
        self.pos = self.pos + 1
      } else if is_alpha_ascii(c) {
        self.temp = self.temp + c.to_string()
        self.add_data(c)
        self.pos = self.pos + 1
      } else {
        self.tstate = StScriptEscaped
      }
    } else if st == StScriptDoubleEscaped || st == StScriptDoubleEscapedDash || st == StScriptDoubleEscapedDashDash {
      if c == '-' {
        self.add_data('-')
        self.tstate = match st {
          StScriptDoubleEscaped => StScriptDoubleEscapedDash
          StScriptDoubleEscapedDash => StScriptDoubleEscapedDashDash
          _ => st
        }
        self.pos = self.pos + 1
      } else if c == '<' {
        self.tstate = StScriptDoubleEscapedLt
        self.pos = self.pos + 1
      } else if c == '>' && st == StScriptDoubleEscapedDashDash {
        self.add_data('>')
        self.tstate = StScriptData
        self.pos = self.pos + 1
      } else if c == '\u{0}' {
        self.add_data('\u{FFFD}')
        self.tstate = StScriptDoubleEscaped
        self.pos = self.pos + 1
      } else {
        self.add_data(c)
        self.tstate = StScriptDoubleEscaped
        self.pos = self.pos + 1
      }
    } else if st == StScriptDoubleEscapedLt {
      if c == '/' {
        // The '<' was held back by the previous state; both it and the '/' are
        // text here.
        self.add_data_str("</")
        self.temp = ""
        self.tstate = StScriptDoubleEscapeEnd
        self.pos = self.pos + 1
      } else {
        self.add_data('<')
        self.tstate = StScriptDoubleEscaped
      }
    } else if st == StScriptDoubleEscapeEnd {
      if is_space_h(c) || c == '/' || c == '>' {
        if lower_str(self.temp) == "script" {
          self.tstate = StScriptEscaped
        } else {
          self.tstate = StScriptDoubleEscaped
        }
        self.add_data(c)
        self.pos = self.pos + 1
      } else if is_alpha_ascii(c) {
        self.temp = self.temp + c.to_string()
        self.add_data(c)
        self.pos = self.pos + 1
      } else {
        self.tstate = StScriptDoubleEscaped
      }
    } else {
      // Unreachable, but a tokenizer must always make progress.
      self.pos = self.pos + 1
    }
  }
  Eof
}

/// Append a character to the data buffer, mapping NUL to U+FFFD.
fn push_repl_data(h : H, c : Char) -> Unit {
  if c == '\u{0}' {
    h.add_data('\u{FFFD}')
  } else {
    h.add_data(c)
  }
}

fn repl_char(c : Char) -> Char {
  if c == '\u{0}' {
    '\u{FFFD}'
  } else {
    c
  }
}

fn append_opt(v : String?, c : Char) -> String? {
  match v {
    Some(x) => Some(x + c.to_string())
    None => Some(c.to_string())
  }
}
