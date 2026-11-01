fn one_line(s : String) -> String {
  let sb = StringBuilder()
  for c in s {
    if c == '\n' {
      sb.write_string("\\n")
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

test "h5 diag" {
  let want = "tests19.dat"
  let mut shown = 0
  for c in h5_cases() {
    if c.file == want && shown < 6 {
      let actual = dump_case(c)
      if actual != c.doc {
        shown = shown + 1
        println("== in=" + one_line(c.input) + " frag=[" + c.fragment + "]")
        println("EXP " + one_line(c.doc))
        println("GOT " + one_line(actual))
      }
    }
  }
}
