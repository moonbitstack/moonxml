///|
test "decode drops the byte-order mark and names the fault" {
  assert_eq(@text.decode(b"\xEF\xBB\xBFh\xC3\xA9llo"), Ok("héllo"))
  assert_eq(@text.decode(b"A\xFF"), Err(1))
  assert_eq(@text.decode(b"ab\xE2\x82"), Err(2))
  assert_eq(@text.decode(b"\xC0\x80"), Err(0))
}

///|
test "strip_bom removes one leading mark and nothing else" {
  assert_eq(@text.strip_bom("\u{FEFF}<a/>"), "<a/>")
  assert_eq(@text.strip_bom("<a/>"), "<a/>")
  assert_eq(@text.strip_bom(""), "")
}
