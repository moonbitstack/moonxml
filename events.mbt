/// Reading a finished tree back as an event stream.
///
/// This is the second way to read a document: `@xml.scan` produces events from
/// text, and `Document::events` produces them from a tree. A caller counting
/// tags or streaming rows can implement `@event.Sink` once and use either.

/// Walk the document, pushing its events to `sink` in document order.
pub fn Document::events(self : Document, sink : &@event.Sink) -> Unit {
  for c in self.root.children {
    push_node_events(c, sink)
  }
}

fn push_node_events(node : Node, sink : &@event.Sink) -> Unit {
  match node {
    ElementNode(e) => {
      sink.push(@event.Event::StartTag(name=e.name, attrs=e.attrs, self_closing=e.closed))
      for c in e.children {
        push_node_events(c, sink)
      }
      sink.push(@event.Event::EndTag(name=e.name))
    }
    TextNode(s) => sink.push(@event.Event::Text(text=s))
    CDataNode(s) => sink.push(@event.Event::CData(text=s))
    CommentNode(s) => sink.push(@event.Event::Comment(text=s))
    ProcessingInstructionNode(pi) => sink.push(@event.Event::ProcessingInstruction(target=pi.target, data=pi.data))
    DoctypeNode(s) => sink.push(@event.Event::Doctype(text=s))
    _ => ()
  }
}
