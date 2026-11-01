/// One test per insertion mode.
///
/// The tree builder's state machine is the part of the parser most likely to
/// regress silently, because a wrong mode usually still produces a plausible
/// tree. These tests pin one behaviour per mode, named after the mode that owns
/// it, so a regression names its own cause.

// --- initial, before html, before head -------------------------------------

test "initial: a doctype and a comment before html stay at the top level" {
  let doc = @html.loads("<!DOCTYPE html><!--c--><p>x")
  let kids = doc.root().children
  assert_eq(kids.length(), 3)
  assert_eq(kids[0].is_element(), false)
  assert_eq(kids[1].is_element(), false)
  assert_eq(kids[2].is_element(), true)
  assert_eq(doc.css("body p").length(), 1)
}

test "before html: content creates html and head on the way in" {
  let doc = @html.loads("hello")
  assert_eq(doc.css("html").length(), 1)
  assert_eq(doc.css("head").length(), 1)
  assert_eq(doc.css("body").text(), "hello")
}

test "before head: whitespace is dropped, head content still lands in head" {
  let doc = @html.loads("  \n <meta charset=\"utf-8\"> <p>x")
  assert_eq(doc.css("head meta").length(), 1)
  assert_eq(doc.css("head").text(), " ")
  assert_eq(doc.css("body p").length(), 1)
}

// --- in head ---------------------------------------------------------------

test "in head: title and style are head content, p starts the body" {
  let doc = @html.loads("<title>t</title><style>a{}</style><p>x")
  assert_eq(doc.css("head title").text(), "t")
  assert_eq(doc.css("head style").text(), "a{}")
  assert_eq(doc.css("head").text(), "ta{}")
  assert_eq(doc.css("body p").length(), 1)
}

test "in head: a second head is ignored and html attributes merge" {
  let doc = @html.loads("<html lang=\"en\"><head></head><head></head><body>x")
  assert_eq(doc.css("html").length(), 1)
  assert_eq(doc.css("html").attr("lang"), Some("en"))
  assert_eq(doc.css("head").length(), 1)
}

test "in head noscript: with scripting off its content is parsed as markup" {
  let doc = @html.loads("<noscript><link rel=\"x\"></noscript><p>y")
  assert_eq(doc.css("head noscript link").length(), 1)
  assert_eq(doc.css("body p").length(), 1)
}

// --- after head ------------------------------------------------------------

test "after head: head content met late still goes to head" {
  let doc = @html.loads("<body><p>x</p><meta name=\"late\">")
  assert_eq(doc.css("head meta").length(), 0)
  assert_eq(doc.css("body meta").length(), 1)
  let doc2 = @html.loads("<html><head></head><meta name=\"early\"><p>x")
  assert_eq(doc2.css("head meta").length(), 1)
}

// --- in body and text ------------------------------------------------------

test "in body: p closes p, li closes li" {
  let doc = @html.loads("<p>a<p>b<ul><li>1<li>2</ul>")
  assert_eq(doc.css("body > p").length(), 2)
  assert_eq(doc.css("li").length(), 2)
  assert_eq(doc.css("li").eq(1).text(), "2")
}

test "text: script, style, textarea and title are raw text" {
  let doc = @html.loads("<script>if (a < b) x()</script><textarea><b>y</b></textarea>")
  assert_eq(doc.css("script").text(), "if (a < b) x()")
  assert_eq(doc.css("textarea").text(), "<b>y</b>")
  assert_eq(doc.css("textarea b").length(), 0)
}

test "text: a title ends at its own end tag, not at another" {
  let doc = @html.loads("<title>a</style></title><p>x")
  assert_eq(doc.css("title").text(), "a</style>")
  assert_eq(doc.css("body p").length(), 1)
}

// --- in table, in table text ----------------------------------------------

test "in table: rows get an implied tbody and cells an implied row" {
  let doc = @html.loads("<table><tr><td>a<td>b</table>")
  assert_eq(doc.css("table > tbody").length(), 1)
  assert_eq(doc.css("tbody > tr").length(), 1)
  assert_eq(doc.css("tr > td").length(), 2)
}

test "in table text: text is fostered before the table" {
  let doc = @html.loads("<div><table>abc<tr><td>x</table></div>")
  let body = doc.css("div").items[0].as_element().unwrap()
  assert_eq(body.children[0].is_text(), true)
  assert_eq(body.children[1].is_element(), true)
  assert_eq(doc.css("table").text(), "x")
}

test "in caption: a cell closes the caption first" {
  let doc = @html.loads("<table><caption>c<td>x</table>")
  assert_eq(doc.css("caption").text(), "c")
  assert_eq(doc.css("caption td").length(), 0)
  assert_eq(doc.css("td").length(), 1)
}

test "in column group: col belongs to a colgroup" {
  let doc = @html.loads("<table><col><col><tbody><tr><td>x</table>")
  assert_eq(doc.css("table > colgroup").length(), 1)
  assert_eq(doc.css("colgroup > col").length(), 2)
  assert_eq(doc.css("tbody tr td").length(), 1)
}

// --- select ----------------------------------------------------------------

test "in select: options nest one level and other tags are ignored" {
  let doc = @html.loads("<select><option>a<option>b<div>c</select>")
  assert_eq(doc.css("select > option").length(), 2)
  assert_eq(doc.css("select div").length(), 0)
  assert_eq(doc.css("select").text(), "abc")
}

test "in select in table: a table tag closes the select" {
  let doc = @html.loads("<table><tr><td><select><option>a<tr><td>b</table>")
  assert_eq(doc.css("select option").length(), 1)
  assert_eq(doc.css("tr").length(), 2)
  assert_eq(doc.css("table select").length(), 1)
}

// --- template --------------------------------------------------------------

test "in template: table parts live in template content" {
  let doc = @html.loads("<template><tr><td>x</template>")
  let t = doc.css("template").items[0].as_element().unwrap()
  assert_eq(t.children.length(), 1)
  assert_eq(doc.css("template tr").length(), 1)
  assert_eq(doc.css("template td").text(), "x")
  assert_eq(doc.css("body > tr").length(), 0)
}

test "in template: a nested template keeps its own content" {
  let doc = @html.loads("<template><div><template><p>x</template>y</template>")
  assert_eq(doc.css("template").length(), 2)
  assert_eq(doc.css("template p").text(), "x")
  assert_eq(doc.css("body").text(), "")
}

// --- after body and after after body --------------------------------------

test "after body: a comment lands inside html, after the body" {
  let doc = @html.loads("<body><p>x</p></body><!--c-->")
  let html = doc.css("html").items[0].as_element().unwrap()
  let last = html.children[html.children.length() - 1]
  assert_eq(last.is_element(), false)
  assert_eq(doc.css("body").text(), "x")
}

test "after body: text pulls the parser back into the body" {
  let doc = @html.loads("<body><p>x</p></body>tail")
  assert_eq(doc.css("body").text(), "xtail")
}

// --- frameset --------------------------------------------------------------

test "in frameset: only frames and noframes are inserted" {
  let doc = @html.loads("<frameset><frame><noframes>no</noframes></frameset>")
  assert_eq(doc.css("frameset > frame").length(), 1)
  assert_eq(doc.css("frameset noframes").text(), "no")
  assert_eq(doc.css("body").length(), 0)
}

test "after frameset: html end switches to the frameset aftermath" {
  let doc = @html.loads("<frameset></frameset></html><noframes>n</noframes>")
  assert_eq(doc.css("frameset").length(), 1)
  assert_eq(doc.css("noframes").text(), "n")
  assert_eq(doc.css("body").length(), 0)
}

// --- foreign content -------------------------------------------------------

test "foreign: svg and math put their children in their own namespace" {
  let doc = @html.loads("<svg><g><circle/></g></svg><math><mi>x</mi></math>")
  let circle = doc.css("circle").items[0].as_element().unwrap()
  assert_eq(circle.namespace_uri(), "http://www.w3.org/2000/svg")
  let mi = doc.css("mi").items[0].as_element().unwrap()
  assert_eq(mi.namespace_uri() == "http://www.w3.org/1998/Math/MathML", true)
}

test "foreign: an integration point holds HTML" {
  let doc = @html.loads("<svg><foreignObject><div>x</div></foreignObject></svg>")
  let div = doc.css("div").items[0].as_element().unwrap()
  assert_eq(div.namespace_uri(), "")
  assert_eq(doc.css("foreignObject div").text(), "x")
}

test "foreign: an HTML block breaks out of foreign content" {
  let doc = @html.loads("<svg><g><p>x")
  let p = doc.css("p").items[0].as_element().unwrap()
  assert_eq(p.namespace_uri(), "")
  assert_eq(doc.css("body > p").text(), "x")
}

// --- fragments -------------------------------------------------------------

test "fragment: the context element decides the namespace and the mode" {
  let svg = @html.loads_fragment("<circle/>", context="svg path")
  let c = svg.css("circle").items[0].as_element().unwrap()
  assert_eq(c.namespace_uri(), "http://www.w3.org/2000/svg")

  let table = @html.loads_fragment("<tr><td>x", context="table")
  assert_eq(table.css("tbody").length(), 1)
  assert_eq(table.css("td").text(), "x")
  assert_eq(table.css("table").length(), 0)

  let cell = @html.loads_fragment("<b>x</b>", context="td")
  assert_eq(cell.css("b").text(), "x")
}

test "fragment: a table part in a body context is ignored" {
  let doc = @html.loads_fragment("<td>x", context="body")
  assert_eq(doc.css("td").length(), 0)
  assert_eq(doc.root().text(), "x")
}

// --- namespace-sensitive end tags -----------------------------------------

test "foreign: an end tag closes the HTML namesake, not the foreign one" {
  // The cell's `</td>` must close the HTML `td` even though an `svg td` sits
  // above it, which is what sends `Foo` back out to the body.
  let doc = @html.loads("<table><tr><td><svg><td><foreignObject><span></td>Foo")
  assert_eq(doc.css("body").text(), "Foo")
  assert_eq(doc.css("table").text(), "")
  assert_eq(doc.css("svg td").length(), 1)
  let svg_td = doc.css("svg td").items[0].as_element().unwrap()
  assert_eq(svg_td.namespace_uri(), "http://www.w3.org/2000/svg")
}

test "foreign: an end tag closes the HTML template, not a foreign namesake" {
  // The SVG `template` stays in the tree, but `</template>` pops everything
  // above and including the HTML one, so the trailing div lands in the body.
  let doc = @html.loads("<template><svg><foo><template><foreignObject><div></template><div>")
  assert_eq(doc.css("template").length(), 2)
  assert_eq(doc.css("foreignObject div").length(), 1)
  assert_eq(doc.css("body > div").length(), 1)
}

test "foreign: a frameset still replaces a body whose text was only NUL" {
  let doc = @html.loads("<svg>\u{0}</svg><frameset></frameset>")
  assert_eq(doc.css("frameset").length(), 1)
  assert_eq(doc.css("body").length(), 0)
  assert_eq(doc.css("svg").length(), 0)
}
