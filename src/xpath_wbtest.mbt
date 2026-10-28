// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// XPath 1.0 against a document with mixed content, nested lists, an
/// attribute or two and a comment: the grammar, every axis, the predicates,
/// the operator precedence, the core function library and the typed answer.
fn library() -> Document {
  let doc = Document::new(flavour=Xml)
  let catalog = Element::new("catalog", attrs=[("lang", "en")])
  let book1 = Element::new("book", attrs=[("id", "b1"), ("year", "1998")])
  let title1 = Element::new("title", children=[TextNode("Lions")])
  let author1 = Element::new("author", children=[TextNode("Ann")])
  let price1 = Element::new("price", children=[TextNode("29.5")])
  let book2 = Element::new("book", attrs=[("id", "b2"), ("year", "2004")])
  let title2 = Element::new("title", children=[TextNode("Tigers")])
  let author2 = Element::new("author", children=[TextNode("Bo")])
  let price2 = Element::new("price", children=[TextNode("12.0")])
  let note = Element::new("note", children=[
    CommentNode("draft"),
    TextNode("draft text"),
  ])
  doc.root.append(ElementNode(catalog))
  catalog.append(ElementNode(book1))
  book1.append(ElementNode(title1))
  book1.append(ElementNode(author1))
  book1.append(ElementNode(price1))
  catalog.append(ElementNode(book2))
  book2.append(ElementNode(title2))
  book2.append(ElementNode(author2))
  book2.append(ElementNode(price2))
  catalog.append(ElementNode(note))
  doc
}

///|
/// Four predicates, so a typed answer reads as one line.
fn XPathValue::is_num(self : XPathValue, wanted : Double) -> Bool {
  match self {
    Num(have) => have == wanted
    _ => false
  }
}

///|
fn XPathValue::is_str(self : XPathValue, wanted : String) -> Bool {
  match self {
    Str(have) => have == wanted
    _ => false
  }
}

///|
fn XPathValue::is_flag(self : XPathValue, wanted : Bool) -> Bool {
  match self {
    Flag(have) => have == wanted
    _ => false
  }
}

///|
fn XPathValue::is_nodes(self : XPathValue, wanted : Int32) -> Bool {
  match self {
    Nodes(sel) => sel.items.length() == wanted
    _ => false
  }
}

///|
/// The names the query answers, joined for comparison.
fn names(doc : Document, query : String) -> String raise Refused {
  let out : Array[String] = []
  for node in doc.xpath(query).items {
    out.push(node.name())
  }
  out.join(",")
}

///|
fn texts(doc : Document, query : String) -> String raise Refused {
  let out : Array[String] = []
  for node in doc.xpath(query).items {
    out.push(node.text())
  }
  out.join(",")
}

///|
test "absolute and relative paths" {
  let doc = library()
  assert_eq(names(doc, "/catalog"), "catalog")
  assert_eq(names(doc, "/catalog/book"), "book,book")
  assert_eq(names(doc, "//book"), "book,book")
  assert_eq(names(doc, "//book/title"), "title,title")
  assert_eq(names(doc, "//book/*"), "title,author,price,title,author,price")
  assert_eq(
    names(doc, "//*"),
    "catalog,book,title,author,price,book,title,author,price,note",
  )
}

///|
test "axes" {
  let doc = library()
  assert_eq(names(doc, "//title/parent::*"), "book,book")
  assert_eq(names(doc, "//title/ancestor::*"), "catalog,book,book")
  assert_eq(
    names(doc, "//title/ancestor-or-self::*"),
    "catalog,book,title,book,title",
  )
  assert_eq(names(doc, "//book/following-sibling::*"), "book,note")
  assert_eq(
    names(doc, "//price/preceding-sibling::*"),
    "title,author,title,author",
  )
  assert_eq(
    names(doc, "//author/following::*"),
    "price,book,title,author,price,note",
  )
  assert_eq(
    names(doc, "//price/preceding::*"),
    "book,title,author,price,title,author",
  )
  assert_eq(names(doc, "/catalog/descendant::price"), "price,price")
  assert_eq(names(doc, "//book/self::book"), "book,book")
  assert_eq(doc.xpath("//book/@id").length(), 2)
  assert_eq(texts(doc, "//book/@id"), "b1,b2")
  assert_eq(doc.xpath("//book/@*").length(), 4)
  assert_eq(texts(doc, "//book/@*"), "b1,1998,b2,2004")
  assert_eq(texts(doc, "//book/attribute::year"), "1998,2004")
  assert_eq(doc.xpath("//note/space::*").length(), 0)
}

///|
test "node tests" {
  let doc = library()
  assert_eq(texts(doc, "//note/text()"), "draft text")
  assert_eq(doc.xpath("//note/comment()").length(), 1)
  assert_eq(doc.xpath("//note/comment()").text(), "draft")
  assert_eq(texts(doc, "//book/node()"), "Lions,Ann,29.5,Tigers,Bo,12.0")
  assert_eq(texts(doc, "//note/processing-instruction()"), "")
  assert_eq(names(doc, "//note/*"), "")
}

///|
test "positional predicates, including on a reverse axis" {
  let doc = library()
  assert_eq(texts(doc, "//book[1]/title"), "Lions")
  assert_eq(texts(doc, "//book[2]/title"), "Tigers")
  assert_eq(texts(doc, "//book[last()]/title"), "Tigers")
  assert_eq(texts(doc, "//book[last()-1]/title"), "Lions")
  assert_eq(texts(doc, "//title[1]"), "Lions,Tigers")
  assert_eq(texts(doc, "//price[position()=2]"), "")
  assert_eq(texts(doc, "(//price)[2]"), "12.0")
  // on a reverse axis the nearest ancestor is position one
  assert_eq(names(doc, "//title/ancestor::*[1]"), "book,book")
  assert_eq(names(doc, "//title/ancestor::*[2]"), "catalog")
  assert_eq(names(doc, "//price/preceding-sibling::*[1]"), "author,author")
}

///|
test "predicates with expressions" {
  let doc = library()
  assert_eq(texts(doc, "//book[@id='b2']/title"), "Tigers")
  assert_eq(texts(doc, "//book[@year>2000]/title"), "Tigers")
  assert_eq(texts(doc, "//book[@year<2000]/title"), "Lions")
  assert_eq(texts(doc, "//book[price>20]/title"), "Lions")
  assert_eq(texts(doc, "//book[title='Tigers']/author"), "Bo")
  assert_eq(texts(doc, "//book[author and price]/title"), "Lions,Tigers")
  assert_eq(texts(doc, "//book[not(@missing)]/title"), "Lions,Tigers")
  assert_eq(names(doc, "//book[contains(@id, 'b')]"), "book,book")
  assert_eq(texts(doc, "//book[starts-with(title, 'Ti')]/title"), "Tigers")
}

///|
test "operators and their precedence" {
  let doc = library()
  assert_eq(doc.xpath_value("1+2*3").is_num(7.0), true)
  assert_eq(doc.xpath_value("(1+2)*3").is_num(9.0), true)
  assert_eq(doc.xpath_value("7 div 2").is_num(3.5), true)
  assert_eq(doc.xpath_value("7 mod 2").is_num(1.0), true)
  assert_eq(doc.xpath_value("2 - 5").is_num(-3.0), true)
  assert_eq(doc.xpath_value("-2 + 5").is_num(3.0), true)
  assert_eq(doc.xpath_value("1 = 1 and 2 = 2").is_flag(true), true)
  assert_eq(doc.xpath_value("1 = 2 or 2 = 2").is_flag(true), true)
  assert_eq(doc.xpath_value("1 < 2").is_flag(true), true)
  assert_eq(doc.xpath_value("2 <= 2").is_flag(true), true)
  assert_eq(doc.xpath_value("3 > 2").is_flag(true), true)
  assert_eq(doc.xpath_value("3 >= 4").is_flag(false), true)
  assert_eq(doc.xpath_value("1 != 2").is_flag(true), true)
  assert_eq(texts(doc, "//book[1]/title | //book[2]/title"), "Lions,Tigers")
  assert_eq(names(doc, "//price | //title"), "title,price,title,price")
}

///|
test "the core function library" {
  let doc = library()
  assert_eq(names(doc, "//book[count(*) = 3]"), "book,book")
  assert_eq(doc.xpath_value("count(//book)").is_num(2.0), true)
  assert_eq(doc.xpath_value("sum(//price)").is_num(41.5), true)
  assert_eq(doc.xpath_value("string(//title)").is_str("Lions"), true)
  assert_eq(
    doc.xpath_value("concat(//title, ' / ', //author)").is_str("Lions / Ann"),
    true,
  )
  assert_eq(doc.xpath_value("substring('abcdef', 2, 3)").is_str("bcd"), true)
  assert_eq(doc.xpath_value("substring('abcdef', 4)").is_str("def"), true)
  assert_eq(doc.xpath_value("substring-before('a-b', '-')").is_str("a"), true)
  assert_eq(doc.xpath_value("substring-after('a-b', '-')").is_str("b"), true)
  assert_eq(doc.xpath_value("string-length('abc')").is_num(3.0), true)
  assert_eq(doc.xpath_value("normalize-space('  a   b  ')").is_str("a b"), true)
  assert_eq(doc.xpath_value("translate('abc', 'ab', 'xy')").is_str("xyc"), true)
  assert_eq(doc.xpath_value("translate('abc', 'a', '')").is_str("bc"), true)
  assert_eq(doc.xpath_value("boolean(//book)").is_flag(true), true)
  assert_eq(doc.xpath_value("not(//missing)").is_flag(true), true)
  assert_eq(doc.xpath_value("true()").is_flag(true), true)
  assert_eq(doc.xpath_value("false()").is_flag(false), true)
  assert_eq(doc.xpath_value("number('12.5')").is_num(12.5), true)
  assert_eq(doc.xpath_value("string(1 div 2)").is_str("0.5"), true)
  assert_eq(doc.xpath_value("string(42)").is_str("42"), true)
  assert_eq(doc.xpath_value("string(1 div 0)").is_str("Infinity"), true)
  assert_eq(doc.xpath_value("string(-1 div 0)").is_str("-Infinity"), true)
  assert_eq(doc.xpath_value("string(0 div 0)").is_str("NaN"), true)
  assert_eq(doc.xpath_value("floor(2.7)").is_num(2.0), true)
  assert_eq(doc.xpath_value("ceiling(2.1)").is_num(3.0), true)
  assert_eq(doc.xpath_value("round(2.5)").is_num(3.0), true)
  assert_eq(doc.xpath_value("round(-2.5)").is_num(-2.0), true)
  assert_eq(doc.xpath_value("name(//book)").is_str("book"), true)
  assert_eq(doc.xpath_value("local-name(//book)").is_str("book"), true)
  assert_eq(doc.xpath_value("space-uri(//book)").is_str(""), true)
  assert_eq(doc.xpath("id('b2')/title/text()").text(), "Tigers")
  assert_eq(doc.xpath_value("lang('en')").is_flag(false), true)
}

///|
test "the string value of a node-set is its first node" {
  let doc = library()
  assert_eq(doc.xpath_value("//title").is_nodes(2), true)
  assert_eq(doc.xpath_value("string(//title)").is_str("Lions"), true)
  assert_eq(doc.xpath_value("//missing").is_nodes(0), true)
  assert_eq(doc.xpath_value("string(//missing)").is_str(""), true)
}

///|
test "number formatting is XPath's, not the language's" {
  let doc = library()
  assert_eq(doc.xpath_value("string(1)").is_str("1"), true)
  assert_eq(doc.xpath_value("string(-0)").is_str("0"), true)
  assert_eq(doc.xpath_value("string(100)").is_str("100"), true)
  assert_eq(doc.xpath_value("string(1.25)").is_str("1.25"), true)
  assert_eq(doc.xpath_value("string(1.0)").is_str("1"), true)
}

///|
test "the chain takes the node-set and the typed answer is separate" {
  let doc = library()
  assert_eq(texts(doc, "//book/title"), "Lions,Tigers")
  assert_eq(texts(doc, "//book/@id"), "b1,b2")
  assert_eq(doc.xpath("//book").length(), 2)
  assert_eq(doc.xpath_value("count(//book)").is_num(2.0), true)
  assert_eq(doc.xpath("string(//title)").text(), "Lions")
  assert_eq(doc.xpath("count(//book)").text(), "2")
}

///|
test "xpath and css narrow the same chain, either way round" {
  let doc = library()
  assert_eq(doc.xpath("//book").css("title").length(), 2)
  assert_eq(doc.css("book").xpath("./title").length(), 2)
  assert_eq(doc.xpath("//book").css("price").xpath(".//text()").length(), 2)
  assert_eq(doc.css("book").xpath("..").length(), 1)
  assert_eq(doc.xpath("//book[1]").css("author").text(), "Ann")
}

///|
test "a context node anchors a relative path" {
  let doc = library()
  let book = doc.xpath("//book").first()
  assert_eq(book.xpath("./title").text(), "Lions")
  assert_eq(book.xpath("author").text(), "Ann")
  assert_eq(book.xpath("../book").length(), 2)
  assert_eq(book.xpath("ancestor::catalog").length(), 1)
}

///|
test "results are deduplicated and in document order" {
  let doc = library()
  assert_eq(doc.xpath("//title | //title").length(), 2)
  assert_eq(doc.xpath("//book | //book").length(), 2)
  assert_eq(names(doc, "//price | //title"), "title,price,title,price")
}

///|
test "a broken expression names the fault" {
  let doc = library()
  let failed = try {
    ignore(doc.xpath("//book["))
    false
  } catch {
    _ => true
  }
  assert_eq(failed, true)
  let failed2 = try {
    ignore(doc.xpath("//book/unknown-axis::x"))
    false
  } catch {
    _ => true
  }
  assert_eq(failed2, true)
  let failed3 = try {
    ignore(doc.xpath("$unbound"))
    false
  } catch {
    _ => true
  }
  assert_eq(failed3, true)
}
