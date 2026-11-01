/// The tokenizer, exposed.
///
/// The tree builder consumes the same stream, but a caller sometimes wants to
/// see what the tokenizer made of a string: for debugging, for a conformance
/// harness, or for building a tree in another shape. This is that view, and it
/// is deliberately the *tokenizer's* answer rather than the tree builder's:
/// character data keeps its NUL, entities are decoded, and a doctype still has
/// its three parts and its force-quirks flag.

/// One token.
pub(all) enum Token {
  /// Character data, with character references already decoded.
  TokenChars(String)
  /// A start tag: lowercased name, attributes in source order, self-closing
  /// flag as written.
  TokenStart(name~ : String, attrs~ : Array[(String, String)], self_closing~ : Bool)
  /// An end tag, lowercased.
  TokenEnd(String)
  /// A comment, without its delimiters.
  TokenComment(String)
  /// A doctype. `None` marks the null identifiers the specification allows.
  TokenDoctype(
    name~ : String?,
    public_id~ : String?,
    system_id~ : String?,
    force_quirks~ : Bool
  )
}

/// Tokenize `text` from the given content model.
///
/// `state` is one of `"data"`, `"rcdata"`, `"rawtext"`, `"script"`,
/// `"plaintext"` or `"cdata"`; `last_start_tag` is the tag name that decides
/// which end tag closes a raw-text run, as the specification's "appropriate end
/// tag token" definition needs.
pub fn tokenize(
  text : String,
  state? : String = "data",
  last_start_tag? : String = ""
) -> Array[Token] {
  let h = H::new(preprocess_impl(text, false))
  h.raw_tag = last_start_tag.to_lower()
  h.tstate = match state {
    "rcdata" => StRcdata
    "rawtext" => StRawtext
    "script" => StScriptData
    "plaintext" => StPlaintext
    "cdata" => StCdataSection
    _ => StData
  }
  let out : Array[Token] = []
  let mut done = false
  while not(done) {
    match h.next_token() {
      Chars(s) => out.push(TokenChars(s))
      Start(name, attrs, sc) => out.push(TokenStart(name~, attrs~, self_closing=sc))
      End(name) => out.push(TokenEnd(name))
      Comment(s) => out.push(TokenComment(s))
      Doctype(name, pub_id, sys_id, q) =>
        out.push(TokenDoctype(name~, public_id=pub_id, system_id=sys_id, force_quirks=q))
      Eof => done = true
    }
  }
  out
}
