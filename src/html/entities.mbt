// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The named character references HTML defines — all 2231 spellings of them,
/// in the table the standard keeps, generated into `entities_table.mbt`.
///
/// A name that may be written without its semicolon is in the table twice, so
/// `named_reference("amp")` and `named_reference("amp;")` answer the same `&`.
/// An unknown name answers `None`, which is the tokenizer's cue to leave the
/// text as it stands.
pub fn named_reference(name : String) -> String? {
  let mut low = 0
  let mut high = named_table.length() - 1
  while low <= high {
    let mid = (low + high) / 2
    let (here, value) = named_table[mid]
    match compare(name, here) {
      -1 => high = mid - 1
      1 => low = mid + 1
      _ => return Some(value)
    }
  }
  None
}

///|
/// `-1`, `0` or `1`: the order the standard's table is kept in, by UTF-16 code
/// unit.
fn compare(a : String, b : String) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  let mut i = 0
  while i < n {
    let left = a.at(i)
    let right = b.at(i)
    if left < right {
      return -1
    }
    if left > right {
      return 1
    }
    i = i + 1
  }
  if a.length() < b.length() {
    -1
  } else if a.length() > b.length() {
    1
  } else {
    0
  }
}

///|
/// The longest name at `from` that the table carries, with the position just
/// past it. The standard's rule: the longest match wins, semicolon or not.
fn longest_reference(text : String, from : Int32) -> (String, Int32)? {
  let n = text.length()
  let mut length = 32
  if n - from < length {
    length = n - from
  }
  while length >= 1 {
    let probe = text[from:from + length].to_owned()
    match named_reference(probe) {
      Some(value) => return Some((value, from + length))
      None => length = length - 1
    }
  }
  None
}
