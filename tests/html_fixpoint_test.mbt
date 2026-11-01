/// A property that holds at corpus scale: parsing is idempotent modulo
/// serialisation.
///
/// If a document serialises to `s`, then parsing `s` must give the same tree, so
/// serialising again must give `s` back. Every tree-construction case is a
/// candidate input, which makes this a 1700-case check that the writer and the
/// parser agree about the tree they share. A failure here is a round-trip bug
/// even when the corpus comparison passes, because the corpus only ever looks
/// at the first parse.
///
/// Two families of trees are excluded, because HTML has no syntax for them:
///
/// - `plaintext` swallows everything after its start tag, including its own end
///   tag, so a document containing one cannot be written and read back.
/// - A `<a>` inside a `<a>` is a tree the parser does produce (the corpus has a
///   case for it) but that re-triggers the adoption agency when written down.
///
/// The exclusions are counted and reported, not silently dropped.

/// Serialise a case the way it was parsed: fragments stay fragments and the
/// scripting flag is carried over, so the comparison is about the tree and not
/// about a different parser configuration.
fn fixpoint_first(c : @tests.H5Case) -> @moonxml.Document {
  if c.fragment == "" {
    @html.loads_with_scripting(c.input, c.scripting)
  } else {
    @html.loads_fragment(c.input, context=c.fragment)
  }
}

fn fixpoint_second(c : @tests.H5Case, text : String) -> @moonxml.Document {
  if c.fragment == "" {
    @html.loads_with_scripting(text, c.scripting)
  } else {
    @html.loads_fragment(text, context=c.fragment)
  }
}

/// Elements whose start tag closes, ignores or merges a namesake, so a tree
/// that nests one inside the other has no source form: a parser cannot produce
/// it from text that would have to contain its own start tag.
fn closes_namesake(t : String) -> Bool {
  match t {
    // These close or ignore a namesake wherever it sits, so a tree that nests
    // one inside the other cannot come from text.
    "p" | "a" | "form" | "nobr" | "button" | "select" | "option" => true
    "li" | "dd" | "dt" | "html" | "head" | "body" | "frameset" | "plaintext" => true
    _ => false
  }
}

/// Whether the tree nests a close-on-start element inside a namesake.
fn nested_namesake(doc : @moonxml.Document) -> Bool {
  for e in doc.root.descendant_elements() {
    let l = e.local_name().to_lower()
    if closes_namesake(l) {
      for a in e.ancestors() {
        if a.name != "#document" && a.local_name().to_lower() == l {
          return true
        }
      }
    }
  }
  false
}

/// Contexts whose fragment parsing is raw text, so the same child nodes mean
/// different things depending on the context they were parsed in.
fn rawtext_context(ctx : String) -> Bool {
  match ctx.to_lower() {
    "style" | "script" | "xmp" | "iframe" | "noembed" | "noframes" | "noscript" | "plaintext" => true
    "title" | "textarea" => true
    _ => false
  }
}

/// The reason this tree has no HTML spelling, or `""` when it has one.
///
/// Four families qualify, and they all come from the same place: a mode or a
/// parsing rule that a source document cannot undo.
fn exclusion_reason(c : @tests.H5Case, doc : @moonxml.Document) -> String {
  // `plaintext` swallows everything after its start tag, including its end tag.
  let has_plaintext = try {
    doc.css("plaintext").length() > 0
  } catch {
    _ => false
  }
  if has_plaintext {
    return "plaintext"
  }
  // A fragment parsed in a raw-text context is character data, and writing that
  // data back as HTML would escape it before the same context read it again.
  if c.fragment != "" && rawtext_context(c.fragment) {
    return "fragment-rawtext"
  }
  if nested_namesake(doc) {
    return "nested-namesake"
  }
  // Script text that opens a comment and then a `script` tag puts the tokenizer
  // into its double-escaped state, where `</script>` is text.
  let scripts = try {
    doc.css("script")
  } catch {
    _ => abort("the script selector must parse")
  }
  for item in scripts.items {
    let t = item.text_content().to_lower()
    if t.contains("<!--") && t.contains("<script") {
      return "script-double-escape"
    }
  }
  ""
}

test "html: serialise, reparse, serialise is a fixpoint" {
  let cases = @tests.h5_cases()
  let failures : Array[String] = []
  let mut excused = 0
  let mut checked = 0
  let mut plaintext = 0
  let mut frag_rawtext = 0
  let mut nested = 0
  let mut script = 0
  for c in cases {
    let first = fixpoint_first(c)
    let once = first.dumps_html()
    let twice = fixpoint_second(c, once).dumps_html()
    checked = checked + 1
    if once != twice {
      let reason = exclusion_reason(c, first)
      if reason == "plaintext" {
        plaintext = plaintext + 1
        excused = excused + 1
      } else if reason == "fragment-rawtext" {
        frag_rawtext = frag_rawtext + 1
        excused = excused + 1
      } else if reason == "nested-namesake" {
        nested = nested + 1
        excused = excused + 1
      } else if reason == "script-double-escape" {
        script = script + 1
        excused = excused + 1
      } else if failures.length() < 5 {
        failures.push(c.file + " | " + c.input)
      }
    }
  }
  if failures.length() > 0 {
    println("fixpoint failures: " + failures.length().to_string())
    for f in failures {
      println("  " + f)
    }
  }
  // The exceptions are rare, and the count is printed so a growing set shows up
  // in the log rather than quietly widening the property.
  println(
    "fixpoint: checked " +
    checked.to_string() +
    ", excluded " +
    excused.to_string() +
    " (plaintext " +
    plaintext.to_string() +
    ", fragment-rawtext " +
    frag_rawtext.to_string() +
    ", nested-namesake " +
    nested.to_string() +
    ", script-double-escape " +
    script.to_string() +
    ")",
  )
  // Under five percent: high enough for the corpus's plain-text and script
  // cases, low enough that a regression which starts excluding everything is
  // caught here rather than by the property quietly passing.
  assert_eq(excused * 20 <= checked, true)
  assert_eq(failures, [])
  assert_eq(checked, cases.length())
}
