// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A request htmx would have made: the verb, the address, what it carries,
/// and how the answer is put back.
///
/// Nothing here is sent. A caller reads this, sends it however it likes, and
/// hands the answer to `answer`.
pub(all) struct Request {
  /// `get`, `post`, `put`, `patch` or `delete`.
  verb : String
  /// The address, without the query: `Hx::url` as it was written.
  url : String
  /// The element that asked.
  element : @moonxml.Element
  /// Where the answer goes.
  target : @moonxml.Element
  /// What the request carries, as a form would.
  values : Array[(String, String)]
  /// The headers the element declared.
  headers : Array[(String, String)]
  /// How the answer is put in.
  swap : SwapSpec
  /// The part of the answer to use, when the element asked for a part.
  select : String?
  /// The question to put to the user first, when there is one.
  confirm : String?
  /// Whether the address bar should follow.
  push_url : Bool?
  /// The event that fired.
  trigger : String
}

///|
/// The request an event on this element would make, or `None` when it would
/// make none: no verb, no address, or a trigger that is about something else.
pub fn Hx::request(self : Hx, event : String) -> Request? {
  let mut fired = false
  for trigger in self.triggers() {
    if trigger.matches(event) {
      fired = true
    }
  }
  if !fired {
    return None
  }
  let verb = match self.verb() {
    Some(found) => found
    None => return None
  }
  let url = match self.url() {
    Some(found) => found
    None => return None
  }
  let target = match self.target() {
    Some(found) => found
    None => return None
  }
  Some({
    verb,
    url,
    element: self.element,
    target,
    values: self.values(),
    headers: self.headers(),
    swap: match self.attr("swap") {
      Some(spec) => SwapSpec::parse(spec)
      None => SwapSpec::new()
    },
    select: self.select(),
    confirm: self.confirm(),
    push_url: self.push_url(),
    trigger: event,
  })
}

///|
/// The address to send to: a `get` carries its values in the query, and the
/// other verbs carry them in the body, so only a `get` has them added here.
pub fn Request::address(self : Request) -> String {
  let query = self.query()
  if self.verb != "get" || query.is_empty() {
    return self.url
  }
  if self.url.contains("?") {
    self.url + "&" + query
  } else {
    self.url + "?" + query
  }
}

///|
/// The values as `application/x-www-form-urlencoded` text, without the `?`.
pub fn Request::query(self : Request) -> String {
  let out = StringBuilder()
  let mut first = true
  for pair in self.values {
    if !first {
      out.write_char('&')
    }
    first = false
    out.write_string(percent(pair.0))
    out.write_char('=')
    out.write_string(percent(pair.1))
  }
  out.to_string()
}

///|
/// The headers to send: what the element declared, and the four htmx adds so
/// that a server knows what it is answering.
pub fn Request::headers(self : Request) -> Array[(String, String)] {
  let out = self.headers.copy()
  out.push(("HX-Request", "true"))
  match self.element.attr("id") {
    Some(id) => out.push(("HX-Trigger", id))
    None => ()
  }
  match self.element.attr("name") {
    Some(name) => out.push(("HX-Trigger-Name", name))
    None => ()
  }
  match self.target.attr("id") {
    Some(id) => out.push(("HX-Target", id))
    None => ()
  }
  out
}

///|
/// Form-urlencoded escaping: everything but the unreserved characters, and a
/// space as `+`.
fn percent(text : String) -> String {
  let out = StringBuilder()
  for ch in text {
    let code = ch.to_int()
    let unreserved = (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '-' ||
      ch == '_' ||
      ch == '.' ||
      ch == '~'
    if unreserved {
      out.write_char(ch)
    } else if ch == ' ' {
      out.write_char('+')
    } else {
      out.write_char('%')
      out.write_string(hex_digit(code / 16))
      out.write_string(hex_digit(code % 16))
    }
  }
  out.to_string()
}

///|
fn hex_digit(value : Int32) -> String {
  let digit = value % 16
  if digit < 10 {
    (digit + '0'.to_int()).unsafe_to_char().to_string()
  } else {
    (digit - 10 + 'A'.to_int()).unsafe_to_char().to_string()
  }
}
