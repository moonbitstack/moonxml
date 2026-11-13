#!/usr/bin/env python3
"""Read this library's writing with two mature implementations, and theirs with ours.

`src/interop` parses every case in its corpus and prints what this library
wrote back. This script takes that output and asks lxml and html5lib — neither
of which this project wrote — to read it:

* XML. lxml parses the source and parses what we wrote; the two canonical
  forms must be the same, which is what "the same document" means to an XML
  processor. The bytes are compared too, because the writer promises a
  well-formed document it did not edit comes back exactly as it was.
* HTML. html5lib parses the source and parses what we wrote; serializing both
  with html5lib must give the same text. A browser reading our page and a
  browser reading theirs therefore build the same tree.

Both directions are covered by one exchange: bytes this library produced are
read by the other implementation, and the bytes that implementation produces
are compared against this one's. Every case is reported by name; the run fails
if any case disagrees.

    python3 scripts/check_interop.py                # runs the corpus itself
    python3 scripts/check_interop.py --cases out.tsv  # replays a saved run

Requirements: lxml and html5lib. In CI they are installed before this runs.
"""

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def unescape(text):
    out = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            nxt = text[i + 1]
            out.append({"n": "\n", "t": "\t", "r": "\r", "\\": "\\"}.get(nxt, nxt))
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def cases(args):
    if args.cases:
        text = Path(args.cases).read_text(encoding="utf-8")
    else:
        done = subprocess.run(
            [args.moon, "run", "src/interop", "--target", "native"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        if done.returncode != 0:
            sys.stderr.write(done.stdout)
            sys.stderr.write(done.stderr)
            raise SystemExit("the corpus program did not run")
        text = done.stdout
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) != 4:
            raise SystemExit("a corpus line does not have four fields: %r" % line)
        yield parts[0], parts[1], unescape(parts[2]), unescape(parts[3])


def check_xml(source, written, etree):
    """lxml's reading of the source against lxml's reading of what we wrote."""
    try:
        theirs = etree.fromstring(source.encode("utf-8"))
    except etree.XMLSyntaxError as error:
        return False, False, "lxml refuses the source: %s" % error
    if written.startswith("refused:"):
        return False, False, "this library refuses what lxml reads (%s)" % written
    try:
        ours = etree.fromstring(written.encode("utf-8"))
    except etree.XMLSyntaxError as error:
        return False, False, "lxml refuses what we wrote: %s" % error
    # The canonical form is the comparison an XML processor makes: it ignores
    # prefixes and attribute quoting, and keeps everything a document means.
    if etree.tostring(theirs, method="c14n") != etree.tostring(ours, method="c14n"):
        return False, False, "the canonical forms differ"
    return True, written == source, "lxml reads source and output as one document"


def serialize(tree, html5lib):
    return html5lib.serialize(
        tree,
        tree="etree",
        omit_optional_tags=False,
        quote_attr_values="always",
        alphabetical_attributes=False,
        use_trailing_solidus=False,
    )


def check_html(source, written, html5lib):
    """html5lib's reading of the source against its reading of what we wrote."""
    theirs = serialize(html5lib.parse(source, namespaceHTMLElements=False), html5lib)
    ours = serialize(html5lib.parse(written, namespaceHTMLElements=False), html5lib)
    if theirs != ours:
        return False, False, "html5lib reads the two as different trees://n  %s\n  %s" % (
            theirs,
            ours,
        )
    return True, written == theirs, "html5lib reads both as one tree"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--moon", default="moon")
    ap.add_argument("--cases", help="a corpus run saved earlier, instead of running it")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    try:
        from lxml import etree
        import html5lib
    except ImportError as error:
        print("lxml and html5lib are needed: %s" % error, file=sys.stderr)
        return 2

    passed = 0
    same_bytes = 0
    failed = []
    xml_cases = html_cases = 0
    for name, flavour, source, written in cases(args):
        if flavour == "xml":
            xml_cases += 1
            ok, identical, why = check_xml(source, written, etree)
        else:
            html_cases += 1
            ok, identical, why = check_html(source, written, html5lib)
        if ok:
            passed += 1
            if identical:
                same_bytes += 1
            if args.verbose:
                print("ok   %s — %s%s" % (name, why, "" if identical else ", bytes differ"))
        else:
            failed.append((name, why))
            print("FAIL %s — %s" % (name, why.splitlines()[0]))

    total = xml_cases + html_cases
    print(
        "%d of %d cases agree with lxml and html5lib (%d XML, %d HTML); "
        "%d of them are also byte-identical"
        % (passed, total, xml_cases, html_cases, same_bytes)
    )
    for name, why in failed:
        print("\n%s:\n%s" % (name, why))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
