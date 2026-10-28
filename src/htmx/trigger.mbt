// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// When an element asks: the event, and the conditions htmx puts on it.
///
/// `hx-trigger="keyup changed delay:500ms from:#search"` is one trigger;
/// `hx-trigger="click, keyup[key=='Enter']"` is two.
pub(all) struct Trigger {
  /// The event, in lower case: `click`, `submit`, `every 2s`, `load`.
  mut event : String
  /// The bracketed condition, when the trigger carries one.
  mut filter : String?
  /// Fire once, then forget the listener.
  mut once : Bool
  /// Only when the value changed since the last time.
  mut changed : Bool
  /// Wait this many milliseconds after the event before asking.
  mut delay : Int32
  /// Ask at most once per this many milliseconds. Zero when unset.
  mut throttle : Int32
  /// Whose events: a selector, or one of htmx's relative ones.
  mut from : String?
  /// Where the request goes, when it is not the trigger's own target.
  mut target : String?
  /// `first`, `last`, `all` or `none` — what happens to a request that is
  /// already in flight when another arrives. `None` means htmx's default.
  mut queue : String?
  /// Do not let this event bubble to an ancestor's listener.
  mut consume : Bool
}

///|
/// One trigger, from its spelling.
///
/// The spelling is the event — possibly with a bracketed condition — followed
/// by modifiers separated by spaces. An empty spelling is a `click`.
pub fn Trigger::parse(spec : String) -> Trigger {
  let trigger : Trigger = {
    event: "click",
    filter: None,
    once: false,
    changed: false,
    delay: 0,
    throttle: 0,
    from: None,
    target: None,
    queue: None,
    consume: false,
  }
  let text = spec.trim().to_owned()
  if text.is_empty() {
    return trigger
  }
  // The event name runs until a space that is not inside the condition, and
  // `every 2s` carries a space of its own.
  let mut at = 0
  let n = text.length()
  let mut depth = 0
  while at < n {
    let ch = text.at(at).unsafe_to_char()
    if ch == '[' {
      depth = depth + 1
    } else if ch == ']' {
      depth = depth - 1
    } else if ch == ' ' && depth == 0 {
      // `every` keeps the word after it as part of the event.
      if text[0:at].to_lower().to_owned() != "every" {
        break
      }
    }
    at = at + 1
  }
  let head = text[0:at].trim().to_owned()
  match head.find("[") {
    Some(open) => {
      trigger.event = head[0:open].trim().to_lower().to_owned()
      let close = match head.find("]") {
        Some(found) => found
        None => head.length()
      }
      if close > open + 1 {
        trigger.filter = Some(head[open + 1:close].trim().to_owned())
      }
    }
    None => trigger.event = head.to_lower()
  }
  // The modifiers. A value may hold spaces — `from:closest form` is a
  // selector — so the words are gathered first and read in order.
  let words = words_of(text[at:n].to_owned())
  let mut k = 0
  while k < words.length() {
    let modifier = words[k]
    k = k + 1
    if modifier.is_empty() {
      continue
    }
    match modifier.find(":") {
      Some(colon) => {
        let key = modifier[0:colon].trim().to_lower().to_owned()
        let mut value = modifier[colon + 1:modifier.length()].trim().to_owned()
        if key == "from" || key == "target" {
          while k < words.length() && !is_modifier(words[k]) {
            value = value + " " + words[k]
            k = k + 1
          }
        }
        match key {
          "delay" => trigger.delay = duration(value)
          "throttle" => trigger.throttle = duration(value)
          "from" => trigger.from = Some(value)
          "target" => trigger.target = Some(value)
          "queue" => trigger.queue = Some(value.to_lower())
          _ => ()
        }
      }
      None =>
        match modifier.to_lower() {
          "once" => trigger.once = true
          "changed" => trigger.changed = true
          "consume" => trigger.consume = true
          _ => ()
        }
    }
  }
  trigger
}

///|
/// Every trigger a spelling names, in the order it names them.
///
/// `click, keyup[key=='Enter'] changed delay:500ms` is two triggers. A comma
/// inside a condition does not split.
pub fn Trigger::list(spec : String) -> Array[Trigger] {
  let out : Array[Trigger] = []
  let mut start = 0
  let mut depth = 0
  let n = spec.length()
  let mut at = 0
  while at < n {
    let ch = spec.at(at).unsafe_to_char()
    if ch == '[' {
      depth = depth + 1
    } else if ch == ']' {
      depth = depth - 1
    } else if ch == ',' && depth == 0 {
      let part = spec[start:at].trim().to_owned()
      if !part.is_empty() {
        out.push(Trigger::parse(part))
      }
      start = at + 1
    }
    at = at + 1
  }
  let tail = spec[start:n].trim().to_owned()
  if !tail.is_empty() {
    out.push(Trigger::parse(tail))
  }
  out
}

///|
/// Whether this trigger is about `event`.
pub fn Trigger::matches(self : Trigger, event : String) -> Bool {
  self.event == event.to_lower()
}

///|
/// What an element listens for when it does not say: a form is submitted, a
/// field changes, and everything else is clicked.
pub fn Trigger::default_for(element : @moonxml.Element) -> Trigger {
  let event = match element.name {
    "form" => "submit"
    "input" | "textarea" | "select" => "change"
    _ => "click"
  }
  Trigger::parse(event)
}

///|
/// A `hx-trigger` duration in milliseconds: `500ms`, `2s`, `1.5s`, or a bare
/// number of milliseconds. Anything else is zero, which means "no wait".
fn duration(text : String) -> Int32 {
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
/// The space-separated words of a trigger's tail, with a bracketed condition
/// kept whole however many spaces it holds.
fn words_of(text : String) -> Array[String] {
  let out : Array[String] = []
  let mut word = StringBuilder()
  let mut depth = 0
  for ch in text {
    if ch == '[' {
      depth = depth + 1
    } else if ch == ']' {
      depth = depth - 1
    }
    if ch == ' ' && depth == 0 {
      if word.to_string().length() > 0 {
        out.push(word.to_string())
        word = StringBuilder()
      }
    } else {
      word.write_char(ch)
    }
  }
  if word.to_string().length() > 0 {
    out.push(word.to_string())
  }
  out
}

///|
/// Whether a word is a modifier rather than part of the one before it.
fn is_modifier(word : String) -> Bool {
  match word.find(":") {
    Some(colon) =>
      match word[0:colon].trim().to_lower().to_owned() {
        "delay" | "throttle" | "from" | "target" | "queue" => true
        _ => false
      }
    None =>
      match word.to_lower() {
        "once" | "changed" | "consume" => true
        _ => false
      }
  }
}
