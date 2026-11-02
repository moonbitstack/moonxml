// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// `value`, or the marker for a value that is missing.
fn spell(value : String?) -> String {
  match value {
    Some(text) => "=" + text
    None => "~"
  }
}

///|
/// A token in the corpus's spelling. See `scripts/gen_html5lib_tokens.py`.
fn token_text(token : Token) -> String? {
  match token {
    Characters(text~) => Some("c" + text)
    EndTag(name~) => Some("e" + name)
    CommentToken(text~) => Some("m" + text)
    StartTag(name~, attrs~, self_closing~) => {
      let parts = ["s" + name]
      for pair in attrs {
        parts.push(pair.0 + "=" + pair.1)
      }
      if self_closing {
        parts.push("/")
      }
      Some(parts.join("\u{1F}"))
    }
    DoctypeToken(name~, public_id~, system_id~, force_quirks~) =>
      Some(
        [
          "d" + spell(name),
          spell(public_id),
          spell(system_id),
          if force_quirks {
            "0"
          } else {
            "1"
          },
        ].join("\u{1F}"),
      )
    Eof => None
  }
}

///|
/// The tokens of `source` from `state`, with no tree builder to feed.
fn tokens_of(source : String, state : TokState, last : String) -> Array[String] {
  let out : Array[String] = []
  let collect = (_ : Lexer, token) => {
    guard token_text(token) is Some(text) else { return }
    // The corpus writes adjacent characters as one token.
    if text.has_prefix("c") &&
      out.last() is Some(previous) &&
      previous.has_prefix("c") {
      out[out.length() - 1] = previous + text[1:].to_owned()
    } else {
      out.push(text)
    }
  }
  let builder = Builder::new(@moonxml.Document::new(flavour=@moonxml.Html))
  let lexer = Lexer::new(preprocess(source), builder, out=collect)
  lexer.state = state
  lexer.raw_name = last
  tokenize(lexer)
  out
}

///|
test "the tokenizer corpus: every case reproduces exactly" {
  let mut passed = 0
  let failed : Array[String] = []
  let cases = token_corpus()
  for entry in cases {
    let (file, about, state, last, source, expected) = entry
    if tokens_of(source, state, last) == expected {
      passed += 1
    } else if failed.length() < 40 {
      failed.push("\{file}: \{about}")
    }
  }
  let mut report = ""
  if passed < cases.length() {
    report = "\{passed} of \{cases.length()} reproduce; the rest:\n" +
      failed.join("\n")
  }
  assert_eq(report, "")
}
