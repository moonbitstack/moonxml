// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A page in, a table out: the shape of every scraping job.
///
///     moon run examples/scrape
#coverage.skip
fn main raise @moonxml.Refused {
  let page = @html.loads(
    "<table id=prices><thead><tr><th>item<th>price</thead>" +
    "<tbody><tr><td>coffee<td>4.50<tr><td>tea<td>3.00<tr><td>cocoa<td>5.25</tbody></table>",
  )
  println("item,price")
  for row in page.css("#prices tbody tr").items {
    let cells = row.css("td")
    println("\{cells.first().text()},\{cells.last().text()}")
  }
  let mut total = 0.0
  for cell in page.css("td:last-child").items {
    total = total + parse_price(cell.text())
  }
  println("total,\{total}")
}

///|
fn parse_price(text : String) -> Double {
  @string.parse_double(text) catch {
    _ => 0.0
  }
}
