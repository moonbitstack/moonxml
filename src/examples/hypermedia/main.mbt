// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a hypermedia page declares, and what happens when someone uses it.
///
///     moon run examples/hypermedia
///
/// The page is read, the request a click would make is described, and an
/// answer is put where the page said it goes. Nothing is sent and nothing is
/// awaited: those are the two things a library cannot do for you.
#coverage.skip
fn main {
  run() catch {
    error => println("refused: \{error}")
  }
}

///|
fn run() -> Unit raise @moonxml.Refused {
  let page = @html.loads(
    "<main>" +
    "<form id='add' hx-post='/todos' hx-target='#list' hx-swap='beforeend' hx-vals='{\"owner\": \"you\"}'>" +
    "<input name='title' value='write it down'>" +
    "<select name='priority'><option value='low'>Low</option><option value='high' selected>High</option></select>" +
    "<button>Add</button>" +
    "</form>" +
    "<ul id='list'><li>first</li></ul>" +
    "<span id='count'>1</span>" +
    "<button id='refresh' hx-get='/todos' hx-target='#list' hx-swap='innerHTML' hx-trigger='click, every 30s'>Refresh</button>" +
    "</main>",
  )
  let form = element(page, "#add")
  println("the form posts to \{@htmx.Hx::of(form).url().unwrap()}")
  let request = @htmx.Hx::of(form).request("submit").unwrap()
  println("it carries: \{request.query()}")
  println("it sends:   \{request.verb.to_upper()} \{request.address()}")
  println("headers:    \{headers_text(request)}")
  let answer = "<li>second</li><span id='count' hx-swap-oob='true'>2</span>"
  println(
    "an answer of \{answer.length()} bytes lands in \{request.target.attr("id").unwrap()}",
  )
  ignore(request.answer(answer))
  println("the page now says: \{page.css("ul").html()}")
  println("the badge says:    \{page.css("#count").text()}")
  let refresh = element(page, "#refresh")
  println(
    "the refresh button listens for \{triggers_text(@htmx.Hx::of(refresh).triggers())}",
  )
  println(
    "and a click on it is a request: \{@htmx.Hx::of(refresh).request("click") is Some(_)}",
  )
  println(
    "an event it never listens for is not: \{@htmx.Hx::of(refresh).request("keyup") is Some(_)}",
  )
}

///|
fn element(
  page : @moonxml.Document,
  selector : String,
) -> @moonxml.Element raise @moonxml.Refused {
  let found = page.css(selector)
  match found.items[0] {
    @moonxml.ElementNode(data) => data
    _ => abort("no element")
  }
}

///|
fn headers_text(request : @htmx.Request) -> String {
  let out = StringBuilder()
  for pair in request.headers() {
    if out.to_string().length() > 0 {
      out.write_string(", ")
    }
    out.write_string(pair.0 + ": " + pair.1)
  }
  out.to_string()
}

///|
fn triggers_text(triggers : Array[@htmx.Trigger]) -> String {
  let out = StringBuilder()
  for trigger in triggers {
    if out.to_string().length() > 0 {
      out.write_string(" and ")
    }
    out.write_string(trigger.event)
  }
  out.to_string()
}
