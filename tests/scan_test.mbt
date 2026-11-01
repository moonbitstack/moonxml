struct EventLog {
  events : Array[@event.Event]
}

impl @event.Sink for EventLog with push(self, ev) {
  self.events.push(ev)
}

test "scan streams resolved names and decoded text" {
  let log = EventLog::{ events: [] }
  @xml.scan("<?xml version=\"1.0\"?><r xmlns=\"u\" a=\"1\"><c>&amp;x</c><d/></r>", log)
  let names : Array[String] = []
  let mut d_self_closing = false
  let mut text_ok = false
  for e in log.events {
    match e {
      @event.Event::StartTag(name=n, attrs=_, self_closing=sc) => {
        names.push(n)
        if n == "{u}d" && sc { d_self_closing = true }
      }
      @event.Event::Text(text=t) => if t == "&x" { text_ok = true }
      _ => ()
    }
  }
  assert_eq(names, ["{u}r", "{u}c", "{u}d"])
  assert_eq(d_self_closing, true)
  assert_eq(text_ok, true)
}

test "scan sees comments cdata and doctype" {
  let log = EventLog::{ events: [] }
  @xml.scan("<!DOCTYPE r><r><![CDATA[a<b]]><!--hi--></r>", log)
  let mut cdata = false
  let mut comment = false
  let mut doctype = false
  for e in log.events {
    match e {
      @event.Event::CData(text=t) => if t == "a<b" { cdata = true }
      @event.Event::Comment(text=t) => if t == "hi" { comment = true }
      @event.Event::Doctype(_) => doctype = true
      _ => ()
    }
  }
  assert_eq(cdata, true)
  assert_eq(comment, true)
  assert_eq(doctype, true)
}
