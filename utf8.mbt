// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// UTF-8, the one encoding, over core's codec — wrapped so its failure
/// arrives as this library's own `Refused` and a byte-order mark is the
/// reader's business rather than the caller's.
pub fn utf8_decode(source : Bytes) -> String raise Refused {
  @utf8.decode(source, ignore_bom=true) catch {
    _ => raise Malformed(at=0, why="the bytes are not valid UTF-8")
  }
}

///|
pub fn utf8_encode(text : String) -> Bytes {
  @utf8.encode(text)
}

///|
/// A leading byte-order mark is stripped from text, the one repair a reader
/// makes before reading a document.
pub fn strip_bom(text : String) -> String {
  if text.length() >= 1 && text.at(0) == 0xFEFF {
    return text[1:text.length()].to_owned()
  }
  text
}
