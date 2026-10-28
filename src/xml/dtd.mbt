// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The internal subset: the declarations a document carries in its own
// `<!DOCTYPE … [ … ]>`, and the entity expansion they make possible.
//
// Two entities matter and behave differently. A general entity (`&name;`) may
// stand for markup, so its replacement text is spliced into the document and
// read as content. A parameter entity (`%name;`) stands for text inside the
// DTD, so its replacement is spliced into the subset and read as declarations.
// Neither is fetched from anywhere: a declaration that names a file is
// recorded, and what it stands for is reported as unresolved.

///|
// One declared general entity: its replacement text, or the system identifier
// of a file this reader will not open.
priv enum Entity {
  Replacement(String)
  File
  Unparsed
}

///|
// One attribute a declaration gives an element: its name, whether its type is
// `CDATA` — the one type whose value is not whitespace-collapsed — and the
// default, when the declaration has one.
priv struct AttDef {
  name : String
  cdata : Bool
  default : String?
}

///|
// What the subset declares and what the reader tallies: the two entity tables,
// the attribute defaults, whether anything outside the document is named, and
// how much expansion has been spent.
priv struct Ctx {
  ents : Map[String, Entity]
  pents : Map[String, String]
  defaults : Map[String, Array[AttDef]]
  // Set when the document declares an external subset or an external
  // parameter entity: from then on an undeclared entity is something this
  // reader could not see, not a well-formedness error.
  mut external : Bool
  // A document that says `standalone="yes"` says it needs nothing from
  // outside, so an entity it did not declare itself is a fault, not a gap.
  mut standalone : Bool
  unresolved : Array[String]
  // Set while the declaration being read is an unparsed entity.
  mut unparsed : Bool
  mut expanded : Int32
  limit : Int32
}

///|
fn Ctx::new(limit : Int32) -> Ctx {
  let ctx = {
    ents: Map([]),
    pents: Map([]),
    defaults: Map([]),
    external: false,
    standalone: false,
    unresolved: [],
    unparsed: false,
    expanded: 0,
    limit,
  }
  // The five every document has, declared before it says anything. Their
  // replacement text is a character reference to themselves, which is how
  // `&lt;` stands for a `<` that is text rather than a tag.
  ctx.ents.set("amp", Replacement("&#38;"))
  ctx.ents.set("lt", Replacement("&#60;"))
  ctx.ents.set("gt", Replacement("&#62;"))
  ctx.ents.set("quot", Replacement("&#34;"))
  ctx.ents.set("apos", Replacement("&#39;"))
  ctx
}

///|
// Count `amount` more characters of expansion against the document's budget.
// A document that expands past it is refused rather than read: that is the
// shape of an entity-expansion attack, not of a document.
fn spend(ctx : Ctx, at : Int32, amount : Int32) -> Unit raise @moonxml.Refused {
  ctx.expanded = ctx.expanded + amount
  if ctx.expanded > ctx.limit {
    raise @moonxml.Exceeded(at~, limit=ctx.limit, got=ctx.expanded)
  }
}

///|
// Record an entity this reader did not read, once.
fn note_unresolved(ctx : Ctx, name : String) -> Unit {
  if !ctx.unresolved.contains(name) {
    ctx.unresolved.push(name)
  }
}

///|
// The declarations of the internal subset, up to the `]` that closes it.
fn internal_subset(scanner : Scan) -> Unit raise @moonxml.Refused {
  while true {
    skip_space(scanner)
    if scanner.at >= scanner.text.length() {
      fail(scanner, scanner.at, "the internal subset is never closed")
    }
    if scanner.peek() == 0x5D {
      // ']'
      scanner.at = scanner.at + 1
      return
    }
    if scanner.peek() == 0x25 {
      // '%' — a parameter entity, allowed between declarations. What it
      // stands for is declarations, so it is put where the reference stood and
      // read as such.
      let at = scanner.at
      let value = parameter_reference(scanner)
      let end = scanner.at
      spend(scanner.ctx, at, value.length())
      scanner.at = at
      splice(scanner, end - at, value)
      continue
    }
    if starts_with(scanner, "<!--") {
      comment(scanner)
      continue
    }
    if starts_with(scanner, "<?") {
      instruction(scanner)
      continue
    }
    if starts_with(scanner, "<!") {
      declaration(scanner)
      continue
    }
    fail(scanner, scanner.at, "the internal subset holds declarations only")
  }
}

///|
// One markup declaration: the four the spec defines.
fn declaration(scanner : Scan) -> Unit raise @moonxml.Refused {
  if starts_with(scanner, "<![") {
    fail(
      scanner,
      scanner.at,
      "a conditional section is not in the internal subset",
    )
  }
  scanner.at = scanner.at + 2
  if starts_with(scanner, "ENTITY") {
    scanner.at = scanner.at + 6
    entity_decl(scanner)
  } else if starts_with(scanner, "ATTLIST") {
    scanner.at = scanner.at + 7
    attlist_decl(scanner)
  } else if starts_with(scanner, "ELEMENT") {
    scanner.at = scanner.at + 7
    element_decl(scanner)
  } else if starts_with(scanner, "NOTATION") {
    scanner.at = scanner.at + 8
    notation_decl(scanner)
  } else {
    fail(scanner, scanner.at, "not a declaration XML defines")
  }
}

///|
// `<!ENTITY S Name S EntityDef S? >`, or the same with a `%` after `ENTITY`
// for a parameter entity.
fn entity_decl(scanner : Scan) -> Unit raise @moonxml.Refused {
  let at = scanner.at
  require_space(scanner, "an entity declaration")
  skip_space(scanner)
  let parameter = if scanner.peek() == 0x25 {
    scanner.at = scanner.at + 1
    skip_space(scanner)
    true
  } else {
    false
  }
  let (name, after) = read_name(scanner, scanner.at)
  if name.is_empty() {
    fail(scanner, at, "an entity declaration needs a name")
  }
  if name.contains(":") {
    fail(scanner, at, "an entity name is not a qualified name")
  }
  scanner.at = after
  require_space(scanner, "an entity declaration")
  skip_space(scanner)
  if parameter {
    let value = match definition(scanner, false) {
      Some(text) => text
      None => ""
    }
    // A parameter entity's replacement text is used where declarations go.
    scanner.ctx.pents.set(name, value)
  } else {
    match definition(scanner, true) {
      Some(text) => set_entity(scanner, name, Replacement(text))
      None => {
        // An external entity: recorded so that a reference to it can be
        // reported rather than refused, never opened.
        let unparsed = scanner.ctx.unparsed
        scanner.ctx.unparsed = false
        set_entity(scanner, name, if unparsed { Unparsed } else { File })
        scanner.ctx.external = true
      }
    }
  }
  skip_space(scanner)
  expect(scanner, 0x3E, "an entity declaration ends at `>`")
}

///|
// An entity's definition: its quoted replacement text, or `None` when it names
// a file instead (the external identifiers are read and dropped).
fn definition(
  scanner : Scan,
  unparsed_allowed : Bool,
) -> String? raise @moonxml.Refused {
  match scanner.peek() {
    0x22 | 0x27 => Some(entity_value(scanner))
    0x53 | 0x50 => {
      // SYSTEM or PUBLIC
      external_id(scanner)
      // NDataDecl: the entity is unparsed, and nothing will be read of it.
      // Only a general entity may be unparsed, and only after a space.
      let spaced = is_space_at(scanner, 0)
      skip_space(scanner)
      if starts_with(scanner, "NDATA") {
        if !spaced {
          fail(scanner, scanner.at, "NDATA follows a space")
        }
        if !unparsed_allowed {
          fail(scanner, scanner.at, "a parameter entity is always parsed")
        }
        scanner.ctx.unparsed = true
        scanner.at = scanner.at + 5
        require_space(scanner, "NDATA")
        skip_space(scanner)
        let (name, after) = read_name(scanner, scanner.at)
        if name.is_empty() {
          fail(scanner, scanner.at, "an unparsed entity names its notation")
        }
        scanner.at = after
      }
      None
    }
    _ => fail(scanner, scanner.at, "an entity definition is quoted or external")
  }
}

///|
// A quoted entity value: character references are expanded now, parameter
// entities are included now, and general entity references are left standing,
// to be expanded where the entity is used.
fn entity_value(scanner : Scan) -> String raise @moonxml.Refused {
  let text = scanner.text
  let quote = scanner.peek()
  scanner.at = scanner.at + 1
  let out = StringBuilder()
  while true {
    if scanner.at >= text.length() {
      fail(scanner, scanner.at, "an entity value is unterminated")
    }
    let unit = text.at(scanner.at)
    if unit == quote {
      scanner.at = scanner.at + 1
      return out.to_string()
    }
    if unit == 0x25 {
      // The internal subset may not carry a parameter entity reference inside
      // a markup declaration, and an entity value is one.
      fail(
        scanner,
        scanner.at,
        "a parameter entity reference inside a declaration",
      )
    }
    if unit == 0x26 {
      // '&' — a character reference is expanded, a general entity is bypassed.
      // An `&` that starts neither is the character itself nowhere in XML.
      if scanner.at + 1 < text.length() && text.at(scanner.at + 1) == 0x23 {
        out.write_char(character_reference(scanner))
        continue
      }
      scanner.at = scanner.at + 1
      let (name, after) = read_name(scanner, scanner.at)
      if name.is_empty() {
        fail(scanner, scanner.at, "`&` starts a reference")
      }
      scanner.at = after
      expect(scanner, 0x3B, "an entity reference ends at `;`")
      out.write_string("&" + name + ";")
      continue
    }
    out.write_char(unit_char(unit))
    scanner.at = scanner.at + 1
  }
  out.to_string()
}

///|
// `%name;` in the subset: the parameter entity's replacement text is spliced
// into the subset there and read as declarations. An external parameter entity
// is recorded and stands for nothing.
fn parameter_reference(scanner : Scan) -> String raise @moonxml.Refused {
  let at = scanner.at
  scanner.at = scanner.at + 1
  let (name, after) = read_name(scanner, scanner.at)
  if name.is_empty() {
    fail(scanner, at, "a parameter entity reference needs a name")
  }
  scanner.at = after
  expect(scanner, 0x3B, "a parameter entity reference ends at `;`")
  // A document that uses parameter entities is one whose declarations may
  // live elsewhere, so what it leaves undeclared is a gap rather than a fault.
  scanner.ctx.external = true
  match scanner.ctx.pents.get(name) {
    Some(value) => value
    None => {
      note_unresolved(scanner.ctx, name)
      ""
    }
  }
}

///|
// `<!ATTLIST S Name (S Name S AttType S DefaultDecl)* S? >`, keeping the
// defaults and the types: a default fills in an attribute the document left
// out, and a type decides whether the value is whitespace-collapsed.
fn attlist_decl(scanner : Scan) -> Unit raise @moonxml.Refused {
  require_space(scanner, "an attribute-list declaration")
  skip_space(scanner)
  let (element, after) = read_name(scanner, scanner.at)
  if element.is_empty() {
    fail(scanner, scanner.at, "an attribute list needs an element name")
  }
  scanner.at = after
  let defs : Array[AttDef] = match scanner.ctx.defaults.get(element) {
    Some(have) => have
    None => []
  }
  while true {
    skip_space(scanner)
    if scanner.peek() == 0x3E {
      scanner.at = scanner.at + 1
      scanner.ctx.defaults.set(element, defs)
      return
    }
    if scanner.at >= scanner.text.length() {
      fail(scanner, scanner.at, "an attribute list is unterminated")
    }
    let (attr, after) = read_name(scanner, scanner.at)
    if attr.is_empty() {
      fail(scanner, scanner.at, "an attribute declaration needs a name")
    }
    scanner.at = after
    require_space(scanner, "an attribute declaration")
    skip_space(scanner)
    let cdata = attribute_type(scanner)
    require_space(scanner, "an attribute declaration")
    skip_space(scanner)
    let default = default_decl(scanner)
    match default {
      Some(value) => check_default_references(scanner.ctx, value, scanner.at)
      None => ()
    }
    // A repeated declaration of the same attribute keeps the first, which is
    // what a document that declares it twice ends up with either way.
    let mut seen = false
    for have in defs {
      if have.name == attr {
        seen = true
      }
    }
    if !seen {
      defs.push({ name: attr, cdata, default, })
    }
  }
}

///|
// An attribute's type: `CDATA`, one of the tokenized types, or an enumeration.
// Only the first decides how the value is normalized.
fn attribute_type(scanner : Scan) -> Bool raise @moonxml.Refused {
  if starts_with(scanner, "CDATA") {
    scanner.at = scanner.at + 5
    return true
  }
  let keyword = tokenized_type(scanner)
  if keyword {
    return false
  }
  if starts_with(scanner, "NOTATION") {
    scanner.at = scanner.at + 8
    require_space(scanner, "a notation type")
    skip_space(scanner)
    names_in_parens(scanner, "a notation type")
    return false
  }
  if scanner.peek() == 0x28 {
    list_in_parens(scanner, "an enumeration")
    return false
  }
  fail(scanner, scanner.at, "not an attribute type XML defines")
}

///|
fn tokenized_type(scanner : Scan) -> Bool {
  for
    keyword in [
      "IDREFS", "IDREF", "ID", "ENTITIES", "ENTITY", "NMTOKENS", "NMTOKEN",
    ] {
    if starts_with(scanner, keyword) {
      let next = scanner.at + keyword.length()
      if next >= scanner.text.length() ||
        is_space(scanner.text.at(next)) ||
        scanner.text.at(next) == 0x29 ||
        scanner.text.at(next) == 0x7C {
        scanner.at = next
        return true
      }
    }
  }
  false
}

///|
// `( S? Name (S? '|' S? Name)* S? )`
fn names_in_parens(
  scanner : Scan,
  what : String,
) -> Unit raise @moonxml.Refused {
  expect(scanner, 0x28, what)
  while true {
    skip_space(scanner)
    let (name, after) = read_name(scanner, scanner.at)
    if name.is_empty() {
      fail(scanner, scanner.at, what + " takes names")
    }
    scanner.at = after
    skip_space(scanner)
    if scanner.peek() == 0x7C {
      scanner.at = scanner.at + 1
      continue
    }
    expect(scanner, 0x29, what)
    return
  }
}

///|
// `( S? Nmtoken (S? '|' S? Nmtoken)* S? )`
fn list_in_parens(scanner : Scan, what : String) -> Unit raise @moonxml.Refused {
  expect(scanner, 0x28, what)
  while true {
    skip_space(scanner)
    let (token, after) = read_nmtoken(scanner, scanner.at)
    if token.is_empty() {
      fail(scanner, scanner.at, what + " takes names")
    }
    scanner.at = after
    skip_space(scanner)
    if scanner.peek() == 0x7C {
      scanner.at = scanner.at + 1
      continue
    }
    expect(scanner, 0x29, what)
    return
  }
}

///|
// `#REQUIRED`, `#IMPLIED`, or an attribute value with an optional `#FIXED`
// in front of it.
fn default_decl(scanner : Scan) -> String? raise @moonxml.Refused {
  if scanner.peek() == 0x23 {
    scanner.at = scanner.at + 1
    if starts_with(scanner, "REQUIRED") {
      scanner.at = scanner.at + 8
      return None
    }
    if starts_with(scanner, "IMPLIED") {
      scanner.at = scanner.at + 7
      return None
    }
    if starts_with(scanner, "FIXED") {
      scanner.at = scanner.at + 5
      require_space(scanner, "#FIXED")
      skip_space(scanner)
      return Some(attribute_default(scanner))
    }
    fail(scanner, scanner.at, "not a default XML defines")
  }
  Some(attribute_default(scanner))
}

///|
// The quoted value of a default: character references expanded, general entity
// references left standing for the moment the default is used.
fn attribute_default(scanner : Scan) -> String raise @moonxml.Refused {
  // A default is an attribute value, not an entity value: a `%` in it is the
  // character, and a general entity is bypassed until the default is used.
  match scanner.peek() {
    0x22 | 0x27 => literal_value(scanner)
    _ => fail(scanner, scanner.at, "an attribute default is quoted")
  }
}

///|
/// A quoted attribute value in a declaration: character references expanded,
/// everything else as it stands.
fn literal_value(scanner : Scan) -> String raise @moonxml.Refused {
  let text = scanner.text
  let quote = scanner.peek()
  scanner.at = scanner.at + 1
  let out = StringBuilder()
  while true {
    if scanner.at >= text.length() {
      fail(scanner, scanner.at, "a value is unterminated")
    }
    let unit = text.at(scanner.at)
    if unit == quote {
      scanner.at = scanner.at + 1
      return out.to_string()
    }
    if unit == 0x26 &&
      scanner.at + 1 < text.length() &&
      text.at(scanner.at + 1) == 0x23 {
      out.write_char(character_reference(scanner))
      continue
    }
    if unit == 0x26 {
      let at = scanner.at
      scanner.at = scanner.at + 1
      let (name, after) = read_name(scanner, scanner.at)
      if name.is_empty() {
        fail(scanner, at, "`&` starts a reference")
      }
      scanner.at = after
      expect(scanner, 0x3B, "an entity reference ends at `;`")
      out.write_string("&" + name + ";")
      continue
    }
    if unit == 0x3C {
      fail(scanner, scanner.at, "a `<` in an attribute value")
    }
    out.write_char(unit_char(unit))
    scanner.at = scanner.at + 1
  }
  ""
}

///|
// `<!ELEMENT S Name S contentspec S? >`. The content model is parsed so that a
// malformed one is refused, and then dropped: this reader does not validate.
fn element_decl(scanner : Scan) -> Unit raise @moonxml.Refused {
  require_space(scanner, "an element declaration")
  skip_space(scanner)
  let (name, after) = read_name(scanner, scanner.at)
  if name.is_empty() {
    fail(scanner, scanner.at, "an element declaration needs a name")
  }
  scanner.at = after
  require_space(scanner, "an element declaration")
  skip_space(scanner)
  content_spec(scanner)
  skip_space(scanner)
  expect(scanner, 0x3E, "an element declaration ends at `>`")
}

///|
fn content_spec(scanner : Scan) -> Unit raise @moonxml.Refused {
  if starts_with(scanner, "EMPTY") {
    scanner.at = scanner.at + 5
    return
  }
  if starts_with(scanner, "ANY") {
    scanner.at = scanner.at + 3
    return
  }
  if scanner.peek() != 0x28 {
    fail(scanner, scanner.at, "a content model starts with `(`")
  }
  // A leading `#PCDATA` makes it a mixed model, whose grammar is its own.
  if starts_with(scanner, "(#PCDATA") || starts_with(scanner, "( #PCDATA") {
    mixed(scanner)
    return
  }
  group(scanner)
  occurrence(scanner)
}

///|
fn mixed(scanner : Scan) -> Unit raise @moonxml.Refused {
  expect(scanner, 0x28, "a mixed content model")
  skip_space(scanner)
  if !starts_with(scanner, "#PCDATA") {
    fail(scanner, scanner.at, "a mixed content model starts with #PCDATA")
  }
  scanner.at = scanner.at + 7
  skip_space(scanner)
  let mut more = false
  while scanner.peek() == 0x7C {
    scanner.at = scanner.at + 1
    skip_space(scanner)
    let (name, after) = read_name(scanner, scanner.at)
    if name.is_empty() {
      fail(scanner, scanner.at, "a mixed content model takes element names")
    }
    scanner.at = after
    skip_space(scanner)
    more = true
  }
  expect(scanner, 0x29, "a mixed content model")
  if more {
    expect(scanner, 0x2A, "a mixed content model with names ends at `)*`")
  } else if scanner.peek() == 0x2A {
    scanner.at = scanner.at + 1
  }
}

///|
// `( S? cp (S? ('|' | ',') S? cp)* S? )`
fn group(scanner : Scan) -> Unit raise @moonxml.Refused {
  expect(scanner, 0x28, "a content model")
  skip_space(scanner)
  particle(scanner)
  skip_space(scanner)
  let separator = scanner.peek()
  if separator != 0x7C && separator != 0x2C {
    expect(scanner, 0x29, "a content model with one particle in it")
    return
  }
  while true {
    skip_space(scanner)
    let here = scanner.peek()
    if here != 0x7C && here != 0x2C {
      break
    }
    if here != separator {
      fail(scanner, scanner.at, "one group mixes `|` and `,`")
    }
    scanner.at = scanner.at + 1
    skip_space(scanner)
    particle(scanner)
    skip_space(scanner)
  }
  expect(scanner, 0x29, "a content model")
}

///|
fn particle(scanner : Scan) -> Unit raise @moonxml.Refused {
  skip_space(scanner)
  if scanner.peek() == 0x28 {
    group(scanner)
  } else {
    let (name, after) = read_name(scanner, scanner.at)
    if name.is_empty() {
      fail(scanner, scanner.at, "a content model takes element names")
    }
    scanner.at = after
  }
  occurrence(scanner)
}

///|
fn occurrence(scanner : Scan) -> Unit {
  let here = scanner.peek()
  if here == 0x3F || here == 0x2A || here == 0x2B {
    scanner.at = scanner.at + 1
  }
}

///|
// `<!NOTATION S Name S (ExternalID | PublicID) S? >`
fn notation_decl(scanner : Scan) -> Unit raise @moonxml.Refused {
  require_space(scanner, "a notation declaration")
  skip_space(scanner)
  let (name, after) = read_name(scanner, scanner.at)
  if name.is_empty() {
    fail(scanner, scanner.at, "a notation declaration needs a name")
  }
  if name.contains(":") {
    fail(scanner, scanner.at, "a notation name is not a qualified name")
  }
  scanner.at = after
  require_space(scanner, "a notation declaration")
  skip_space(scanner)
  external_identifier(scanner, false)
  skip_space(scanner)
  expect(scanner, 0x3E, "a notation declaration ends at `>`")
}

///|
// `SYSTEM S SystemLiteral`, or `PUBLIC S PubidLiteral S SystemLiteral`.
fn external_id(scanner : Scan) -> Unit raise @moonxml.Refused {
  external_identifier(scanner, true)
}

///|
/// `SYSTEM S SystemLiteral`, or `PUBLIC S PubidLiteral S SystemLiteral`. A
/// notation is the one declaration whose public identifier may stand alone.
fn external_identifier(
  scanner : Scan,
  system_required : Bool,
) -> Unit raise @moonxml.Refused {
  if starts_with(scanner, "SYSTEM") {
    scanner.at = scanner.at + 6
    require_space(scanner, "SYSTEM")
    skip_space(scanner)
    ignore(system_literal(scanner))
    return
  }
  if starts_with(scanner, "PUBLIC") {
    scanner.at = scanner.at + 6
    require_space(scanner, "PUBLIC")
    skip_space(scanner)
    if scanner.peek() == 0x22 || scanner.peek() == 0x27 {
      scanner.at = scanner.at + 1
      ignore(loop_literal(scanner, true))
    } else {
      fail(scanner, scanner.at, "a public identifier is quoted")
    }
    let spaced = is_space_at(scanner, 0)
    skip_space(scanner)
    if scanner.peek() == 0x22 || scanner.peek() == 0x27 {
      if !spaced {
        fail(scanner, scanner.at, "a system literal follows a space")
      }
      ignore(system_literal(scanner))
    } else if system_required {
      fail(scanner, scanner.at, "a public identifier needs a system literal")
    }
    return
  }
  fail(scanner, scanner.at, "an external identifier is SYSTEM or PUBLIC")
}

///|
fn system_literal(scanner : Scan) -> String raise @moonxml.Refused {
  match scanner.peek() {
    0x22 => {
      scanner.at = scanner.at + 1
      loop_literal(scanner, false)
    }
    0x27 => {
      scanner.at = scanner.at + 1
      loop_literal(scanner, false)
    }
    _ => fail(scanner, scanner.at, "a system identifier is quoted")
  }
}

///|
// The rest of a quoted literal, up to its quote. A system literal may not
// carry the other quote as well as its own; a public identifier is held to the
// characters the spec allows.
fn loop_literal(scanner : Scan, public : Bool) -> String raise @moonxml.Refused {
  let quote = scanner.text.at(scanner.at - 1)
  let start = scanner.at
  while true {
    if scanner.at >= scanner.text.length() {
      fail(scanner, start, "a literal is unterminated")
    }
    let unit = scanner.text.at(scanner.at)
    if unit == quote {
      let body = scanner.text[start:scanner.at].to_owned()
      scanner.at = scanner.at + 1
      return body
    }
    if public {
      let punctuation = match unit_char(unit) {
        '-'
        | '\''
        | '('
        | ')'
        | '+'
        | ','
        | '.'
        | '/'
        | ':'
        | '='
        | '?'
        | ';'
        | '!'
        | '*'
        | '#'
        | '@'
        | '$'
        | '_'
        | '%' => true
        _ => false
      }
      let legal = is_alnum(unit) ||
        unit == 0x20 ||
        unit == 0x0D ||
        unit == 0x0A ||
        punctuation
      if !legal {
        fail(
          scanner,
          scanner.at,
          "a character a public identifier may not hold",
        )
      }
    }
    scanner.at = scanner.at + 1
  }
  ""
}

///|
// Fill in the attributes the declaration gave defaults to, for an element the
// document is about to open. `present` is what the start tag itself carried.
fn apply_defaults(
  ctx : Ctx,
  qname : String,
  present : Array[(String, String)],
  at : Int32,
) -> Array[(String, String)] raise @moonxml.Refused {
  let out : Array[(String, String)] = present.copy()
  match ctx.defaults.get(qname) {
    None => ()
    Some(defs) =>
      for def in defs {
        match def.default {
          None => ()
          Some(value) => {
            let mut seen = false
            for pair in present {
              if pair.0 == def.name {
                seen = true
              }
            }
            if !seen {
              check_default_references(ctx, value, at)
              let expanded = expand_references(ctx, value, at, [], false)
              out.push((def.name, normalize(expanded, def.cdata)))
            }
          }
        }
      }
  }
  out
}

///|
// Whether the declaration says this element's attribute is typed `CDATA`, and
// therefore keeps the whitespace it was written with.
fn declared_cdata(ctx : Ctx, qname : String, attr : String) -> Bool {
  match ctx.defaults.get(qname) {
    Some(defs) =>
      for def in defs {
        if def.name == attr {
          return def.cdata
        }
      }
    None => ()
  }
  true
}

///|
// The spec's attribute-value normalization: a literal tab or newline is a
// space, and a typed attribute collapses runs of spaces and trims them.
fn normalize(value : String, cdata : Bool) -> String {
  let out = StringBuilder()
  let mut space = false
  for ch in value {
    if ch == '\t' || ch == '\n' || ch == '\r' {
      out.write_char(' ')
      space = true
    } else if ch == ' ' {
      if !cdata && space {
        continue
      }
      out.write_char(' ')
      space = true
    } else {
      out.write_char(ch)
      space = false
    }
  }
  if cdata {
    return out.to_string()
  }
  let text = out.to_string()
  let mut from = 0
  let mut to = text.length()
  while from < to && text.at(from) == 0x20 {
    from = from + 1
  }
  while to > from && text.at(to - 1) == 0x20 {
    to = to - 1
  }
  text[from:to].to_owned()
}

///|
// Expand the references inside an entity's replacement text or a default
// value: character references become their character, general entities become
// what they stand for. `stack` is the chain of entities being expanded, which
// is how recursion is caught.
fn expand_references(
  ctx : Ctx,
  body : String,
  at : Int32,
  stack : Array[String],
  content : Bool,
) -> String raise @moonxml.Refused {
  if !body.contains("&") {
    if !content && body.contains("<") {
      raise @moonxml.Malformed(
        at~,
        why="a `<` in an entity an attribute value names",
      )
    }
    return body
  }
  let out = StringBuilder()
  let n = body.length()
  let mut i = 0
  while i < n {
    if body.at(i) == 0x3C && body[i:n].has_prefix("<![CDATA[") {
      // A CDATA section is recognised before references are: what it holds is
      // text, `&` and all.
      let close = match find_text(body, "]]>", i) {
        Some(found) => found + 3
        None => n
      }
      out.write_string(body[i:close].to_owned())
      i = close
      continue
    }
    if body.at(i) != 0x26 {
      // Literal text is markup if it is markup; a literal `&` is the
      // character, and has to survive the second reading as one. Read as
      // attribute text there is no markup to be had, so a `<` is an error.
      if content && body.at(i) == 0x26 {
        out.write_string("&#38;")
      } else if !content && body.at(i) == 0x3C {
        raise @moonxml.Malformed(
          at~,
          why="a `<` in an entity an attribute value names",
        )
      } else {
        out.write_char(unit_char(body.at(i)))
      }
      i = i + 1
      continue
    }
    // a reference: `&#…;` or `&name;`. An `&` that starts neither is the
    // character itself — that is how `&amp;` stands for one ampersand without
    // the expansion being read as a reference again.
    let semi = find_char(body, i + 1, ';')
    if semi is None {
      raise @moonxml.Malformed(
        at~,
        why="a reference in replacement text never ends",
      )
    }
    let end = semi.unwrap()
    let name = body[i + 1:end].to_owned()
    if name.has_prefix("#") {
      // A character reference stands for a character, never for markup: in
      // content its `<` has to survive the second reading as text.
      let ch = numeric(name, at)
      if content && (ch == '&' || ch == '<') {
        out.write_string(if ch == '&' { "&#38;" } else { "&#60;" })
      } else {
        out.write_char(ch)
      }
    } else {
      out.write_string(expand_entity(ctx, name, at, stack, content~))
    }
    i = end + 1
  }
  out.to_string()
}

///|
// The character a numeric reference spells, as `&#65;` or `&#x41;`.
fn numeric(spelling : String, at : Int32) -> Char raise @moonxml.Refused {
  let hex = spelling.has_prefix("#x")
  let digits = if hex {
    spelling[2:spelling.length()].to_owned()
  } else {
    spelling[1:spelling.length()].to_owned()
  }
  let code = Some(@string.parse_int(digits, base=if hex { 16 } else { 10 })) catch {
    _ => None
  }
  match code {
    Some(value) =>
      if !is_char(value) {
        raise @moonxml.Malformed(
          at~,
          why="a character reference XML does not allow",
        )
      } else {
        value.unsafe_to_char()
      }
    None =>
      raise @moonxml.Malformed(
        at~,
        why="a character reference that is not a number",
      )
  }
}

///|
// What a general entity stands for, fully expanded. An entity this reader did
// not read — one declared in a file — stands for nothing, and its name is
// reported.
fn expand_entity(
  ctx : Ctx,
  name : String,
  at : Int32,
  stack : Array[String],
  content~ : Bool,
) -> String raise @moonxml.Refused {
  if stack.contains(name) {
    raise @moonxml.Malformed(at~, why="the entity `&\{name};` contains itself")
  }
  match ctx.ents.get(name) {
    None =>
      if ctx.external && !ctx.standalone {
        note_unresolved(ctx, name)
        ""
      } else {
        raise @moonxml.Malformed(at~, why="`&\{name};` was never declared")
      }
    Some(File) => {
      note_unresolved(ctx, name)
      ""
    }
    Some(Unparsed) =>
      raise @moonxml.Malformed(
        at~,
        why="`&\{name};` is unparsed: it stands for no text",
      )
    Some(Replacement(body)) => {
      spend(ctx, at, body.length())
      stack.push(name)
      let expanded = expand_references(ctx, body, at, stack, content)
      ignore(stack.pop())
      expanded
    }
  }
}

///|
/// Record a general entity, unless the name already stands for something: the
/// first declaration of a name is the one that binds.
fn set_entity(scanner : Scan, name : String, entity : Entity) -> Unit {
  if scanner.ctx.ents.get(name) is None {
    scanner.ctx.ents.set(name, entity)
  }
}

///|
/// A default value is read where its declaration stands, so the entities it
/// names have to be declared by then, and none of them may be a file: a
/// default is text, and a file is not read.
fn check_default_references(
  ctx : Ctx,
  value : String,
  at : Int32,
) -> Unit raise @moonxml.Refused {
  let n = value.length()
  let mut i = 0
  while i < n {
    if value.at(i) != 0x26 {
      i = i + 1
      continue
    }
    let semi = match find_char(value, i + 1, ';') {
      Some(found) => found
      None => raise @moonxml.Malformed(at~, why="a reference never ends")
    }
    let name = value[i + 1:semi].to_owned()
    if !name.has_prefix("#") {
      match ctx.ents.get(name) {
        None =>
          raise @moonxml.Malformed(
            at~,
            why="a default names an entity declared later",
          )
        Some(File) | Some(Unparsed) =>
          raise @moonxml.Malformed(
            at~,
            why="a default value is not a place for a file",
          )
        Some(Replacement(_)) => ()
      }
    }
    i = semi + 1
  }
}
