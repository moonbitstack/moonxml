// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The tokenizer: the HTML standard's states, one function each. The tree
// builder reads the tokens this produces; nothing else does.
//
// Two departures from a literal transcription, neither of which changes an
// answer. Characters are collected into a run and handed over as one token
// (`Characters`), split where the run changes between whitespace and not —
// which is the only distinction a tree builder's modes ask about. And a
// character reference is looked up whole rather than one code point at a time:
// the table is sorted, so the longest match is a search, not a state walk.

///|
/// The tokenizer's states, in the standard's order.
priv enum TokState {
  Data
  Rcdata
  Rawtext
  ScriptData
  Plaintext
  TagOpen
  EndTagOpen
  TagName
  RcdataLessThan
  RcdataEndTagOpen
  RcdataEndTagName
  RawtextLessThan
  RawtextEndTagOpen
  RawtextEndTagName
  ScriptLessThan
  ScriptEndTagOpen
  ScriptEndTagName
  ScriptEscapeStart
  ScriptEscapeStartDash
  ScriptEscaped
  ScriptEscapedDash
  ScriptEscapedDashDash
  ScriptEscapedLessThan
  ScriptEscapedEndTagOpen
  ScriptEscapedEndTagName
  ScriptDoubleEscapeStart
  ScriptDoubleEscaped
  ScriptDoubleEscapedDash
  ScriptDoubleEscapedDashDash
  ScriptDoubleEscapedLessThan
  ScriptDoubleEscapeEnd
  BeforeAttributeName
  AttributeName
  AfterAttributeName
  BeforeAttributeValue
  AttributeValueDouble
  AttributeValueSingle
  AttributeValueUnquoted
  AfterAttributeValueQuoted
  SelfClosingStartTag
  BogusComment
  MarkupDeclarationOpen
  CommentStart
  CommentStartDash
  Comment
  CommentLessThan
  CommentLessThanBang
  CommentLessThanBangDash
  CommentLessThanBangDashDash
  CommentEndDash
  CommentEnd
  CommentEndBang
  Doctype
  BeforeDoctypeName
  DoctypeName
  AfterDoctypeName
  AfterDoctypePublicKeyword
  BeforeDoctypePublicIdentifier
  DoctypePublicIdentifierDouble
  DoctypePublicIdentifierSingle
  AfterDoctypePublicIdentifier
  BetweenDoctypePublicAndSystem
  AfterDoctypeSystemKeyword
  BeforeDoctypeSystemIdentifier
  DoctypeSystemIdentifierDouble
  DoctypeSystemIdentifierSingle
  AfterDoctypeSystemIdentifier
  BogusDoctype
  CdataSection
  CdataSectionBracket
  CdataSectionEnd
  CharacterReference
  NumericCharacterReference
  HexadecimalCharacterReferenceStart
  HexadecimalCharacterReference
  DecimalCharacterReferenceStart
  DecimalCharacterReference
  NumericCharacterReferenceEnd
}

///|
/// One token. The tree builder's whole input.
priv enum Token {
  StartTag(
    name~ : String,
    attrs~ : Array[(String, String)],
    self_closing~ : Bool
  )
  EndTag(name~ : String)
  Characters(text~ : String)
  CommentToken(text~ : String)
  DoctypeToken(
    name~ : String,
    public_id~ : String,
    system_id~ : String,
    force_quirks~ : Bool
  )
  Eof
}

///|
/// The tokenizer's state: where it is in the source, what it is in the middle
/// of building, and the run of characters it has not handed over yet.
priv struct Lexer {
  text : String
  mut at : Int32
  mut width : Int32
  mut state : TokState
  builder : Builder
  mut run : StringBuilder
  /// Whether the run so far is all whitespace; a run that changes answers the
  /// question "is this text or space" that the modes ask.
  mut run_space : Bool
  mut run_empty : Bool
  // the tag being built
  mut is_end : Bool
  mut tag_name : StringBuilder
  mut attrs : Array[(String, String)]
  mut attr_name : StringBuilder
  mut attr_value : StringBuilder
  mut self_closing : Bool
  // comment and doctype data
  mut comment : StringBuilder
  mut doctype_name : StringBuilder
  mut doctype_public : StringBuilder
  mut doctype_system : StringBuilder
  mut force_quirks : Bool
  // the character reference being decoded
  mut reference : StringBuilder
  mut ref_return : TokState
  mut ref_in_attribute : Bool
  mut finished : Bool
  /// Set when the last read was the end of the input: handing that character
  /// back would rewind into the text and read it for ever.
  mut at_eof : Bool
  /// The name of the end tag being read in raw text, in the case it was
  /// written: when it turns out not to be an end tag, that is what goes back
  /// into the text.
  mut raw_buf : StringBuilder
  /// The name of the element whose end tag closes the raw text the tokenizer is
  /// in the middle of, if it is in the middle of one.
  mut raw_name : String
}

///|
fn Lexer::new(text : String, builder : Builder) -> Lexer {
  {
    text,
    at: 0,
    width: 1,
    state: Data,
    builder,
    run: StringBuilder(),
    run_space: true,
    run_empty: true,
    is_end: false,
    tag_name: StringBuilder(),
    attrs: [],
    attr_name: StringBuilder(),
    attr_value: StringBuilder(),
    self_closing: false,
    comment: StringBuilder(),
    doctype_name: StringBuilder(),
    doctype_public: StringBuilder(),
    doctype_system: StringBuilder(),
    force_quirks: false,
    reference: StringBuilder(),
    ref_return: Data,
    ref_in_attribute: false,
    finished: false,
    at_eof: false,
    raw_buf: StringBuilder(),
    raw_name: "",
  }
}

///|
/// The next code point, or `-1` at the end of the input.
fn Lexer::next(self : Lexer) -> Int32 {
  let n = self.text.length()
  if self.at >= n {
    self.width = 1
    self.at_eof = true
    return -1
  }
  self.at_eof = false
  let unit = self.text.at(self.at)
  if unit >= 0xD800 && unit <= 0xDBFF && self.at + 1 < n {
    let low = self.text.at(self.at + 1)
    if low >= 0xDC00 && low <= 0xDFFF {
      self.width = 2
      self.at = self.at + 2
      return (unit.to_int() - 0xD800) * 1024 + (low.to_int() - 0xDC00) + 0x10000
    }
  }
  self.width = 1
  self.at = self.at + 1
  unit.to_int()
}

///|
fn Lexer::reconsume(self : Lexer) -> Unit {
  if !self.at_eof {
    self.at = self.at - self.width
  }
}

///|
/// The rest of the input starts with this spelling, in any case.
fn Lexer::starts_ci(self : Lexer, probe : String) -> Bool {
  let n = self.text.length()
  let m = probe.length()
  if self.at + m > n {
    return false
  }
  let mut i = 0
  while i < m {
    let left = lower_unit(self.text.at(self.at + i))
    let right = lower_unit(probe.at(i))
    if left != right {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn Lexer::after(self : Lexer, count : Int32) -> Unit {
  self.at = self.at + count
  self.width = 1
  self.at_eof = false
}

///|
fn lower_unit(unit : UInt16) -> UInt16 {
  if unit >= 0x41 && unit <= 0x5A {
    unit + 0x20
  } else {
    unit
  }
}

///|
fn is_white(code : Int32) -> Bool {
  code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0C || code == 0x0D
}

///|
fn is_alpha(code : Int32) -> Bool {
  (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)
}

///|
fn is_digit(code : Int32) -> Bool {
  code >= 0x30 && code <= 0x39
}

///|
fn is_alnum(code : Int32) -> Bool {
  is_alpha(code) || is_digit(code)
}

///|
fn is_hex(code : Int32) -> Bool {
  is_digit(code) ||
  (code >= 0x41 && code <= 0x46) ||
  (code >= 0x61 && code <= 0x66)
}

///|
fn as_char(code : Int32) -> Char {
  code.unsafe_to_char()
}

// ------------------------------------------------------------------ emitting

///|
/// One character of text. A run that turns from text to space, or back, is
/// handed over first: the modes ask whether what arrived is whitespace.
fn emit_char(lexer : Lexer, code : Int32) -> Unit {
  let space = is_white(code)
  if !lexer.run_empty && space != lexer.run_space {
    flush_run(lexer)
  }
  lexer.run.write_char(as_char(code))
  lexer.run_space = space
  lexer.run_empty = false
}

///|
fn emit_text(lexer : Lexer, text : String) -> Unit {
  for ch in text {
    emit_char(lexer, ch.to_int())
  }
}

///|
fn flush_run(lexer : Lexer) -> Unit {
  if lexer.run_empty {
    return
  }
  let text = lexer.run.to_string()
  lexer.run = StringBuilder()
  lexer.run_empty = true
  lexer.run_space = true
  process(lexer, Characters(text~))
}

///|
fn emit_token(lexer : Lexer, token : Token) -> Unit {
  flush_run(lexer)
  process(lexer, token)
}

///|
fn emit_tag(lexer : Lexer) -> Unit {
  let name = lexer.tag_name.to_string()
  let attrs = lexer.attrs
  lexer.tag_name = StringBuilder()
  lexer.attrs = []
  let is_end = lexer.is_end
  let self_closing = lexer.self_closing
  lexer.self_closing = false
  lexer.is_end = false
  if is_end {
    emit_token(lexer, EndTag(name~))
  } else {
    emit_token(lexer, StartTag(name~, attrs~, self_closing~))
  }
}

///|
fn emit_comment(lexer : Lexer) -> Unit {
  let text = lexer.comment.to_string()
  lexer.comment = StringBuilder()
  emit_token(lexer, CommentToken(text~))
}

///|
fn emit_doctype(lexer : Lexer) -> Unit {
  let name = lexer.doctype_name.to_string()
  let public_id = lexer.doctype_public.to_string()
  let system_id = lexer.doctype_system.to_string()
  let force_quirks = lexer.force_quirks
  lexer.doctype_name = StringBuilder()
  lexer.doctype_public = StringBuilder()
  lexer.doctype_system = StringBuilder()
  lexer.force_quirks = false
  emit_token(lexer, DoctypeToken(name~, public_id~, system_id~, force_quirks~))
}

///|
/// Put the attribute being built on the tag, unless its name is empty or the
/// name is already there: a repeated attribute keeps the first.
fn finish_attr(lexer : Lexer) -> Unit {
  let name = lexer.attr_name.to_string()
  let value = lexer.attr_value.to_string()
  lexer.attr_name = StringBuilder()
  lexer.attr_value = StringBuilder()
  if name.is_empty() {
    return
  }
  for pair in lexer.attrs {
    if pair.0 == name {
      lexer.builder.repairs.dropped = lexer.builder.repairs.dropped + 1
      return
    }
  }
  lexer.attrs.push((name, value))
}

///|
fn new_tag(lexer : Lexer, is_end : Bool) -> Unit {
  lexer.tag_name = StringBuilder()
  lexer.raw_buf = StringBuilder()
  lexer.attrs = []
  lexer.self_closing = false
  lexer.is_end = is_end
  // The name of the raw-text element whose end tag may close it, for the
  // states that look for it.
  lexer.attr_name = StringBuilder()
  lexer.attr_value = StringBuilder()
}

// ------------------------------------------------------------- the main loop

///|
/// Run the tokenizer to the end of the input, handing every token to the tree
/// builder. The end of the input is a token of its own — the tree builder has
/// things to finish — and it ends the loop.
fn tokenize(lexer : Lexer) -> Unit {
  while !lexer.finished {
    step(lexer, lexer.next())
  }
}

///|
fn emit_eof(lexer : Lexer) -> Unit {
  lexer.finished = true
  emit_token(lexer, Eof)
}

///|
fn step(lexer : Lexer, ch : Int32) -> Unit {
  match lexer.state {
    Data => data_state(lexer, ch)
    Rcdata => rcdata_state(lexer, ch)
    Rawtext => rawtext_state(lexer, ch)
    ScriptData => script_data_state(lexer, ch)
    Plaintext => plaintext_state(lexer, ch)
    TagOpen => tag_open_state(lexer, ch)
    EndTagOpen => end_tag_open_state(lexer, ch)
    TagName => tag_name_state(lexer, ch)
    RcdataLessThan => rcdata_less_than_state(lexer, ch)
    RcdataEndTagOpen => rcdata_end_tag_open_state(lexer, ch)
    RcdataEndTagName => rcdata_end_tag_name_state(lexer, ch)
    RawtextLessThan => rawtext_less_than_state(lexer, ch)
    RawtextEndTagOpen => rawtext_end_tag_open_state(lexer, ch)
    RawtextEndTagName => rawtext_end_tag_name_state(lexer, ch)
    ScriptLessThan => script_less_than_state(lexer, ch)
    ScriptEndTagOpen => script_end_tag_open_state(lexer, ch)
    ScriptEndTagName => script_end_tag_name_state(lexer, ch)
    ScriptEscapeStart => script_escape_start_state(lexer, ch)
    ScriptEscapeStartDash => script_escape_start_dash_state(lexer, ch)
    ScriptEscaped => script_escaped_state(lexer, ch)
    ScriptEscapedDash => script_escaped_dash_state(lexer, ch)
    ScriptEscapedDashDash => script_escaped_dash_dash_state(lexer, ch)
    ScriptEscapedLessThan => script_escaped_less_than_state(lexer, ch)
    ScriptEscapedEndTagOpen => script_escaped_end_tag_open_state(lexer, ch)
    ScriptEscapedEndTagName => script_escaped_end_tag_name_state(lexer, ch)
    ScriptDoubleEscapeStart => script_double_escape_start_state(lexer, ch)
    ScriptDoubleEscaped => script_double_escaped_state(lexer, ch)
    ScriptDoubleEscapedDash => script_double_escaped_dash_state(lexer, ch)
    ScriptDoubleEscapedDashDash =>
      script_double_escaped_dash_dash_state(lexer, ch)
    ScriptDoubleEscapedLessThan =>
      script_double_escaped_less_than_state(lexer, ch)
    ScriptDoubleEscapeEnd => script_double_escape_end_state(lexer, ch)
    BeforeAttributeName => before_attribute_name_state(lexer, ch)
    AttributeName => attribute_name_state(lexer, ch)
    AfterAttributeName => after_attribute_name_state(lexer, ch)
    BeforeAttributeValue => before_attribute_value_state(lexer, ch)
    AttributeValueDouble => attribute_value_double_state(lexer, ch)
    AttributeValueSingle => attribute_value_single_state(lexer, ch)
    AttributeValueUnquoted => attribute_value_unquoted_state(lexer, ch)
    AfterAttributeValueQuoted => after_attribute_value_quoted_state(lexer, ch)
    SelfClosingStartTag => self_closing_start_tag_state(lexer, ch)
    BogusComment => bogus_comment_state(lexer, ch)
    MarkupDeclarationOpen => markup_declaration_open_state(lexer, ch)
    CommentStart => comment_start_state(lexer, ch)
    CommentStartDash => comment_start_dash_state(lexer, ch)
    Comment => comment_state(lexer, ch)
    CommentLessThan => comment_less_than_state(lexer, ch)
    CommentLessThanBang => comment_less_than_bang_state(lexer, ch)
    CommentLessThanBangDash => comment_less_than_bang_dash_state(lexer, ch)
    CommentLessThanBangDashDash =>
      comment_less_than_bang_dash_dash_state(lexer, ch)
    CommentEndDash => comment_end_dash_state(lexer, ch)
    CommentEnd => comment_end_state(lexer, ch)
    CommentEndBang => comment_end_bang_state(lexer, ch)
    Doctype => doctype_state(lexer, ch)
    BeforeDoctypeName => before_doctype_name_state(lexer, ch)
    DoctypeName => doctype_name_state(lexer, ch)
    AfterDoctypeName => after_doctype_name_state(lexer, ch)
    AfterDoctypePublicKeyword => after_doctype_public_keyword_state(lexer, ch)
    BeforeDoctypePublicIdentifier =>
      before_doctype_public_identifier_state(lexer, ch)
    DoctypePublicIdentifierDouble => doctype_public_double_state(lexer, ch)
    DoctypePublicIdentifierSingle => doctype_public_single_state(lexer, ch)
    AfterDoctypePublicIdentifier =>
      after_doctype_public_identifier_state(lexer, ch)
    BetweenDoctypePublicAndSystem =>
      between_doctype_public_and_system_state(lexer, ch)
    AfterDoctypeSystemKeyword => after_doctype_system_keyword_state(lexer, ch)
    BeforeDoctypeSystemIdentifier =>
      before_doctype_system_identifier_state(lexer, ch)
    DoctypeSystemIdentifierDouble => doctype_system_double_state(lexer, ch)
    DoctypeSystemIdentifierSingle => doctype_system_single_state(lexer, ch)
    AfterDoctypeSystemIdentifier =>
      after_doctype_system_identifier_state(lexer, ch)
    BogusDoctype => bogus_doctype_state(lexer, ch)
    CdataSection => cdata_section_state(lexer, ch)
    CdataSectionBracket => cdata_section_bracket_state(lexer, ch)
    CdataSectionEnd => cdata_section_end_state(lexer, ch)
    CharacterReference => character_reference_state(lexer, ch)
    NumericCharacterReference => numeric_character_reference_state(lexer, ch)
    HexadecimalCharacterReferenceStart => hex_start_state(lexer, ch)
    HexadecimalCharacterReference => hex_state(lexer, ch)
    DecimalCharacterReferenceStart => decimal_start_state(lexer, ch)
    DecimalCharacterReference => decimal_state(lexer, ch)
    NumericCharacterReferenceEnd => numeric_end_state(lexer, ch)
  }
}
