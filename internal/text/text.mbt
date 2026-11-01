/// Character classification and small string helpers shared by the XML and HTML
/// parsers. Nothing here depends on the tree; the two parsers and the writers
/// call it so their notion of "space" and "a name" cannot diverge.

/// Whether `c` is one of XML's four whitespace characters: space, tab, CR, LF.
pub fn is_xml_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

/// Whether `c` is HTML whitespace. The set is the same four characters; HTML
/// also treats a form feed as whitespace.
pub fn is_html_space(c : Char) -> Bool {
  is_xml_space(c) || c == '\u{0C}'
}

/// Whether `c` is an ASCII digit.
pub fn is_ascii_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

/// Whether `c` is an ASCII upper- or lower-case letter.
pub fn is_ascii_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

/// Whether `c` is an ASCII letter or digit.
pub fn is_ascii_alnum(c : Char) -> Bool {
  is_ascii_alpha(c) || is_ascii_digit(c)
}

fn is_ascii_hex(c : Char) -> Bool {
  is_ascii_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

fn hex_value(c : Char) -> Int {
  if is_ascii_digit(c) {
    Char::to_int(c) - Char::to_int('0')
  } else if c >= 'a' && c <= 'f' {
    Char::to_int(c) - Char::to_int('a') + 10
  } else {
    Char::to_int(c) - Char::to_int('A') + 10
  }
}

fn is_hex(c : Char) -> Bool {
  is_ascii_hex(c)
}

/// Whether `c` may start an XML name. `:` is included (XML 1.0 permits it in a
/// Name); a namespace-aware parser splits on it before this is consulted.
pub fn is_name_start_char(c : Char) -> Bool {
  if is_ascii_alpha(c) {
    return true
  }
  if c == '_' || c == ':' || c == '\u{B7}' {
    return true
  }
  let n = Char::to_int(c)
  if n >= 0xC0 && n <= 0xD6 {
    return true
  }
  if n >= 0xD8 && n <= 0xF6 {
    return true
  }
  if n >= 0xF8 && n <= 0x2FF {
    return true
  }
  if n >= 0x370 && n <= 0x37D {
    return true
  }
  if n >= 0x37F && n <= 0x1FFF {
    return true
  }
  if n >= 0x200C && n <= 0x200D {
    return true
  }
  if n >= 0x2070 && n <= 0x218F {
    return true
  }
  if n >= 0x2C00 && n <= 0x2FEF {
    return true
  }
  if n >= 0x3001 && n <= 0xD7FF {
    return true
  }
  if n >= 0xF900 && n <= 0xFDCF {
    return true
  }
  if n >= 0xFDF0 && n <= 0xFFFD {
    return true
  }
  if n >= 0x10000 && n <= 0xEFFFF {
    return true
  }
  false
}

/// Whether `c` may continue an XML name.
pub fn is_name_char(c : Char) -> Bool {
  if is_name_start_char(c) {
    return true
  }
  if is_ascii_digit(c) {
    return true
  }
  if c == '-' || c == '.' || c == '\u{B7}' {
    return true
  }
  let n = Char::to_int(c)
  if n >= 0x300 && n <= 0x36F {
    return true
  }
  if n >= 0x203F && n <= 0x2040 {
    return true
  }
  false
}

/// Lower-case `s` using the unrestricted Unicode mapping the HTML parser wants
/// for tag and attribute names.
pub fn lower(s : String) -> String {
  s.to_lower()
}

/// A one-character string, used where the API is `String` but the unit is `Char`.
pub fn char_str(c : Char) -> String {
  c.to_string()
}

/// Whether `n` is a legal XML 1.0 character code point.
pub fn is_valid_xml_char(n : Int) -> Bool {
  if n == 0x9 || n == 0xA || n == 0xD {
    return true
  }
  if n >= 0x20 && n <= 0xD7FF {
    return true
  }
  if n >= 0xE000 && n <= 0xFFFD {
    return true
  }
  if n >= 0x10000 && n <= 0x10FFFF {
    return true
  }
  false
}

/// Turn a numeric character reference's code point into a string, substituting
/// U+FFFD for anything XML forbids. `n` is already the decoded number.
pub fn code_point_to_string(n : Int) -> String {
  if is_valid_xml_char(n) {
    Char::from_int(n).to_string()
  } else {
    "\u{FFFD}"
  }
}

/// Parse a run of hex digits (without a leading `#x`) into a code point.
pub fn parse_hex(s : String) -> Int {
  let mut n = 0
  for c in s {
    if is_hex(c) == false {
      return -1
    }
    n = n * 16 + hex_value(c)
  }
  n
}

/// Parse a run of decimal digits into a code point.
pub fn parse_dec(s : String) -> Int {
  let mut n = 0
  for c in s {
    if is_ascii_digit(c) == false {
      return -1
    }
    n = n * 10 + (Char::to_int(c) - Char::to_int('0'))
  }
  n
}

/// Whether `s` is empty or contains only XML whitespace.
pub fn is_blank(s : String) -> Bool {
  for c in s {
    if is_xml_space(c) == false {
      return false
    }
  }
  true
}
