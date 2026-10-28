// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The values this element's request carries: what `hx-include` names, the
/// element's own fields, and `hx-vals` over the top of them.
///
/// A form contributes every control inside it that has a name and is not
/// disabled; a field contributes itself; `hx-include` adds the fields of
/// whatever its selectors answer. `hx-params` then keeps or drops names, the
/// way a server would expect.
pub fn Hx::values(self : Hx) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  match self.attr("include") {
    Some(list) =>
      for item in list.split(",") {
        let one = item.trim().to_owned()
        if one.is_empty() {
          continue
        }
        match resolve_target(self.element, one) {
          Some(element) => collect_controls(element, out)
          None => ()
        }
      }
    None => ()
  }
  if self.element.name == "form" {
    collect_controls(self.element, out)
  } else {
    control_value(self.element, out)
  }
  match self.attr("vals") {
    Some(text) =>
      if !text.has_prefix("js:") {
        for pair in json_members(text) {
          set_value(out, pair.0, pair.1)
        }
      }
    None => ()
  }
  match self.attr("params") {
    Some(spec) => filter_params(out, spec)
    None => out
  }
}

///|
/// The headers this element's request carries: `hx-headers`, a JSON object.
pub fn Hx::headers(self : Hx) -> Array[(String, String)] {
  match self.attr("headers") {
    Some(text) => json_members(text)
    None => []
  }
}

///|
/// Set a name, replacing the value it already has: `hx-vals` wins over the
/// fields it is written beside.
fn set_value(
  pairs : Array[(String, String)],
  name : String,
  value : String,
) -> Unit {
  let mut k = 0
  while k < pairs.length() {
    if pairs[k].0 == name {
      pairs[k] = (name, value)
      return
    }
    k = k + 1
  }
  pairs.push((name, value))
}

///|
/// `hx-params`: `*` keeps everything, `none` keeps nothing, `not a, b` drops
/// those names, and a bare list keeps only them.
fn filter_params(
  pairs : Array[(String, String)],
  spec : String,
) -> Array[(String, String)] {
  let text = spec.trim()
  if text == "*" || text.is_empty() {
    return pairs
  }
  if text.to_lower() == "none" {
    return []
  }
  let dropping = text.to_lower().has_prefix("not ")
  let body = if dropping { text[4:text.length()].trim() } else { text }
  let names : Array[String] = []
  for item in body.split(",") {
    names.push(item.trim().to_owned())
  }
  let out : Array[(String, String)] = []
  for pair in pairs {
    if names.contains(pair.0) != dropping {
      out.push(pair)
    }
  }
  out
}

///|
/// Every control in this element and under it, in document order.
fn collect_controls(
  element : @moonxml.Element,
  out : Array[(String, String)],
) -> Unit {
  control_value(element, out)
  for child in element.children {
    if child is @moonxml.ElementNode(data) {
      collect_controls(data, out)
    }
  }
}

///|
/// One element's own contribution: nothing unless it is a control with a name
/// that a form would send.
fn control_value(
  element : @moonxml.Element,
  out : Array[(String, String)],
) -> Unit {
  if element.has_attr("disabled") {
    return
  }
  let name = match element.attr("name") {
    Some(value) => value
    None => return
  }
  if name.is_empty() {
    return
  }
  match element.name {
    "input" => {
      let kind = match element.attr("type") {
        Some(value) => value.to_lower()
        None => "text"
      }
      match kind {
        "submit" | "button" | "reset" | "file" | "image" => return
        "checkbox" | "radio" => if !element.has_attr("checked") { return }
        _ => ()
      }
      let value = match element.attr("value") {
        Some(found) => found
        None => if kind == "checkbox" || kind == "radio" { "on" } else { "" }
      }
      out.push((name, value))
    }
    "textarea" => out.push((name, element.text()))
    "select" => {
      let options : Array[@moonxml.Element] = []
      collect_options(element, options)
      let chosen : Array[String] = []
      if element.has_attr("multiple") {
        for option in options {
          if option.has_attr("selected") {
            chosen.push(option_value(option))
          }
        }
      } else {
        let mut picked : @moonxml.Element? = None
        for option in options {
          if option.has_attr("selected") {
            picked = Some(option)
            break
          }
        }
        if picked is None && options.length() > 0 {
          picked = Some(options[0])
        }
        match picked {
          Some(option) => chosen.push(option_value(option))
          None => ()
        }
      }
      for value in chosen {
        out.push((name, value))
      }
    }
    "button" =>
      match element.attr("value") {
        Some(value) => out.push((name, value))
        None => out.push((name, ""))
      }
    _ => ()
  }
}

///|
fn collect_options(
  element : @moonxml.Element,
  into : Array[@moonxml.Element],
) -> Unit {
  for child in element.children {
    if child is @moonxml.ElementNode(data) {
      if data.name == "option" {
        into.push(data)
      }
      collect_options(data, into)
    }
  }
}

///|
/// What an option sends: its `value`, or its text when it has none.
fn option_value(option : @moonxml.Element) -> String {
  match option.attr("value") {
    Some(value) => value
    None => option.text().trim().to_owned()
  }
}
