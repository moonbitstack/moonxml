// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The tree builder: one consumer of the event stream, shared by whoever
/// emits events — the XML scanner, or a caller reading a log of them. The
/// open-element stack is the builder's state; after a document it is empty.
pub impl @event.Sink for Document with fn push(self, event) {
  let parent = match self.nesting.last() {
    Some(top) => top
    None => self.root
  }
  match event {
    StartTag(name~, attrs~, self_closing~) => {
      let element = Element::new(name, attrs=attrs.copy(), closed=self_closing)
      parent.append(ElementNode(element))
      if !self_closing {
        self.nesting.push(element)
      }
    }
    EndTag(name~) =>
      // The scanner checks pairing; a stray close is still not a reason to
      // lose the rest of the document.
      match self.nesting.last() {
        Some(top) => if top.name == name { ignore(self.nesting.pop()) }
        None => ()
      }
    Text(text~) => if !text.is_empty() { parent.append(TextNode(text)) }
    CData(text~) => parent.append(CDataNode(text))
    Comment(text~) => parent.append(CommentNode(text))
    ProcessingInstruction(target~, data~) =>
      parent.append(ProcessingInstructionNode({ target, data, }))
    Doctype(text~) => self.root.append(DoctypeNode(text))
  }
}

///|
pub extend Document with @event.Sink::{push}

///|
/// Read a finished tree back as the event stream it would have produced.
pub fn Document::events(self : Document) -> Array[@event.Event] {
  let out : Array[@event.Event] = []
  fn walk(node : Node) -> Unit {
    match node {
      ElementNode(data) => {
        out.push(
          @event.StartTag(
            name=data.name,
            attrs=data.attrs.copy(),
            self_closing=data.children.is_empty() && data.closed,
          ),
        )
        for child in data.children {
          walk(child)
        }
        out.push(@event.EndTag(name=data.name))
      }
      TextNode(text) => out.push(@event.Text(text~))
      CDataNode(text) => out.push(@event.CData(text~))
      CommentNode(text) => out.push(@event.Comment(text~))
      ProcessingInstructionNode(pi) =>
        out.push(@event.ProcessingInstruction(target=pi.target, data=pi.data))
      DoctypeNode(text) => out.push(@event.Doctype(text~))
    }
  }
  for child in self.root.children {
    walk(child)
  }
  out
}
