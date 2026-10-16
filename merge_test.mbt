///|
test "parallel plans recompute interacting incoming outgoing and same-line references commutatively" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "README.md", "😀 [guide](docs/a.md) ![logo](assets/a.bin)\r\n",
    ),
    @mndocmove.Entry::markdown(
      "docs/a.md", "[Home](../README.md) ![logo](../assets/a.bin)",
    ),
    @mndocmove.Entry::new("assets/a.bin", b"\xFF\x00"),
  ])
  let docs = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("docs", "manual/start"),
  ])
  let images = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("assets", "media"),
  ])
  let saved_docs = @mndocmove.MovePlan::from_json_string(docs.to_json_string())
  let merged = saved_docs.merge(images)
  assert_eq(merged.to_json_string(), images.merge(docs).to_json_string())
  assert_eq(merged.to_json_string(), merged.merge(docs).to_json_string())
  assert_eq(merged.moves().length(), 2)
  let output = merged.replay(tree)
  assert_eq(
    output.get("README.md").unwrap().text(),
    "😀 [guide](manual/start/a.md) ![logo](media/a.bin)\r\n",
  )
  assert_eq(
    output.get("manual/start/a.md").unwrap().text(),
    "[Home](../../README.md) ![logo](../../media/a.bin)",
  )
  assert_eq(output.get("media/a.bin").unwrap().data(), b"\xFF\x00")
  assert_true(merged.review().contains("media/a.bin"))
  assert_eq(merged.restore(output).entries(), tree.entries())
  assert_eq(docs.moves().length(), 1)
  assert_eq(images.moves().length(), 1)
}

///|
test "parallel merge rejects all snapshot drift including equal-length opaque edits" {
  let tree = @mndocmove.DocTree::new([@mndocmove.Entry::new("a.bin", b"A")])
  let first = @mndocmove.plan_moves(tree, [])
  for
    entries in [
      [@mndocmove.Entry::new("a.bin", b"B")],
      [],
      [
        @mndocmove.Entry::new("a.bin", b"A"),
        @mndocmove.Entry::new("b.bin", b""),
      ],
    ] {
    let other = @mndocmove.plan_moves(@mndocmove.DocTree::new(entries), [])
    expect_code(() => ignore(first.merge(other)), "MergeSnapshot")
    expect_code(() => ignore(other.merge(first)), "MergeSnapshot")
  }
  assert_eq(first.merge(first).to_json_string(), first.to_json_string())
}

///|
test "parallel merge rejects profile changes contradictory and parent-child intentions without mutations" {
  let tree = @mndocmove.DocTree::new([@mndocmove.Entry::new("docs/a.bin", b"A")])
  let first = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("docs", "manual"),
  ])
  let other = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("docs", "guides"),
  ])
  let child = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("docs/a.bin", "media/a.bin"),
  ])
  let html = @mndocmove.plan_moves(tree, [], profile=StaticHtml)
  expect_code(() => ignore(first.merge(other)), "MergeConflict")
  expect_code(() => ignore(other.merge(first)), "MergeConflict")
  expect_code(() => ignore(first.merge(child)), "OverlappingMoves")
  expect_code(() => ignore(first.merge(html)), "MergeProfile")
  assert_eq(first.replay(tree).get("manual/a.bin").unwrap().data(), b"A")
  assert_eq(first.moves().length(), 1)
}

///|
test "parallel destinations are validated together including safe directory sharing and unsafe collisions" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("a/x.bin", b"A"),
    @mndocmove.Entry::new("b/y.bin", b"B"),
  ])
  let first = @mndocmove.plan_moves(tree, [@mndocmove.Move::new("a", "shared")])
  let other = @mndocmove.plan_moves(tree, [@mndocmove.Move::new("b", "shared")])
  assert_eq(first.merge(other).replay(tree).entries().length(), 2)
  let collision = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("b/y.bin", "shared/x.bin"),
  ])
  expect_code(() => ignore(first.merge(collision)), "PathCollision")
  let case_alias = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("b/y.bin", "SHARED/X.BIN"),
  ])
  expect_code(() => ignore(first.merge(case_alias)), "PathCollision")
  assert_eq(
    first.merge(other).restore(first.merge(other).replay(tree)).entries(),
    tree.entries(),
  )
}

///|
test "parallel static media plans keep all descriptors metadata and exact snapshot round trips" {
  let tree = media_tree(
    "<video src='assets/clip.webm' poster='assets/poster.svg' controls></video>",
  )
  let first = @mndocmove.plan_moves(
    tree,
    [@mndocmove.Move::new("README.md", "manual/README.md")],
    profile=StaticHtml,
  )
  let other = @mndocmove.plan_moves(
    tree,
    [@mndocmove.Move::new("assets", "media")],
    profile=StaticHtml,
  )
  let merged = first.merge(other)
  let loaded = @mndocmove.MovePlan::from_json_string(merged.to_json_string())
  assert_eq(loaded.edits(), merged.edits())
  assert_eq(loaded.restore(loaded.replay(tree)).entries(), tree.entries())
  assert_eq(loaded.to_json_string(), other.merge(first).to_json_string())
}

///|
test "merge maximum identical inventories coalesces all 4096 intentions without exceeding move limit" {
  let entries = []
  let moves = []
  for i in 0..<4096 {
    let name = "a" + i.to_string() + ".bin"
    entries.push(@mndocmove.Entry::new("docs/" + name, b""))
    moves.push(@mndocmove.Move::new("docs/" + name, "out/" + name))
  }
  let tree = @mndocmove.DocTree::new(entries)
  let plan = @mndocmove.plan_moves(tree, moves)
  let merged = plan.merge(plan)
  assert_eq(merged.moves().length(), 4096)
  assert_eq(merged.to_json_string(), plan.to_json_string())
  let parent = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("docs", "manual"),
  ])
  expect_code(() => ignore(plan.merge(parent)), "PlanLimit")
}
