// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// An element's htmx attributes — its own, or the ones it inherits.
///
/// htmx's attributes travel down the tree: `hx-target` on a container is the
/// target of every button inside it, until something nearer says otherwise or
/// `hx-disinherit` stops the inheritance at a boundary. Reading an attribute
/// through `Hx` is reading it the way htmx would.
pub struct Hx {
  element : @moonxml.Element
}

///|
/// The htmx attributes of `element`, as htmx would see them.
pub fn Hx::of(element : @moonxml.Element) -> Hx {
  { element, }
}

///|
/// The element the attributes were read off.
pub fn Hx::element(self : Hx) -> @moonxml.Element {
  self.element
}

///|
/// The value of `hx-<name>` — `attr("target")` is `hx-target` — inherited
/// from the nearest ancestor that declares it. `None` when nothing does, and
/// when the nearest declaration is `unset`.
pub fn Hx::attr(self : Hx, name : String) -> String? {
  match self.lookup(name) {
    Some((value, _)) => Some(value)
    None => None
  }
}

///|
/// The value and the element that declared it: a relative selector means
/// something different depending on where it was written.
fn Hx::lookup(self : Hx, name : String) -> (String, @moonxml.Element)? {
  let attribute = "hx-" + name
  let mut node : @moonxml.Element? = Some(self.element)
  let mut answer : (String, @moonxml.Element)? = None
  let mut walking = true
  while walking {
    match node {
      Some(current) =>
        match current.attr(attribute) {
          Some(value) =>
            if value.trim().to_owned() == "unset" {
              walking = false
            } else {
              answer = Some((value, current))
              walking = false
            }
          None =>
            // Moving out of `current` to its parent: if `current` disinherits
            // this attribute, nothing above it may be read.
            if disinherits(current, name) {
              walking = false
            } else {
              node = current.parent
            }
        }
      None => walking = false
    }
  }
  answer
}

///|
/// Whether an element stops `name` being inherited past it. `hx-disinherit`
/// names attributes with or without the `hx-`, or says `*` for all of them;
/// `hx-inherit` on the same element names the ones that stay.
fn disinherits(element : @moonxml.Element, name : String) -> Bool {
  let names = match element.attr("hx-disinherit") {
    Some(value) => value
    None => return false
  }
  if names_for(names, name) {
    match element.attr("hx-inherit") {
      Some(allowed) => return !names_for(allowed, name)
      None => ()
    }
    true
  } else {
    false
  }
}

///|
/// Whether a comma-separated list of attribute names covers `name`.
fn names_for(list : String, name : String) -> Bool {
  let text = list.trim()
  if text.is_empty() || text == "*" {
    return true
  }
  for item in text.split(",") {
    let one = item.trim()
    if one == "*" || one == name || one == "hx-" + name {
      return true
    }
  }
  false
}

///|
/// The verb this element asks with, in lower case — `get`, `post`, `put`,
/// `patch` or `delete` — taken from the first of those it declares.
///
/// A boosted link asks with `get` and a boosted form with `post`, which is
/// what `hx-boost` is: an ordinary element that becomes a request.
pub fn Hx::verb(self : Hx) -> String? {
  for verb in ["get", "post", "put", "patch", "delete"] {
    if self.lookup(verb) is Some(_) {
      return Some(verb)
    }
  }
  if self.boosted() {
    match self.element.name {
      "a" => if self.element.has_attr("href") { return Some("get") }
      "form" => if self.element.has_attr("action") { return Some("post") }
      _ => ()
    }
  }
  None
}

///|
/// Where the request goes: the value of the verb's attribute, or the `href`
/// of a boosted link, or the `action` of a boosted form.
pub fn Hx::url(self : Hx) -> String? {
  match self.verb() {
    Some(verb) =>
      match self.attr(verb) {
        Some(value) => Some(value)
        None =>
          if self.boosted() {
            match self.element.name {
              "a" => self.element.attr("href")
              "form" => self.element.attr("action")
              _ => None
            }
          } else {
            None
          }
      }
    None => None
  }
}

///|
/// Whether the element is boosted: `hx-boost="true"` somewhere on the way up.
pub fn Hx::boosted(self : Hx) -> Bool {
  match self.attr("boost") {
    Some(value) => truthy(value)
    None => false
  }
}

///|
/// What an event on this element asks: the `hx-trigger` it declares, or the
/// event an element of its kind listens for when it declares none.
pub fn Hx::triggers(self : Hx) -> Array[Trigger] {
  match self.attr("trigger") {
    Some(spec) => Trigger::list(spec)
    None => [Trigger::default_for(self.element)]
  }
}

///|
/// Where the answer goes: `hx-target`, resolved. A bare selector is looked up
/// in the document; `this`, `closest …`, `find …`, `next …` and `previous …`
/// are resolved from the element that wrote them.
pub fn Hx::target(self : Hx) -> @moonxml.Element? {
  match self.lookup("target") {
    Some((value, declarer)) => resolve_target(declarer, value)
    None => Some(self.element)
  }
}

///|
/// The part of the answer to use: `hx-select`, a selector over the response.
pub fn Hx::select(self : Hx) -> String? {
  self.attr("select")
}

///|
/// The question to ask before asking: `hx-confirm`.
pub fn Hx::confirm(self : Hx) -> String? {
  self.attr("confirm")
}

///|
/// The element that says the request is in flight: `hx-indicator`, resolved
/// the way a target is.
pub fn Hx::indicator(self : Hx) -> @moonxml.Element? {
  match self.lookup("indicator") {
    Some((value, declarer)) => resolve_target(declarer, value)
    None => None
  }
}

///|
/// Whether the address bar should follow: `hx-push-url`. `Some(true)` and
/// `Some(false)` are the two things htmx lets it say, `None` is silence.
pub fn Hx::push_url(self : Hx) -> Bool? {
  match self.attr("push-url") {
    Some(value) => Some(truthy(value))
    None => None
  }
}

///|
/// A target spelling, resolved from the element that wrote it.
fn resolve_target(
  declarer : @moonxml.Element,
  spelling : String,
) -> @moonxml.Element? {
  let text = spelling.trim().to_owned()
  if text.is_empty() || text == "this" {
    return Some(declarer)
  }
  let (command, rest) = match text.find(" ") {
    Some(at) =>
      (
        text[0:at].to_lower().to_owned(),
        text[at + 1:text.length()].trim().to_owned(),
      )
    None => (text.to_lower(), "")
  }
  if rest.is_empty() && command != "this" {
    // A bare word is a selector.
    return first_match(declarer, text)
  }
  match command {
    "this" => Some(declarer)
    "closest" => {
      let found = declarer.closest(rest) catch {
        _ => @moonxml.Selection::new()
      }
      first_element(found)
    }
    "find" => {
      let found = declarer.css(rest) catch { _ => @moonxml.Selection::new() }
      first_element(found)
    }
    "next" => sibling(declarer, rest, 1)
    "previous" => sibling(declarer, rest, -1)
    _ => first_match(declarer, text)
  }
}

///|
/// The first element a selector answers, looked up from the document the
/// declarer is in — or from the declarer's own subtree when it is detached.
fn first_match(
  declarer : @moonxml.Element,
  selector : String,
) -> @moonxml.Element? {
  match declarer.document() {
    Some(doc) => {
      let found = doc.css(selector) catch { _ => @moonxml.Selection::new() }
      first_element(found)
    }
    None => {
      let found = declarer.css(selector) catch {
        _ => @moonxml.Selection::new()
      }
      first_element(found)
    }
  }
}

///|
/// The first element of a selection, if it has one.
fn first_element(found : @moonxml.Selection) -> @moonxml.Element? {
  if found.length() == 0 {
    return None
  }
  match found.items[0] {
    @moonxml.ElementNode(data) => Some(data)
    _ => None
  }
}

///|
/// The sibling `step` places along that matches `selector`, or the nearest
/// sibling when the selector is empty. htmx's `next` and `previous`.
fn sibling(
  element : @moonxml.Element,
  selector : String,
  step : Int32,
) -> @moonxml.Element? {
  let parent = match element.parent {
    Some(here) => here
    None => return None
  }
  let mut at = -1
  let mut k = 0
  while k < parent.children.length() {
    if parent.children[k] is @moonxml.ElementNode(data) &&
      physical_equal(data, element) {
      at = k
      break
    }
    k = k + 1
  }
  if at < 0 {
    return None
  }
  let mut k = at + step
  while k >= 0 && k < parent.children.length() {
    if parent.children[k] is @moonxml.ElementNode(data) {
      if selector.is_empty() || matches(data, selector) {
        return Some(data)
      }
    }
    k = k + step
  }
  None
}

///|
/// Whether an element answers a selector: the nearest match from the element
/// itself is the element.
fn matches(element : @moonxml.Element, selector : String) -> Bool {
  let found = element.closest(selector) catch { _ => @moonxml.Selection::new() }
  match first_element(found) {
    Some(first) => physical_equal(first, element)
    None => false
  }
}
