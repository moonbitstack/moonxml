/// Runs the vendored html5lib tokenizer corpus and reports a pass rate.
///
/// Each case is one string fed to the tokenizer from a given content model, and
/// the expected answer is the exact token list. Tokens are compared as strings
/// in the encoding `scripts/gen_tokenizer_tests.py` documents, so a failure
/// prints the first token that differs rather than a nested structure.
///
/// The floor is a ratchet: raise it as the tokenizer improves, never lower it.

/// Upper-case hexadecimal, matching the generator's `\u{%X}` escapes.
fn tok_hex(o : Int) -> String {
  let digits = "0123456789ABCDEF"
  let da = digits.to_array()
  if o == 0 {
    return "0"
  }
  let out : Array[Char] = []
  let mut v = o
  while v > 0 {
    out.push(da[v % 16])
    v = v / 16
  }
  let sb = StringBuilder()
  let mut i = out.length() - 1
  while i >= 0 {
    sb.write_char(out[i])
    i = i - 1
  }
  sb.to_string()
}

fn tok_esc(s : String) -> String {
  let sb = StringBuilder()
  for c in s {
    let o = Char::to_int(c)
    if c == '\\' {
      sb.write_string("\\\\")
    } else if c == '\n' {
      sb.write_string("\\n")
    } else if c == '\r' {
      sb.write_string("\\r")
    } else if c == '\t' {
      sb.write_string("\\t")
    } else if o < 0x20 || o == 0x1F {
      sb.write_string("\\u{" + tok_hex(o) + "}")
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

fn tok_opt(v : String?) -> String {
  match v {
    None => "~"
    Some(x) => "=" + tok_esc(x)
  }
}

fn dump_token(t : @html.Token) -> String {
  match t {
    @html.TokenChars(s) => "c" + tok_esc(s)
    @html.TokenEnd(n) => "e" + tok_esc(n)
    @html.TokenComment(s) => "m" + tok_esc(s)
    @html.TokenStart(name~, attrs~, self_closing~) => {
      let parts : Array[String] = ["s" + tok_esc(name)]
      for pair in attrs {
        let (k, v) = pair
        parts.push(tok_esc(k) + "=" + tok_esc(v))
      }
      if self_closing {
        parts.push("/")
      }
      tok_join(parts)
    }
    @html.TokenDoctype(name~, public_id~, system_id~, force_quirks~) => {
      let q = if force_quirks { "1" } else { "0" }
      tok_join(["d" + tok_opt_char(name), tok_opt_char(public_id), tok_opt_char(system_id), q])
    }
  }
}

/// Field separator, matching the generator (U+001F).
fn tok_join(parts : Array[String]) -> String {
  let sb = StringBuilder()
  let mut first = true
  for p in parts {
    if first {
      first = false
    } else {
      sb.write_char('\u{1F}')
    }
    sb.write_string(p)
  }
  sb.to_string()
}

fn tok_opt_char(v : String?) -> String {
  tok_opt(v)
}

fn tok_dump_case(c : TokCase) -> Array[String] {
  let toks = @html.tokenize(c.input, state=c.state, last_start_tag=c.last)
  let out : Array[String] = []
  // The corpus coalesces adjacent character tokens into one.
  for t in toks {
    match t {
      @html.TokenChars(s) => {
        let n = out.length()
        if n > 0 && out[n - 1].has_prefix("c") {
          out[n - 1] = out[n - 1] + tok_esc(s)
        } else {
          out.push("c" + tok_esc(s))
        }
      }
      _ => out.push(dump_token(t))
    }
  }
  out
}

fn tok_same(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut i = 0
  while i < a.length() {
    if a[i] != b[i] {
      return false
    }
    i = i + 1
  }
  true
}

test "html5lib tokenizer conformance" {
  let cases = tok_cases()
  let mut pass = 0
  let mut shown = 0
  let fnames : Array[String] = []
  let fpass : Array[Int] = []
  let ftotal : Array[Int] = []
  for c in cases {
    let fi = file_slot(fnames, fpass, ftotal, c.file)
    ftotal[fi] = ftotal[fi] + 1
    let got = tok_dump_case(c)
    if tok_same(got, c.expected) {
      pass = pass + 1
      fpass[fi] = fpass[fi] + 1
    } else if shown < 8 {
      shown = shown + 1
      println("TFAIL " + c.file + " [" + c.state + "] in=" + tok_esc(c.input))
      println("  exp: " + tok_join(c.expected))
      println("  got: " + tok_join(got))
    }
  }
  println("html5lib tokenizer: " + pass.to_string() + "/" + cases.length().to_string())
  let mut f = 0
  while f < fnames.length() {
    println("  " + fnames[f] + " " + fpass[f].to_string() + "/" + ftotal[f].to_string())
    f = f + 1
  }
  // Ratchet: raise this as the tokenizer improves, never lower it.
  assert_eq(pass >= 6584, true)
}
