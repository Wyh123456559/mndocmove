///|
test "adoption uses baseline ownership to repair merged destinations without inverse guessing" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "a/r.md", "[B](../b/s.md) [asset](../asset.bin)\r\n",
    ),
    @mndocmove.Entry::markdown("b/s.md", "[A](../a/r.md)"),
    @mndocmove.Entry::markdown("README.md", "[A](a/r.md) [B](b/s.md)"),
    @mndocmove.Entry::new("asset.bin", b"\x00\xFF"),
    @mndocmove.Entry::new("manual/unmoved.bin", b"Keep"),
  ])
  let moves = [
    @mndocmove.Move::new("b", "manual"),
    @mndocmove.Move::new("a", "manual"),
  ]
  let pending = @mndocmove.plan_moves(tree, moves)
  let current = renamed_tree(tree, moves)
  expect_code(
    () => ignore(@mndocmove.plan_relinks(current, moves)),
    "RelinkAmbiguity",
  )
  assert_true(pending.check_renamed(current).is_match())
  let saved_pending = pending.to_json_string()
  let adopted = pending.adopt(current)
  assert_eq(adopted.moves(), [])
  assert_eq(adopted.relinks(), pending.moves())
  let output = adopted.replay(current)
  assert_eq(output.entries(), pending.replay(tree).entries())
  assert_eq(
    output.get("manual/r.md").unwrap().text(),
    "[B](s.md) [asset](../asset.bin)\r\n",
  )
  assert_eq(adopted.restore(output).entries(), current.entries())
  assert_eq(pending.to_json_string(), saved_pending)
  let edits = adopted.edits()
  for edit in edits {
    assert_eq(
      current.get(edit.path).unwrap().text()[edit.start:edit.end].to_owned(),
      edit.before,
    )
  }
  edits.clear()
  let historical = adopted.relinks()
  historical.clear()
  assert_true(!adopted.edits().is_empty())
  assert_eq(adopted.relinks().length(), 2)
  let wire = adopted.to_json_string()
  assert_true(wire.has_prefix("[\"mndocmove-adopt\",1,"))
  let loaded = @mndocmove.MovePlan::from_json_string(wire)
  assert_eq(loaded.to_json_string(), wire)
  assert_eq(loaded.edits(), adopted.edits())
  assert_eq(loaded.replay(current).entries(), output.entries())
  assert_eq(loaded.review(), adopted.review())
  assert_true(loaded.review().contains("Verified move adoption"))
  assert_true(!loaded.review().contains("\nmove "))
  assert_true(loaded.preview().has_prefix("[\"mndocmove-adopt-preview\",1,"))
  expect_code(() => ignore(loaded.adopt(current)), "AdoptPlanKind")
  expect_code(() => ignore(loaded.check_renamed(current)), "AdoptPlanKind")
}

///|
test "adoption reports all physical drift including equal sized edits and recovers after refusal" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[asset](a.bin)"),
    @mndocmove.Entry::new("a.bin", b"A"),
    @mndocmove.Entry::new("b.bin", b"B"),
  ])
  let moves = [@mndocmove.Move::new("r.md", "manual/r.md")]
  let pending = @mndocmove.plan_moves(tree, moves)
  let current = renamed_tree(tree, moves)
  let drift = @mndocmove.DocTree::new([
    // Still valid old-coordinate Markdown referencing a different existing file.
    @mndocmove.Entry::markdown("manual/r.md", "[asset](b.bin)"),
    @mndocmove.Entry::new("a.bin", b"Z"),
    @mndocmove.Entry::new("extra.bin", b""),
  ])
  let report = pending.check_renamed(drift)
  assert_eq(report.changes(), [
    @mndocmove.Modified("a.bin", 1, 1),
    @mndocmove.Removed("b.bin", 1),
    @mndocmove.Added("extra.bin", 0),
    @mndocmove.Modified("manual/r.md", 14, 14),
  ])
  assert_eq(
    report.to_json_string(),
    "[\"mndocmove-check\",1,\"source\",3,3,[[\"modified\",\"a.bin\",1,1],[\"removed\",\"b.bin\",1],[\"added\",\"extra.bin\",0],[\"modified\",\"manual/r.md\",14,14]]]",
  )
  expect_code(() => ignore(pending.adopt(drift)), "AdoptionMismatch")
  let isolated = report.changes()
  isolated.clear()
  assert_eq(report.changes().length(), 4)
  assert_eq(drift.get("a.bin").unwrap().data(), b"Z")
  let retry = pending.adopt(current)
  assert_eq(retry.replay(current).entries(), pending.replay(tree).entries())
  expect_code(() => ignore(retry.replay(drift)), "StaleSnapshot")
  expect_code(() => ignore(retry.restore(drift)), "RestoreMismatch")
  assert_true(pending.check_renamed(current).is_match())
}

///|
test "adoption refuses partial renames and already rewritten contents even when all links remain valid" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[asset](a.bin)"),
    @mndocmove.Entry::new("a.bin", b"A"),
  ])
  let pending = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("r.md", "manual/r.md"),
    @mndocmove.Move::new("a.bin", "media/a.bin"),
  ])
  assert_eq(pending.check_renamed(tree).changes().length(), 4)
  expect_code(() => ignore(pending.adopt(tree)), "AdoptionMismatch")
  let partially = renamed_tree(tree, [
    @mndocmove.Move::new("r.md", "manual/r.md"),
  ])
  expect_code(() => ignore(pending.adopt(partially)), "AdoptionMismatch")
  let already_rewritten = pending.replay(tree)
  assert_eq(pending.check_renamed(already_rewritten).changes().length(), 1)
  expect_code(
    () => ignore(pending.adopt(already_rewritten)),
    "AdoptionMismatch",
  )
  let current = renamed_tree(tree, pending.moves())
  let repair = @mndocmove.plan_relinks(current, pending.moves())
  expect_code(() => ignore(repair.adopt(current)), "AdoptPlanKind")
  assert_eq(
    pending.adopt(current).replay(current).entries(),
    already_rewritten.entries(),
  )
}

///|
test "adoption preserves static media BOM CRLF emoji spans and swap ownership" {
  let text = "\uFEFF# 😀\r\n\r\n[Root](.)\r\n\r\n<video src='assets/clip.webm' poster='assets/poster.svg' controls></video>\r\n\r\n<img sizes='100vw' srcset='assets/a.png 320w, assets/b.png 640w'>"
  let files = media_tree(text).entries()
  files.push(@mndocmove.Entry::new("assets/a.png", b"\x89PNG"))
  files.push(@mndocmove.Entry::new("assets/b.png", b"\xFF\x00"))
  let tree = @mndocmove.DocTree::new(files)
  let moves = [
    @mndocmove.Move::new("README.md", "manual/r.md"),
    @mndocmove.Move::new("assets", "media"),
  ]
  let pending = @mndocmove.plan_moves(tree, moves, profile=StaticHtml)
  let current = renamed_tree(tree, moves)
  let adopted = @mndocmove.MovePlan::from_json_string(
    pending.adopt(current).to_json_string(),
  )
  assert_eq(adopted.replay(current).entries(), pending.replay(tree).entries())
  assert_eq(
    adopted.restore(adopted.replay(current)).entries(),
    current.entries(),
  )
  for edit in adopted.edits() {
    assert_eq(
      current.get(edit.path).unwrap().text()[edit.start:edit.end].to_owned(),
      edit.before,
    )
  }
  let swap = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("a.md", "[B](b.md)"),
    @mndocmove.Entry::markdown("b.md", "[A](a.md)"),
  ])
  let pending = @mndocmove.plan_moves(swap, [
    @mndocmove.Move::new("a.md", "b.md"),
    @mndocmove.Move::new("b.md", "a.md"),
  ])
  let physical = renamed_tree(swap, pending.moves())
  assert_eq(
    pending.adopt(physical).replay(physical).entries(),
    pending.replay(swap).entries(),
  )
  expect_code(() => ignore(pending.adopt(swap)), "AdoptionMismatch")
}

///|
test "adopted plans retain baseline provenance through chains with exact current-path restoration" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[asset](a.bin)"),
    @mndocmove.Entry::new("a.bin", b"\xFF"),
  ])
  let pending = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("r.md", "manual/r.md"),
  ])
  let current = renamed_tree(tree, pending.moves())
  let adopted = pending.adopt(current)
  let chain = adopted.then_moves([@mndocmove.Move::new("a.bin", "media/a.bin")])
  let saved = @mndocmove.MoveChain::from_json_string(chain.to_json_string())
  let output = saved.replay(current)
  assert_eq(
    output.get("manual/r.md").unwrap().text(),
    "[asset](../media/a.bin)",
  )
  assert_eq(saved.restore(output).entries(), current.entries())
  assert_true(saved.check(current).is_match())
  assert_true(saved.check(output, side=Result).is_match())
  assert_true(saved.review().contains("Verified move adoption"))
  assert_eq(saved.to_json_string(), chain.to_json_string())
  expect_code(() => ignore(adopted.merge(pending)), "MergeRelink")
  expect_code(
    () => ignore(@mndocmove.MovePlan::from_json_string(chain.to_json_string())),
    "InvalidPlan",
  )
  expect_code(() => ignore(saved.replay(tree)), "StaleSnapshot")
}

///|
test "adoption wire rejects unknown extra malformed baseline and invalid intents without losing pending data" {
  let valid = "[\"mndocmove-adopt\",1,\"commonmark\",[[\"a.bin\",\"FF\"]],[[\"a.bin\",\"b.bin\"]]]"
  let loaded = @mndocmove.MovePlan::from_json_string(valid)
  assert_eq(loaded.to_json_string(), valid)
  assert_true(
    loaded
    .check(@mndocmove.DocTree::new([@mndocmove.Entry::new("b.bin", b"\xFF")]))
    .is_match(),
  )
  for
    invalid in [
      valid.replace(old=",1,", new=",2,"),
      valid.replace(old="commonmark", new="unknown"),
      valid.replace(old="\"FF\"", new="\"F\""),
      valid.replace(old="\"FF\"", new="{}"),
      valid + "[]",
      "[\"mndocmove-adopt\",1,\"commonmark\",[],[],null]",
    ] {
    expect_code(
      () => ignore(@mndocmove.MovePlan::from_json_string(invalid)),
      "InvalidPlan",
    )
  }
  expect_code(
    () => {
      ignore(
        @mndocmove.MovePlan::from_json_string(
          valid.replace(old="b.bin", new="a.md"),
        ),
      )
    },
    "FileKindChange",
  )
  assert_eq(
    @mndocmove.MovePlan::from_json_string(valid).to_json_string(),
    valid,
  )
}

///|
test "adoption of empty intentions stays canonical and verifies opaque empty inputs" {
  for
    tree in [
      @mndocmove.DocTree::new([]),
      @mndocmove.DocTree::new([
        @mndocmove.Entry::new("invalid.md", b"\xFF"),
        @mndocmove.Entry::new("empty.bin", b""),
      ]),
    ] {
    let pending = @mndocmove.plan_moves(tree, [])
    let adopted = pending.adopt(tree)
    assert_eq(adopted.to_json_string(), pending.to_json_string())
    assert_eq(adopted.replay(tree).entries(), tree.entries())
    assert_true(pending.check_renamed(tree).is_match())
    let extra = tree.entries()
    extra.push(@mndocmove.Entry::new("extra.bin", b""))
    expect_code(
      () => ignore(pending.adopt(@mndocmove.DocTree::new(extra))),
      "AdoptionMismatch",
    )
  }
  let empty = @mndocmove.MovePlan::from_json_string(
    "[\"mndocmove-adopt\",1,\"commonmark\",[],[]]",
  )
  assert_eq(empty.to_json_string(), "[\"mndocmove\",1,\"commonmark\",[],[]]")
}

///|
test "adoption equivalence and deterministic exchange hold across simultaneous move topologies" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "README.md", "[D](docs/r.md) [P](posts/s.md) [I](icons/a%20b.bin)",
    ),
    @mndocmove.Entry::markdown(
      "docs/r.md", "😀 [P](../posts/s.md) [Home](../README.md)\r\n",
    ),
    @mndocmove.Entry::markdown(
      "posts/s.md", "[D](../docs/r.md) [I](../icons/a%20b.bin)",
    ),
    @mndocmove.Entry::new("icons/a b.bin", b"\x00\xFF"),
  ])
  for
    moves in [
      [],
      [@mndocmove.Move::new("README.md", "manual/README.md")],
      [@mndocmove.Move::new("icons", "manual/media")],
      [
        @mndocmove.Move::new("docs", "manual"),
        @mndocmove.Move::new("posts", "manual"),
      ],
      [
        @mndocmove.Move::new("docs", "posts"),
        @mndocmove.Move::new("posts", "docs"),
      ],
      [
        @mndocmove.Move::new("docs", "manual"),
        @mndocmove.Move::new("posts", "manual/start"),
        @mndocmove.Move::new("icons", "manual"),
      ],
      [
        @mndocmove.Move::new("README.md", "汉😀/Home.md"),
        @mndocmove.Move::new("icons/a b.bin", "media/a,b.bin"),
      ],
    ] {
    let pending = @mndocmove.plan_moves(tree, moves)
    let current = renamed_tree(tree, moves)
    let adopted = pending.adopt(current)
    let loaded = @mndocmove.MovePlan::from_json_string(adopted.to_json_string())
    let expected = pending.replay(tree)
    assert_eq(loaded.replay(current).entries(), expected.entries())
    assert_eq(loaded.restore(expected).entries(), current.entries())
    assert_eq(loaded.edits(), adopted.edits())
    assert_true(loaded.check(expected, side=Result).is_match())
    let entries = current.entries()
    entries.sort_by(fn(a, b) { b.path().compare(a.path()) })
    let reordered = @mndocmove.DocTree::new(entries)
    assert_eq(
      pending.adopt(reordered).to_json_string(),
      adopted.to_json_string(),
    )
  }
}
