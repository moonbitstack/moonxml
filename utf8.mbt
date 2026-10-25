// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// UTF-8, the one encoding, over core's codec — wrapped so its failure
/// arrives as this library's own `Refused`, with the offset of the byte that
/// spoiled the sequence, and a byte-order mark is the reader's business rather
/// than the caller's.
pub fn utf8_decode(source : Bytes) -> String raise Refused {
  @utf8.decode(source, ignore_bom=true) catch {
    _ =>
      raise Malformed(at=fault_at(source), why="the bytes are not valid UTF-8")
  }
}

///|
/// Where the first byte that cannot begin or continue a UTF-8 sequence sits.
/// core's decoder says *that* a document is not UTF-8; this says *where*, which
/// is the difference between an error a caller can act on and one it cannot.
fn fault_at(source : Bytes) -> Int32 {
  let n = source.length()
  let mut i = 0
  while i < n {
    let lead = source[i].to_int()
    if lead < 0x80 {
      i = i + 1
      continue
    }
    let (more, low, high) = if lead >= 0xC2 && lead <= 0xDF {
      (1, 0x80, 0x7FF)
    } else if lead >= 0xE0 && lead <= 0xEF {
      (2, 0x800, 0xFFFF)
    } else if lead >= 0xF0 && lead <= 0xF4 {
      (3, 0x10000, 0x10FFFF)
    } else {
      // a continuation byte where a lead belongs, or 0xC0/0xC1/0xF5..0xFF
      return i
    }
    if i + more >= n {
      return i
    }
    let mut code = lead & (0x7F >> more)
    for k = 1; k <= more; k = k + 1 {
      let unit = source[i + k].to_int()
      if (unit & 0xC0) != 0x80 {
        return i
      }
      code = (code << 6) | (unit & 0x3F)
    }
    // overlong sequences, surrogates and the two non-characters above the
    // last plane are all invalid in UTF-8
    if code < low || code > high || (code >= 0xD800 && code <= 0xDFFF) {
      return i
    }
    i = i + more + 1
  }
  n
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
