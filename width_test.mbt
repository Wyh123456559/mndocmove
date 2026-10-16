///|
test "width candidates and static sizes retain exact source while document and assets move" {
  let source = "\uFEFF# 😀\r\n\r\n<picture>\r\n<source sizes='(max-width: 40em) 100vw, 800px' srcset='assets/a.png 000000320w,\tassets/b.png 999999999w'>\r\n<img SRCSET=\"assets/a.png 320w, assets/b.png 640w\" SIZES=\"(min-width: 30rem) 50vw, 100vw\" src='assets/a.png' alt='Keep'>\r\n</picture>"
  let tree = srcset_tree(source)
  let plan = @mndocmove.plan_moves(
    tree,
    [
      @mndocmove.Move::new("README.md", "manual/README.md"),
      @mndocmove.Move::new("assets", "images"),
    ],
    profile=StaticHtml,
  )
  let wire = plan.to_json_string()
  let loaded = @mndocmove.MovePlan::from_json_string(wire)
  assert_eq(loaded.to_json_string(), wire)
  assert_eq(plan.edits().length(), 5)
  for edit in plan.edits() {
    assert_eq(source[edit.start:edit.end].to_owned(), edit.before)
    assert_true(!edit.before.contains("w"))
  }
  let output = loaded.replay(tree)
  assert_eq(
    output.get("manual/README.md").unwrap().text(),
    source.replace_all(old="assets/", new="../images/"),
  )
  assert_true(loaded.review().contains("000000320w"))
  assert_true(loaded.check(output, side=Result).is_match())
  assert_eq(loaded.restore(output).entries(), tree.entries())
  assert_eq(tree.get("README.md").unwrap().text(), source)
}

///|
test "width sets allow browser default size and preserve external candidates and query entities" {
  for
    sizes in [
      "", " sizes='0'", " sizes='(max-width: 600px) 99.500vw, 0px'", " sizes='(min-width: 0) 100vmin, 50VMAX'",
    ] {
    let source = "<img srcset='assets/a.png?x=1&amp;y=2#part 320w, https://example.com/b.png 640w'" +
      sizes +
      ">"
    let tree = srcset_tree(source)
    let plan = @mndocmove.plan_moves(
      tree,
      [@mndocmove.Move::new("assets", "images")],
      profile=StaticHtml,
    )
    assert_eq(
      plan.replay(tree).get("README.md").unwrap().text(),
      source.replace(old="assets/", new="images/"),
    )
  }
}

///|
test "invalid widths mixed descriptors and duplicate numerical widths refuse atomically" {
  for
    value in [
      "0w", "000w", "-1w", "+1w", "1.0w", "1e2w", "1W", "1000000000w", "w", "320w 640w",
    ] {
    let source = "<img srcset='assets/a.png " + value + "'>"
    assert_eq(srcset_diagnostic(source).code, "UnsupportedHtml")
  }
  for
    value in [
      "assets/a.png 320w, assets/b.png 0320w", "assets/a.png 320w, assets/b.png 2x",
      "assets/a.png, assets/b.png 320w", "assets/a.png 320w, assets/b.png",
    ] {
    assert_eq(
      srcset_diagnostic("<source srcset='" + value + "'>").code,
      "UnsupportedHtml",
    )
  }
  let tree = srcset_tree("<img srcset='assets/a.png 320w'>")
  assert_eq(
    @mndocmove.plan_moves(
      tree,
      [@mndocmove.Move::new("assets", "images")],
      profile=StaticHtml,
    )
    .edits()
    .length(),
    1,
  )
}

///|
test "sizes refuse unsupported CSS rather than silently passing unknown URL grammars" {
  for
    value in [
      "", " ", "auto", "100%", "calc(100vw - 10px)", "url(a.png)", "var(--size)",
      "100\\76w", "&#49;00vw", "-1px", ".5vw", "1.vw", "1e2px", "1.0000000px", "1000000000px",
      "100vw,", "100vw, 50vw", ", 100vw", "(max-width: 600px) 100vw", "(orientation: portrait) 100vw, 800px",
      "(max-width: 60vw) 100vw, 800px", "(max-width:600px)100vw, 800px", "(max-width: 600px) and (min-width: 300px) 100vw, 800px",
      "(max-width: 600px 100vw, 800px", "\u00A0100vw", "100vw\u00A0", "100vw\u007F",
    ] {
    let source = "😀 <img srcset='assets/a.png 320w' sizes='" + value + "'>"
    let diagnostic = srcset_diagnostic(source)
    assert_eq(diagnostic.code, "UnsupportedHtml")
    assert_eq(diagnostic.path, "README.md")
    assert_true(diagnostic.offset >= 3 && diagnostic.offset < source.length())
  }
  for
    source in [
      "<img sizes='100vw'>", "<img srcset='assets/a.png 1x' sizes='100vw'>", "<img srcset='assets/a.png 320w' sizes='100vw' SIZES='50vw'>",
      "<a sizes='100vw'>x</a>",
    ] {
    assert_eq(srcset_diagnostic(source).code, "UnsupportedHtml")
  }
}

///|
test "sizes entry and UTF16 budgets accept exact boundary then recover after refusal" {
  let entries = StringBuilder()
  for _ in 0..<31 {
    entries.write_string("(max-width: 1px) 1vw, ")
  }
  entries.write_string("100vw")
  let valid = "<img sizes='" +
    entries.to_string() +
    "' srcset='assets/a.png 1w'>"
  let tree = srcset_tree(valid)
  let plan = @mndocmove.plan_moves(
    tree,
    [@mndocmove.Move::new("assets", "images")],
    profile=StaticHtml,
  )
  assert_eq(plan.edits().length(), 1)
  assert_eq(
    srcset_diagnostic(
      valid.replace(old="100vw", new="(max-width: 2px) 1vw, 100vw"),
    ).code,
    "UnsupportedHtml",
  )
  let spaces = StringBuilder()
  for _ in 0..<4095 {
    spaces.write_string(" ")
  }
  let source = "<img sizes='0" +
    spaces.to_string() +
    "' srcset='assets/a.png 1w'>"
  let bounded = srcset_tree(source)
  assert_eq(
    @mndocmove.plan_moves(
      bounded,
      [@mndocmove.Move::new("assets", "images")],
      profile=StaticHtml,
    )
    .edits()
    .length(),
    1,
  )
  assert_eq(
    srcset_diagnostic(source.replace(old="sizes='0", new="sizes='0 ")).code,
    "UnsupportedHtml",
  )
  assert_eq(plan.restore(plan.replay(tree)).entries(), tree.entries())
}
