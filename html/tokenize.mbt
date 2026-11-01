/// The token stream.
///
/// The tree builder consumes tokens, not characters: the tokenizer decides
/// where a tag, a comment or a run of text ends, and the builder decides what
/// to do with it. Separating the two is what makes a real insertion-mode state
/// machine possible, because a mode can switch the tokenizer into RCDATA and
/// expect a single character token back.
///
/// A tag token carries the tag name (lowercased), its attributes in source
/// order, and whether it was written self-closing. Character tokens carry
/// decoded text with NUL already handled per state.

enum Tok {
  Chars(String)
  Start(String, Array[(String, String)], Bool)
  End(String)
  Comment(String)
  Doctype(String)
  Eof
}

/// The states the tree builder switches the tokenizer between. The five
/// content models are the ones the spec lets the builder choose.
enum TokState {
  TsData
  TsRcdata
  TsRawtext
  TsScript
  TsPlaintext
}

fn is_ascii_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

fn is_ascii_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

/// Read one token. Returns `Eof` once the input is exhausted, and never
/// returns an empty character token.
fn H::next_token(self : H) -> Tok {
  while true {
    if self.at_end() {
      return Eof
    }
    match self.tstate {
      TsPlaintext => {
        let s = slice_of(self.s, self.pos, self.n)
        self.pos = self.n
        return Chars(nul_to_fffd(s))
      }
      TsRcdata => {
        match self.scan_raw(true, false) {
          Some(t) => return t
          None => continue
        }
      }
      TsRawtext => {
        match self.scan_raw(false, false) {
          Some(t) => return t
          None => continue
        }
      }
      TsScript => {
        match self.scan_raw(false, true) {
          Some(t) => return t
          None => continue
        }
      }
      TsData => ()
    }
    // Data state. A run of text up to the next `<`.
    let start = self.pos
    while not(self.at_end()) && self.peek() != '<' {
      self.pos = self.pos + 1
    }
    if self.pos > start {
      let raw = slice_of(self.s, start, self.pos)
      return Chars(decode_entities(raw))
    }
    // At a `<`. Which construct it opens decides the token.
    if self.starts_with("<!--") {
      return self.scan_comment_token()
    }
    if self.starts_with_ci("<!doctype") {
      self.pos = self.pos + 9
      return Doctype(self.parse_doctype_html())
    }
    if self.starts_with("<![CDATA[") && self.adjusted_foreign() {
      return self.scan_cdata_token()
    }
    if self.starts_with("<!") {
      return self.scan_bogus_comment(2)
    }
    if self.starts_with("<?") {
      // The `?` is part of the comment's data, as the spec's reconsume does.
      return self.scan_bogus_comment(1)
    }
    if self.starts_with("</") {
      if self.pos + 2 >= self.n {
        // A trailing `</` at end of input is text.
        self.pos = self.n
        return Chars("</")
      }
      if not(is_ascii_alpha(self.peek_at(2))) {
        if self.peek_at(2) == '>' {
          // `</>`: a missing end tag name, and no token comes out of it.
          self.pos = self.pos + 3
          continue
        }
        return self.scan_bogus_comment(2)
      }
      return self.scan_tag(true)
    }
    if is_ascii_alpha(self.peek_at(1)) {
      return self.scan_tag(false)
    }
    // A bare `<` is text.
    self.pos = self.pos + 1
    return Chars("<")
  }
  Eof
}

/// Characters up to the `</tag` that ends a RAWTEXT/RCDATA/script element.
/// `None` means the end tag starts right here: put the tokenizer back into the
/// data state and let it emit the end tag.
fn H::scan_raw(self : H, decode : Bool, script : Bool) -> Tok? {
  let n = self.n
  let end = if script {
    find_script_end(self.s, self.pos, n)
  } else {
    find_rawtext_end(self.s, self.pos, n, self.raw_tag)
  }
  if end < 0 {
    let raw = slice_of(self.s, self.pos, n)
    self.pos = n
    self.tstate = TsData
    if raw.length() == 0 {
      return None
    }
    return Some(Chars(if decode { decode_entities(nul_to_fffd(raw)) } else { nul_to_fffd(raw) }))
  }
  if end == self.pos {
    self.tstate = TsData
    return None
  }
  let raw = slice_of(self.s, self.pos, end)
  self.pos = end
  if decode {
    Some(Chars(decode_entities(nul_to_fffd(raw))))
  } else {
    Some(Chars(nul_to_fffd(raw)))
  }
}

fn H::scan_comment_token(self : H) -> Tok {
  self.pos = self.pos + 4
  // `<!-->` and `<!--->` are empty comments closed abruptly.
  if not(self.at_end()) && self.peek() == '>' {
    self.pos = self.pos + 1
    return Comment("")
  }
  if self.starts_with("->") {
    self.pos = self.pos + 2
    return Comment("")
  }
  let (text, next) = scan_comment(self.s, self.pos)
  self.pos = next
  Comment(nul_to_fffd(text))
}

fn H::scan_bogus_comment(self : H, skip : Int) -> Tok {
  self.pos = self.pos + skip
  let start = self.pos
  while not(self.at_end()) && self.peek() != '>' {
    self.pos = self.pos + 1
  }
  let text = slice_of(self.s, start, self.pos)
  if not(self.at_end()) {
    self.pos = self.pos + 1
  }
  Comment(nul_to_fffd(text))
}

/// A CDATA section is character data inside `svg`/`math`; the opening and
/// closing markers are not part of the text.
fn H::scan_cdata_token(self : H) -> Tok {
  self.pos = self.pos + 9
  let start = self.pos
  let mut end = self.n
  let mut after = self.n
  let mut i = start
  while i + 2 < self.n {
    if self.s[i] == ']' && self.s[i + 1] == ']' && self.s[i + 2] == '>' {
      end = i
      after = i + 3
      break
    }
    i = i + 1
  }
  let text = slice_of(self.s, start, end)
  self.pos = after
  Chars(nul_to_fffd(text))
}

/// Read a start or end tag. The attribute scanner follows the spec's tokenizer:
/// names stop at whitespace, `/`, `>` or `=`, a duplicate name is dropped, and
/// an unquoted value ends at whitespace or `>`.
fn H::scan_tag(self : H, is_end : Bool) -> Tok {
  self.pos = self.pos + 1
  if is_end {
    self.pos = self.pos + 1
  }
  let name = self.read_tag_name()
  if name.length() == 0 {
    // `<` followed by something that is not a name: treat as text.
    return Chars("<")
  }
  let attrs : Array[(String, String)] = []
  let mut self_closing = false
  while true {
    while not(self.at_end()) && @text.is_html_space(self.peek()) {
      self.pos = self.pos + 1
    }
    if self.at_end() {
      break
    }
    let c = self.peek()
    if c == '>' {
      self.pos = self.pos + 1
      break
    }
    if c == '/' {
      if self.peek_at(1) == '>' {
        self.pos = self.pos + 2
        self_closing = true
        break
      }
      self.pos = self.pos + 1
      continue
    }
    // Attribute name.
    let astart = self.pos
    while not(self.at_end()) &&
      not(@text.is_html_space(self.peek())) &&
      self.peek() != '=' &&
      self.peek() != '>' &&
      self.peek() != '/' {
      self.pos = self.pos + 1
    }
    let aname = slice_of(self.s, astart, self.pos).to_lower()
    while not(self.at_end()) && @text.is_html_space(self.peek()) {
      self.pos = self.pos + 1
    }
    let mut avalue = ""
    if not(self.at_end()) && self.peek() == '=' {
      self.pos = self.pos + 1
      while not(self.at_end()) && @text.is_html_space(self.peek()) {
        self.pos = self.pos + 1
      }
      if not(self.at_end()) && (self.peek() == '"' || self.peek() == '\'') {
        let q = self.peek()
        self.pos = self.pos + 1
        let vstart = self.pos
        while not(self.at_end()) && self.peek() != q {
          self.pos = self.pos + 1
        }
        avalue = decode_entities_attr(nul_to_fffd(slice_of(self.s, vstart, self.pos)))
        if not(self.at_end()) {
          self.pos = self.pos + 1
        }
      } else {
        let vstart = self.pos
        while not(self.at_end()) &&
          not(@text.is_html_space(self.peek())) &&
          self.peek() != '>' {
          self.pos = self.pos + 1
        }
        avalue = decode_entities_attr(nul_to_fffd(slice_of(self.s, vstart, self.pos)))
      }
    }
    if aname.length() > 0 && not(has_attr(attrs, aname)) {
      attrs.push((aname, avalue))
    }
  }
  if is_end {
    End(name)
  } else {
    Start(name, attrs, self_closing)
  }
}

fn has_attr(attrs : Array[(String, String)], name : String) -> Bool {
  for pair in attrs {
    let (k, _) = pair
    if k == name {
      return true
    }
  }
  false
}
