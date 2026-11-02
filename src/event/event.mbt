// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One event of a document being read: a tag opening, a run of text, a
/// comment. libexpat's second reading of a document, in one type.
///
/// `@xml.scan` and `@html.scan` stream these; `Document::events` reads a
/// finished tree back as the same stream. HTML's stream is its tokenizer's:
/// the tree construction that follows needs to see the tree it is building, so
/// a document's events describe a tree that already exists.
pub(all) enum Event {
  StartTag(
    name~ : String,
    attrs~ : Array[(String, String)],
    self_closing~ : Bool
  )
  EndTag(name~ : String)
  Text(text~ : String)
  CData(text~ : String)
  Comment(text~ : String)
  ProcessingInstruction(target~ : String, data~ : String)
  Doctype(text~ : String)
}

///|
/// Where events go. The tree builder is one implementation; a caller counting
/// tags or writing rows to a database is another, and it never builds a tree.
pub(open) trait Sink {
  fn push(Self, event : Event) -> Unit
}
