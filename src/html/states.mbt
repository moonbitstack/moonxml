// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The tokenizer's states, one function each, in the order the standard lists
// them. Every function reads one code point and decides what happens to it;
// the ones that need to look at a character twice hand it back with
// `reconsume`.

///|
/// A character that belongs to the current token's text: a character token, or
/// the attribute value being built.
fn put_char(lexer : Lexer, code : Int32) -> Unit {
  if lexer.ref_in_attribute {
    lexer.attr_value.write_char(as_char(code))
  } else {
    emit_char(lexer, code)
  }
}

///|
/// Where a character reference's result goes.
fn put_text(lexer : Lexer, text : String) -> Unit {
  if lexer.ref_in_attribute {
    lexer.attr_value.write_string(text)
  } else {
    emit_text(lexer, text)
  }
}

// ------------------------------------------------------------------ the data

///|
fn data_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == -1 {
    emit_eof(lexer)
    return
  }
  if ch == 0x26 {
    lexer.reference = StringBuilder()
    lexer.ref_return = Data
    lexer.ref_in_attribute = false
    lexer.state = CharacterReference
    return
  }
  if ch == 0x3C {
    lexer.state = TagOpen
    return
  }
  emit_char(lexer, ch)
}

///|
fn rcdata_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == -1 {
    emit_eof(lexer)
    return
  }
  if ch == 0x26 {
    lexer.reference = StringBuilder()
    lexer.ref_return = Rcdata
    lexer.ref_in_attribute = false
    lexer.state = CharacterReference
    return
  }
  if ch == 0x3C {
    lexer.state = RcdataLessThan
    return
  }
  emit_char(lexer, ch)
}

///|
fn rawtext_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == -1 {
    emit_eof(lexer)
    return
  }
  if ch == 0x3C {
    lexer.state = RawtextLessThan
    return
  }
  emit_char(lexer, ch)
}

///|
fn script_data_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == -1 {
    emit_eof(lexer)
    return
  }
  if ch == 0x3C {
    lexer.state = ScriptLessThan
    return
  }
  emit_char(lexer, ch)
}

///|
fn plaintext_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == -1 {
    emit_eof(lexer)
    return
  }
  emit_char(lexer, ch)
}

// -------------------------------------------------------------------- markup

///|
fn tag_open_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x21 {
    lexer.state = MarkupDeclarationOpen
    return
  }
  if ch == 0x2F {
    lexer.state = EndTagOpen
    return
  }
  if is_alpha(ch) {
    new_tag(lexer, false)
    lexer.state = TagName
    lexer.reconsume()
    return
  }
  if ch == 0x3F {
    lexer.comment = StringBuilder()
    lexer.state = BogusComment
    lexer.reconsume()
    return
  }
  if ch == -1 {
    emit_char(lexer, 0x3C)
    emit_eof(lexer)
    return
  }
  emit_char(lexer, 0x3C)
  lexer.state = Data
  lexer.reconsume()
}

///|
fn end_tag_open_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_alpha(ch) {
    new_tag(lexer, true)
    lexer.state = TagName
    lexer.reconsume()
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    return
  }
  if ch == -1 {
    emit_char(lexer, 0x3C)
    emit_char(lexer, 0x2F)
    emit_eof(lexer)
    return
  }
  lexer.comment = StringBuilder()
  lexer.state = BogusComment
  lexer.reconsume()
}

///|
fn tag_name_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    lexer.state = BeforeAttributeName
    return
  }
  if ch == 0x2F {
    lexer.state = SelfClosingStartTag
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    emit_tag(lexer)
    return
  }
  if ch == -1 {
    emit_eof(lexer)
    return
  }
  if ch == 0 {
    lexer.tag_name.write_char('\u{FFFD}')
    return
  }
  if ch >= 0x41 && ch <= 0x5A {
    lexer.tag_name.write_char(as_char(ch + 0x20))
    return
  }
  lexer.tag_name.write_char(as_char(ch))
}

///|
fn before_attribute_name_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    return
  }
  if ch == 0x2F || ch == 0x3E || ch == -1 {
    lexer.state = AfterAttributeName
    lexer.reconsume()
    return
  }
  if ch == 0x3D {
    lexer.attr_name = StringBuilder()
    lexer.attr_value = StringBuilder()
    lexer.attr_name.write_char('=')
    lexer.state = AttributeName
    return
  }
  lexer.attr_name = StringBuilder()
  lexer.attr_value = StringBuilder()
  lexer.state = AttributeName
  lexer.reconsume()
}

///|
fn attribute_name_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) || ch == 0x2F || ch == 0x3E || ch == -1 {
    lexer.state = AfterAttributeName
    lexer.reconsume()
    return
  }
  if ch == 0x3D {
    lexer.state = BeforeAttributeValue
    return
  }
  if ch == 0 {
    lexer.attr_name.write_char('\u{FFFD}')
    return
  }
  if ch >= 0x41 && ch <= 0x5A {
    lexer.attr_name.write_char(as_char(ch + 0x20))
    return
  }
  lexer.attr_name.write_char(as_char(ch))
}

///|
fn after_attribute_name_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    return
  }
  if ch == 0x2F {
    // The attribute is done even if what follows the solidus is not `>`.
    finish_attr(lexer)
    lexer.state = SelfClosingStartTag
    return
  }
  if ch == 0x3D {
    lexer.state = BeforeAttributeValue
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    finish_attr(lexer)
    emit_tag(lexer)
    return
  }
  if ch == -1 {
    finish_attr(lexer)
    emit_eof(lexer)
    return
  }
  finish_attr(lexer)
  lexer.attr_name = StringBuilder()
  lexer.attr_value = StringBuilder()
  lexer.state = AttributeName
  lexer.reconsume()
}

///|
fn before_attribute_value_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    return
  }
  if ch == 0x22 {
    lexer.state = AttributeValueDouble
    return
  }
  if ch == 0x27 {
    lexer.state = AttributeValueSingle
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    finish_attr(lexer)
    emit_tag(lexer)
    return
  }
  lexer.state = AttributeValueUnquoted
  lexer.reconsume()
}

///|
fn attribute_value_double_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x22 {
    lexer.state = AfterAttributeValueQuoted
    return
  }
  if ch == 0x26 {
    lexer.reference = StringBuilder()
    lexer.ref_return = AttributeValueDouble
    lexer.ref_in_attribute = true
    lexer.state = CharacterReference
    return
  }
  if ch == -1 {
    finish_attr(lexer)
    emit_eof(lexer)
    return
  }
  if ch == 0 {
    lexer.attr_value.write_char('\u{FFFD}')
    return
  }
  lexer.attr_value.write_char(as_char(ch))
}

///|
fn attribute_value_single_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x27 {
    lexer.state = AfterAttributeValueQuoted
    return
  }
  if ch == 0x26 {
    lexer.reference = StringBuilder()
    lexer.ref_return = AttributeValueSingle
    lexer.ref_in_attribute = true
    lexer.state = CharacterReference
    return
  }
  if ch == -1 {
    finish_attr(lexer)
    emit_eof(lexer)
    return
  }
  if ch == 0 {
    lexer.attr_value.write_char('\u{FFFD}')
    return
  }
  lexer.attr_value.write_char(as_char(ch))
}

///|
fn attribute_value_unquoted_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    lexer.state = BeforeAttributeName
    finish_attr(lexer)
    return
  }
  if ch == 0x26 {
    lexer.reference = StringBuilder()
    lexer.ref_return = AttributeValueUnquoted
    lexer.ref_in_attribute = true
    lexer.state = CharacterReference
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    finish_attr(lexer)
    emit_tag(lexer)
    return
  }
  if ch == -1 {
    finish_attr(lexer)
    emit_eof(lexer)
    return
  }
  if ch == 0 {
    lexer.attr_value.write_char('\u{FFFD}')
    return
  }
  lexer.attr_value.write_char(as_char(ch))
}

///|
fn after_attribute_value_quoted_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    lexer.state = BeforeAttributeName
    finish_attr(lexer)
    return
  }
  if ch == 0x2F {
    lexer.state = SelfClosingStartTag
    finish_attr(lexer)
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    finish_attr(lexer)
    emit_tag(lexer)
    return
  }
  if ch == -1 {
    finish_attr(lexer)
    emit_eof(lexer)
    return
  }
  lexer.state = BeforeAttributeName
  lexer.reconsume()
}

///|
fn self_closing_start_tag_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x3E {
    finish_attr(lexer)
    lexer.self_closing = true
    lexer.state = Data
    emit_tag(lexer)
    return
  }
  if ch == -1 {
    finish_attr(lexer)
    emit_eof(lexer)
    return
  }
  lexer.state = BeforeAttributeName
  lexer.reconsume()
}

///|
fn bogus_comment_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x3E {
    lexer.state = Data
    emit_comment(lexer)
    return
  }
  if ch == -1 {
    emit_comment(lexer)
    emit_eof(lexer)
    return
  }
  if ch == 0 {
    lexer.comment.write_char('\u{FFFD}')
    return
  }
  lexer.comment.write_char(as_char(ch))
}

///|
fn markup_declaration_open_state(lexer : Lexer, ch : Int32) -> Unit {
  ignore(ch)
  // The character after `<!` has been read; the spelling to match starts
  // there, so it is handed back first.
  lexer.reconsume()
  let text = lexer.text
  let n = text.length()
  if lexer.at + 2 <= n && text[lexer.at:lexer.at + 2] == "--" {
    lexer.after(2)
    lexer.comment = StringBuilder()
    lexer.state = CommentStart
    return
  }
  if lexer.starts_ci("doctype") {
    lexer.after(7)
    lexer.state = Doctype
    return
  }
  if lexer.at + 7 <= n && text[lexer.at:lexer.at + 7] == "[CDATA[" {
    lexer.after(7)
    if lexer.builder.in_foreign() {
      lexer.state = CdataSection
      return
    }
    // Outside foreign content a CDATA section is a bogus comment that says so.
    lexer.comment = StringBuilder()
    lexer.comment.write_string("[CDATA[")
    lexer.state = BogusComment
    return
  }
  lexer.comment = StringBuilder()
  lexer.state = BogusComment
}

// ----------------------------------------------------------------- comments

///|
fn comment_start_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2D {
    lexer.state = CommentStartDash
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    emit_comment(lexer)
    return
  }
  lexer.state = Comment
  lexer.reconsume()
}

///|
fn comment_start_dash_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2D {
    lexer.state = CommentEnd
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    emit_comment(lexer)
    return
  }
  if ch == -1 {
    emit_comment(lexer)
    emit_eof(lexer)
    return
  }
  lexer.comment.write_char('-')
  lexer.state = Comment
  lexer.reconsume()
}

///|
fn comment_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x3C {
    lexer.comment.write_char('<')
    lexer.state = CommentLessThan
    return
  }
  if ch == 0x2D {
    lexer.state = CommentEndDash
    return
  }
  if ch == -1 {
    emit_comment(lexer)
    emit_eof(lexer)
    return
  }
  if ch == 0 {
    lexer.comment.write_char('\u{FFFD}')
    return
  }
  lexer.comment.write_char(as_char(ch))
}

///|
fn comment_less_than_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x21 {
    lexer.comment.write_char('!')
    lexer.state = CommentLessThanBang
    return
  }
  if ch == 0x3C {
    lexer.comment.write_char('<')
    return
  }
  lexer.state = Comment
  lexer.reconsume()
}

///|
fn comment_less_than_bang_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2D {
    lexer.state = CommentLessThanBangDash
    return
  }
  lexer.state = Comment
  lexer.reconsume()
}

///|
fn comment_less_than_bang_dash_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2D {
    lexer.state = CommentLessThanBangDashDash
    return
  }
  lexer.state = CommentEndDash
  lexer.reconsume()
}

///|
fn comment_less_than_bang_dash_dash_state(lexer : Lexer, ch : Int32) -> Unit {
  ignore(ch)
  lexer.state = CommentEnd
  lexer.reconsume()
}

///|
fn comment_end_dash_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2D {
    lexer.state = CommentEnd
    return
  }
  if ch == -1 {
    emit_comment(lexer)
    emit_eof(lexer)
    return
  }
  lexer.comment.write_char('-')
  lexer.state = Comment
  lexer.reconsume()
}

///|
fn comment_end_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x3E {
    lexer.state = Data
    emit_comment(lexer)
    return
  }
  if ch == 0x21 {
    lexer.state = CommentEndBang
    return
  }
  if ch == 0x2D {
    lexer.comment.write_char('-')
    return
  }
  if ch == -1 {
    emit_comment(lexer)
    emit_eof(lexer)
    return
  }
  lexer.comment.write_string("--")
  lexer.state = Comment
  lexer.reconsume()
}

///|
fn comment_end_bang_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2D {
    lexer.comment.write_string("--!")
    lexer.state = CommentEndDash
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    emit_comment(lexer)
    return
  }
  if ch == -1 {
    emit_comment(lexer)
    emit_eof(lexer)
    return
  }
  lexer.comment.write_string("--!")
  lexer.state = Comment
  lexer.reconsume()
}

// ------------------------------------------------------------------ doctype

///|
fn doctype_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    lexer.state = BeforeDoctypeName
    return
  }
  if ch == 0x3E {
    lexer.state = BeforeDoctypeName
    lexer.reconsume()
    return
  }
  if ch == -1 {
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  lexer.state = BeforeDoctypeName
  lexer.reconsume()
}

///|
fn before_doctype_name_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    return
  }
  if ch == 0 {
    lexer.doctype_name = StringBuilder()
    lexer.doctype_name.write_char('\u{FFFD}')
    lexer.state = DoctypeName
    return
  }
  if ch == 0x3E {
    lexer.doctype_name = StringBuilder()
    lexer.force_quirks = true
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == -1 {
    lexer.doctype_name = StringBuilder()
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  lexer.doctype_name = StringBuilder()
  if ch >= 0x41 && ch <= 0x5A {
    lexer.doctype_name.write_char(as_char(ch + 0x20))
  } else {
    lexer.doctype_name.write_char(as_char(ch))
  }
  lexer.state = DoctypeName
}

///|
fn doctype_name_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    lexer.state = AfterDoctypeName
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == -1 {
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  if ch == 0 {
    lexer.doctype_name.write_char('\u{FFFD}')
    return
  }
  if ch >= 0x41 && ch <= 0x5A {
    lexer.doctype_name.write_char(as_char(ch + 0x20))
    return
  }
  lexer.doctype_name.write_char(as_char(ch))
}

///|
fn after_doctype_name_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == -1 {
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  // PUBLIC or SYSTEM: the character that decided it has been read, so the
  // spelling is looked at from there.
  lexer.reconsume()
  if lexer.starts_ci("public") {
    lexer.after(6)
    lexer.state = AfterDoctypePublicKeyword
    return
  }
  if lexer.starts_ci("system") {
    lexer.after(6)
    lexer.state = AfterDoctypeSystemKeyword
    return
  }
  lexer.force_quirks = true
  lexer.state = BogusDoctype
}

///|
fn after_doctype_public_keyword_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    lexer.state = BeforeDoctypePublicIdentifier
    return
  }
  if ch == 0x22 {
    lexer.doctype_public = StringBuilder()
    lexer.state = DoctypePublicIdentifierDouble
    return
  }
  if ch == 0x27 {
    lexer.doctype_public = StringBuilder()
    lexer.state = DoctypePublicIdentifierSingle
    return
  }
  if ch == 0x3E {
    lexer.force_quirks = true
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == -1 {
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  lexer.force_quirks = true
  lexer.state = BogusDoctype
  lexer.reconsume()
}

///|
fn before_doctype_public_identifier_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    return
  }
  if ch == 0x22 {
    lexer.doctype_public = StringBuilder()
    lexer.state = DoctypePublicIdentifierDouble
    return
  }
  if ch == 0x27 {
    lexer.doctype_public = StringBuilder()
    lexer.state = DoctypePublicIdentifierSingle
    return
  }
  if ch == 0x3E {
    lexer.force_quirks = true
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == -1 {
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  lexer.force_quirks = true
  lexer.state = BogusDoctype
  lexer.reconsume()
}

///|
fn doctype_public_double_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x22 {
    lexer.state = AfterDoctypePublicIdentifier
    return
  }
  if ch == 0 {
    lexer.doctype_public.write_char('\u{FFFD}')
    return
  }
  if ch == 0x3E {
    lexer.force_quirks = true
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == -1 {
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  lexer.doctype_public.write_char(as_char(ch))
}

///|
fn doctype_public_single_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x27 {
    lexer.state = AfterDoctypePublicIdentifier
    return
  }
  if ch == 0 {
    lexer.doctype_public.write_char('\u{FFFD}')
    return
  }
  if ch == 0x3E {
    lexer.force_quirks = true
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == -1 {
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  lexer.doctype_public.write_char(as_char(ch))
}

///|
fn after_doctype_public_identifier_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    lexer.state = BetweenDoctypePublicAndSystem
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == 0x22 {
    lexer.doctype_system = StringBuilder()
    lexer.state = DoctypeSystemIdentifierDouble
    return
  }
  if ch == 0x27 {
    lexer.doctype_system = StringBuilder()
    lexer.state = DoctypeSystemIdentifierSingle
    return
  }
  if ch == -1 {
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  lexer.force_quirks = true
  lexer.state = BogusDoctype
  lexer.reconsume()
}

///|
fn between_doctype_public_and_system_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == 0x22 {
    lexer.doctype_system = StringBuilder()
    lexer.state = DoctypeSystemIdentifierDouble
    return
  }
  if ch == 0x27 {
    lexer.doctype_system = StringBuilder()
    lexer.state = DoctypeSystemIdentifierSingle
    return
  }
  if ch == -1 {
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  lexer.force_quirks = true
  lexer.state = BogusDoctype
  lexer.reconsume()
}

///|
fn after_doctype_system_keyword_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    lexer.state = BeforeDoctypeSystemIdentifier
    return
  }
  if ch == 0x22 {
    lexer.doctype_system = StringBuilder()
    lexer.state = DoctypeSystemIdentifierDouble
    return
  }
  if ch == 0x27 {
    lexer.doctype_system = StringBuilder()
    lexer.state = DoctypeSystemIdentifierSingle
    return
  }
  if ch == 0x3E {
    lexer.force_quirks = true
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == -1 {
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  lexer.force_quirks = true
  lexer.state = BogusDoctype
  lexer.reconsume()
}

///|
fn before_doctype_system_identifier_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    return
  }
  if ch == 0x22 {
    lexer.doctype_system = StringBuilder()
    lexer.state = DoctypeSystemIdentifierDouble
    return
  }
  if ch == 0x27 {
    lexer.doctype_system = StringBuilder()
    lexer.state = DoctypeSystemIdentifierSingle
    return
  }
  if ch == 0x3E {
    lexer.force_quirks = true
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == -1 {
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  lexer.force_quirks = true
  lexer.state = BogusDoctype
  lexer.reconsume()
}

///|
fn doctype_system_double_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x22 {
    lexer.state = AfterDoctypeSystemIdentifier
    return
  }
  if ch == 0 {
    lexer.doctype_system.write_char('\u{FFFD}')
    return
  }
  if ch == 0x3E {
    lexer.force_quirks = true
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == -1 {
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  lexer.doctype_system.write_char(as_char(ch))
}

///|
fn doctype_system_single_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x27 {
    lexer.state = AfterDoctypeSystemIdentifier
    return
  }
  if ch == 0 {
    lexer.doctype_system.write_char('\u{FFFD}')
    return
  }
  if ch == 0x3E {
    lexer.force_quirks = true
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == -1 {
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  lexer.doctype_system.write_char(as_char(ch))
}

///|
fn after_doctype_system_identifier_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) {
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == -1 {
    lexer.force_quirks = true
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
  lexer.state = BogusDoctype
  lexer.reconsume()
}

///|
fn bogus_doctype_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x3E {
    lexer.state = Data
    emit_doctype(lexer)
    return
  }
  if ch == -1 {
    emit_doctype(lexer)
    emit_eof(lexer)
    return
  }
}

// -------------------------------------------------------------------- CDATA

///|
fn cdata_section_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == -1 {
    emit_eof(lexer)
    return
  }
  if ch == 0x5D {
    lexer.state = CdataSectionBracket
    return
  }
  emit_char(lexer, ch)
}

///|
fn cdata_section_bracket_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x5D {
    lexer.state = CdataSectionEnd
    return
  }
  emit_char(lexer, 0x5D)
  lexer.state = CdataSection
  lexer.reconsume()
}

///|
fn cdata_section_end_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x5D {
    emit_char(lexer, 0x5D)
    return
  }
  if ch == 0x3E {
    lexer.state = Data
    return
  }
  emit_char(lexer, 0x5D)
  emit_char(lexer, 0x5D)
  lexer.state = CdataSection
  lexer.reconsume()
}

// ----------------------------------------------------- character references

///|
fn character_reference_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_alnum(ch) {
    // The name is looked up whole, from where it starts.
    let start = lexer.at - lexer.width
    match longest_reference(lexer.text, start) {
      Some((value, end)) => {
        let name = lexer.text[start:end].to_owned()
        let ends_with_semicolon = name.has_suffix(";")
        let after = if end < lexer.text.length() {
          lexer.text.at(end).to_int()
        } else {
          -1
        }
        if lexer.ref_in_attribute &&
          !ends_with_semicolon &&
          (after == 0x3D || is_alnum(after)) {
          // A name without its semicolon that runs into a value is the text it
          // looks like, not a reference: `&not` in `&notit;` is four letters.
          lexer.attr_value.write_string("&" + name)
          lexer.at = end
          lexer.width = 1
        } else {
          put_text(lexer, value)
          lexer.at = end
          lexer.width = 1
        }
        lexer.state = lexer.ref_return
      }
      None => {
        put_char(lexer, 0x26)
        lexer.at = start
        lexer.width = 1
        lexer.state = lexer.ref_return
      }
    }
    return
  }
  if ch == 0x23 {
    lexer.reference = StringBuilder()
    lexer.state = NumericCharacterReference
    return
  }
  put_char(lexer, 0x26)
  lexer.state = lexer.ref_return
  lexer.reconsume()
}

///|
fn numeric_character_reference_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x78 || ch == 0x58 {
    lexer.reference.write_char(as_char(ch))
    lexer.state = HexadecimalCharacterReferenceStart
    return
  }
  lexer.state = DecimalCharacterReferenceStart
  lexer.reconsume()
}

///|
fn hex_start_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_hex(ch) {
    lexer.state = HexadecimalCharacterReference
    lexer.reconsume()
    return
  }
  // No digits: the text was never a reference.
  put_char(lexer, 0x26)
  put_char(lexer, 0x23)
  let spelling = lexer.reference.to_string()
  for unit in spelling {
    put_char(lexer, unit.to_int())
  }
  lexer.state = lexer.ref_return
  lexer.reconsume()
}

///|
fn hex_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_hex(ch) {
    lexer.reference.write_char(as_char(ch))
    return
  }
  if ch == 0x3B {
    lexer.state = NumericCharacterReferenceEnd
    return
  }
  lexer.state = NumericCharacterReferenceEnd
  lexer.reconsume()
}

///|
fn decimal_start_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_digit(ch) {
    lexer.state = DecimalCharacterReference
    lexer.reconsume()
    return
  }
  put_char(lexer, 0x26)
  put_char(lexer, 0x23)
  lexer.state = lexer.ref_return
  lexer.reconsume()
}

///|
fn decimal_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_digit(ch) {
    lexer.reference.write_char(as_char(ch))
    return
  }
  if ch == 0x3B {
    lexer.state = NumericCharacterReferenceEnd
    return
  }
  lexer.state = NumericCharacterReferenceEnd
  lexer.reconsume()
}

///|
/// The character a numeric reference stands for, with the repairs the standard
/// asks for: a reference to nothing is a replacement character, a reference
/// into C1 means what that byte meant on a page written in 1997.
fn numeric_end_state(lexer : Lexer, ch : Int32) -> Unit {
  ignore(ch)
  let spelling = lexer.reference.to_string()
  let hex = spelling.has_prefix("x") || spelling.has_prefix("X")
  let digits = if hex {
    spelling[1:spelling.length()].to_owned()
  } else {
    spelling
  }
  let parsed = Some(@string.parse_int(digits, base=if hex { 16 } else { 10 })) catch {
    _ => None
  }
  let value = match parsed {
    Some(found) => found
    None => 0
  }
  if value == 0 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF) {
    put_char(lexer, 0xFFFD)
    lexer.state = lexer.ref_return
    lexer.reconsume()
    return
  }
  put_char(lexer, remap_c1(value))
  lexer.state = lexer.ref_return
  lexer.reconsume()
}

///|
/// The standard's Windows-1252 repair: a reference in the C1 range means what
/// the byte meant on a page written in 1997, so `&#x80;` is a euro sign.
fn remap_c1(value : Int32) -> Int32 {
  match value {
    0x80 => 0x20AC
    0x82 => 0x201A
    0x83 => 0x0192
    0x84 => 0x201E
    0x85 => 0x2026
    0x86 => 0x2020
    0x87 => 0x2021
    0x88 => 0x02C6
    0x89 => 0x2030
    0x8A => 0x0160
    0x8B => 0x2039
    0x8C => 0x0152
    0x8E => 0x017D
    0x91 => 0x2018
    0x92 => 0x2019
    0x93 => 0x201C
    0x94 => 0x201D
    0x95 => 0x2022
    0x96 => 0x2013
    0x97 => 0x2014
    0x98 => 0x02DC
    0x99 => 0x2122
    0x9A => 0x0161
    0x9B => 0x203A
    0x9C => 0x0153
    0x9E => 0x017E
    0x9F => 0x0178
    _ => value
  }
}

// ------------------------------------------------- the raw text end tags

///|
/// Whether the end tag being read is the one that closes the raw text: the
/// standard's "appropriate end tag token", which is a name comparison.
fn appropriate_end_tag(lexer : Lexer) -> Bool {
  lexer.tag_name.to_string() == lexer.raw_name
}

///|
/// The `<` that may open an end tag in RCDATA text.
fn rcdata_less_than_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2F {
    lexer.tag_name = StringBuilder()
    lexer.state = RcdataEndTagOpen
    return
  }
  emit_char(lexer, 0x3C)
  lexer.state = Rcdata
  lexer.reconsume()
}

///|
fn rcdata_end_tag_open_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_alpha(ch) {
    new_tag(lexer, true)
    lexer.state = RcdataEndTagName
    lexer.reconsume()
    return
  }
  emit_char(lexer, 0x3C)
  emit_char(lexer, 0x2F)
  lexer.state = Rcdata
  lexer.reconsume()
}

///|
fn rcdata_end_tag_name_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) && appropriate_end_tag(lexer) {
    lexer.state = BeforeAttributeName
    return
  }
  if ch == 0x2F && appropriate_end_tag(lexer) {
    lexer.state = SelfClosingStartTag
    return
  }
  if ch == 0x3E && appropriate_end_tag(lexer) {
    lexer.state = Data
    emit_tag(lexer)
    return
  }
  if is_alpha(ch) {
    push_raw_tag_char(lexer, ch)
    return
  }
  // Not the end tag after all: everything read so far was text.
  emit_raw_tag_back(lexer)
  lexer.state = Rcdata
  lexer.reconsume()
}

///|
fn rawtext_less_than_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2F {
    lexer.tag_name = StringBuilder()
    lexer.state = RawtextEndTagOpen
    return
  }
  emit_char(lexer, 0x3C)
  lexer.state = Rawtext
  lexer.reconsume()
}

///|
fn rawtext_end_tag_open_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_alpha(ch) {
    new_tag(lexer, true)
    lexer.state = RawtextEndTagName
    lexer.reconsume()
    return
  }
  emit_char(lexer, 0x3C)
  emit_char(lexer, 0x2F)
  lexer.state = Rawtext
  lexer.reconsume()
}

///|
fn rawtext_end_tag_name_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) && appropriate_end_tag(lexer) {
    lexer.state = BeforeAttributeName
    return
  }
  if ch == 0x2F && appropriate_end_tag(lexer) {
    lexer.state = SelfClosingStartTag
    return
  }
  if ch == 0x3E && appropriate_end_tag(lexer) {
    lexer.state = Data
    emit_tag(lexer)
    return
  }
  if is_alpha(ch) {
    push_raw_tag_char(lexer, ch)
    return
  }
  emit_raw_tag_back(lexer)
  lexer.state = Rawtext
  lexer.reconsume()
}

///|
fn script_less_than_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2F {
    lexer.tag_name = StringBuilder()
    lexer.state = ScriptEndTagOpen
    return
  }
  if ch == 0x21 {
    emit_char(lexer, 0x3C)
    emit_char(lexer, 0x21)
    lexer.state = ScriptEscapeStart
    return
  }
  emit_char(lexer, 0x3C)
  lexer.state = ScriptData
  lexer.reconsume()
}

///|
fn script_end_tag_open_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_alpha(ch) {
    new_tag(lexer, true)
    lexer.state = ScriptEndTagName
    lexer.reconsume()
    return
  }
  emit_char(lexer, 0x3C)
  emit_char(lexer, 0x2F)
  lexer.state = ScriptData
  lexer.reconsume()
}

///|
fn script_end_tag_name_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) && appropriate_end_tag(lexer) {
    lexer.state = BeforeAttributeName
    return
  }
  if ch == 0x2F && appropriate_end_tag(lexer) {
    lexer.state = SelfClosingStartTag
    return
  }
  if ch == 0x3E && appropriate_end_tag(lexer) {
    lexer.state = Data
    emit_tag(lexer)
    return
  }
  if is_alpha(ch) {
    push_raw_tag_char(lexer, ch)
    return
  }
  emit_raw_tag_back(lexer)
  lexer.state = ScriptData
  lexer.reconsume()
}

///|
fn script_escape_start_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2D {
    emit_char(lexer, 0x2D)
    lexer.state = ScriptEscapeStartDash
    return
  }
  lexer.state = ScriptData
  lexer.reconsume()
}

///|
fn script_escape_start_dash_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2D {
    emit_char(lexer, 0x2D)
    lexer.state = ScriptEscapedDashDash
    return
  }
  lexer.state = ScriptData
  lexer.reconsume()
}

///|
fn script_escaped_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2D {
    emit_char(lexer, 0x2D)
    lexer.state = ScriptEscapedDash
    return
  }
  if ch == 0x3C {
    lexer.state = ScriptEscapedLessThan
    return
  }
  if ch == -1 {
    emit_eof(lexer)
    return
  }
  if ch == 0 {
    emit_char(lexer, 0xFFFD)
    return
  }
  emit_char(lexer, ch)
}

///|
fn script_escaped_dash_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2D {
    emit_char(lexer, 0x2D)
    lexer.state = ScriptEscapedDashDash
    return
  }
  if ch == 0x3C {
    lexer.state = ScriptEscapedLessThan
    return
  }
  if ch == -1 {
    emit_eof(lexer)
    return
  }
  if ch == 0 {
    emit_char(lexer, 0xFFFD)
    lexer.state = ScriptEscaped
    return
  }
  emit_char(lexer, ch)
  lexer.state = ScriptEscaped
}

///|
fn script_escaped_dash_dash_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2D {
    emit_char(lexer, 0x2D)
    return
  }
  if ch == 0x3C {
    lexer.state = ScriptEscapedLessThan
    return
  }
  if ch == 0x3E {
    emit_char(lexer, 0x3E)
    lexer.state = ScriptData
    return
  }
  if ch == -1 {
    emit_eof(lexer)
    return
  }
  if ch == 0 {
    emit_char(lexer, 0xFFFD)
    lexer.state = ScriptEscaped
    return
  }
  emit_char(lexer, ch)
  lexer.state = ScriptEscaped
}

///|
fn script_escaped_less_than_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2F {
    lexer.tag_name = StringBuilder()
    lexer.state = ScriptEscapedEndTagOpen
    return
  }
  if is_alpha(ch) {
    lexer.tag_name = StringBuilder()
    emit_char(lexer, 0x3C)
    lexer.state = ScriptDoubleEscapeStart
    lexer.reconsume()
    return
  }
  emit_char(lexer, 0x3C)
  lexer.state = ScriptEscaped
  lexer.reconsume()
}

///|
fn script_escaped_end_tag_open_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_alpha(ch) {
    new_tag(lexer, true)
    lexer.state = ScriptEscapedEndTagName
    lexer.reconsume()
    return
  }
  emit_char(lexer, 0x3C)
  emit_char(lexer, 0x2F)
  lexer.state = ScriptEscaped
  lexer.reconsume()
}

///|
fn script_escaped_end_tag_name_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) && appropriate_end_tag(lexer) {
    lexer.state = BeforeAttributeName
    return
  }
  if ch == 0x2F && appropriate_end_tag(lexer) {
    lexer.state = SelfClosingStartTag
    return
  }
  if ch == 0x3E && appropriate_end_tag(lexer) {
    lexer.state = Data
    emit_tag(lexer)
    return
  }
  if is_alpha(ch) {
    push_raw_tag_char(lexer, ch)
    return
  }
  emit_raw_tag_back(lexer)
  lexer.state = ScriptEscaped
  lexer.reconsume()
}

///|
fn script_double_escape_start_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) || ch == 0x2F || ch == 0x3E {
    let name = lexer.tag_name.to_string()
    let script = name == "script"
    emit_char(lexer, ch)
    lexer.state = if script { ScriptDoubleEscaped } else { ScriptEscaped }
    return
  }
  if is_alpha(ch) {
    lexer.tag_name.write_char(
      as_char(if ch >= 0x41 && ch <= 0x5A { ch + 0x20 } else { ch }),
    )
    emit_char(lexer, ch)
    return
  }
  lexer.state = ScriptEscaped
  lexer.reconsume()
}

///|
fn script_double_escaped_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2D {
    emit_char(lexer, 0x2D)
    lexer.state = ScriptDoubleEscapedDash
    return
  }
  if ch == 0x3C {
    emit_char(lexer, 0x3C)
    lexer.state = ScriptDoubleEscapedLessThan
    return
  }
  if ch == -1 {
    emit_eof(lexer)
    return
  }
  if ch == 0 {
    emit_char(lexer, 0xFFFD)
    return
  }
  emit_char(lexer, ch)
}

///|
fn script_double_escaped_dash_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2D {
    emit_char(lexer, 0x2D)
    lexer.state = ScriptDoubleEscapedDashDash
    return
  }
  if ch == 0x3C {
    emit_char(lexer, 0x3C)
    lexer.state = ScriptDoubleEscapedLessThan
    return
  }
  if ch == -1 {
    emit_eof(lexer)
    return
  }
  if ch == 0 {
    emit_char(lexer, 0xFFFD)
    lexer.state = ScriptDoubleEscaped
    return
  }
  emit_char(lexer, ch)
  lexer.state = ScriptDoubleEscaped
}

///|
fn script_double_escaped_dash_dash_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2D {
    emit_char(lexer, 0x2D)
    return
  }
  if ch == 0x3C {
    emit_char(lexer, 0x3C)
    lexer.state = ScriptDoubleEscapedLessThan
    return
  }
  if ch == 0x3E {
    emit_char(lexer, 0x3E)
    lexer.state = ScriptData
    return
  }
  if ch == -1 {
    emit_eof(lexer)
    return
  }
  if ch == 0 {
    emit_char(lexer, 0xFFFD)
    lexer.state = ScriptDoubleEscaped
    return
  }
  emit_char(lexer, ch)
  lexer.state = ScriptDoubleEscaped
}

///|
fn script_double_escaped_less_than_state(lexer : Lexer, ch : Int32) -> Unit {
  if ch == 0x2F {
    lexer.tag_name = StringBuilder()
    emit_char(lexer, 0x2F)
    lexer.state = ScriptDoubleEscapeEnd
    return
  }
  lexer.state = ScriptDoubleEscaped
  lexer.reconsume()
}

///|
fn script_double_escape_end_state(lexer : Lexer, ch : Int32) -> Unit {
  if is_white(ch) || ch == 0x2F || ch == 0x3E {
    let name = lexer.tag_name.to_string()
    let script = name == "script"
    emit_char(lexer, ch)
    lexer.state = if script { ScriptEscaped } else { ScriptDoubleEscaped }
    return
  }
  if is_alpha(ch) {
    lexer.tag_name.write_char(
      as_char(if ch >= 0x41 && ch <= 0x5A { ch + 0x20 } else { ch }),
    )
    emit_char(lexer, ch)
    return
  }
  lexer.state = ScriptDoubleEscaped
  lexer.reconsume()
}

///|
/// The name of a raw-text end tag as it is written: the tag name is folded to
/// lower case for the comparison with the element that opened the raw text, but
/// what goes back into the text is the spelling that was read.
fn push_raw_tag_char(lexer : Lexer, ch : Int32) -> Unit {
  lexer.raw_buf.write_char(as_char(ch))
  if ch >= 0x41 && ch <= 0x5A {
    lexer.tag_name.write_char(as_char(ch + 0x20))
  } else {
    lexer.tag_name.write_char(as_char(ch))
  }
}

///|
/// Everything read as a failed end tag, put back into the text.
fn emit_raw_tag_back(lexer : Lexer) -> Unit {
  emit_char(lexer, 0x3C)
  emit_char(lexer, 0x2F)
  for unit in lexer.raw_buf.to_string() {
    emit_char(lexer, unit.to_int())
  }
  lexer.tag_name = StringBuilder()
  lexer.raw_buf = StringBuilder()
}
