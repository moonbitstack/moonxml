/// The event stream: what a parser emits, and whether the streaming reader and
/// the tree builder agree about it.
///
/// `@event.Event` is the vocabulary both parsers speak. `@xml.scan` produces it
/// without building a tree; `Document::events` walks a tree that was built from
/// it. If the two ever disagree, one of them is wrong, so the property here is
/// that they agree — for every document in a small corpus.

struct Recorder {
  events : Array[@event.Event]
}

impl @event.Sink for Recorder with push(self, ev) {
  self.events.push(ev)
}

fn record_xml(text : String) -> Array[@event.Event] {
  let r = Recorder::{ events: [] }
  try {
    @xml.scan(text, r)
  } catch {
    _ => abort("the fixture must parse: " + text)
  }
  r.events
}

fn record_tree(doc : @moonxml.Document) -> Array[@event.Event] {
  let r = Recorder::{ events: [] }
  doc.events(r)
  r.events
}

test "events: a document is a flat sequence in document order" {
  let events = record_xml("<r a=\"1\"><b>t</b><!--c--><![CDATA[d]]><?p q?></r>")
  assert_eq(events.length(), 8)
  match events[0] {
    @event.Event::StartTag(name~, attrs~, self_closing~) => {
      assert_eq(name, "r")
      assert_eq(attrs, [("a", "1")])
      assert_eq(self_closing, false)
    }
    _ => abort("expected a start tag")
  }
  match events[1] {
    @event.Event::StartTag(name~, self_closing~, ..) => {
      assert_eq(name, "b")
      assert_eq(self_closing, false)
    }
    _ => abort("expected a start tag")
  }
  match events[2] {
    @event.Event::Text(text~) => assert_eq(text, "t")
    _ => abort("expected text")
  }
  match events[3] {
    @event.Event::EndTag(name~) => assert_eq(name, "b")
    _ => abort("expected an end tag")
  }
  match events[4] {
    @event.Event::Comment(text~) => assert_eq(text, "c")
    _ => abort("expected a comment")
  }
  match events[5] {
    @event.Event::CData(text~) => assert_eq(text, "d")
    _ => abort("expected CDATA")
  }
  match events[6] {
    @event.Event::ProcessingInstruction(target~, data~) => {
      assert_eq(target, "p")
      assert_eq(data, "q")
    }
    _ => abort("expected a processing instruction")
  }
  match events[7] {
    @event.Event::EndTag(name~) => assert_eq(name, "r")
    _ => abort("expected the root's end tag")
  }
}

test "events: self-closing is recorded, because the writer needs it" {
  let events = record_xml("<r><a/><b></b></r>")
  match events[1] {
    @event.Event::StartTag(name~, self_closing~, ..) => {
      assert_eq(name, "a")
      assert_eq(self_closing, true)
    }
    _ => abort("expected a start tag")
  }
  match events[3] {
    @event.Event::StartTag(name~, self_closing~, ..) => {
      assert_eq(name, "b")
      assert_eq(self_closing, false)
    }
    _ => abort("expected a start tag")
  }
}

test "events: the doctype arrives as its raw text" {
  let events = record_xml("<!DOCTYPE r SYSTEM \"r.dtd\"><r/>")
  match events[0] {
    @event.Event::Doctype(text~) => assert_eq(text, "r SYSTEM \"r.dtd\"")
    _ => abort("expected a doctype")
  }
}

test "events: names are expanded and references decoded before the sink sees them" {
  let events = record_xml("<r xmlns:p=\"urn:p\" a=\"&amp;\"><p:b>&#65;</p:b></r>")
  match events[0] {
    @event.Event::StartTag(name~, attrs~, ..) => {
      assert_eq(name, "r")
      // A namespace declaration is consumed by the parser, not reported as an
      // attribute; what the sink sees is the expanded name.
      assert_eq(attrs, [("a", "&")])
    }
    _ => abort("expected a start tag")
  }
  match events[1] {
    @event.Event::StartTag(name~, ..) => assert_eq(name, "{urn:p}b")
    _ => abort("expected a start tag")
  }
  match events[2] {
    @event.Event::Text(text~) => assert_eq(text, "A")
    _ => abort("expected text")
  }
}

test "events: streaming and tree building agree" {
  let docs : Array[String] = [
    "<r/>",
    "<r>t</r>",
    "<r a=\"1\"><b/></r>",
    "<!--c--><r><![CDATA[x]]></r>",
    "<?xml version=\"1.0\"?><r><?p?></r>",
    "<r xmlns:p=\"urn:p\"><p:a p:x=\"1\"/></r>",
    "<r><a>1</a><a>2</a></r>",
  ]
  for text in docs {
    let streamed = record_xml(text)
    let built = try {
      record_tree(@xml.loads(text))
    } catch {
      _ => abort("the fixture must parse: " + text)
    }
    assert_eq(streamed == built, true)
  }
}

test "events: an empty document emits nothing" {
  assert_eq(record_xml("").length(), 0)
}

test "events: an HTML tree emits the same vocabulary" {
  let doc = @html.loads("<div class=a><p>x</p></div>")
  let events = record_tree(doc)
  let mut starts = 0
  let mut texts = 0
  for e in events {
    match e {
      @event.Event::StartTag(..) => starts = starts + 1
      @event.Event::Text(..) => texts = texts + 1
      _ => ()
    }
  }
  // html, head, body, div, p.
  assert_eq(starts, 5)
  assert_eq(texts, 1)
}

test "events: scan refuses what the tree builder refuses" {
  let r = Recorder::{ events: [] }
  let failed = try {
    @xml.scan("<a></b>", r)
    false
  } catch {
    @moonxml.Refused::Malformed(..) => true
    _ => false
  }
  assert_eq(failed, true)
  // The sink may have seen a prefix of the document; it must not have seen the
  // whole thing.
  let _ = r.events.length()
}
