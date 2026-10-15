///|
fn fixture() -> @mndocmove.DocTree raise {
  @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "README.md", "😀 [Guide](docs/guide.md#intro)\r\n![diagram](img/a.png)\r\n",
    ),
    @mndocmove.Entry::markdown(
      "docs/guide.md", "[Home](../README.md)\n[diagram][d]\n\n[d]: ../img/a.png \"keep title\"\n",
    ),
    @mndocmove.Entry::new("img/a.png", b"\x00\xFF\x01"),
  ])
}

///|
test "incoming outgoing reference links and opaque assets are relocated together" {
  let tree = fixture()
  let plan = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("docs", "manual/deep"),
    @mndocmove.Move::new("img", "assets"),
  ])
  let next = plan.replay(tree)
  assert_eq(
    next.get("README.md").unwrap().text(),
    "😀 [Guide](manual/deep/guide.md#intro)\r\n![diagram](assets/a.png)\r\n",
  )
  assert_eq(
    next.get("manual/deep/guide.md").unwrap().text(),
    "[Home](../../README.md)\n[diagram][d]\n\n[d]: ../../assets/a.png \"keep title\"\n",
  )
  assert_eq(next.get("assets/a.png").unwrap().data(), b"\x00\xFF\x01")
  assert_eq(plan.edits().length(), 4)
  assert_eq(tree.get("docs/guide.md").unwrap().path(), "docs/guide.md")
}

///|
test "full wire roundtrip recomputes edits and preserves arbitrary bytes" {
  let tree = fixture()
  let p = @mndocmove.plan_moves(tree, [@mndocmove.Move::new("docs", "manual")])
  let restored = @mndocmove.MovePlan::from_json_string(p.to_json_string())
  assert_eq(restored.to_json_string(), p.to_json_string())
  assert_eq(restored.preview(), p.preview())
  assert_true(restored.replay(tree).entries() == p.replay(tree).entries())
}

///|
test "move ordering and inventory ordering do not affect deterministic output" {
  let tree = fixture()
  let moves = [
    @mndocmove.Move::new("docs", "manual"),
    @mndocmove.Move::new("img", "assets"),
  ]
  let reversed = [moves[1], moves[0]]
  let files = tree.entries()
  let alternate = @mndocmove.DocTree::new([files[2], files[1], files[0]])
  assert_eq(
    @mndocmove.plan_moves(tree, moves).to_json_string(),
    @mndocmove.plan_moves(alternate, reversed).to_json_string(),
  )
}

///|
test "source formatting is untouched outside URLs and code stays literal" {
  let text = "# Heading\r\n\r\n`[literal](missing.md)`\r\n\r\n```md\r\n[x](missing.md)\r\n```\r\n\r\n[go](<a%20b.md?x=1&amp;y=2#z> 'Title')\r\n[web](https://example.com/a)\r\n[local](#Heading)\r\n"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", text),
    @mndocmove.Entry::markdown("a b.md", "Hi"),
  ])
  let p = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("a b.md", "中文/z.md"),
  ])
  assert_eq(p.edits()[0].before, "a%20b.md?x=1&amp;y=2#z")
  assert_eq(p.edits()[0].after, "%E4%B8%AD%E6%96%87/z.md?x=1&amp;y=2#z")
  let result = p.replay(tree)
  let second = @mndocmove.plan_moves(result, [
    @mndocmove.Move::new("中文/z.md", "a b.md"),
  ])
  assert_eq(second.replay(result).get("r.md").unwrap().text(), text)
}

///|
test "unchanged relation keeps unusual raw escape spelling" {
  let source = "[x](a%20b.md)\n"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("d/r.md", source),
    @mndocmove.Entry::markdown("d/a b.md", ""),
  ])
  let p = @mndocmove.plan_moves(tree, [@mndocmove.Move::new("d", "m")])
  assert_eq(p.edits().length(), 0)
  assert_eq(p.replay(tree).get("m/r.md").unwrap().text(), source)
}

///|
fn expect_code(
  action : () -> Unit raise @mndocmove.MoveError,
  code : String,
) -> Unit raise {
  let actual = try {
    action()
    "NO_ERROR"
  } catch {
    @mndocmove.Refused(d) => d.code
  }
  assert_eq(actual, code)
}

///|
test "stale snapshot includes assets deleted files and additions" {
  let tree = fixture()
  let p = @mndocmove.plan_moves(tree, [@mndocmove.Move::new("docs", "manual")])
  let files = tree.entries()
  files.push(@mndocmove.Entry::markdown("new.md", ""))
  expect_code(
    () => ignore(p.replay(@mndocmove.DocTree::new(files))),
    "StaleSnapshot",
  )
  expect_code(
    () => ignore(p.replay(@mndocmove.DocTree::new([tree.entries()[0]]))),
    "StaleSnapshot",
  )
  let changed = tree
    .entries()
    .map(fn(e) {
      if e.path() == "img/a.png" {
        @mndocmove.Entry::new("img/a.png", b"new")
      } else {
        e
      }
    })
  expect_code(
    () => ignore(p.replay(@mndocmove.DocTree::new(changed))),
    "StaleSnapshot",
  )
}

///|
test "collisions path aliases reserved names and source overlap are rejected" {
  for
    path in [
      "../a.md", "/a.md", "a//b", "a\\b", "a/CON.txt", "a/x.", "C:/x", "a/x ",
    ] {
    expect_code(
      () => {
        ignore(@mndocmove.DocTree::new([@mndocmove.Entry::markdown(path, "")]))
      },
      "InvalidPath",
    )
  }
  expect_code(
    () => {
      ignore(
        @mndocmove.DocTree::new([
          @mndocmove.Entry::markdown("A", ""),
          @mndocmove.Entry::markdown("a/b", ""),
        ]),
      )
    },
    "PathCollision",
  )
  let tree = fixture()
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_moves(tree, [
          @mndocmove.Move::new("docs/guide.md", "img/a.png"),
        ]),
      )
    },
    "PathCollision",
  )
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_moves(tree, [
          @mndocmove.Move::new("docs", "a"),
          @mndocmove.Move::new("docs/guide.md", "b"),
        ]),
      )
    },
    "OverlappingMoves",
  )
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_moves(tree, [@mndocmove.Move::new("missing", "b")]),
      )
    },
    "MissingSource",
  )
}

///|
test "unsupported syntax bad escapes missing targets and root escapes refuse atomically" {
  for
    (source, code) in [
      ("[x](missing.md)", "MissingTarget"),
      ("[x](../x.md)", "OutsideRoot"),
      ("[x](/x.md)", "UnsupportedUrl"),
      ("[x](a%ZZ.md)", "InvalidEscape"),
      ("[x](a%2Fb.md)", "AmbiguousEscape"),
      ("[x](%FF.md)", "InvalidEscape"),
      ("<img src=\"a.png\">", "UnsupportedMarkdown"),
      ("[[wiki]]", "UnsupportedMarkdown"),
    ] {
    let tree = @mndocmove.DocTree::new([
      @mndocmove.Entry::markdown("r.md", source),
    ])
    expect_code(
      () => {
        ignore(
          @mndocmove.plan_moves(tree, [@mndocmove.Move::new("r.md", "d/r.md")]),
        )
      },
      code,
    )
    assert_eq(tree.get("r.md").unwrap().text(), source)
  }
  // A failure leaves no state in the planner; an independent valid operation works.
  assert_eq(
    @mndocmove.plan_moves(fixture(), [@mndocmove.Move::new("docs", "manual")])
    .edits()
    .length(),
    1,
  )
}

///|
test "invalid UTF8 is preserved by no-op and rejected when parsing" {
  let tree = @mndocmove.DocTree::new([@mndocmove.Entry::new("r.md", b"\xFF")])
  assert_eq(
    @mndocmove.plan_moves(tree, []).replay(tree).get("r.md").unwrap().data(),
    b"\xFF",
  )
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_moves(tree, [@mndocmove.Move::new("r.md", "s.md")]),
      )
    },
    "InvalidUtf8",
  )
}

///|
test "malformed and unknown wire data is rejected without ignoring fields" {
  for
    text in [
      "{}", "[]", "null", "[\"mndocmove\",2,\"commonmark\",[],[]]", "[\"mndocmove\",1,\"commonmark\",[],[],0]",
      "[\"mndocmove\",1,\"commonmark\",[[\"a\",\"F\"]],[]]", "[\"mndocmove\",1,\"commonmark\",[[\"a\",\"ZZ\"]],[]]",
      "[\"mndocmove\",1,\"unknown\",[],[]]", "[\"\\uD800\"]", "[",
    ] {
    expect_code(
      () => ignore(@mndocmove.MovePlan::from_json_string(text)),
      "InvalidPlan",
    )
  }
  expect_code(
    () => ignore(@mndocmove.moves_from_json("[[\"a\",\"b\",\"extra\"]]")),
    "InvalidPlan",
  )
}

///|
test "caller arrays and returned arrays cannot mutate plan state" {
  let files = fixture().entries()
  let tree = @mndocmove.DocTree::new(files)
  files.clear()
  let moves = [@mndocmove.Move::new("docs", "manual")]
  let p = @mndocmove.plan_moves(tree, moves)
  moves.clear()
  p.moves().clear()
  p.edits().clear()
  tree.entries().clear()
  assert_eq(p.edits().length(), 1)
  assert_eq(p.replay(tree).entries().length(), 3)
}

///|
test "swaps use original paths simultaneously" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("a.md", "[b](b.md)"),
    @mndocmove.Entry::markdown("b.md", "[a](a.md)"),
  ])
  let p = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("a.md", "b.md"),
    @mndocmove.Move::new("b.md", "a.md"),
  ])
  assert_eq(p.replay(tree).get("b.md").unwrap().text(), "[b](a.md)")
}
