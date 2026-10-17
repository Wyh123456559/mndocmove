///|
test "retarget existing pages and assets without removing old or unrelated files" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "README.md", "[Guide](old.md?view=1#intro) ![logo](old.bin)\r\n",
    ),
    @mndocmove.Entry::markdown("old.md", "Old [self](old.md)"),
    @mndocmove.Entry::markdown("manual/new.md", "New [back](../old.md)"),
    @mndocmove.Entry::new("old.bin", b"OLD\xFF"),
    @mndocmove.Entry::new("assets/new.bin", b"NEW\x00"),
  ])
  let pairs = [
    @mndocmove.Move::new("old.md", "manual/new.md"),
    @mndocmove.Move::new("old.bin", "assets/new.bin"),
  ]
  let plan = @mndocmove.plan_retargets(tree, pairs)
  let output = plan.replay(tree)
  assert_eq(
    output.entries().map(fn(e) { e.path() }),
    tree.entries().map(fn(e) { e.path() }),
  )
  assert_eq(
    output.get("README.md").unwrap().text(),
    "[Guide](manual/new.md?view=1#intro) ![logo](assets/new.bin)\r\n",
  )
  assert_eq(output.get("old.md").unwrap().text(), "Old [self](manual/new.md)")
  assert_eq(output.get("manual/new.md").unwrap().text(), "New [back](new.md)")
  assert_eq(output.get("old.bin").unwrap().data(), b"OLD\xFF")
  assert_eq(output.get("assets/new.bin").unwrap().data(), b"NEW\x00")
  assert_eq(plan.restore(output).entries(), tree.entries())
  assert_eq(plan.moves(), [])
  assert_eq(plan.relinks(), [])
  assert_eq(plan.retargets().length(), 2)
  pairs.clear()
  let copy = plan.retargets()
  copy.clear()
  assert_eq(plan.retargets().length(), 2)
  let saved = @mndocmove.MovePlan::from_json_string(plan.to_json_string())
  assert_eq(saved.to_json_string(), plan.to_json_string())
  assert_eq(saved.edits(), plan.edits())
  assert_eq(saved.replay(tree).entries(), output.entries())
  assert_true(plan.preview().has_prefix("[\"mndocmove-retarget-preview\",1,"))
  assert_true(
    plan.review().contains("retarget \"old.md\" -> \"manual/new.md\""),
  )
  assert_true(!plan.review().contains("\nmove "))
}

///|
test "retarget pairs act once simultaneously including cycles and many to one" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "r.md", "[A](a.bin) [B](b.bin) [C](c.bin) [dir](assets/)",
    ),
    @mndocmove.Entry::new("a.bin", b"A"),
    @mndocmove.Entry::new("b.bin", b"B"),
    @mndocmove.Entry::new("c.bin", b"C"),
    @mndocmove.Entry::new("assets/stay.bin", b"S"),
  ])
  for
    (pairs, expected) in [
      (
        [
          @mndocmove.Move::new("a.bin", "b.bin"),
          @mndocmove.Move::new("b.bin", "c.bin"),
        ],
        "[A](b.bin) [B](c.bin) [C](c.bin) [dir](assets/)",
      ),
      (
        [
          @mndocmove.Move::new("a.bin", "b.bin"),
          @mndocmove.Move::new("b.bin", "a.bin"),
        ],
        "[A](b.bin) [B](a.bin) [C](c.bin) [dir](assets/)",
      ),
      (
        [
          @mndocmove.Move::new("a.bin", "c.bin"),
          @mndocmove.Move::new("b.bin", "c.bin"),
        ],
        "[A](c.bin) [B](c.bin) [C](c.bin) [dir](assets/)",
      ),
    ] {
    let plan = @mndocmove.plan_retargets(tree, pairs)
    assert_eq(plan.replay(tree).get("r.md").unwrap().text(), expected)
    assert_eq(plan.restore(plan.replay(tree)).entries(), tree.entries())
    assert_eq(
      @mndocmove.plan_retargets(tree, [pairs[1], pairs[0]]).to_json_string(),
      plan.to_json_string(),
    )
  }
}

///|
test "retarget preserves reference definitions static HTML media Unicode and exact source spans" {
  let text = "\uFEFF# 😀\r\n\r\n[clip][c]\r\n\r\n[c]: assets/clip.webm?x=1&amp;y=2#t \"Keep\"\r\n\r\n<video src='assets/clip.webm' controls></video>\r\n\r\n`[code](assets/clip.webm)`"
  let files = media_tree(text).entries()
  files.push(@mndocmove.Entry::new("new/中文 clip.webm", b"\xFF\x00NEW"))
  let tree = @mndocmove.DocTree::new(files)
  let pairs = [@mndocmove.Move::new("assets/clip.webm", "new/中文 clip.webm")]
  expect_code(
    () => ignore(@mndocmove.plan_retargets(tree, pairs)),
    "UnsupportedMarkdown",
  )
  let plan = @mndocmove.plan_retargets(tree, pairs, profile=StaticHtml)
  assert_eq(plan.edits().length(), 2)
  for edit in plan.edits() {
    assert_eq(
      tree.get(edit.path).unwrap().text()[edit.start:edit.end].to_owned(),
      edit.before,
    )
    assert_eq(edit.new_target, "new/中文 clip.webm")
  }
  let output = plan.replay(tree)
  assert_true(
    output
    .get("README.md")
    .unwrap()
    .text()
    .contains("new/%E4%B8%AD%E6%96%87%20clip.webm"),
  )
  assert_true(
    output
    .get("README.md")
    .unwrap()
    .text()
    .contains("`[code](assets/clip.webm)`"),
  )
  assert_eq(plan.restore(output).entries(), tree.entries())
}

///|
test "retarget refuses absent directory duplicate and unsafe mappings before rewriting" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[A](a.bin)"),
    @mndocmove.Entry::new("a.bin", b"A"),
    @mndocmove.Entry::new("dir/b.bin", b"B"),
  ])
  for
    (pairs, code) in [
      ([@mndocmove.Move::new("a.bin", "a.bin")], "IdentityMove"),
      ([@mndocmove.Move::new("missing.bin", "a.bin")], "MissingRetargetSource"),
      ([@mndocmove.Move::new("dir", "a.bin")], "MissingRetargetSource"),
      ([@mndocmove.Move::new("a.bin", "dir")], "MissingRetargetTarget"),
      ([@mndocmove.Move::new("a.bin", "missing.bin")], "MissingRetargetTarget"),
      ([@mndocmove.Move::new("a.bin", "../escape")], "InvalidPath"),
      (
        [
          @mndocmove.Move::new("a.bin", "dir/b.bin"),
          @mndocmove.Move::new("a.bin", "dir/b.bin"),
        ],
        "RetargetConflict",
      ),
    ] {
    expect_code(() => ignore(@mndocmove.plan_retargets(tree, pairs)), code)
  }
  let valid = @mndocmove.plan_retargets(tree, [
    @mndocmove.Move::new("a.bin", "dir/b.bin"),
  ])
  assert_eq(valid.replay(tree).get("r.md").unwrap().text(), "[A](dir/b.bin)")
  let entries = tree.entries()
  entries.push(@mndocmove.Entry::new("extra.bin", b""))
  let changed = @mndocmove.DocTree::new(entries)
  expect_code(() => ignore(valid.replay(changed)), "StaleSnapshot")
  expect_code(() => ignore(valid.restore(changed)), "RestoreMismatch")
  expect_code(() => ignore(valid.check_renamed(tree)), "AdoptPlanKind")
  expect_code(
    () => ignore(valid.merge(@mndocmove.plan_moves(tree, []))),
    "MergeRetarget",
  )
}

///|
test "retarget saved plans compose with later physical moves and reject malformed intent wire" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[A](a.bin)"),
    @mndocmove.Entry::new("a.bin", b"A"),
    @mndocmove.Entry::new("b.bin", b"B"),
  ])
  let plan = @mndocmove.plan_retargets(tree, [
    @mndocmove.Move::new("a.bin", "b.bin"),
  ])
  let chain = plan.then_moves([@mndocmove.Move::new("b.bin", "media/b.bin")])
  let saved = @mndocmove.MoveChain::from_json_string(chain.to_json_string())
  assert_eq(saved.replay(tree).get("r.md").unwrap().text(), "[A](media/b.bin)")
  assert_eq(saved.restore(saved.replay(tree)).entries(), tree.entries())
  assert_true(saved.check(tree).is_match())
  for
    invalid in [
      plan.to_json_string().replace(old=",1,", new=",2,"),
      plan.to_json_string().replace(old="commonmark", new="unknown"),
      plan.to_json_string() + "[]",
      "[\"mndocmove-retarget\",1,\"commonmark\",[],[],null]",
    ] {
    expect_code(
      () => ignore(@mndocmove.MovePlan::from_json_string(invalid)),
      "InvalidPlan",
    )
  }
  assert_eq(
    @mndocmove.MovePlan::from_json_string(plan.to_json_string()).preview(),
    plan.preview(),
  )
  let no_op = @mndocmove.plan_retargets(
    @mndocmove.DocTree::new([@mndocmove.Entry::new("bad.md", b"\xFF")]),
    [],
  )
  assert_eq(no_op.retargets(), [])
  assert_true(no_op.to_json_string().has_prefix("[\"mndocmove\",1,"))
}

///|
test "retarget validates every document without dropping unsupported or broken references" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[A](a.bin) [bad](missing.bin)"),
    @mndocmove.Entry::new("a.bin", b"A"),
    @mndocmove.Entry::new("b.bin", b"B"),
  ])
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_retargets(tree, [@mndocmove.Move::new("a.bin", "b.bin")]),
      )
    },
    "MissingTarget",
  )
  assert_eq(tree.get("r.md").unwrap().text(), "[A](a.bin) [bad](missing.bin)")
}

///|
test "retarget accepts 4096 exact file mappings and refuses the next declaration" {
  let files = []
  let pairs = []
  for i in 0..<4096 {
    files.push(@mndocmove.Entry::new(i.to_string() + ".bin", b"\xFF"))
    pairs.push(
      @mndocmove.Move::new(
        i.to_string() + ".bin",
        ((i + 1) % 4096).to_string() + ".bin",
      ),
    )
  }
  let tree = @mndocmove.DocTree::new(files)
  let plan = @mndocmove.plan_retargets(tree, pairs)
  assert_eq(plan.retargets().length(), 4096)
  assert_eq(plan.replay(tree).entries(), tree.entries())
  pairs.push(@mndocmove.Move::new("0.bin", "1.bin"))
  expect_code(() => ignore(@mndocmove.plan_retargets(tree, pairs)), "PlanLimit")
  assert_eq(plan.retargets().length(), 4096)
}
