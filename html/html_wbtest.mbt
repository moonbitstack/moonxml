// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A tree in the shape html5lib's own test corpus spells it: one node a line,
/// two spaces per level. It is the format the fixtures are written in, so a
/// difference reads as a diff.
fn render(doc : @moonxml.Document) -> String {
  let out = StringBuilder()
  fn line(depth : Int32, body : String) -> Unit {
    out.write_string("| ")
    for _k = 0; _k < depth; _k = _k + 1 {
      out.write_string("  ")
    }
    out.write_string(body)
    out.write_char('\n')
  }
  fn walk(node : @moonxml.Node, depth : Int32) -> Unit {
    match node {
      @moonxml.ElementNode(data) => {
        line(depth, "<" + data.name + ">")
        for pair in data.attrs {
          line(depth + 1, pair.0 + "=\"" + pair.1 + "\"")
        }
        for child in data.childrens {
          walk(child, depth + 1)
        }
      }
      @moonxml.TextNode(text) => line(depth, "\"" + text + "\"")
      @moonxml.CDataNode(text) => line(depth, "\"" + text + "\"")
      @moonxml.CommentNode(text) => line(depth, "<!-- " + text + " -->")
      @moonxml.ProcessingInstructionNode(pi) =>
        line(depth, "<?" + pi.target + " " + pi.data + "?>")
      @moonxml.DoctypeNode(text) => line(depth, "<!DOCTYPE " + text + ">")
    }
  }
  for child in doc.root.childrens {
    walk(child, 0)
  }
  out.to_string()
}

///|
fn shape(text : String) -> String {
  render(loads(text))
}

///|
/// The names of the elements in a document, in document order: what a test
/// about structure wants to say.
fn names_of(doc : @moonxml.Document) -> Array[String] {
  let out : Array[String] = []
  fn walk(node : @moonxml.Node) -> Unit {
    match node {
      @moonxml.ElementNode(data) => {
        out.push(data.name)
        for child in data.childrens {
          walk(child)
        }
      }
      _ => ()
    }
  }
  for child in doc.root.childrens {
    walk(child)
  }
  out
}

///|
test "an ordinary document" {
  assert_eq(
    shape("<p>hello"),
    "| <html>\n" +
    "|   <head>\n" +
    "|   <body>\n" +
    "|     <p>\n" +
    "|       \"hello\"\n",
  )
}

///|
test "a document with a head, a body and a title" {
  assert_eq(
    shape(
      "<!DOCTYPE html><html><head><title>T</title></head><body><p>x</p></body></html>",
    ),
    "| <!DOCTYPE html>\n" +
    "| <html>\n" +
    "|   <head>\n" +
    "|     <title>\n" +
    "|       \"T\"\n" +
    "|   <body>\n" +
    "|     <p>\n" +
    "|       \"x\"\n",
  )
}

///|
test "an unclosed paragraph closes on the next block" {
  let doc = loads("<p>one<p>two")
  assert_eq(doc.css("p").length(), 2)
  assert_eq(doc.css("p").items[0].text(), "one")
  assert_eq(doc.css("p").items[1].text(), "two")
}

///|
test "a list item closes the one before it" {
  let doc = loads("<ul><li>a<li>b</ul>")
  assert_eq(doc.css("li").length(), 2)
  assert_eq(doc.css("ul").items[0].childrens().length(), 2)
}

///|
test "a table gains the tbody the document never wrote" {
  let doc = loads("<table><tr><td>x</td></tr></table>")
  assert_eq(names_of(doc), [
    "html", "head", "body", "table", "tbody", "tr", "td",
  ])
  assert_eq(doc.css("td").text(), "x")
}

///|
test "a cell closes itself at the next cell" {
  let doc = loads("<table><td>a<td>b</table>")
  assert_eq(doc.css("td").length(), 2)
  assert_eq(doc.css("tr").items[0].childrens().length(), 2)
}

///|
test "a table's stray content goes before it" {
  assert_eq(
    shape("<table><div>x</div></table>"),
    "| <html>\n" +
    "|   <head>\n" +
    "|   <body>\n" +
    "|     <div>\n" +
    "|       \"x\"\n" +
    "|     <table>\n",
  )
}

///|
test "stray text inside a table is put before it" {
  let doc = loads("<table>text<tr><td>x</td></tr></table>")
  assert_eq(doc.css("table").items[0].text(), "x")
  assert_eq(
    doc.css("body").items[0].childrens()[0] is @moonxml.TextNode(_),
    true,
  )
}

///|
test "a block inside formatting keeps the formatting open" {
  let doc = loads("<b>a<p>b</p>c")
  assert_eq(names_of(doc), ["html", "head", "body", "b", "p"])
  assert_eq(doc.css("b").text(), "abc")
}

///|
test "a paragraph's end returns the formatting that was inside it" {
  // The bold ran inside the paragraph; the text after it needs its own.
  let doc = loads("<p><b>a</p>b")
  assert_eq(names_of(doc), ["html", "head", "body", "p", "b", "b"])
  assert_eq(doc.css("b").text(), "ab")
}

///|
test "formatting is put back before the text that needs it" {
  let doc = loads("<p><b>one</p><div>two</div>three")
  assert_eq(names_of(doc), ["html", "head", "body", "p", "b", "div", "b", "b"])
  assert_eq(doc.css("b").length(), 3)
  assert_eq(doc.css("div").css("b").text(), "two")
}

///|
test "misnested formatting is repaired by the adoption agency" {
  let doc = loads("<b><p>x</b>y")
  assert_eq(doc.css("b").length(), 2)
  assert_eq(doc.css("p").items[0].childrens()[0].name(), "b")
}

///|
test "an end tag that matches nothing is dropped" {
  let doc = loads("<div></span>x</div>")
  assert_eq(doc.css("div").text(), "x")
  assert_eq(doc.repairs().dropped > 0, true)
}

///|
test "void elements take no children" {
  let doc = loads("<br>a<img src=x>b")
  assert_eq(doc.css("br").length(), 1)
  assert_eq(doc.css("img").attr("src"), Some("x"))
  assert_eq(doc.css("body").text(), "ab")
}

///|
test "character references decode, named and numeric" {
  let doc = loads("<p>a&amp;b&nbsp;c&#65;&#x42;&unknown;")
  assert_eq(doc.css("p").text(), "a&b\u{A0}cAB&unknown;")
}

///|
test "raw text keeps its angle brackets" {
  let doc = loads("<script>if (a < b) { }</script><style>a > b { }</style>")
  assert_eq(doc.css("script").text(), "if (a < b) { }")
  assert_eq(doc.css("style").text(), "a > b { }")
}

///|
test "rcdata decodes references but keeps its tags" {
  let doc = loads("<title>a &amp; b</title><textarea><b>x</b></textarea>")
  assert_eq(doc.css("title").text(), "a & b")
  assert_eq(doc.css("textarea").text(), "<b>x</b>")
}

///|
test "a comment is a node, and a bogus one becomes a comment" {
  let doc = loads("<!-- hello --><?php echo ?><p>x")
  assert_eq(doc.root.childrens[0] is CommentNode(_), true)
  assert_eq(doc.root.childrens[1] is CommentNode(_), true)
}

///|
test "attributes fold their names to lower case and keep their order" {
  let doc = loads("<div B='2' a='1'>x</div>")
  let div = doc.css("div")
  assert_eq(div.attr("b"), Some("2"))
  assert_eq(div.attr("a"), Some("1"))
  assert_eq(div.items[0].name(), "div")
}

///|
test "a repeated attribute keeps the first" {
  let doc = loads("<div a='1' a='2'>x</div>")
  assert_eq(doc.css("div").attr("a"), Some("1"))
  assert_eq(doc.repairs().dropped > 0, true)
}

///|
test "an unquoted attribute value ends at the space" {
  let doc = loads("<div a=1 b=x>y</div>")
  assert_eq(doc.css("div").attr("a"), Some("1"))
  assert_eq(doc.css("div").attr("b"), Some("x"))
}

///|
test "a select keeps its options in order" {
  let doc = loads(
    "<select><option>a<option>b<optgroup label=g><option>c</select>",
  )
  assert_eq(doc.css("option").length(), 3)
  assert_eq(doc.css("optgroup").attr("label"), Some("g"))
}

///|
test "nesting past the depth bound is still read, not refused" {
  let mut source = ""
  for _k = 0; _k < 600; _k = _k + 1 {
    source = source + "<div>"
  }
  let doc = loads(source)
  assert_eq(doc.css("div").length() >= 500, true)
}

///|
test "an empty document is a document" {
  assert_eq(shape(""), "| <html>\n|   <head>\n|   <body>\n")
}

///|
test "text before any tag still lands in the body" {
  assert_eq(
    shape("hello"),
    "| <html>\n|   <head>\n|   <body>\n|     \"hello\"\n",
  )
}

///|
test "an h1 closes an open h2" {
  let doc = loads("<h2>a<h3>b")
  assert_eq(doc.css("h2").items[0].childrens().length(), 1)
  assert_eq(doc.css("h2").items[0].childrens()[0].name(), "")
}

///|
test "the body the reader never wrote is implied" {
  let doc = loads("<p>x")
  assert_eq(doc.document_element().unwrap().name, "html")
  assert_eq(doc.css("body").length(), 1)
  assert_eq(doc.repairs().implied >= 2, true)
}

///|
test "the chain reads an HTML document like any other" {
  let doc = loads(
    "<!DOCTYPE html><html><body><div id='a'><p class='x'>one</p></div></body></html>",
  )
  assert_eq(doc.flavor(), @moonxml.Html)
  assert_eq(doc.css("#a .x").text(), "one")
  assert_eq(doc.xpath("//p").text(), "one")
  assert_eq(doc.by_id("a").css("p").attr("class"), Some("x"))
}
