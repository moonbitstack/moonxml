// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn page(html : String) -> @moonxml.Document {
  @html.loads(html)
}

///|
fn element(doc : @moonxml.Document, selector : String) -> @moonxml.Element {
  let found = doc.css(selector) catch { _ => @moonxml.Selection::new() }
  if found.length() == 0 {
    abort("no element for " + selector)
  }
  match found.items[0] {
    @moonxml.ElementNode(data) => data
    _ => abort("not an element")
  }
}

///|
/// `name=value` for each pair, in order, so a set of values reads as one line.
fn pairs(values : Array[(String, String)]) -> String {
  let out = StringBuilder()
  for pair in values {
    if out.to_string().length() > 0 {
      out.write_char(' ')
    }
    out.write_string(pair.0 + "=" + pair.1)
  }
  out.to_string()
}

///|
test "a trigger is the event and the modifiers after it" {
  let simple = Trigger::parse("click")
  assert_eq(simple.event, "click")
  assert_eq(simple.delay, 0)
  let keyed = Trigger::parse("keyup[key=='Enter'] changed delay:500ms once")
  assert_eq(keyed.event, "keyup")
  assert_eq(keyed.filter, Some("key=='Enter'"))
  assert_eq(keyed.changed, true)
  assert_eq(keyed.once, true)
  assert_eq(keyed.delay, 500)
  let polling = Trigger::parse("every 2s")
  assert_eq(polling.event, "every 2s")
  let from = Trigger::parse("input from:closest form queue:last")
  assert_eq(from.from, Some("closest form"))
  assert_eq(from.queue, Some("last"))
}

///|
test "a trigger list splits on the commas outside a condition" {
  let triggers = Trigger::list("click, keyup[key=='a,b'] throttle:1s")
  assert_eq(triggers.length(), 2)
  assert_eq(triggers[1].event, "keyup")
  assert_eq(triggers[1].filter, Some("key=='a,b'"))
  assert_eq(triggers[1].throttle, 1000)
}

///|
test "what an element listens for when it says nothing" {
  let doc = page(
    "<form><input name=q><select name=s></select><button></button></form>",
  )
  assert_eq(Trigger::default_for(element(doc, "form")).event, "submit")
  assert_eq(Trigger::default_for(element(doc, "input")).event, "change")
  assert_eq(Trigger::default_for(element(doc, "button")).event, "click")
}

///|
test "a swap is a position and its timing" {
  let plain = SwapSpec::parse("")
  assert_eq(plain.style.spec(), "innerHTML")
  let outer = SwapSpec::parse("outerHTML")
  assert_eq(outer.style.spec(), "outerHTML")
  let timed = SwapSpec::parse(
    "beforeend swap:100ms settle:50ms transition:true",
  )
  assert_eq(timed.style.spec(), "beforeend")
  assert_eq(timed.delay, 100)
  assert_eq(timed.settle, 50)
  assert_eq(timed.transition, true)
  assert_eq(SwapSpec::parse("delete").style.spec(), "delete")
  assert_eq(SwapSpec::parse("none").style.spec(), "none")
}

///|
test "an attribute is inherited until something nearer says otherwise" {
  let doc = page(
    "<div hx-target='#out' hx-confirm='sure?'><button id='b' hx-get='/go'></button></div><div id='out'></div>",
  )
  let button = element(doc, "#b")
  let hx = Hx::of(button)
  assert_eq(hx.attr("target"), Some("#out"))
  assert_eq(hx.attr("confirm"), Some("sure?"))
  // the button's own verb wins, and there is no inherited one to win over it
  assert_eq(hx.verb(), Some("get"))
  assert_eq(hx.url(), Some("/go"))
  match hx.target() {
    Some(target) => assert_eq(target.attr("id"), Some("out"))
    None => assert_eq(true, false)
  }
}

///|
test "unset and hx-disinherit both stop the inheritance" {
  let doc = page(
    "<section hx-target='#a'><div hx-disinherit='target'><button id='b' hx-get='/go'></button></div><button id='c' hx-get='/go' hx-confirm='unset' hx-target='unset'></button></section>",
  )
  let inside = element(doc, "#b")
  assert_eq(Hx::of(inside).attr("target"), None)
  let unset = element(doc, "#c")
  assert_eq(Hx::of(unset).attr("target"), None)
  // a target of its own still resolves to itself
  match Hx::of(unset).target() {
    Some(target) => assert_eq(target.attr("id"), Some("c"))
    None => assert_eq(true, false)
  }
}

///|
test "a boosted link is a request" {
  let doc = page("<div hx-boost='true'><a id='x' href='/page'>next</a></div>")
  let link = element(doc, "#x")
  assert_eq(Hx::of(link).boosted(), true)
  assert_eq(Hx::of(link).verb(), Some("get"))
  assert_eq(Hx::of(link).url(), Some("/page"))
}

///|
test "a target is resolved from the element that wrote it" {
  let doc = page(
    "<div id='box'><p id='first'></p><p id='second'></p><span id='third'></span><button id='b' hx-get='/go' hx-target='closest div'></button></div>",
  )
  let button = element(doc, "#b")
  match Hx::of(button).target() {
    Some(target) => assert_eq(target.attr("id"), Some("box"))
    None => assert_eq(true, false)
  }
  let relative = page(
    "<div><p id='one'></p><p id='two'></p><button id='go' hx-get='/x' hx-target='previous p'></button></div>",
  )
  match Hx::of(element(relative, "#go")).target() {
    Some(target) => assert_eq(target.attr("id"), Some("two"))
    None => assert_eq(true, false)
  }
}

///|
test "a form sends the controls a form sends" {
  let doc = page(
    "<form id='f' hx-post='/save'>" +
    "<input name='a' value='1'>" +
    "<input type='checkbox' name='yes' checked>" +
    "<input type='checkbox' name='no'>" +
    "<input name='skip' value='x' disabled>" +
    "<select name='pick'><option value='first'>First</option><option value='second' selected>Second</option></select>" +
    "<textarea name='note'>hello</textarea>" +
    "</form>",
  )
  let values = Hx::of(element(doc, "#f")).values()
  assert_eq(pairs(values), "a=1 yes=on pick=second note=hello")
}

///|
test "hx-vals is added over the fields, and hx-params decides what stays" {
  let doc = page(
    "<form id='f' hx-post='/save' hx-vals='{\"a\": \"9\", \"extra\": \"two words\"}'>" +
    "<input name='a' value='1'><input name='b' value='2'></form>",
  )
  assert_eq(
    pairs(Hx::of(element(doc, "#f")).values()),
    "a=9 b=2 extra=two words",
  )
  let kept = page(
    "<form id='f' hx-post='/save' hx-params='not b'><input name='a' value='1'><input name='b' value='2'></form>",
  )
  assert_eq(pairs(Hx::of(element(kept, "#f")).values()), "a=1")
}

///|
test "hx-include adds the fields its selector answers" {
  let doc = page(
    "<input id='q' name='q' value='cat'><form id='f' hx-post='/s' hx-include='#q'><input name='a' value='1'></form>",
  )
  assert_eq(pairs(Hx::of(element(doc, "#f")).values()), "q=cat a=1")
}

///|
test "a request is made by the event it listens for" {
  let doc = page(
    "<button id='b' hx-get='/search' hx-target='#out' hx-vals='{\"q\": \"hello world\"}'>go</button><div id='out'></div>",
  )
  let button = element(doc, "#b")
  let made = Hx::of(button).request("click")
  assert_eq(made is None, false)
  let request = made.unwrap()
  assert_eq(request.verb, "get")
  assert_eq(request.address(), "/search?q=hello+world")
  // an event it does not listen for makes no request
  assert_eq(Hx::of(button).request("submit") is None, true)
  // a post keeps its values out of the address
  let post = page(
    "<form id='f' hx-post='/save'><input name='a' value='1'></form>",
  )
  let form = element(post, "#f")
  let made = Hx::of(form).request("submit").unwrap()
  assert_eq(made.address(), "/save")
  assert_eq(made.query(), "a=1")
}

///|
test "the headers carry what a server needs to know" {
  let doc = page(
    "<button id='b' name='go' hx-get='/x' hx-target='#out' hx-headers='{\"X-From\": \"htmx\"}'>go</button><div id='out'></div>",
  )
  let request = Hx::of(element(doc, "#b")).request("click").unwrap()
  let headers = pairs(request.headers())
  assert_eq(headers.contains("X-From=htmx"), true)
  assert_eq(headers.contains("HX-Request=true"), true)
  assert_eq(headers.contains("HX-Trigger=b"), true)
  assert_eq(headers.contains("HX-Trigger-Name=go"), true)
  assert_eq(headers.contains("HX-Target=out"), true)
}

///|
test "an answer is swapped in at the position the element asked for" {
  let doc = page(
    "<div id='list'><p>old</p></div><button id='b' hx-get='/x' hx-target='#list'>go</button>",
  )
  let request = Hx::of(element(doc, "#b")).request("click").unwrap()
  let kept = request.answer("<p>new</p><p>again</p>")
  assert_eq(kept.length(), 2)
  assert_eq(
    doc.dumps_html().contains("<div id=\"list\"><p>new</p><p>again</p></div>"),
    true,
  )
}

///|
test "outerHTML replaces the target, and beforeend adds after it" {
  let doc = page(
    "<div id='box'>old</div><button id='b' hx-get='/x' hx-target='#box' hx-swap='outerHTML'>go</button>",
  )
  let request = Hx::of(element(doc, "#b")).request("click").unwrap()
  ignore(request.answer("<span id='fresh'>new</span>"))
  assert_eq(doc.dumps_html().contains("<span id=\"fresh\">new</span>"), true)
  assert_eq(doc.dumps_html().contains("id=\"box\""), false)

  let list = page(
    "<ul id='items'><li>one</li></ul><button id='b' hx-get='/x' hx-target='#items' hx-swap='beforeend'>go</button>",
  )
  let add = Hx::of(element(list, "#b")).request("click").unwrap()
  ignore(add.answer("<li>two</li><li>three</li>"))
  assert_eq(
    list.dumps_html().contains("<li>one</li><li>two</li><li>three</li>"),
    true,
  )
}

///|
test "hx-select takes a part of the answer" {
  let doc = page(
    "<div id='out'></div><button id='b' hx-get='/x' hx-target='#out' hx-select='#wanted'>go</button>",
  )
  let request = Hx::of(element(doc, "#b")).request("click").unwrap()
  ignore(
    request.answer("<div><p id='wanted'>this one</p><p>not this</p></div>"),
  )
  assert_eq(doc.dumps_html().contains("this one"), true)
  assert_eq(doc.dumps_html().contains("not this"), false)
}

///|
test "an out-of-band element goes to the id it names, not into the target" {
  let doc = page(
    "<span id='badge'>0</span><div id='out'></div>" +
    "<button id='b' hx-get='/x' hx-target='#out'>go</button>",
  )
  let request = Hx::of(element(doc, "#b")).request("click").unwrap()
  ignore(
    request.answer("<p>main</p><span id='badge' hx-swap-oob='true'>7</span>"),
  )
  assert_eq(doc.dumps_html().contains("<span id=\"badge\">7</span>"), true)
  // and it is not also part of what went into the target
  assert_eq(
    doc.dumps_html().contains("<div id=\"out\"><p>main</p></div>"),
    true,
  )
}

///|
test "a request outside a document answers nothing rather than failing" {
  let loose = @moonxml.Element::new("div")
  assert_eq(Hx::of(loose).verb() is None, true)
  assert_eq(Hx::of(loose).request("click") is None, true)
}
