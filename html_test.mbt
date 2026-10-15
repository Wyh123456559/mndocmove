///|
fn html_tree(source : String) -> @mndocmove.DocTree raise {
  @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("README.md", source),
    @mndocmove.Entry::markdown("doc/guide.md", "[Home](../README.md)\n"),
    @mndocmove.Entry::new("doc/logo.svg", b"<svg/>"),
  ])
}

///|
test "HTML opt-in updates inline and block href src with original quotes and layout" {
  let source = "😀 <a HREF='doc/guide.md?x=1&amp;y=2#part' title=\"a > b\">Go</a>\r\n\r\n<p align=\"center\">\r\n  <img SRC=\"doc/logo.svg\" alt='logo' width=\"100\" />\r\n</p>\r\n"
  let tree = html_tree(source)
  let moves = [@mndocmove.Move::new("doc", "assets")]
  expect_code(
    () => ignore(@mndocmove.plan_moves(tree, moves)),
    "UnsupportedMarkdown",
  )
  let plan = @mndocmove.plan_moves(tree, moves, profile=StaticHtml)
  assert_eq(plan.edits().length(), 2)
  let expected = source
    .replace(old="doc/guide.md", new="assets/guide.md")
    .replace(old="doc/logo.svg", new="assets/logo.svg")
  assert_eq(plan.replay(tree).get("README.md").unwrap().text(), expected)
  assert_true(plan.profile() is @mndocmove.StaticHtml)
  assert_eq(
    @mndocmove.MovePlan::from_json_string(plan.to_json_string()).preview(),
    plan.preview(),
  )
}

///|
test "HTML and Markdown links share simultaneous source and target moves" {
  let tree = html_tree(
    "<a href=\"doc/guide.md\">Go</a> [Markdown](doc/guide.md)\n",
  )
  let p = @mndocmove.plan_moves(
    tree,
    [
      @mndocmove.Move::new("README.md", "manual/README.md"),
      @mndocmove.Move::new("doc", "assets"),
    ],
    profile=StaticHtml,
  )
  let next = p.replay(tree)
  assert_eq(
    next.get("manual/README.md").unwrap().text(),
    "<a href=\"../assets/guide.md\">Go</a> [Markdown](../assets/guide.md)\n",
  )
  assert_eq(
    next.get("assets/guide.md").unwrap().text(),
    "[Home](../manual/README.md)\n",
  )
}

///|
test "HTML source encoding preserves suffix semantics through reparse" {
  let original = "<a href='doc/guide.md?x=&#39;q&#39;&amp;y=(2)#frag'>Guide</a>\n"
  let tree = html_tree(original)
  let p = @mndocmove.plan_moves(
    tree,
    [@mndocmove.Move::new("doc", "new docs/中文")],
    profile=StaticHtml,
  )
  let next = p.replay(tree)
  assert_eq(
    next.get("README.md").unwrap().text(),
    "<a href='new%20docs/%E4%B8%AD%E6%96%87/guide.md?x=&#39;q&#39;&amp;y=(2)#frag'>Guide</a>\n",
  )
  let back = @mndocmove.plan_moves(
    next,
    [@mndocmove.Move::new("new docs/中文", "doc")],
    profile=StaticHtml,
  )
  assert_eq(back.replay(next).get("README.md").unwrap().text(), original)
}

///|
test "comments code examples external URLs and details layout stay unchanged" {
  let source = "<!-- <img src=\"missing\"> -->\n\n`<img src=\"missing\">`\n\n```html\n<img src=\"missing\">\n```\n\n<details open class=\"info\">\n<summary>Info</summary>\n<a href=\"https://example.com/?x=1&amp;y=2\">Web</a>\n<img src=\"doc/logo.svg\" aria-label=\"Logo\">\n</details>\n"
  let tree = html_tree(source)
  let p = @mndocmove.plan_moves(
    tree,
    [@mndocmove.Move::new("doc", "assets")],
    profile=StaticHtml,
  )
  assert_eq(p.edits().length(), 1)
  assert_eq(
    p.replay(tree).get("README.md").unwrap().text(),
    source.replace(old="doc/logo.svg", new="assets/logo.svg"),
  )
}

///|
test "unknown URL grammars dynamic HTML and duplicate attributes refuse whole plan" {
  for
    source in [
      "<img src=\"doc/logo.svg\" srcset=\"doc/logo.svg 2x\">", "<img src=\"doc/logo.svg\" SRC=\"doc/logo.svg\">",
      "<a href=\"doc/guide.md\" style=\"background:url(doc/logo.svg)\">x</a>", "<img src=\"doc/logo.svg\" data-src=\"doc/logo.svg\">",
      "<img src=doc/logo.svg>", "<base href=\"doc/\">", "<script src=\"doc/logo.svg\"></script>",
      "<picture><img src=\"doc/logo.svg\"></picture>", "<a href=\"doc/guide.md?x=1&y=2\">x</a>",
      "<a href=\"doc/guide.md?x=&bogus;\">x</a>", "<img src=\"{{image}}\">", "<div>\n{{content}}\n</div>",
      "<a href=\" doc/guide.md\">x</a>", "<a href=\"doc/guide.md&#9;\">x</a>",
    ] {
    let tree = html_tree(source)
    expect_code(
      () => {
        ignore(
          @mndocmove.plan_moves(
            tree,
            [@mndocmove.Move::new("doc", "assets")],
            profile=StaticHtml,
          ),
        )
      },
      "UnsupportedHtml",
    )
    assert_eq(tree.get("README.md").unwrap().text(), source)
  }
  assert_eq(
    @mndocmove.plan_moves(
      html_tree("<img src='doc/logo.svg'>"),
      [@mndocmove.Move::new("doc", "assets")],
      profile=StaticHtml,
    )
    .edits()
    .length(),
    1,
  )
}

///|
test "HTML backslash is not silently decoded as Markdown escape" {
  let tree = html_tree("<a href=\"doc/guide\\.md\">x</a>")
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_moves(
          tree,
          [@mndocmove.Move::new("doc", "assets")],
          profile=StaticHtml,
        ),
      )
    },
    "UnsupportedUrl",
  )
}

///|
test "first capability wire and defaults remain byte compatible" {
  let old = "[\"mndocmove\",1,\"commonmark\",[[\"r.md\",\"4869\"]],[[\"r.md\",\"s.md\"]]]"
  let p = @mndocmove.MovePlan::from_json_string(old)
  assert_eq(p.to_json_string(), old)
  assert_eq(
    p
    .replay(@mndocmove.DocTree::new([@mndocmove.Entry::markdown("r.md", "Hi")]))
    .get("s.md")
    .unwrap()
    .text(),
    "Hi",
  )
  assert_true(p.profile() is @mndocmove.CommonMark)
  let tree = html_tree("<img src='doc/logo.svg'>")
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_moves(tree, [@mndocmove.Move::new("doc", "assets")]),
      )
    },
    "UnsupportedMarkdown",
  )
}

///|
test "document moves cannot reinterpret opaque bytes as Markdown or vice versa" {
  let tree = html_tree("[Guide](doc/guide.md)")
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_moves(
          tree,
          [@mndocmove.Move::new("doc/logo.svg", "logo.md")],
          profile=StaticHtml,
        ),
      )
    },
    "FileKindChange",
  )
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_moves(tree, [
          @mndocmove.Move::new("README.md", "README.txt"),
        ]),
      )
    },
    "FileKindChange",
  )
}

///|
test "rewriting validates decoded suffixes including entity-encoded line breaks" {
  let tree = html_tree("[Guide](doc/guide.md?x=&NewLine;#a)\n")
  let p = @mndocmove.plan_moves(tree, [@mndocmove.Move::new("doc", "assets")])
  assert_eq(
    p.replay(tree).get("README.md").unwrap().text(),
    "[Guide](assets/guide.md?x=&#10;#a)\n",
  )
}
