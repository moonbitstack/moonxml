// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why a document could not be read, or a query could not be run. One family
/// for the whole library, so there is one thing to catch.
pub(all) suberror Refused {
  /// The input is not well-formed where it must be: `at` is the offset in the
  /// input, counted in UTF-16 code units as `String::length` counts them.
  Malformed(at~ : Int32, why~ : String)
  /// A selector or XPath expression does not parse; `at` is the offset in the
  /// query itself.
  BadQuery(at~ : Int32, why~ : String)
  /// `selector(name, ..)` was called with a name nobody registered.
  UnknownSelector(name~ : String)
  /// A named gap rather than a syntax error: an XPath variable with no
  /// binding, and the like.
  Unsupported(what~ : String)
  /// The input went past a configured bound: `got` against `limit`, noticed at
  /// offset `at`.
  Exceeded(at~ : Int32, limit~ : Int32, got~ : Int32)
} derive(Eq, Debug)

///|
pub extend Refused with Eq::{equal, not_equal}

///|
pub extend Refused with Debug::{to_repr}

///|
pub impl Show for Refused with fn output(self, logger) {
  logger.write_string(
    match self {
      Malformed(at~, why~) => "malformed at \{at}: \{why}"
      BadQuery(at~, why~) => "bad query at \{at}: \{why}"
      UnknownSelector(name~) => "no selector registered as \{name}"
      Unsupported(what~) => "unsupported: \{what}"
      Exceeded(at~, limit~, got~) =>
        "\{got} exceeds the limit of \{limit} at \{at}"
    },
  )
}

///|
pub extend Refused with Show::{output, to_string}

///|
/// What the HTML parser repaired. WHATWG says repairs happen silently; this
/// tally makes them answerable afterwards, for a caller who wants to ask.
pub(all) struct Repairs {
  mut implied : Int32
  mut dropped : Int32
  mut reparented : Int32
  mut closed_at_eof : Int32
}

///|
/// A tally with nothing in it.
pub fn Repairs::new() -> Repairs {
  { implied: 0, dropped: 0, reparented: 0, closed_at_eof: 0, }
}

///|
/// Every repair the parser made, added up.
pub fn Repairs::total(self : Repairs) -> Int32 {
  self.implied + self.dropped + self.reparented + self.closed_at_eof
}

///|
/// Whether the parser repaired anything at all.
pub fn Repairs::any(self : Repairs) -> Bool {
  self.total() > 0
}
