test "xml byte roundtrip" {
  let text = "<root a=\"1\" b=\"2\"><!--c--><![CDATA[x<y]]><?pi d?><child/></root>"
  let doc = @xml.loads(text)
  assert_eq(doc.dumps(), text)
}

test "xml declaration roundtrip" {
  let text = "<?xml version=\"1.0\"?><root/>"
  let doc = @xml.loads(text)
  assert_eq(doc.dumps(), text)
}

test "html dumps void and escaping" {
  let doc = @html.loads("<div><br><p>a &amp; b</p></div>")
  let h = doc.dumps_html()
  assert_eq(h.contains("<br>"), true)
  assert_eq(h.contains("a &amp; b"), true)
}

struct Collector {
  events : Array[@event.Event]
}

impl @event.Sink for Collector with push(self, ev) {
  self.events.push(ev)
}

test "document events" {
  let doc = @xml.loads("<r><a>1</a></r>")
  let c = Collector::{ events: [] }
  doc.events(c)
  let mut starts = 0
  for e in c.events {
    match e {
      @event.Event::StartTag(name=_, attrs=_, self_closing=_) => starts = starts + 1
      _ => ()
    }
  }
  assert_eq(starts, 2)
}

test "xml scan" {
  let c = Collector::{ events: [] }
  @xml.scan("<r><a/>text</r>", c)
  assert_eq(c.events.length() > 0, true)
}
