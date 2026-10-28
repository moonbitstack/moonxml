// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Every selector this library implements, run against one document, printed
/// as the rows the demonstration page is built from:
///
///     moon run src/examples/selectors
///
/// One line of the output is the document itself, escaped onto one line; the
/// rest are `row`, then the group, the engine, the query as it is written, how
/// many nodes came back, and what they are. `scripts/gen_selectors.py` turns
/// that into `docs/selectors.html`, so the page cannot claim anything this
/// program did not do.
#coverage.skip
fn main {
  run() catch {
    error => println("refused: \{error}")
  }
}

///|
fn run() -> Unit raise @moonxml.Refused {
  println("document\t" + one_line(sample()))
  let page = @html.loads(sample())
  page.register(
    "pricey",
    @moonxml.SelectorFn::new((ctx, _query) => {
      ctx
      .css("[data-price]")
      .filter(fn(node) {
        match node {
          @moonxml.ElementNode(data) =>
            match data.attr("data-price") {
              Some(price) => number(price) >= 16
              None => false
            }
          _ => false
        }
      })
    }),
  )
  simple(page)
  combinators(page)
  pseudo(page)
  chain(page)
  values(page)
  same_node(page)
}

///|
/// The document every query below runs against. It is written to be awkward on
/// purpose: siblings of the same type, an element with nothing in it, a form
/// with every state CSS can ask about, and attributes carrying numbers.
fn sample() -> String {
  let lines = [
    "<!DOCTYPE html>", "<html lang=\"en\">", "<head>", "<title>Field Notes</title>",
    "</head>", "<body>", "<article id=\"shop\" class=\"catalogue\" data-region=\"eu\">",
    "  <header id=\"masthead\" class=\"masthead\">", "    <h1>Field Notes</h1>",
    "    <p class=\"dek\">Coffee, tea, and the machinery of both</p>", "  </header>",
    "  <ul id=\"items\" class=\"list\">", "    <li class=\"item\" data-kind=\"bean\" data-price=\"18\">Yirgacheffe</li>",
    "    <li class=\"item\" data-kind=\"bean\" data-price=\"22\" lang=\"en-GB\">Huila</li>",
    "    <li class=\"item sold\" data-kind=\"leaf\" data-price=\"9\">Sencha</li>",
    "    <li class=\"item\" data-kind=\"leaf\" data-price=\"14\">Assam</li>", "    <li class=\"item\" data-kind=\"blend\" data-price=\"16\"><a href=\"/b/1\">House</a></li>",
    "  </ul>", "  <form id=\"order\" action=\"/order\" method=\"post\">", "    <label for=\"qty\">Quantity</label>",
    "    <input id=\"qty\" name=\"qty\" type=\"number\" value=\"2\" required>", "    <input id=\"gift\" name=\"gift\" type=\"checkbox\" disabled>",
    "    <select name=\"grind\">", "      <option value=\"fine\">Fine</option>",
    "      <option value=\"coarse\" selected>Coarse</option>", "    </select>", "    <button id=\"send\" type=\"submit\" class=\"btn primary\">Order</button>",
    "    <span id=\"hollow\" class=\"flag\"></span>", "  </form>", "  <table id=\"prices\">",
    "    <caption>Per 250 g</caption>", "    <thead><tr><th>Item</th><th>Price</th></tr></thead>",
    "    <tbody>", "      <tr data-band=\"high\"><td>Huila</td><td>22</td></tr>",
    "      <tr data-band=\"low\"><td>Sencha</td><td>9</td></tr>", "    </tbody>",
    "  </table>", "  <p class=\"note\">Prices in <abbr title=\"United States dollars\">USD</abbr>, roasted weekly.</p>",
    "  <section id=\"aside\">", "    <h2>Notes</h2>", "    <p>One shipment a week.</p>",
    "  </section>", "</article>", "</body>", "</html>",
  ]
  let out = StringBuilder()
  for k = 0; k < lines.length(); k = k + 1 {
    if k > 0 {
      out.write_char('\n')
    }
    out.write_string(lines[k])
  }
  out.to_string()
}

///|
fn simple(page : @moonxml.Document) -> Unit raise @moonxml.Refused {
  let g = "simple"
  row(g, "css", "*", page.css("*"))
  row(g, "css", "li", page.css("li"))
  row(g, "css", ".item", page.css(".item"))
  row(g, "css", ".sold", page.css(".sold"))
  row(g, "css", "#items", page.css("#items"))
  row(g, "css", "[data-price]", page.css("[data-price]"))
  row(g, "css", "[data-price=\"18\"]", page.css("[data-price=\"18\"]"))
  row(g, "css", "[data-price^=\"1\"]", page.css("[data-price^=\"1\"]"))
  row(g, "css", "[data-price$=\"2\"]", page.css("[data-price$=\"2\"]"))
  row(g, "css", "[data-price*=\"4\"]", page.css("[data-price*=\"4\"]"))
  row(g, "css", "[lang|=\"en\"]", page.css("[lang|=\"en\"]"))
  row(g, "css", "[class~=\"sold\"]", page.css("[class~=\"sold\"]"))
  row(g, "css", "[data-kind=\"BEAN\" i]", page.css("[data-kind=\"BEAN\" i]"))
  row(g, "css", "[data-kind=\"BEAN\" s]", page.css("[data-kind=\"BEAN\" s]"))
  row(g, "css", "[data-kind=\"bean\"]", page.css("[data-kind=\"bean\"]"))
  row(g, "css", "li, td", page.css("li, td"))
}

///|
fn combinators(page : @moonxml.Document) -> Unit raise @moonxml.Refused {
  let g = "combinators"
  row(g, "css", "#items > li", page.css("#items > li"))
  row(g, "css", "#items li", page.css("#items li"))
  row(g, "css", "li + li", page.css("li + li"))
  row(g, "css", "li ~ li", page.css("li ~ li"))
  row(g, "css", "#shop > ul > li", page.css("#shop > ul > li"))
  row(
    g,
    "css",
    "#prices tr > td:last-child",
    page.css("#prices tr > td:last-child"),
  )
}

///|
fn pseudo(page : @moonxml.Document) -> Unit raise @moonxml.Refused {
  let g = "pseudo"
  row(g, "css", "li:first-child", page.css("li:first-child"))
  row(g, "css", "li:last-child", page.css("li:last-child"))
  row(g, "css", "li:nth-child(2)", page.css("li:nth-child(2)"))
  row(g, "css", "li:nth-child(odd)", page.css("li:nth-child(odd)"))
  row(g, "css", "li:nth-child(3n+1)", page.css("li:nth-child(3n+1)"))
  row(g, "css", "li:nth-last-child(1)", page.css("li:nth-last-child(1)"))
  row(g, "css", "td:nth-of-type(2)", page.css("td:nth-of-type(2)"))
  row(g, "css", "p:first-of-type", page.css("p:first-of-type"))
  row(g, "css", "td:last-of-type", page.css("td:last-of-type"))
  row(g, "css", "#aside > p:only-of-type", page.css("#aside > p:only-of-type"))
  row(g, "css", ":root", page.css(":root"))
  row(g, "css", "#hollow:empty", page.css("#hollow:empty"))
  row(g, "css", "option:checked", page.css("option:checked"))
  row(g, "css", "input:disabled", page.css("input:disabled"))
  row(g, "css", "input:enabled", page.css("input:enabled"))
  row(g, "css", "input:required", page.css("input:required"))
  row(g, "css", "input:optional", page.css("input:optional"))
  row(g, "css", "li > a:only-child", page.css("li > a:only-child"))
  row(g, "css", "td:nth-last-of-type(1)", page.css("td:nth-last-of-type(1)"))
  row(g, "css", "a:link", page.css("a:link"))
  row(g, "css", "a:any-link", page.css("a:any-link"))
  row(g, "css", "li:not(.sold)", page.css("li:not(.sold)"))
  row(
    g,
    "css",
    "li:is(.sold, [data-kind=\"blend\"])",
    page.css("li:is(.sold, [data-kind=\"blend\"])"),
  )
  row(g, "css", ":where(.item, .btn)", page.css(":where(.item, .btn)"))
  row(
    g,
    "css",
    "#order:has(option[selected])",
    page.css("#order:has(option[selected])"),
  )
  row(g, "css", "li:has(> a)", page.css("li:has(> a)"))
  row(g, "css", "li:has(+ li.sold)", page.css("li:has(+ li.sold)"))
}

///|
fn chain(page : @moonxml.Document) -> Unit raise @moonxml.Refused {
  let g = "chain"
  row(
    g,
    "css",
    "page.css(\"#items\").css(\"li[data-kind=leaf]\")",
    page.css("#items").css("li[data-kind=leaf]"),
  )
  row(
    g,
    "css",
    "page.css(\"tbody tr\").xpath(\"./td[2]\")",
    page.css("tbody tr").xpath("./td[2]"),
  )
  row(g, "css", "page.css(\"li\").first()", page.css("li").first())
  row(g, "css", "page.css(\"li\").last()", page.css("li").last())
  row(g, "css", "page.css(\"li\").eq(2)", page.css("li").eq(2))
  row(g, "css", "page.css(\"td\").parent()", page.css("td").parent())
  row(
    g,
    "css",
    "page.css(\"#prices\").children()",
    page.css("#prices").children(),
  )
  row(
    g,
    "css",
    "page.css(\"abbr\").closest(\"p\")",
    page.css("abbr").closest("p"),
  )
  row(g, "css", "page.by_id(\"order\")", page.by_id("order"))
  row(g, "css", "page.by_tag(\"option\")", page.by_tag("option"))
  row(g, "css", "page.by_class(\"sold\")", page.by_class("sold"))
  row(g, "css", "page.by_name(\"grind\")", page.by_name("grind"))
  row(g, "css", "page.selector(\"pricey\", \"\")", page.selector("pricey", ""))
  row(
    g,
    "css",
    "page.css(\"li\").items[4].css(\"a\")",
    page.css("li").items[4].css("a"),
  )
  row(g, "xpath", "page.xpath(\"//li[last()]\")", page.xpath("//li[last()]"))
  row(
    g,
    "xpath",
    "page.xpath(\"//tr[td[2] > 15]\")",
    page.xpath("//tr[td[2] > 15]"),
  )
}

///|
fn values(page : @moonxml.Document) -> Unit raise @moonxml.Refused {
  let g = "values"
  value(
    g,
    "text",
    "page.css(\"#items li\").text()",
    page.css("#items li").text(),
  )
  value(g, "text", "page.css(\"li.sold\").text()", page.css("li.sold").text())
  value(
    g,
    "attr",
    "page.css(\"li.sold\").attr(\"data-price\")",
    page.css("li.sold").attr("data-price").unwrap_or(""),
  )
  value(
    g,
    "attr",
    "page.css(\"li\").attr(\"data-kind\")",
    page.css("li").attr("data-kind").unwrap_or(""),
  )
  value(
    g,
    "attr",
    "page.css(\"abbr\").attr(\"title\")",
    page.css("abbr").attr("title").unwrap_or(""),
  )
  value(
    g,
    "attr",
    "page.css(\"option[selected]\").attr(\"value\")",
    page.css("option[selected]").attr("value").unwrap_or(""),
  )
  value(
    g,
    "attr",
    "page.css(\"#prices tbody tr\").attr(\"data-band\")",
    page.css("#prices tbody tr").attr("data-band").unwrap_or(""),
  )
  value(
    g,
    "html",
    "page.css(\"#items li\").last().html()",
    page.css("#items li").last().html(),
  )
  value(g, "html", "page.css(\"#order\").html()", page.css("#order").html())
  value(
    g,
    "xpath",
    "page.xpath_value(\"count(//li)\")",
    page.xpath_value("count(//li)").to_string(),
  )
  value(
    g,
    "xpath",
    "page.xpath_value(\"string(//abbr/@title)\")",
    page.xpath_value("string(//abbr/@title)").to_string(),
  )
  value(
    g,
    "xpath",
    "page.xpath_value(\"//li[@data-price > 15]\")",
    page.xpath_value("//li[@data-price > 15]").to_string(),
  )
  value(
    g,
    "xpath",
    "page.xpath_value(\"//li[@data-price > 15] and count(//li) = 5\")",
    page.xpath_value("//li[@data-price > 15] and count(//li) = 5").to_string(),
  )
}

///|
fn same_node(page : @moonxml.Document) -> Unit raise @moonxml.Refused {
  let g = "same"
  row(g, "css", "#order", page.css("#order"))
  row(g, "css", "form", page.css("form"))
  row(g, "css", "form[action=\"/order\"]", page.css("form[action=\"/order\"]"))
  row(g, "css", "#shop > form", page.css("#shop > form"))
  row(g, "css", "article :is(form)", page.css("article :is(form)"))
  row(g, "xpath", "//form", page.xpath("//form"))
  row(g, "xpath", "//*[@action]", page.xpath("//*[@action]"))
}

// ------------------------------------------------------------------ printing

///|
/// One query, its answer written the way the page shows it.
fn row(
  group : String,
  engine : String,
  query : String,
  found : @moonxml.Selection,
) -> Unit {
  println(
    "row\t" +
    group +
    "\t" +
    engine +
    "\t" +
    one_line(query) +
    "\t" +
    found.length().to_string() +
    "\t" +
    describe(found),
  )
}

///|
/// One value taken out of the tree: a text, an attribute, some markup, or
/// XPath's answer.
fn value(
  kind : String,
  engine : String,
  query : String,
  answer : String,
) -> Unit {
  // A value that is markup is shown as one flowing line: the table has no
  // room for indentation, and the point is what the markup says.
  println(
    "row\t" +
    kind +
    "\t" +
    engine +
    "\t" +
    one_line(query) +
    "\t\t" +
    one_line(squeeze(answer)),
  )
}

///|
/// What a selection holds, one label per node.
fn describe(found : @moonxml.Selection) -> String {
  if found.length() == 0 {
    return "nothing"
  }
  let out = StringBuilder()
  let mut k = 0
  let shown = if found.length() > 6 { 5 } else { found.length() }
  while k < shown {
    if k > 0 {
      out.write_string(" · ")
    }
    out.write_string(label(found.items[k]))
    k = k + 1
  }
  if found.length() > shown {
    out.write_string(" · +")
    out.write_string((found.length() - shown).to_string())
  }
  out.to_string()
}

///|
/// How a node reads in a table: its name, its id and first class, and the text
/// it holds.
fn label(node : @moonxml.Node) -> String {
  match node {
    @moonxml.ElementNode(data) => {
      let mut out = data.name
      match data.attr("id") {
        Some(id) => out = out + "#" + id
        None => ()
      }
      let classes = data.classes()
      if classes.length() > 0 {
        out = out + "." + classes[0]
      }
      let text = squeeze(data.text())
      if !text.is_empty() && text.length() <= 28 {
        out = out + " " + quote(text)
      }
      out
    }
    @moonxml.TextNode(text) =>
      if squeeze(text).is_empty() {
        "#text (blank)"
      } else {
        "#text " + quote(squeeze(text))
      }
    @moonxml.CDataNode(text) => "#cdata " + quote(squeeze(text))
    @moonxml.CommentNode(_) => "<!-- -->"
    @moonxml.ProcessingInstructionNode(pi) => "<?" + pi.target + "?>"
    @moonxml.DoctypeNode(text) => "<!DOCTYPE " + text + ">"
  }
}

///|
/// A value as the page shows it, shortened so a row stays a row.
fn quote(text : String) -> String {
  let flat = squeeze(text)
  let cut = if flat.length() > 34 {
    flat[0:33].to_owned() + "…"
  } else {
    flat
  }
  "\"" + cut + "\""
}

///|
/// Text on one line, with runs of whitespace folded into one space.
fn squeeze(text : String) -> String {
  let out = StringBuilder()
  let mut space = false
  for ch in text {
    if ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r' {
      space = true
      continue
    }
    if space && out.to_string().length() > 0 {
      out.write_char(' ')
    }
    space = false
    out.write_char(ch)
  }
  out.to_string().trim().to_owned()
}

///|
fn one_line(text : String) -> String {
  let out = StringBuilder()
  for ch in text {
    if ch == '\n' {
      out.write_string("\\n")
    } else if ch == '\t' {
      out.write_string("\\t")
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// A number written in a decimal string, for the price comparison.
fn number(text : String) -> Int32 {
  let mut value = 0
  for ch in text {
    if ch >= '0' && ch <= '9' {
      value = value * 10 + (ch.to_int() - '0'.to_int())
    }
  }
  value
}
