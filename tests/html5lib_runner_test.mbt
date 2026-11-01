/// Runs the vendored html5lib tree-construction corpus and reports a pass rate.
/// The floor is a ratchet: raise it as the parser improves, never lower it.

fn indent(sb : StringBuilder, depth : Int) -> Unit {
  sb.write_string("| ")
  let mut i = 0
  while i < depth {
    sb.write_string("  ")
    i = i + 1
  }
}

fn sort_attrs(a : Array[(String, String)]) -> Array[(String, String)] {
  let out = a.copy()
  let n = out.length()
  let mut i = 1
  while i < n {
    let cur = out[i]
    let mut j = i - 1
    while j >= 0 {
      let (k, _) = out[j]
      let (ck, _) = cur
      if k > ck {
        out[j + 1] = out[j]
        j = j - 1
      } else {
        break
      }
    }
    out[j + 1] = cur
    i = i + 1
  }
  out
}

fn dump_node(n : @moonxml.Node, depth : Int, sb : StringBuilder) -> Unit {
  match n {
    @moonxml.Node::ElementNode(e) => {
      let ns = e.namespace_uri()
      let desig = if ns == "http://www.w3.org/2000/svg" {
        "svg "
      } else if ns == "http://www.w3.org/1998/Math/MathML" {
        "math "
      } else {
        ""
      }
      indent(sb, depth)
      sb.write_string("<" + desig + e.local_name() + ">\n")
      for pair in sort_attrs(e.attrs) {
        let (k, v) = pair
        indent(sb, depth + 1)
        sb.write_string(k + "=\"" + v + "\"\n")
      }
      if e.local_name() == "template" && ns == "" {
        indent(sb, depth + 1)
        sb.write_string("content\n")
        for c in e.children {
          dump_node(c, depth + 2, sb)
        }
      } else {
        for c in e.children {
          dump_node(c, depth + 1, sb)
        }
      }
    }
    @moonxml.Node::TextNode(s) => {
      indent(sb, depth)
      sb.write_string("\"" + s + "\"\n")
    }
    @moonxml.Node::CommentNode(s) => {
      indent(sb, depth)
      sb.write_string("<!-- " + s + " -->\n")
    }
    @moonxml.Node::DoctypeNode(s) => {
      indent(sb, depth)
      sb.write_string("<!DOCTYPE " + s + ">\n")
    }
    @moonxml.Node::ProcessingInstructionNode(pi) => {
      indent(sb, depth)
      if pi.data == "" {
        sb.write_string("<?" + pi.target + ">\n")
      } else {
        sb.write_string("<?" + pi.target + " " + pi.data + ">\n")
      }
    }
    _ => ()
  }
}

fn dump_root(root : @moonxml.Element) -> String {
  let sb = StringBuilder()
  for c in root.children {
    dump_node(c, 0, sb)
  }
  let s = sb.to_string()
  if s.has_suffix("\n") {
    s.substring(start=0, end=s.length() - 1)
  } else {
    s
  }
}

fn file_slot(names : Array[String], passes : Array[Int], totals : Array[Int], name : String) -> Int {
  let mut i = 0
  while i < names.length() {
    if names[i] == name {
      return i
    }
    i = i + 1
  }
  names.push(name)
  passes.push(0)
  totals.push(0)
  names.length() - 1
}

fn dump_case(c : H5Case) -> String {
  let doc = if c.fragment == "" {
    @html.loads_with_scripting(c.input, c.scripting)
  } else {
    @html.loads_fragment(c.input, context=c.fragment)
  }
  dump_root(doc.root)
}

test "html5lib conformance" {
  let cases = h5_cases()
  let mut pass = 0
  let mut shown = 0
  let fnames : Array[String] = []
  let fpass : Array[Int] = []
  let ftotal : Array[Int] = []
  for c in cases {
    let fi = file_slot(fnames, fpass, ftotal, c.file)
    ftotal[fi] = ftotal[fi] + 1
    let actual = dump_case(c)
    if actual == c.doc {
      pass = pass + 1
      fpass[fi] = fpass[fi] + 1
    } else if shown < 6 {
      shown = shown + 1
      println("FAIL " + c.file + " in=" + c.input)
      println("  exp: " + c.doc)
      println("  got: " + actual)
    }
  }
  println("html5lib tree-construction: " + pass.to_string() + "/" + cases.length().to_string())
  let mut f = 0
  while f < fnames.length() {
    println("  " + fnames[f] + " " + fpass[f].to_string() + "/" + ftotal[f].to_string())
    f = f + 1
  }
  // Ratchet: raise this as the parser improves, never lower it.
  assert_eq(pass >= 1345, true)
}
