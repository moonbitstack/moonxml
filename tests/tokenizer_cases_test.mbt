/// The tokenizer as a user-facing API.
///
/// The corpus runner proves conformance; these tests pin the shape of the
/// answer a caller actually gets, which the corpus format cannot show.

test "tokenize: the stream in source order" {
  let toks = @html.tokenize("<p class=x>a&amp;b</p>")
  assert_eq(toks.length(), 3)
  match toks[0] {
    @html.TokenStart(name~, attrs~, self_closing~) => {
      assert_eq(name, "p")
      assert_eq(attrs.length(), 1)
      assert_eq(attrs[0], ("class", "x"))
      assert_eq(self_closing, false)
    }
    _ => fail("expected a start tag")
  }
  match toks[1] {
    @html.TokenChars(s) => assert_eq(s, "a&b")
    _ => fail("expected character data")
  }
  match toks[2] {
    @html.TokenEnd(n) => assert_eq(n, "p")
    _ => fail("expected an end tag")
  }
}

test "tokenize: a doctype keeps its parts and its force-quirks flag" {
  let toks = @html.tokenize("<!DOCTYPE html PUBLIC \"a\" \"b\">")
  match toks[0] {
    @html.TokenDoctype(name~, public_id~, system_id~, force_quirks~) => {
      assert_eq(name, Some("html"))
      assert_eq(public_id, Some("a"))
      assert_eq(system_id, Some("b"))
      assert_eq(force_quirks, false)
    }
    _ => fail("expected a doctype")
  }
  let bad = @html.tokenize("<!DOCTYPE htm>")
  match bad[0] {
    @html.TokenDoctype(name~, force_quirks~, ..) => {
      assert_eq(name, Some("htm"))
      assert_eq(force_quirks, false)
    }
    _ => fail("expected a doctype")
  }
}

test "tokenize: raw text states do not decode entities" {
  let rc = @html.tokenize("a&amp;b</t>", state="rcdata", last_start_tag="t")
  match rc[0] {
    @html.TokenChars(s) => assert_eq(s, "a&b")
    _ => fail("expected character data")
  }
  let raw = @html.tokenize("a&amp;b</t>", state="rawtext", last_start_tag="t")
  match raw[0] {
    @html.TokenChars(s) => assert_eq(s, "a&amp;b")
    _ => fail("expected character data")
  }
  match raw[1] {
    @html.TokenEnd(n) => assert_eq(n, "t")
    _ => fail("expected the end tag")
  }
}

test "tokenize: CDATA is text and keeps its NUL" {
  let toks = @html.tokenize("a\u{0}b]]>c", state="cdata")
  match toks[0] {
    @html.TokenChars(s) => assert_eq(s, "a\u{0}b")
    _ => fail("expected character data")
  }
  match toks[1] {
    @html.TokenChars(s) => assert_eq(s, "c")
    _ => fail("expected the text after the section")
  }
}

test "tokenize: attributes keep source order and drop duplicates" {
  // A solidus inside an unquoted value belongs to the value, so the space
  // before it is what makes this a self-closing tag.
  let toks = @html.tokenize("<i b=1 a=2 b=3 />")
  match toks[0] {
    @html.TokenStart(name~, attrs~, self_closing~) => {
      assert_eq(name, "i")
      assert_eq(attrs.length(), 2)
      assert_eq(attrs[0], ("b", "1"))
      assert_eq(attrs[1], ("a", "2"))
      assert_eq(self_closing, true)
    }
    _ => fail("expected a start tag")
  }
}
