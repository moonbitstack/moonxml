// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The members of a JSON object, flattened to the strings a form would carry.
///
/// `hx-vals` and `hx-headers` are JSON objects of scalars; a nested object or
/// array is kept as the compact text it was written as, because that is what
/// htmx sends. Text that is not an object answers the empty list.
fn json_members(text : String) -> Array[(String, String)] {
  let chars : Array[Char] = []
  for ch in text {
    chars.push(ch)
  }
  let mut at = skip_space(chars, 0)
  let out : Array[(String, String)] = []
  if at >= chars.length() || chars[at] != '{' {
    return out
  }
  at = skip_space(chars, at + 1)
  while at < chars.length() && chars[at] != '}' {
    if chars[at] != '"' {
      return out
    }
    let key = StringBuilder()
    at = read_string(chars, at, key)
    at = skip_space(chars, at)
    if at >= chars.length() || chars[at] != ':' {
      return out
    }
    at = skip_space(chars, at + 1)
    let value = StringBuilder()
    at = read_value(chars, at, value)
    out.push((key.to_string(), value.to_string()))
    at = skip_space(chars, at)
    if at < chars.length() && chars[at] == ',' {
      at = skip_space(chars, at + 1)
    } else {
      break
    }
  }
  out
}

///|
fn skip_space(chars : Array[Char], from : Int32) -> Int32 {
  let mut at = from
  while at < chars.length() &&
        (
          chars[at] == ' ' ||
          chars[at] == '\n' ||
          chars[at] == '\t' ||
          chars[at] == '\r'
        ) {
    at = at + 1
  }
  at
}

///|
/// Read a quoted string into `out`, answering where it ended. A string that
/// never closes ends at the end of the text.
fn read_string(chars : Array[Char], from : Int32, out : StringBuilder) -> Int32 {
  let mut at = from + 1
  while at < chars.length() {
    let ch = chars[at]
    if ch == '"' {
      return at + 1
    }
    if ch == '\\' && at + 1 < chars.length() {
      let escape = chars[at + 1]
      match escape {
        'n' => out.write_char('\n')
        't' => out.write_char('\t')
        'r' => out.write_char('\r')
        'b' => out.write_char('\u{8}')
        'f' => out.write_char('\u{c}')
        'u' => {
          let code = hex4(chars, at + 2)
          out.write_char(code.unsafe_to_char())
          at = at + 6
          continue
        }
        '"' => out.write_char('"')
        '\\' => out.write_char('\\')
        '/' => out.write_char('/')
        _ => out.write_char(escape)
      }
      at = at + 2
      continue
    }
    out.write_char(ch)
    at = at + 1
  }
  at
}

///|
/// Four hexadecimal digits, or zero when they are not.
fn hex4(chars : Array[Char], from : Int32) -> Int32 {
  let mut value = 0
  let mut at = from
  while at < from + 4 && at < chars.length() {
    let ch = chars[at]
    let digit = if ch >= '0' && ch <= '9' {
      ch.to_int() - '0'.to_int()
    } else if ch >= 'a' && ch <= 'f' {
      ch.to_int() - 'a'.to_int() + 10
    } else if ch >= 'A' && ch <= 'F' {
      ch.to_int() - 'A'.to_int() + 10
    } else {
      return 0
    }
    value = value * 16 + digit
    at = at + 1
  }
  value
}

///|
/// Read a JSON value into `out` as the text a form would send, answering
/// where it ended. A container is kept whole.
fn read_value(chars : Array[Char], from : Int32, out : StringBuilder) -> Int32 {
  if from >= chars.length() {
    return from
  }
  let ch = chars[from]
  if ch == '"' {
    return read_string(chars, from, out)
  }
  if ch == '{' || ch == '[' {
    let close = if ch == '{' { '}' } else { ']' }
    let mut depth = 0
    let mut at = from
    while at < chars.length() {
      let here = chars[at]
      if here == '"' {
        let ignored = StringBuilder()
        at = read_string(chars, at, ignored)
        continue
      }
      if here == ch {
        depth = depth + 1
      } else if here == close {
        depth = depth - 1
        if depth == 0 {
          at = at + 1
          break
        }
      }
      at = at + 1
    }
    for k = from; k < at; k = k + 1 {
      out.write_char(chars[k])
    }
    return at
  }
  // A number, `true`, `false` or `null`, up to the next comma or brace.
  let mut at = from
  while at < chars.length() &&
        chars[at] != ',' &&
        chars[at] != '}' &&
        chars[at] != ']' &&
        chars[at] != ' ' {
    at = at + 1
  }
  let literal = StringBuilder()
  for k = from; k < at; k = k + 1 {
    literal.write_char(chars[k])
  }
  let text = literal.to_string()
  if text != "null" {
    out.write_string(text)
  }
  at
}
