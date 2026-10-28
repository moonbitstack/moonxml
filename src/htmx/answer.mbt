// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Put an answer into the page: parse it, take the part the element asked
/// for, send the out-of-band pieces to the places they name, and swap the
/// rest into the target.
///
/// The nodes that went in are answered, in the order they were put there.
pub fn Request::answer(self : Request, text : String) -> @moonxml.Selection {
  let response = @html.loads(text)
  let content = content_of(response, self.select)
  let rest = out_of_band(content, self.target)
  apply_swap(self.target, self.swap.style, rest)
}

///|
/// The part of the response that belongs to the target: what `hx-select`
/// names, or, when it names nothing, the body's children.
fn content_of(
  response : @moonxml.Document,
  select : String?,
) -> Array[@moonxml.Node] {
  match select {
    Some(selector) => {
      let found = response.css(selector.trim().to_owned()) catch {
        _ => @moonxml.Selection::new()
      }
      found.items.copy()
    }
    None => {
      let body = response.css("body") catch { _ => @moonxml.Selection::new() }
      if body.length() > 0 {
        match body.items[0] {
          @moonxml.ElementNode(data) => data.children.copy()
          _ => []
        }
      } else {
        response.root.children.copy()
      }
    }
  }
}

///|
/// Swap every `hx-swap-oob` element in the answer into the place it names,
/// and answer what is left for the target.
///
/// `hx-swap-oob="true"` replaces the element with the same `id`;
/// `hx-swap-oob="beforeend:#list"` puts it at the end of what that selector
/// answers; `hx-swap-oob="delete"` takes the element away. An out-of-band
/// element is not part of the target's content.
fn out_of_band(
  content : Array[@moonxml.Node],
  target : @moonxml.Element,
) -> Array[@moonxml.Node] {
  let remaining : Array[@moonxml.Node] = []
  for node in content {
    match node {
      @moonxml.ElementNode(element) =>
        match element.attr("hx-swap-oob") {
          Some(value) =>
            if value.trim().is_empty() {
              remaining.push(node)
            } else {
              swap_out_of_band(element, value.trim().to_owned(), target)
            }
          None => remaining.push(node)
        }
      _ => remaining.push(node)
    }
  }
  remaining
}

///|
/// One out-of-band element: where it goes, and into what.
fn swap_out_of_band(
  element : @moonxml.Element,
  spec : String,
  target : @moonxml.Element,
) -> Unit {
  // `true` means the default position; anything else is a position, and
  // after a colon, the element it applies to.
  let (style_text, selector) = match spec.find(":") {
    Some(colon) =>
      (
        spec[0:colon].trim().to_owned(),
        Some(spec[colon + 1:spec.length()].trim().to_owned()),
      )
    None => (spec, None)
  }
  let style = if style_text.to_lower() == "true" {
    Outer
  } else {
    SwapSpec::parse(style_text).style
  }
  let query = match selector {
    Some(given) => Some(given)
    None =>
      match element.attr("id") {
        Some(id) => Some("#" + id)
        None => None
      }
  }
  let page = match target.document() {
    Some(found) => found
    None => return
  }
  match query {
    Some(text) => {
      let found = page.css(text) catch { _ => @moonxml.Selection::new() }
      if found.length() > 0 {
        match found.items[0] {
          @moonxml.ElementNode(host) => {
            // The directive has been carried out; it is not part of the page.
            ignore(element.remove_attr("hx-swap-oob"))
            ignore(apply_swap(host, style, [@moonxml.ElementNode(element)]))
          }
          _ => ()
        }
      }
    }
    None => ()
  }
}

///|
/// Put nodes at a position relative to `target`.
fn apply_swap(
  target : @moonxml.Element,
  style : Swap,
  nodes : Array[@moonxml.Node],
) -> @moonxml.Selection {
  let out : Array[@moonxml.Node] = []
  match style {
    Inner => {
      target.clear()
      for node in nodes {
        target.append(node)
        out.push(node)
      }
    }
    Outer => {
      for node in nodes {
        ignore(target.insert_before(node))
        out.push(node)
      }
      ignore(target.remove())
    }
    BeforeBegin =>
      for node in nodes {
        ignore(target.insert_before(node))
        out.push(node)
      }
    AfterBegin => {
      // Prepending one at a time would reverse them; the last first keeps the
      // order the answer was written in.
      let mut k = nodes.length() - 1
      while k >= 0 {
        target.prepend(nodes[k])
        out.push(nodes[k])
        k = k - 1
      }
    }
    BeforeEnd =>
      for node in nodes {
        target.append(node)
        out.push(node)
      }
    AfterEnd => {
      let mut k = nodes.length() - 1
      while k >= 0 {
        ignore(target.insert_after(nodes[k]))
        out.push(nodes[k])
        k = k - 1
      }
    }
    Delete => ignore(target.remove())
    NoSwap => ()
  }
  @moonxml.Selection::of(out)
}
