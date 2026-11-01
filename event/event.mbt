/// The vocabulary the two parsers speak and the contract a caller's own sink
/// implements. This package depends on nothing: there is no tree here, only the
/// events a parser emits.
///
/// A parser is an event producer. `moonxml/xml` streams these events directly
/// (`@xml.scan`), and both parsers build the tree by feeding them to exactly one
/// builder, so tolerance cannot drift between two implementations.

/// One step in a document's event stream.
pub(all) enum Event {
  /// A start tag. `attrs` keeps document order and already has entities and
  /// namespaces resolved; `self_closing` records `<a/>` versus `<a>`.
  StartTag(name~ : String, attrs~ : Array[(String, String)], self_closing~ : Bool)
  /// An end tag for `name`.
  EndTag(name~ : String)
  /// A run of character data, with references decoded.
  Text(text~ : String)
  /// A CDATA section's content, kept distinct so it round-trips.
  CData(text~ : String)
  /// A comment's text, without the `<!--` and `-->`.
  Comment(text~ : String)
  /// A processing instruction: its target and the raw data between them.
  ProcessingInstruction(target~ : String, data~ : String)
  /// A doctype declaration, raw, minus `<!DOCTYPE` and `>`.
  Doctype(text~ : String)
} derive(Eq, Debug)

/// A consumer of events. A caller implementing this is one `match` away from
/// counting tags, filtering rows, or writing to a database without ever
/// materialising a tree.
pub(open) trait Sink {
  /// Receive one event. Events arrive in document order.
  push(Self, event : Event) -> Unit
}
