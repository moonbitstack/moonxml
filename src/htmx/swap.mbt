// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where an answer goes. The first six are the ones the DOM can be told to do
/// without asking a stylesheet; `Delete` takes the target away, and `NoSwap`
/// keeps the answer out of the page entirely — for a response that is only
/// out-of-band content.
pub(all) enum Swap {
  Inner
  Outer
  BeforeBegin
  AfterBegin
  BeforeEnd
  AfterEnd
  Delete
  NoSwap
}

///|
/// How an answer goes there: the position, and the timing a page might want
/// to know about.
pub(all) struct SwapSpec {
  /// Where the answer goes.
  mut style : Swap
  /// Milliseconds to wait before showing the new content.
  mut delay : Int32
  /// Milliseconds after the new content is in place before the page is
  /// considered settled.
  mut settle : Int32
  /// Whether the swap should be a CSS transition rather than a change.
  mut transition : Bool
  /// Keep the document's own `<title>` rather than the answer's.
  mut ignore_title : Bool
}

///|
/// The default: the inside of the target, at once.
pub fn SwapSpec::new() -> SwapSpec {
  { style: Inner, delay: 0, settle: 0, transition: false, ignore_title: false, }
}

///|
/// A `hx-swap` spelling: a position and, after it, modifiers.
///
/// `innerHTML`, `outerHTML`, `beforebegin`, `afterbegin`, `beforeend`,
/// `afterend`, `delete` and `none` are the positions; `swap:100ms`,
/// `settle:50ms`, `transition:true` and `ignoreTitle:true` are the modifiers
/// this reader keeps. `scroll:` and `show:` are the page's business, and are
/// read but not carried out.
pub fn SwapSpec::parse(spec : String) -> SwapSpec {
  let out = SwapSpec::new()
  let text = spec.trim().to_owned()
  if text.is_empty() {
    return out
  }
  let mut first = true
  for word in text.split(" ") {
    let piece = word.trim().to_owned()
    if piece.is_empty() {
      continue
    }
    if first {
      first = false
      out.style = match piece.to_lower() {
        "innerhtml" => Inner
        "outerhtml" => Outer
        "beforebegin" => BeforeBegin
        "afterbegin" => AfterBegin
        "beforeend" => BeforeEnd
        "afterend" => AfterEnd
        "delete" => Delete
        "none" => NoSwap
        _ => Inner
      }
      continue
    }
    match piece.find(":") {
      Some(colon) => {
        let key = piece[0:colon].trim().to_lower().to_owned()
        let value = piece[colon + 1:piece.length()].trim().to_owned()
        match key {
          "swap" => out.delay = milliseconds(value)
          "settle" => out.settle = milliseconds(value)
          "transition" => out.transition = truthy(value)
          "ignoretitle" => out.ignore_title = truthy(value)
          _ => ()
        }
      }
      None => ()
    }
  }
  out
}

///|
/// Whether a modifier's value says yes.
fn truthy(value : String) -> Bool {
  let text = value.to_lower()
  text == "true" || text == "1" || text == "yes"
}

///|
/// A duration in milliseconds, the same spellings `hx-trigger` takes.
fn milliseconds(text : String) -> Int32 {
  let value = text.trim().to_owned()
  if value.is_empty() {
    return 0
  }
  let mut end = value.length()
  let mut scale = 1.0
  if value.has_suffix("ms") {
    end = end - 2
  } else if value.has_suffix("s") {
    end = end - 1
    scale = 1000.0
  }
  let number = value[0:end]
  if number.is_empty() {
    return 0
  }
  let mut total = 0.0
  let mut seen_dot = false
  let mut place = 0.1
  for ch in number {
    if ch == '.' && !seen_dot {
      seen_dot = true
      continue
    }
    if ch < '0' || ch > '9' {
      return 0
    }
    let digit = (ch.to_int() - '0'.to_int()).to_double()
    if seen_dot {
      total = total + digit * place
      place = place / 10.0
    } else {
      total = total * 10.0 + digit
    }
  }
  (total * scale).to_int()
}

///|
/// The position as htmx spells it.
pub fn Swap::spec(self : Swap) -> String {
  match self {
    Inner => "innerHTML"
    Outer => "outerHTML"
    BeforeBegin => "beforebegin"
    AfterBegin => "afterbegin"
    BeforeEnd => "beforeend"
    AfterEnd => "afterend"
    Delete => "delete"
    NoSwap => "none"
  }
}
