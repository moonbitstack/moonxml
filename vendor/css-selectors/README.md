# W3C CSS3 selectors suite (vendored)

Source: <https://github.com/web-platform-tests/wpt>, `css/selectors/old-tests`,
vendored on 2026-11-01 from `master` (`41ce24f042d9`). That directory is the
CSS3 Selectors Test Suite, converted to XHTML and kept by wpt for the cases a
browser test harness can still run.

Layout: one test per `css3-modsel-N.xml`. Each file has a `<style>` element with
the rule under test (the one that paints `lime`), the document to run it against
inline, and a script that asserts which element ids end up lime:

```js
assert_background_color('t1', LIME);          // t1 must match
assert_not_background_color('u1', LIME);      // u1 must not match
assert_equals(getComputedStyle(document.getElementById('t1'))
                .backgroundColor, "rgb(0, 255, 0)");
```

Only the `*.xml` files are vendored; `common.js` and `WEB_FEATURES.yml` are not
needed because the assertions are read statically by
`scripts/gen_css_selector_cases.py`.

Files that cannot be decided by a static query are skipped by the generator, and
the count is printed when it runs:

- **interaction** — the script uses `promise_test` or `test_driver`, so the
  result depends on a pointer or a timer;
- **dynamic** — the selector uses `:hover`, `:active`, `:focus`, `:visited`,
  `:target` or `:link`;
- **no-rule** — no rule paints lime, so there is nothing to check;
- **no-ids** — the file carries no machine-readable assertion (the older part of
  the suite relied on a human looking at the rendering).

The `LICENSE.md` file is wpt's licence (BSD-3-Clause).
