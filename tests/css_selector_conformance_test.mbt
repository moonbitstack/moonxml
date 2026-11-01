/// Runs the vendored W3C CSS3 selectors suite and reports a pass rate.
///
/// Each case is a rule from the suite's `<style>` element, together with the ids
/// its script asserts must and must not be painted lime. The document is the
/// test file itself, parsed as HTML (the files are XHTML served as text/html).
///
/// The floor is a ratchet: raise it as the engine improves, never lower it.
/// Selectors the engine refuses (a pseudo-class it does not implement, a
/// namespace prefix) count as failures and are reported as `unsupported`, which
/// keeps them visible instead of being skipped.
///
/// The suite has 292 files; the generator keeps the 99 that carry a
/// machine-readable assertion for a rule that paints lime, which gives 116
/// cases. The sixteen that are refused are all `prefix|name` selectors: the
/// suite declares `@namespace` rules and this engine keeps no prefix map. The
/// rest of the corpus is skipped for reasons the generator counts — pointer and
/// timer tests, selectors that depend on `:hover`, files whose only assertion is
/// a human looking at the rendering.

fn css_case_ids(s : String) -> Array[String] {
  let out : Array[String] = []
  if s == "" {
    return out
  }
  let sb = StringBuilder()
  for c in s {
    if c == ',' {
      out.push(sb.to_string())
      sb.reset()
    } else {
      sb.write_char(c)
    }
  }
  if sb.to_string().length() > 0 {
    out.push(sb.to_string())
  }
  out
}

fn css_matched_ids(sel : @moonxml.Selection) -> Array[String] {
  let out : Array[String] = []
  for item in sel.items {
    match item {
      @moonxml.ElementNode(e) => match e.attr("id") {
        Some(id) => out.push(id)
        None => ()
      }
      _ => ()
    }
  }
  out
}

test "w3c css selectors conformance" {
  let docs = css_selector_docs()
  let cases = css_selector_cases()
  // The suite's files are XHTML and many cases are namespace-sensitive, so the
  // document is read as XML where it is well-formed; a file that uses an
  // undefined entity falls back to the HTML parser, which is how a browser
  // serves it.
  let parsed : Array[(@moonxml.Document, String)] = []
  for pair in docs {
    let (name, text) = pair
    let doc = try {
      @xml.loads(text)
    } catch {
      _ => @html.loads(text)
    }
    parsed.push((doc, name))
  }
  let mut pass = 0
  let mut unsupported = 0
  let mut wrong = 0
  let mut shown = 0
  for c in cases {
    let mut doc = @xml.loads("<r/>") catch {
      _ => abort("the empty document must parse")
    }
    for p in parsed {
      let (d, name) = p
      if name == c.file {
        doc = d
      }
    }
    let sel = try {
      doc.css(c.selector)
    } catch {
      @moonxml.Refused::Unsupported(..) => {
        unsupported = unsupported + 1
        if shown < 5 {
          shown = shown + 1
          println("FAIL " + c.file + " selector=" + c.selector)
          println("  unsupported")
        }
        continue
      }
      @moonxml.Refused::BadQuery(..) => {
        unsupported = unsupported + 1
        if shown < 5 {
          shown = shown + 1
          println("FAIL " + c.file + " selector=" + c.selector)
          println("  bad query")
        }
        continue
      }
      _ => {
        unsupported = unsupported + 1
        continue
      }
    }
    let matched = css_matched_ids(sel)
    let mut ok = true
    for id in css_case_ids(c.expect) {
      if !matched.contains(id) {
        ok = false
      }
    }
    for id in css_case_ids(c.reject) {
      if matched.contains(id) {
        ok = false
      }
    }
    if ok {
      pass = pass + 1
    } else {
      wrong = wrong + 1
      if shown < 5 {
        shown = shown + 1
        println("FAIL " + c.file + " selector=" + c.selector)
        println("  want " + c.expect + " and not " + c.reject)
        println("  got  " + matched.join(","))
      }
    }
  }
  println(
    "w3c css selectors: " +
    pass.to_string() +
    "/" +
    cases.length().to_string() +
    " (unsupported " +
    unsupported.to_string() +
    ", wrong " +
    wrong.to_string() +
    ")",
  )
  assert_eq(pass >= 70, true)
}
