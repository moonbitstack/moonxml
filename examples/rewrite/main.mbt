// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read a feed, change it, write it back: the edit verbs, and the round trip
/// that proves nothing else moved.
///
///     moon run examples/rewrite
#coverage.skip
fn main raise @moonxml.Refused {
  let source = "<feed version=\"1\"><entry id=\"1\"><title>One</title></entry>" +
    "<entry id=\"2\"><title>Two</title></entry></feed>"
  let feed = @xml.loads(source)

  feed.css("entry").add_class("read")
  for entry in feed.css("entry").items {
    let title = entry.css("title").text()
    entry.css("title").set_text(title + " (read)")
  }
  feed.css("feed").set_attr("count", feed.css("entry").length().to_string())
  println(feed.dumps())

  println("entries: \{feed.css("entry").length()}")
  println("second: \{feed.xpath("//entry[@id='2']/title").text()}")
}
