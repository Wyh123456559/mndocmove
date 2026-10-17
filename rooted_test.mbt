///|
test "explicit root profile rewrites rooted and relative references while preserving their forms" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "docs/r.md", "\uFEFF😀 [A](/assets/a.bin?x=1&amp;y=2#part) [B](../assets/a.bin) [Root](/?q=1#top)\r\n",
    ),
    @mndocmove.Entry::markdown("README.md", "[Guide](/docs/r.md)"),
    @mndocmove.Entry::new("assets/a.bin", b"\x00\xFF"),
  ])
  let moves = [
    @mndocmove.Move::new("docs", "manual/start"),
    @mndocmove.Move::new("assets", "media"),
  ]
  expect_code(
    () => ignore(@mndocmove.plan_moves(tree, moves)),
    "UnsupportedUrl",
  )
  let plan = @mndocmove.plan_moves(tree, moves, profile=CommonMarkRoot)
  let output = plan.replay(tree)
  assert_eq(
    output.get("manual/start/r.md").unwrap().text(),
    "\uFEFF😀 [A](/media/a.bin?x=1&amp;y=2#part) [B](../../media/a.bin) [Root](/?q=1#top)\r\n",
  )
  assert_eq(
    output.get("README.md").unwrap().text(),
    "[Guide](/manual/start/r.md)",
  )
  for edit in plan.edits() {
    assert_eq(
      tree.get(edit.path).unwrap().text()[edit.start:edit.end].to_owned(),
      edit.before,
    )
  }
  assert_eq(plan.restore(output).entries(), tree.entries())
  let loaded = @mndocmove.MovePlan::from_json_string(plan.to_json_string())
  assert_eq(loaded.to_json_string(), plan.to_json_string())
  assert_eq(loaded.edits(), plan.edits())
  assert_eq(loaded.replay(tree).entries(), output.entries())
}

///|
test "root references unaffected by document moves keep exact original spelling and external authorities" {
  let text = "[A](/a%20b.bin) [Root](/) [External](//example.org/a.bin) [HTTPS](https://example.org/a.bin) [Fragment](#intro)"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", text),
    @mndocmove.Entry::new("a b.bin", b"A"),
  ])
  let plan = @mndocmove.plan_moves(
    tree,
    [@mndocmove.Move::new("r.md", "manual/deep/r.md")],
    profile=CommonMarkRoot,
  )
  assert_eq(plan.replay(tree).get("manual/deep/r.md").unwrap().text(), text)
  assert_eq(plan.edits(), [])
}

///|
test "root static HTML media and responsive references retain encoded entities and URL classes" {
  let text = "\uFEFF😀\r\n\r\n<video src='/assets/clip.webm' poster='/assets/poster.svg' controls></video>\r\n\r\n<img srcset='/assets/a.png 1x, /assets/b.png 2x' src='/assets/a.png'>"
  let files = media_tree(text).entries()
  files.push(@mndocmove.Entry::new("assets/a.png", b"A"))
  files.push(@mndocmove.Entry::new("assets/b.png", b"B"))
  let tree = @mndocmove.DocTree::new(files)
  let moves = [
    @mndocmove.Move::new("assets", "media/中文 space"),
    @mndocmove.Move::new("README.md", "manual/r.md"),
  ]
  expect_code(
    () => ignore(@mndocmove.plan_moves(tree, moves, profile=StaticHtml)),
    "UnsupportedUrl",
  )
  expect_code(
    () => ignore(@mndocmove.plan_moves(tree, moves, profile=CommonMarkRoot)),
    "UnsupportedMarkdown",
  )
  let plan = @mndocmove.plan_moves(tree, moves, profile=StaticHtmlRoot)
  assert_eq(plan.edits().length(), 5)
  assert_eq(
    plan.replay(tree).get("manual/r.md").unwrap().text(),
    text.replace_all(old="/assets/", new="/media/%E4%B8%AD%E6%96%87%20space/"),
  )
  assert_eq(plan.restore(plan.replay(tree)).entries(), tree.entries())
}

///|
test "root profiles retain strict escape missing directory and syntax refusals with recovery" {
  for
    (url, code) in [
      ("/../a.bin", "OutsideRoot"),
      ("/%2Fetc", "AmbiguousEscape"),
      ("/%5cetc", "AmbiguousEscape"),
      ("/%00", "AmbiguousEscape"),
      ("/%FF", "InvalidEscape"),
      ("/missing.bin", "MissingTarget"),
      ("/a.bin/", "InvalidDirectoryTarget"),
    ] {
    let tree = @mndocmove.DocTree::new([
      @mndocmove.Entry::markdown("r.md", "[x](" + url + ")"),
      @mndocmove.Entry::new("a.bin", b"A"),
    ])
    expect_code(
      () => {
        ignore(
          @mndocmove.plan_moves(
            tree,
            [@mndocmove.Move::new("a.bin", "b.bin")],
            profile=CommonMarkRoot,
          ),
        )
      },
      code,
    )
  }
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[x](/d/)"),
    @mndocmove.Entry::new("d/a.bin", b"A"),
  ])
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_moves(
          tree,
          [@mndocmove.Move::new("d/a.bin", "e/a.bin")],
          profile=CommonMarkRoot,
        ),
      )
    },
    "MissingProjectedTarget",
  )
  let plan = @mndocmove.plan_moves(
    tree,
    [@mndocmove.Move::new("d", "e")],
    profile=CommonMarkRoot,
  )
  assert_eq(plan.replay(tree).get("r.md").unwrap().text(), "[x](/e/)")
}

///|
test "root profiles compose with retargeting adoption relink chains and batch audit" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[A](/a.bin) [B](a.bin)"),
    @mndocmove.Entry::new("a.bin", b"A"),
    @mndocmove.Entry::new("b.bin", b"B"),
  ])
  let pairs = [@mndocmove.Move::new("a.bin", "b.bin")]
  let retarget = @mndocmove.plan_retargets(tree, pairs, profile=CommonMarkRoot)
  assert_eq(
    retarget.replay(tree).get("r.md").unwrap().text(),
    "[A](/b.bin) [B](b.bin)",
  )
  let moves = [
    @mndocmove.Move::new("a.bin", "media/a.bin"),
    @mndocmove.Move::new("r.md", "manual/r.md"),
  ]
  let plan = @mndocmove.plan_moves(tree, moves, profile=CommonMarkRoot)
  let audit = @mndocmove.audit_moves(tree, moves, profile=CommonMarkRoot)
  assert_eq(audit.plan().unwrap().to_json_string(), plan.to_json_string())
  let physical = renamed_tree(tree, moves)
  let adopted = plan.adopt(physical)
  assert_eq(adopted.replay(physical).entries(), plan.replay(tree).entries())
  let relink = @mndocmove.plan_relinks(physical, moves, profile=CommonMarkRoot)
  assert_eq(relink.replay(physical).entries(), plan.replay(tree).entries())
  let chain = retarget.then_moves([@mndocmove.Move::new("b.bin", "media/b.bin")])
  let loaded = @mndocmove.MoveChain::from_json_string(chain.to_json_string())
  assert_eq(
    loaded.replay(tree).get("r.md").unwrap().text(),
    "[A](/media/b.bin) [B](media/b.bin)",
  )
  assert_eq(loaded.restore(loaded.replay(tree)).entries(), tree.entries())
  expect_code(() => ignore(retarget.merge(plan)), "MergeRetarget")
}

///|
test "root profiles preserve no-op compatibility and exact original profile wire bytes" {
  let tree = @mndocmove.DocTree::new([@mndocmove.Entry::new("bad.md", b"\xFF")])
  for
    profile in [
      @mndocmove.Profile::CommonMarkRoot,
      @mndocmove.Profile::StaticHtmlRoot,
    ] {
    let plan = @mndocmove.plan_moves(tree, [], profile~)
    assert_eq(
      @mndocmove.MovePlan::from_json_string(plan.to_json_string()).to_json_string(),
      plan.to_json_string(),
    )
    assert_eq(plan.replay(tree).entries(), tree.entries())
  }
  assert_eq(
    @mndocmove.plan_moves(@mndocmove.DocTree::new([]), []).to_json_string(),
    "[\"mndocmove\",1,\"commonmark\",[],[]]",
  )
  assert_eq(
    @mndocmove.plan_moves(@mndocmove.DocTree::new([]), [], profile=StaticHtml).to_json_string(),
    "[\"mndocmove\",1,\"static-html\",[],[]]",
  )
}

///|
test "root references through directory swaps are deterministic and byte reversible" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "a/r.md", "[A](/a/r.md) [B](/b/s.md) [R](/a/../)",
    ),
    @mndocmove.Entry::markdown("b/s.md", "[A](/a/r.md)"),
  ])
  let moves = [@mndocmove.Move::new("a", "b"), @mndocmove.Move::new("b", "a")]
  let plan = @mndocmove.plan_moves(tree, moves, profile=CommonMarkRoot)
  assert_eq(
    plan.replay(tree).get("b/r.md").unwrap().text(),
    "[A](/b/r.md) [B](/a/s.md) [R](/a/../)",
  )
  assert_eq(
    @mndocmove.plan_moves(tree, [moves[1], moves[0]], profile=CommonMarkRoot).to_json_string(),
    plan.to_json_string(),
  )
  assert_eq(plan.restore(plan.replay(tree)).entries(), tree.entries())
}
