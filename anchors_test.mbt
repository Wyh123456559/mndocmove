///|
fn anchor(
  source : String,
  fragment : String,
  destination : String,
  replacement : String,
) -> @mndocmove.AnchorRetarget {
  { source, fragment, destination, replacement, }
}

///|
test "anchor rename keeps self paths queries exact spans BOM CRLF and unselected bytes" {
  let source = "\uFEFF😀 [self](#old) [explicit](./r.md?x=1&amp;y=2#%6Fld) [query](?q#old) [none]() [empty](#) [other](#Old)\r\n"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", source),
  ])
  let plan = @mndocmove.plan_anchor_retargets(tree, [
    anchor("r.md", "old", "r.md", "new #中/😀"),
  ])
  let output = plan.replay(tree)
  assert_eq(
    output.get("r.md").unwrap().text(),
    "\uFEFF😀 [self](#new%20%23%E4%B8%AD/%F0%9F%98%80) [explicit](./r.md?x=1&amp;y=2#new%20%23%E4%B8%AD/%F0%9F%98%80) [query](?q#new%20%23%E4%B8%AD/%F0%9F%98%80) [none]() [empty](#) [other](#Old)\r\n",
  )
  assert_eq(plan.edits().length(), 3)
  for e in plan.edits() {
    assert_eq(source[e.start:e.end].to_owned(), e.before)
    assert_eq(e.old_target, "r.md")
    assert_eq(e.new_target, "r.md")
  }
  assert_eq(plan.restore(output).entries(), tree.entries())
  let empty = @mndocmove.plan_anchor_retargets(tree, [
      anchor("r.md", "", "r.md", "empty"),
    ])
    .replay(tree)
    .get("r.md")
    .unwrap()
    .text()
  assert_true(empty.contains("[empty](#empty)"))
  assert_true(empty.contains("[none]()"))
}

///|
test "anchor consolidation supports references root URLs static HTML and opaque asset IDs" {
  let text = "[ref][x]\n\n[x]: /old.md?q=1&amp;x=2#part%2Fone \"Keep\"\n\n<a href='/old.md#part%2Fone'>Guide</a>\n\n![icon](icons/a.svg#symbol) [plain](old.md) [other](old.md#other)\n"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("index.md", text),
    @mndocmove.Entry::markdown("old.md", "# Old\n[self](#part/one)"),
    @mndocmove.Entry::markdown("manual/new.md", "# New\n"),
    @mndocmove.Entry::new("icons/a.svg", b"OLD\xFF"),
    @mndocmove.Entry::new("icons/b.svg", b"NEW\x00"),
  ])
  let pairs = [
    anchor("old.md", "part/one", "manual/new.md", "new"),
    anchor("icons/a.svg", "symbol", "icons/b.svg", "replacement"),
  ]
  let plan = @mndocmove.plan_anchor_retargets(
    tree,
    pairs,
    profile=StaticHtmlRoot,
  )
  let result = plan.replay(tree)
  assert_eq(
    result.get("index.md").unwrap().text(),
    "[ref][x]\n\n[x]: /manual/new.md?q=1&amp;x=2#new \"Keep\"\n\n<a href='/manual/new.md#new'>Guide</a>\n\n![icon](icons/b.svg#replacement) [plain](old.md) [other](old.md#other)\n",
  )
  assert_eq(
    result.get("old.md").unwrap().text(),
    "# Old\n[self](manual/new.md#new)",
  )
  assert_eq(
    result.get("manual/new.md").unwrap().data(),
    tree.get("manual/new.md").unwrap().data(),
  )
  assert_eq(result.get("icons/a.svg").unwrap().data(), b"OLD\xFF")
  assert_eq(result.get("icons/b.svg").unwrap().data(), b"NEW\x00")
  assert_eq(
    result.entries().map(fn(e) { e.path() }),
    tree.entries().map(fn(e) { e.path() }),
  )
  assert_eq(plan.restore(result).entries(), tree.entries())
  let saved = @mndocmove.MovePlan::from_json_string(plan.to_json_string())
  assert_true(saved.profile() is @mndocmove.StaticHtmlRoot)
  assert_eq(saved.replay(tree).entries(), result.entries())
}

///|
test "anchor substitutions are deterministic simultaneous one hop including cycles and many to one" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[a](#a) [b](#b) [c](#c)"),
  ])
  for
    (pairs, expected) in [
      (
        [anchor("r.md", "a", "r.md", "b"), anchor("r.md", "b", "r.md", "c")],
        "[a](#b) [b](#c) [c](#c)",
      ),
      (
        [anchor("r.md", "a", "r.md", "b"), anchor("r.md", "b", "r.md", "a")],
        "[a](#b) [b](#a) [c](#c)",
      ),
      (
        [anchor("r.md", "a", "r.md", "c"), anchor("r.md", "b", "r.md", "c")],
        "[a](#c) [b](#c) [c](#c)",
      ),
    ] {
    let plan = @mndocmove.plan_anchor_retargets(tree, pairs)
    assert_eq(plan.replay(tree).get("r.md").unwrap().text(), expected)
    assert_eq(
      @mndocmove.plan_anchor_retargets(tree, [pairs[1], pairs[0]]).to_json_string(),
      plan.to_json_string(),
    )
    assert_eq(plan.restore(plan.replay(tree)).entries(), tree.entries())
  }
}

///|
test "anchor saved plans integrate preview review source result guards and later moves" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[a](old.md?q#old)"),
    @mndocmove.Entry::markdown("old.md", "Old"),
    @mndocmove.Entry::markdown("new.md", "New"),
    @mndocmove.Entry::new("asset.bin", b"\xFF\x00"),
  ])
  let pairs = [anchor("old.md", "old", "new.md", "new")]
  let plan = @mndocmove.plan_anchor_retargets(tree, pairs)
  pairs.clear()
  let copy = plan.anchor_retargets()
  copy.clear()
  assert_eq(plan.anchor_retargets().length(), 1)
  assert_eq(plan.moves(), [])
  assert_eq(plan.retargets(), [])
  assert_eq(plan.relinks(), [])
  let saved = @mndocmove.MovePlan::from_json_string(plan.to_json_string())
  assert_eq(saved.to_json_string(), plan.to_json_string())
  assert_eq(saved.edits(), plan.edits())
  assert_true(plan.to_json_string().has_prefix("[\"mndocmove-anchors\",1,"))
  assert_true(plan.preview().has_prefix("[\"mndocmove-anchors-preview\",1,"))
  expect_code(
    () => ignore(@mndocmove.MovePlan::from_json_string(plan.preview())),
    "InvalidPlan",
  )
  assert_true(
    plan
    .review()
    .contains("retarget-anchor \"old.md\" \"old\" -> \"new.md\" \"new\""),
  )
  assert_true(!plan.review().contains("\nmove "))
  let result = plan.replay(tree)
  assert_true(plan.check(result, side=Result).is_match())
  let changed = @mndocmove.DocTree::new(
    [@mndocmove.Entry::new("asset.bin", b"\x00\xFF")] +
    tree.entries().filter(fn(e) { e.path() != "asset.bin" }),
  )
  expect_code(() => ignore(plan.replay(changed)), "StaleSnapshot")
  expect_code(() => ignore(plan.restore(tree)), "RestoreMismatch")
  expect_code(() => ignore(plan.check_renamed(tree)), "AdoptPlanKind")
  expect_code(
    () => ignore(plan.merge(@mndocmove.plan_moves(tree, []))),
    "MergeAnchors",
  )
  let chain = plan.then_moves([@mndocmove.Move::new("new.md", "manual/new.md")])
  let loaded = @mndocmove.MoveChain::from_json_string(chain.to_json_string())
  let last = loaded.replay(tree)
  assert_eq(last.get("r.md").unwrap().text(), "[a](manual/new.md?q#new)")
  assert_eq(loaded.restore(last).entries(), tree.entries())
}

///|
test "anchor mapping rejects ambiguous missing directory identity malformed and oversized intentions" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[a](#a)"),
    @mndocmove.Entry::new("dir/a.bin", b""),
  ])
  let good = anchor("r.md", "a", "r.md", "b")
  for
    (pairs, code) in [
      ([good, good], "AnchorConflict"),
      ([anchor("r.md", "a", "r.md", "a")], "IdentityAnchor"),
      ([anchor("missing", "a", "r.md", "b")], "MissingAnchorSource"),
      ([anchor("dir", "a", "r.md", "b")], "MissingAnchorSource"),
      ([anchor("r.md", "a", "dir", "b")], "MissingAnchorTarget"),
      ([anchor("r.md", "a", "missing", "b")], "MissingAnchorTarget"),
      ([anchor("r.md", "a", "r.md", "\n")], "InvalidFragment"),
      ([anchor("r.md", "\u0000", "r.md", "b")], "InvalidFragment"),
      ([anchor("r.md", "a", "r.md", "x".repeat(4097))], "InvalidFragment"),
      ([anchor("r.md", "x".repeat(4097), "r.md", "b")], "InvalidFragment"),
    ] {
    expect_code(
      () => ignore(@mndocmove.plan_anchor_retargets(tree, pairs)),
      code,
    )
  }
  for
    bad in [
      "{}", "[{}]", "[[\"r.md\",\"a\",\"r.md\"]]", "[[\"r.md\",\"a\",\"r.md\",\"b\",0]]",
      "[[\"r.md\",0,\"r.md\",\"b\"]]", "[", "null",
    ] {
    expect_code(
      () => ignore(@mndocmove.anchor_retargets_from_json(bad)),
      "InvalidPlan",
    )
  }
  assert_eq(
    @mndocmove.anchor_retargets_from_json("[[\"r.md\",\"a\",\"r.md\",\"b\"]]"),
    [good],
  )
  assert_eq(
    @mndocmove.plan_anchor_retargets(tree, [good])
    .replay(tree)
    .get("r.md")
    .unwrap()
    .text(),
    "[a](#b)",
  )
  let limit = @mndocmove.plan_anchor_retargets(tree, [
    anchor("r.md", "a", "r.md", "x".repeat(4096)),
  ])
  assert_eq(
    limit.replay(tree).incoming("r.md").references()[0].fragment,
    Some("x".repeat(4096)),
  )
  let pairs = Array::makei(4096, fn(i) {
    anchor("r.md", i.to_string(), "r.md", "next")
  })
  assert_eq(
    @mndocmove.plan_anchor_retargets(tree, pairs).anchor_retargets().length(),
    4096,
  )
  pairs.push(good)
  expect_code(
    () => ignore(@mndocmove.plan_anchor_retargets(tree, pairs)),
    "PlanLimit",
  )
}

///|
test "anchor scan fails completely for unselected broken unsupported or malformed data and recovers" {
  for
    (text, code) in [
      ("[x](missing#other)", "MissingTarget"),
      ("[x](dir/#other)", "InvalidDirectoryTarget"),
      ("[x](#%FF)", "InvalidFragment"),
      ("[x](#%0A)", "InvalidFragment"),
      ("[x](#%zz)", "InvalidFragment"),
      ("[x](#%)", "InvalidFragment"),
      ("<a href='#old'>x</a>", "UnsupportedMarkdown"),
    ] {
    let tree = @mndocmove.DocTree::new([
      @mndocmove.Entry::markdown("r.md", text),
      @mndocmove.Entry::new("dir", b""),
    ])
    expect_code(
      () => {
        ignore(
          @mndocmove.plan_anchor_retargets(tree, [
            anchor("r.md", "old", "r.md", "new"),
          ]),
        )
      },
      code,
    )
    assert_eq(tree.get("r.md").unwrap().text(), text)
  }
  let invalid = @mndocmove.DocTree::new([@mndocmove.Entry::new("r.md", b"\xFF")])
  let noop = @mndocmove.plan_anchor_retargets(invalid, [])
  assert_eq(noop.replay(invalid).entries(), invalid.entries())
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_anchor_retargets(invalid, [
          anchor("r.md", "old", "r.md", "new"),
        ]),
      )
    },
    "InvalidUtf8",
  )
  let valid = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "r.md", "[x](#old) [external](https://example.com/#%zz) `[#old](#old)`",
    ),
  ])
  assert_eq(
    @mndocmove.plan_anchor_retargets(valid, [
      anchor("r.md", "old", "r.md", "new"),
    ])
    .edits()
    .length(),
    1,
  )
}

///|
test "anchor saved tuple refuses changed versions profiles extra fields and invalid declarations" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[x](#old)"),
  ])
  let wire = @mndocmove.plan_anchor_retargets(tree, [
    anchor("r.md", "old", "r.md", "new"),
  ]).to_json_string()
  for
    bad in [
      wire.replace_all(old="anchors\",1", new="anchors\",2"),
      wire.replace_all(old="commonmark", new="unknown"),
      wire[:wire.length() - 1].to_owned() + ",0]",
      wire.replace_all(old="\"new\"]", new="\"new\",0]"),
      wire.replace_all(
        old="\"old\",\"r.md\",\"new\"",
        new="\"old\",\"absent\",\"new\"",
      ),
    ] {
    expect_code(
      () => ignore(@mndocmove.MovePlan::from_json_string(bad)),
      if bad.contains("absent") {
        "MissingAnchorTarget"
      } else {
        "InvalidPlan"
      },
    )
  }
  assert_eq(@mndocmove.MovePlan::from_json_string(wire).to_json_string(), wire)
}

///|
test "anchor output budget refuses expansion before returning any partial plan" {
  let text = "[x](#a) ".repeat(257)
  let tree = @mndocmove.DocTree::new([@mndocmove.Entry::markdown("r.md", text)])
  let long = "x".repeat(4096)
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_anchor_retargets(tree, [
          anchor("r.md", "a", "r.md", long),
        ]),
      )
    },
    "MarkdownLimit",
  )
  assert_eq(tree.get("r.md").unwrap().text(), text)
  let valid = @mndocmove.plan_anchor_retargets(tree, [
    anchor("r.md", "a", "r.md", "b"),
  ])
  assert_eq(valid.edits().length(), 257)
  assert_eq(valid.restore(valid.replay(tree)).entries(), tree.entries())
}
