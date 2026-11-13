// The site's live demo: the library itself, built to JavaScript, so the page
// runs the queries it shows instead of replaying answers taken earlier.
//
// Everything crosses the boundary as a string — markup in, a JSON document
// out — so the page needs to know nothing about MoonBit values.

///|
/// At most `limit` characters, with an ellipsis when there were more. A demo
/// row is a line on a page, not a dump of the subtree.
fn clipped(text : String, limit : Int32) -> String {
  let out = StringBuilder()
  let mut seen = 0
  for ch in text {
    if seen >= limit {
      out.write_string("…")
      break
    }
    out.write_char(ch)
    seen += 1
  }
  out.to_string()
}

///|
/// Runs of whitespace in text a page indented for its own sake become one
/// space, so a row shows what a reader would see.
fn collapsed(text : String) -> String {
  let out = StringBuilder()
  let mut space = false
  let mut written = 0
  for ch in text.trim() {
    if ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r' {
      space = true
    } else {
      if space && written > 0 {
        out.write_char(' ')
      }
      space = false
      out.write_char(ch)
      written += 1
    }
  }
  out.to_string()
}

///|
/// How the page names a node in a result row: the tag, its id, its classes —
/// the same shape a selector would write.
fn label_of(node : @moonxml.Node) -> String {
  match node {
    ElementNode(element) => {
      let out = StringBuilder()
      out.write_string(@moonxml.local_of(node.name()))
      match element.attr("id") {
        Some(id) => {
          out.write_char('#')
          out.write_string(id)
        }
        None => ()
      }
      for class in element.classes() {
        out.write_char('.')
        out.write_string(class)
      }
      out.to_string()
    }
    TextNode(_) => "#text"
    CDataNode(_) => "#cdata"
    CommentNode(_) => "#comment"
    ProcessingInstructionNode(_) => "#instruction"
    DoctypeNode(_) => "#doctype"
    AttributeNode(attribute) => "@\{attribute.name}"
    NamespaceNode(space) =>
      if space.prefix == "" {
        "xmlns"
      } else {
        "xmlns:\{space.prefix}"
      }
  }
}

///|
fn row_of(node : @moonxml.Node, html~ : Bool) -> Json {
  {
    "label": Json::string(label_of(node)),
    "text": Json::string(clipped(collapsed(node.text()), 80)),
    "markup": Json::string(
      clipped(
        if html {
          @moonxml.dumps_html(node)
        } else {
          @moonxml.dumps(node)
        },
        120,
      ),
    ),
  }
}

///|
fn repairs_json(repairs : @moonxml.Repairs) -> Json {
  {
    "implied": Json::number(
      repairs.implied.to_double(),
      repr=repairs.implied.to_string(),
    ),
    "dropped": Json::number(
      repairs.dropped.to_double(),
      repr=repairs.dropped.to_string(),
    ),
    "reparented": Json::number(
      repairs.reparented.to_double(),
      repr=repairs.reparented.to_string(),
    ),
    "closed_at_eof": Json::number(
      repairs.closed_at_eof.to_double(),
      repr=repairs.closed_at_eof.to_string(),
    ),
    "total": Json::number(
      repairs.total().to_double(),
      repr=repairs.total().to_string(),
    ),
  }
}

///|
/// The page may ask for more rows than a table can carry; the count it shows
/// is the whole answer's, the rows are the first few.
const ROWS_SHOWN : Int32 = 40

///|
fn answer_json(
  document : @moonxml.Document,
  found : @moonxml.Selection,
  engine : String,
  query : String,
) -> Json {
  let rows : Array[Json] = []
  let mut index = 0
  while index < found.length() && index < ROWS_SHOWN {
    rows.push(row_of(found.at(index), html=true))
    index += 1
  }
  {
    "ok": Json::boolean(true),
    "engine": Json::string(engine),
    "query": Json::string(query),
    "total": Json::number(
      found.length().to_double(),
      repr=found.length().to_string(),
    ),
    "rows": Json::array(rows),
    "repairs": repairs_json(document.repairs()),
    "document": Json::string(document.dumps_html()),
  }
}

///|
fn fault_json(error : Error) -> Json {
  { "ok": Json::boolean(false), "error": Json::string(error.to_string()) }
}

///|
fn select(
  document : @moonxml.Document,
  engine : String,
  query : String,
) -> @moonxml.Selection raise @moonxml.Refused {
  if engine == "xpath" {
    document.xpath(query)
  } else {
    document.css(query)
  }
}

///|
/// Read the markup the visitor typed, run the query, and answer what the
/// engine found — the rows, the count, what the parser repaired, and the
/// document as HTML writes it back.
pub fn probe(markup : String, engine : String, query : String) -> String {
  let document = @html.loads(markup)
  let answer = answer_json(
    document,
    select(document, engine, query),
    engine,
    query,
  ) catch {
    error => fault_json(error)
  }
  answer.stringify()
}

///|
/// The same query, then `set_text` on every node it answered, then the
/// document written back: the whole claim of the library in one call.
pub fn rewrite(
  markup : String,
  engine : String,
  query : String,
  text : String,
) -> String {
  let document = @html.loads(markup)
  let answer = try {
    let found = select(document, engine, query)
    found.set_text(text)
    answer_json(document, found, engine, query)
  } catch {
    error => fault_json(error)
  }
  answer.stringify()
}

///|
/// The document alone: what the tolerance reader made of the markup.
pub fn read(markup : String) -> String {
  let document = @html.loads(markup)
  let answer : Json = {
    "ok": Json::boolean(true),
    "repairs": repairs_json(document.repairs()),
    "document": Json::string(document.dumps_html()),
  }
  answer.stringify()
}
