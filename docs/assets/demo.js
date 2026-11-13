// The site's live demo: every element marked `data-demo` drives the library
// compiled to JavaScript, so what a visitor sees is this engine's answer to
// the markup and query they typed — not a recording of an earlier one.

const panels = document.querySelectorAll("[data-demo]");
if (panels.length) {
  let lib = null;
  // Relative to this module, not to the page: the engine sits beside the
  // pages, this script sits in their assets.
  const ready = import(new URL("../engine/moonxml.js", import.meta.url).href)
    .then((module) => {
      lib = module;
    })
    .catch(() => {
      lib = null;
    });

  const field = (panel, role) => panel.querySelector('[data-role="' + role + '"]');

  // Text goes into the page as text: a visitor's markup is data here, not
  // something this script hands to the HTML parser a second time.
  const cell = (tag, text, className) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    node.textContent = text;
    return node;
  };

  const repairs = (tally) => {
    if (!tally || !tally.total) return "nothing repaired";
    const parts = [];
    if (tally.implied) parts.push(tally.implied + " implied");
    if (tally.reparented) parts.push(tally.reparented + " reparented");
    if (tally.dropped) parts.push(tally.dropped + " dropped");
    if (tally.closed_at_eof) parts.push(tally.closed_at_eof + " closed at the end");
    return "repaired " + tally.total + ": " + parts.join(", ");
  };

  const paint = (panel, answer) => {
    const out = field(panel, "out");
    const rows = field(panel, "rows");
    const doc = field(panel, "doc");
    if (!answer.ok) {
      if (out) out.textContent = answer.error;
      if (rows) rows.replaceChildren();
      if (doc) doc.textContent = "";
      return;
    }
    if (out) {
      out.textContent =
        answer.total +
        (answer.total === 1 ? " node" : " nodes") +
        " · " +
        repairs(answer.repairs);
    }
    if (rows) {
      const body = rows.querySelector("tbody") || rows;
      body.replaceChildren();
      for (const row of answer.rows) {
        const tr = document.createElement("tr");
        const label = document.createElement("td");
        label.append(cell("code", row.label));
        tr.append(label);
        tr.append(cell("td", row.text || "—", row.text ? "" : "none"));
        const markup = document.createElement("td");
        markup.append(cell("code", row.markup));
        tr.append(markup);
        body.append(tr);
      }
    }
    if (doc) doc.textContent = answer.document;
  };

  const parse = (text) => {
    try {
      return JSON.parse(text);
    } catch (error) {
      return { ok: false, error: "the engine answered something that is not JSON" };
    }
  };

  const ask = async (panel, edit) => {
    const status = field(panel, "status");
    await ready;
    if (!lib) {
      if (status) status.textContent = "the engine did not load";
      return;
    }
    if (status) status.textContent = "the engine is running in this page";
    const markup = field(panel, "markup").value;
    const engine = field(panel, "engine") ? field(panel, "engine").value : "css";
    const query = field(panel, "query").value;
    const text = field(panel, "text");
    paint(
      panel,
      parse(
        edit
          ? lib.rewrite(markup, engine, query, text ? text.value : "")
          : lib.probe(markup, engine, query)
      )
    );
  };

  for (const panel of panels) {
    const form = panel.querySelector("form");
    const edit = field(panel, "edit");
    if (form) {
      form.addEventListener("submit", (event) => {
        event.preventDefault();
        ask(panel, false);
      });
    }
    if (edit) {
      edit.addEventListener("click", (event) => {
        event.preventDefault();
        ask(panel, true);
      });
    }
    ask(panel, false);
  }
}
