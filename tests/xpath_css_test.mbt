test "xpath basic" {
  let doc = sample()
  assert_eq(doc.xpath("//li").length(), 3)
  assert_eq(doc.xpath("//li[2]").text(), "2")
  assert_eq(doc.xpath("//li[@class=\"last\"]").text(), "3")
  assert_eq(doc.xpath("//li[last()]").text(), "3")
  assert_eq(doc.xpath("//li[position()=2]").text(), "2")
  assert_eq(doc.xpath("//ul/li").length(), 3)
  assert_eq(doc.xpath("//div//li").length(), 3)
}

test "xpath axes" {
  let doc = sample()
  assert_eq(doc.xpath("//li[1]/following-sibling::*").length(), 2)
  assert_eq(doc.xpath("//li[3]/preceding-sibling::*").length(), 2)
  assert_eq(doc.xpath("//li[1]/parent::ul").length(), 1)
  assert_eq(doc.xpath("//li[1]/ancestor::div").length(), 1)
  assert_eq(doc.xpath("//ul/descendant-or-self::*").length(), 4)
}

test "xpath functions and operators" {
  let doc = sample()
  assert_eq(doc.xpath("count(//li)").text(), "3")
  assert_eq(doc.xpath("sum(//li)").text(), "6")
  assert_eq(doc.xpath("string(//li[1])").text(), "1")
  assert_eq(doc.xpath("//li[contains(text(),\"2\")]").length(), 1)
  assert_eq(doc.xpath("//li[starts-with(text(),\"1\")]").length(), 1)
  assert_eq(doc.xpath("concat(\"a\",\"b\")").text(), "ab")
  assert_eq(doc.xpath("normalize-space(\"  a  b \")").text(), "a b")
  assert_eq(doc.xpath("//li[1] | //p").length(), 2)
  assert_eq(doc.xpath("//li[.=\"2\"]").length(), 1)
  assert_eq(doc.xpath("boolean(//li)").text(), "true")
  assert_eq(doc.xpath("not(//zzz)").text(), "true")
}

test "xpath typed value" {
  let doc = sample()
  match doc.xpath_value("count(//li)") {
    @moonxml.XPathValue::Num(d) => assert_eq(d, 3.0)
    _ => assert_eq(false, true)
  }
  match doc.xpath_value("//li") {
    @moonxml.XPathValue::Nodes(s) => assert_eq(s.length(), 3)
    _ => assert_eq(false, true)
  }
  match doc.xpath_value("string(//li[1])") {
    @moonxml.XPathValue::Str(s) => assert_eq(s, "1")
    _ => assert_eq(false, true)
  }
}

test "css basics" {
  let doc = sample()
  assert_eq(doc.css("#a").length(), 1)
  assert_eq(doc.css(".last").length(), 1)
  assert_eq(doc.css("ul > li").length(), 3)
  assert_eq(doc.css("li + li").length(), 2)
  assert_eq(doc.css("li ~ li").length(), 2)
  assert_eq(doc.css("li:first-child").text(), "1")
  assert_eq(doc.css("li:last-child").text(), "3")
  assert_eq(doc.css("li:nth-child(2)").text(), "2")
  assert_eq(doc.css("li:nth-child(2n+1)").length(), 2)
  assert_eq(doc.css("li:not(.last)").length(), 2)
  assert_eq(doc.css("div:has(ul)").length(), 1)
}

test "css attribute selectors" {
  let doc = sample()
  assert_eq(doc.css("[class]").length(), 1)
  assert_eq(doc.css("[class~=last]").length(), 1)
  assert_eq(doc.css("[class^=la]").length(), 1)
  assert_eq(doc.css("[class$=st]").length(), 1)
  assert_eq(doc.css("[class*=as]").length(), 1)
  assert_eq(doc.css(":is(ul, p)").length(), 2)
  assert_eq(doc.css(":where(ul)").length(), 1)
}
