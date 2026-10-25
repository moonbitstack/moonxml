// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One query language plugged into the chain. Implement this to add your own,
/// register it with `Document::register`, and run it with
/// `selector(name, query)` — or pass it straight to `custom` and skip the
/// registry entirely.
///
///     struct DeepLinks {}
///     impl Selector for DeepLinks with select(_self, ctx, _query) {
///       ctx.css("a[href]").filter(fn(node) {
///         node is ElementNode(e) && e.attr("href").has_prefix("https://")
///       })
///     }
pub(open) trait Selector {
  /// Narrow `ctx` — usually by searching the descendants of its nodes.
  /// `query` is the text the caller wrote; a selector that takes no text may
  /// ignore it.
  fn select(Self, ctx : Selection, query : String) -> Selection raise Refused
}

///|
/// Register a selector under a name. Re-registering a name replaces what was
/// there, built-in or not — and a built-in stays reachable through its own
/// method, which calls the engine directly and never consults the registry.
pub fn Document::register(
  self : Document,
  name : String,
  sel : &Selector,
) -> Unit {
  self.selectors.set(name, sel)
}

///|
/// A selector that is a closure — the shape a selector with no state of its
/// own takes. A selector that carries configuration is a struct implementing
/// `Selector` directly, with a constructor of its own.
pub struct SelectorFn {
  f : (Selection, String) -> Selection raise Refused
}

///|
pub fn SelectorFn::new(
  f : (Selection, String) -> Selection raise Refused,
) -> SelectorFn {
  { f, }
}

///|
pub impl Selector for SelectorFn with fn select(
  self,
  ctx : Selection,
  query : String,
) -> Selection raise Refused {
  (self.f)(ctx, query)
}

///|
pub extend SelectorFn with Selector::{select}

///|
/// The built-ins every document starts with: CSS and XPath, and the four
/// getters the DOM spells `getElement(s)By…`.
priv enum Builtin {
  Css
  Xpath
  Id
  Class
  Tag
  Name
}

///|
impl Selector for Builtin with fn select(self, ctx : Selection, query : String) -> Selection raise Refused {
  match self {
    Css => ctx.css(query)
    Xpath => ctx.xpath(query)
    Id => ctx.by_id(query)
    Class => ctx.by_class(query)
    Tag => ctx.by_tag(query)
    Name => ctx.by_name(query)
  }
}

///|
fn Document::seed_selectors(self : Document) -> Unit {
  self.selectors.set("css", Builtin::Css)
  self.selectors.set("xpath", Builtin::Xpath)
  self.selectors.set("id", Builtin::Id)
  self.selectors.set("class", Builtin::Class)
  self.selectors.set("tag", Builtin::Tag)
  self.selectors.set("name", Builtin::Name)
}
