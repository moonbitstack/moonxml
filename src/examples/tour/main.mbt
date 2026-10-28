// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The whole surface in one run, so a reader can see what this is for before
/// reading any of it:
///
///     moon run examples/tour
///
/// Every step prints what it did, in the order the README introduces them.
#coverage.skip
fn main {
  try {
    html_parse()
    chain()
    edit()
    xml_query()
    stream()
    custom_selector()
  } catch {
    error => println("refused: \{error}")
  }
}

///|
fn rule(title : String) -> Unit {
  let dashes = StringBuilder()
  for _k = 0; _k < 58 - title.length(); _k = _k + 1 {
    dashes.write_char('-')
  }
  println("")
  println("-- \{title} \{dashes}")
}

///|
fn html_parse() -> Unit raise @moonxml.Refused {
  rule("read a page the way a browser reads it")
  let page = @html.loads(
    "<!DOCTYPE html><title>Shop</title><ul id=list><li>coffee<li>tea</ul>",
  )
  println("li elements the document never closed: \{page.css("li").length()}")
  println("elements the parser had to imply: \{page.repairs().implied}")
  println("written back: \{page.dumps()}")
}

///|
fn chain() -> Unit raise @moonxml.Refused {
  rule("query: css, xpath, and both at once")
  let page = @html.loads(
    "<div id=main><p class=a>one</p><p class=b>two</p><span><p>three</p></span></div>",
  )
  println("css   #main p          -> \{page.css("#main p").length()} nodes")
  println("xpath //p[@class=a]    -> \{page.xpath("//p[@class='a']").text()}")
  println("css then xpath         -> \{page.css("span").xpath(".//p").text()}")
  println(
    "chain into a node      -> \{page.css("#main").items[0].css("p").first().text()}",
  )
  println(
    "children of the div   -> \{page.css("#main").children().length()} nodes",
  )
  println(
    "xpath answering a number -> count(//p) answers \{page.xpath_value("count(//p)")}",
  )
}

///|
fn edit() -> Unit raise @moonxml.Refused {
  rule("edit the one tree")
  let page = @html.loads("<ul><li>one</li><li>two</li></ul>")
  page.css("li").first().set_text("edited")
  page.css("li").last().add_class("last")
  let extra = @moonxml.Element::new("li", children=[@moonxml.TextNode("three")])
  page.css("ul").append(@moonxml.ElementNode(extra))
  page.css("li").last().wrap("strong")
  println(page.dumps())
}

///|
fn xml_query() -> Unit raise @moonxml.Refused {
  rule("xml, strictly, and back out byte for byte")
  let source = "<feed xmlns:a=\"urn:a\"><a:entry id=\"1\"><title>One</title></a:entry></feed>"
  let feed = @xml.loads(source)
  println("names are {uri}local_name   : \{feed.css("entry").items[0].name()}")
  println("query by space     : \{feed.css("{urn:a}entry").length()} node")
  println("round trip is exact    : \{feed.dumps() == source}")
}

///|
/// A sink that counts start tags: the point of the event stream is that a
/// consumer need not build a tree at all.
struct Counter {
  mut tags : Int32
}

///|
fn Counter::new() -> Counter {
  { tags: 0, }
}

///|
impl @event.Sink for Counter with fn push(self, event) {
  match event {
    @event.StartTag(_) => self.tags = self.tags + 1
    _ => ()
  }
}

///|
fn stream() -> Unit raise @moonxml.Refused {
  rule("stream events without building a tree")
  let counting = Counter::new()
  @xml.scan("<a><b/><c/></a>", counting)
  println("start tags seen: \{counting.tags}")
  let page = @xml.loads("<a><b>1</b></a>")
  println("events a finished tree yields: \{page.events().length()}")
}

///|
fn custom_selector() -> Unit raise @moonxml.Refused {
  rule("your own selector, in the same chain")
  let page = @html.loads("<a href=https://x>out</a><a href=/in>in</a>")
  page.register(
    "external",
    @moonxml.SelectorFn::new((ctx, _query) => {
      ctx
      .css("a[href]")
      .filter(fn(node) {
        match node {
          @moonxml.ElementNode(data) =>
            match data.attr("href") {
              Some(href) => href.has_prefix("https://")
              None => false
            }
          _ => false
        }
      })
    }),
  )
  println(
    "a, then the registered selector: \{page.selector("external", "").text()}",
  )
}
