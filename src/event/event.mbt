// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One event of a document being read: a tag opening, a run of text, a
/// comment. libexpat's second reading of a document, in one type.
///
/// `@xml.scan` streams these; `Document::events` reads a finished tree back
/// as the same stream. HTML has no streaming read — WHATWG's tree
/// construction needs to see the tree it is building — so its events describe
/// a tree that already exists.
pub(all) enum Event {
  StartTag(
    name~ : String,
    attrs~ : Array[(String, String)],
    self_closing~ : Bool
  )
  EndTag(name~ : String)
  TextRun(text~ : String)
  CDataRun(text~ : String)
  CommentEvent(text~ : String)
  ProcessingInstruction(target~ : String, data~ : String)
  DoctypeEvent(text~ : String)
}

///|
/// Where events go. The tree builder is one implementation; a caller counting
/// tags or writing rows to a database is another, and it never builds a tree.
pub(open) trait Sink {
  fn push(Self, event : Event) -> Unit
}
