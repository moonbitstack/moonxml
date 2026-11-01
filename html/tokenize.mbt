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
  /// A doctype keeps its three parts and its force-quirks flag: the tree
  /// builder flattens it, but the tokenizer must not lose the difference
  /// between a null identifier and an empty one.
  Doctype(String?, String?, String?, Bool)
  Eof
}

fn is_ascii_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
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
