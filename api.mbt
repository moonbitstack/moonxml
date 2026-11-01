/// Node-level conveniences: every chain method also exists on `Element` and
/// `Document`, wrapping the receiver into a one-node selection so a chain never
/// has to stop at a node.

// ---------------------------------------------------------------------------
// Element
// ---------------------------------------------------------------------------

/// Narrow the element's descendants by a CSS selector.
pub fn Element::css(self : Element, query : String) -> Selection raise Refused {
  element_selection(self).css(query)
}

/// Narrow the element's descendants by XPath.
pub fn Element::xpath(self : Element, query : String) -> Selection raise Refused {
  element_selection(self).xpath(query)
}

/// The typed answer of an XPath expression evaluated with this element as context.
pub fn Element::xpath_value(self : Element, query : String) -> XPathValue raise Refused {
  element_selection(self).xpath_value(query)
}

/// Run a named selector with this element as context.
pub fn Element::selector(self : Element, name : String, query : String) -> Selection raise Refused {
  element_selection(self).selector(name, query)
}

/// Descendants with the given `id`.
pub fn Element::by_id(self : Element, v : String) -> Selection {
  element_selection(self).by_id(v)
}

/// Descendants with the given class token.
pub fn Element::by_class(self : Element, v : String) -> Selection {
  element_selection(self).by_class(v)
}

/// Descendants with the given tag name.
pub fn Element::by_tag(self : Element, v : String) -> Selection {
  element_selection(self).by_tag(v)
}

/// Descendants with the given `name` attribute.
pub fn Element::by_name(self : Element, v : String) -> Selection {
  element_selection(self).by_name(v)
}

/// Keep the element if `f` accepts it.
pub fn Element::filter(self : Element, f : (Node) -> Bool) -> Selection {
  element_selection(self).filter(f)
}

/// The nearest ancestor-or-self matching `query`.
pub fn Element::closest(self : Element, query : String) -> Selection raise Refused {
  element_selection(self).closest(query)
}

/// The element's inner HTML, in XML rules.
pub fn Element::html(self : Element) -> String {
  self.inner_html()
}

// ---------------------------------------------------------------------------
// Document
// ---------------------------------------------------------------------------

/// Narrow the whole document by a CSS selector.
pub fn Document::css(self : Document, query : String) -> Selection raise Refused {
  doc_selection(self).css(query)
}

/// Narrow the whole document by XPath.
pub fn Document::xpath(self : Document, query : String) -> Selection raise Refused {
  doc_selection(self).xpath(query)
}

/// The typed answer of an XPath expression evaluated against the document.
pub fn Document::xpath_value(self : Document, query : String) -> XPathValue raise Refused {
  doc_selection(self).xpath_value(query)
}

/// Descendants with the given `id` (the whole tree).
pub fn Document::by_id(self : Document, v : String) -> Selection {
  doc_selection(self).by_id(v)
}

/// Descendants with the given class token.
pub fn Document::by_class(self : Document, v : String) -> Selection {
  doc_selection(self).by_class(v)
}

/// Descendants with the given tag name.
pub fn Document::by_tag(self : Document, v : String) -> Selection {
  doc_selection(self).by_tag(v)
}

/// Descendants with the given `name` attribute.
pub fn Document::by_name(self : Document, v : String) -> Selection {
  doc_selection(self).by_name(v)
}

/// Keep the items for which `f` returns true, over the whole document.
pub fn Document::filter(self : Document, f : (Node) -> Bool) -> Selection {
  doc_selection(self).filter(f)
}

/// For each document element, the nearest ancestor-or-self matching `query`.
pub fn Document::closest(self : Document, query : String) -> Selection raise Refused {
  doc_selection(self).closest(query)
}

/// The whole document's text content.
pub fn Document::text(self : Document) -> String {
  doc_selection(self).text()
}

/// The document element's inner HTML.
pub fn Document::html(self : Document) -> String {
  doc_selection(self).html()
}
