///|
test "migration audit continues across documents and withholds every partial plan" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "a.md", "[missing](absent.bin) [second](also-absent.bin)",
    ),
    @mndocmove.Entry::markdown("b.md", "[[wiki]]"),
    @mndocmove.Entry::new("c.md", b"\xFF"),
    @mndocmove.Entry::markdown("good.md", "[asset](a.bin)"),
    @mndocmove.Entry::new("a.bin", b"\x00\xFF"),
  ])
  let moves = [@mndocmove.Move::new("a.bin", "media/a.bin")]
  let original = tree.entries()
  let audit = @mndocmove.audit_moves(tree, moves)
  assert_true(!audit.is_ready())
  assert_true(audit.plan() is None)
  let issues = audit.diagnostics()
  assert_eq(issues.map(fn(d) { d.path }), ["a.md", "b.md", "c.md"])
  assert_eq(issues.map(fn(d) { d.code }), [
    "MissingTarget", "UnsupportedMarkdown", "InvalidUtf8",
  ])
  assert_eq(issues[0].offset, 10)
  assert_eq(issues[2].offset, -1)
  // Preserve exact fail-fast diagnostics; the first refusal per document is
  // deliberate, rather than claiming every broken reference was discovered.
  let first = try {
    ignore(@mndocmove.plan_moves(tree, moves))
    None
  } catch {
    @mndocmove.Refused(d) => Some(d)
  }
  assert_eq(first, Some(issues[0]))
  issues.clear()
  moves.clear()
  assert_eq(audit.diagnostics().length(), 3)
  assert_eq(tree.entries(), original)
  assert_eq(
    @mndocmove.audit_moves(tree, [@mndocmove.Move::new("a.bin", "media/a.bin")]).to_json_string(),
    audit.to_json_string(),
  )
}

///|
test "ready audit returns the byte identical ordinary plan with incoming and outgoing links" {
  let tree = fixture()
  let moves = [
    @mndocmove.Move::new("img", "assets"),
    @mndocmove.Move::new("docs", "manual/deep"),
  ]
  let audit = @mndocmove.audit_moves(tree, moves)
  assert_true(audit.is_ready())
  assert_eq(audit.diagnostics(), [])
  let plan = audit.plan().unwrap()
  let ordinary = @mndocmove.plan_moves(tree, moves)
  assert_eq(plan.to_json_string(), ordinary.to_json_string())
  assert_eq(plan.preview(), ordinary.preview())
  assert_eq(plan.review(), ordinary.review())
  assert_eq(plan.edits(), ordinary.edits())
  let output = plan.replay(tree)
  assert_eq(output.entries(), ordinary.replay(tree).entries())
  assert_eq(plan.restore(output).entries(), tree.entries())
  assert_eq(
    @mndocmove.MovePlan::from_json_string(plan.to_json_string())
    .replay(tree)
    .entries(),
    output.entries(),
  )
  assert_eq(
    audit.to_json_string(),
    "[\"mndocmove-audit\",1,\"ready\",\"commonmark\",3,2,[]]",
  )
  expect_code(
    () => ignore(@mndocmove.MovePlan::from_json_string(audit.to_json_string())),
    "InvalidPlan",
  )
  expect_code(
    () => ignore(@mndocmove.MoveChain::from_json_string(audit.to_json_string())),
    "InvalidPlan",
  )
  let changed = tree.entries()
  changed.push(@mndocmove.Entry::new("new.bin", b""))
  expect_code(
    () => ignore(plan.replay(@mndocmove.DocTree::new(changed))),
    "StaleSnapshot",
  )
  assert_true(plan.check(tree).is_match())
}

///|
test "audit ordering and JSON diagnostics remain deterministic and escape content without exposing bytes" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("long-name.md", "[long](absent.bin)"),
    @mndocmove.Entry::markdown("汉😀.md", "[unicode](absent.bin)"),
    @mndocmove.Entry::markdown("a.md", "\uFEFF😀 [x](absent.bin)\r\n"),
    @mndocmove.Entry::new("a.bin", b"\xFF"),
  ])
  let moves = [
    @mndocmove.Move::new("a.bin", "media/a.bin"),
    @mndocmove.Move::new("a.md", "manual/a.md"),
  ]
  let audit = @mndocmove.audit_moves(tree, moves)
  let issues = audit.diagnostics()
  assert_eq(issues.map(fn(d) { d.path }), ["a.md", "汉😀.md", "long-name.md"])
  assert_eq(issues[0].offset, 8)
  let reversed = tree.entries()
  reversed.sort_by(fn(a, b) { b.path().compare(a.path()) })
  let reordered = @mndocmove.audit_moves(@mndocmove.DocTree::new(reversed), [
    moves[1],
    moves[0],
  ])
  assert_eq(reordered.diagnostics(), issues)
  assert_eq(reordered.to_json_string(), audit.to_json_string())
  let expected : Json = [
    "mndocmove-audit",
    1,
    "blocked",
    "commonmark",
    4,
    3,
    Json::array(
      issues.map(fn(d) {
        [Json(d.code), Json(d.path), Json(d.offset), Json(d.message)]
      }),
    ),
  ]
  assert_eq(@json.parse(audit.to_json_string()), expected)
  assert_true(!audit.to_json_string().contains("[unicode]"))
  assert_true(!audit.to_json_string().contains("[long]"))
}

///|
test "audit refuses unsafe global maps before content scanning with ordinary error precedence" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("r.md", b"\xFF"),
    @mndocmove.Entry::new("a.bin", b"A"),
    @mndocmove.Entry::new("docs/b.bin", b"B"),
  ])
  for
    (moves, code) in [
      ([@mndocmove.Move::new("r.md", "r.md")], "IdentityMove"),
      ([@mndocmove.Move::new("none", "manual")], "MissingSource"),
      ([@mndocmove.Move::new("r.md", "a.bin")], "PathCollision"),
      ([@mndocmove.Move::new("r.md", "page.bin")], "FileKindChange"),
      (
        [
          @mndocmove.Move::new("docs", "manual"),
          @mndocmove.Move::new("docs/b.bin", "b.bin"),
        ],
        "OverlappingMoves",
      ),
      ([@mndocmove.Move::new("a.bin", "../a.bin")], "InvalidPath"),
    ] {
    expect_code(() => ignore(@mndocmove.audit_moves(tree, moves)), code)
    expect_code(() => ignore(@mndocmove.plan_moves(tree, moves)), code)
  }
  let too_many = Array::make(4097, @mndocmove.Move::new("a.bin", "b.bin"))
  expect_code(() => ignore(@mndocmove.audit_moves(tree, too_many)), "PlanLimit")
  let retry = @mndocmove.audit_moves(tree, [
    @mndocmove.Move::new("a.bin", "b.bin"),
  ])
  assert_eq(retry.diagnostics()[0].code, "InvalidUtf8")
  assert_true(retry.plan() is None)
}

///|
test "audit inherits explicit static HTML profile and handles media errors per file" {
  let text = "\uFEFF# 😀\r\n\r\n<video src='assets/clip.webm' poster='assets/poster.svg' controls></video>"
  let tree = media_tree(text)
  let moves = [
    @mndocmove.Move::new("README.md", "manual/r.md"),
    @mndocmove.Move::new("assets", "media"),
  ]
  let blocked = @mndocmove.audit_moves(tree, moves)
  assert_eq(blocked.diagnostics()[0].code, "UnsupportedMarkdown")
  assert_true(blocked.plan() is None)
  let audit = @mndocmove.audit_moves(tree, moves, profile=StaticHtml)
  let plan = audit.plan().unwrap()
  assert_eq(
    plan.to_json_string(),
    @mndocmove.plan_moves(tree, moves, profile=StaticHtml).to_json_string(),
  )
  assert_true(audit.to_json_string().contains("\"static-html\""))
  for edit in plan.edits() {
    assert_eq(
      tree.get(edit.path).unwrap().text()[edit.start:edit.end].to_owned(),
      edit.before,
    )
  }
  assert_eq(plan.restore(plan.replay(tree)).entries(), tree.entries())
  let files = tree.entries()
  files.push(
    @mndocmove.Entry::markdown(
      "bad.md", "<img srcset='assets/a.png 1x, assets/b.png 1x'>",
    ),
  )
  files.push(@mndocmove.Entry::new("assets/a.png", b"A"))
  files.push(@mndocmove.Entry::new("assets/b.png", b"B"))
  let bad = @mndocmove.audit_moves(
    @mndocmove.DocTree::new(files),
    moves,
    profile=StaticHtml,
  )
  assert_true(!bad.is_ready())
  assert_eq(bad.diagnostics().length(), 1)
  assert_eq(bad.diagnostics()[0].path, "bad.md")
  assert_true(bad.plan() is None)
}

///|
test "audit recovers after document fixes and produces a complete saved export plan" {
  let broken = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("a.md", "[missing](a.bin)"),
    @mndocmove.Entry::markdown("b.md", "[missing](b.bin)"),
  ])
  let moves = [@mndocmove.Move::new("a.md", "manual/a.md")]
  let blocked = @mndocmove.audit_moves(broken, moves)
  assert_eq(blocked.diagnostics().length(), 2)
  let fixed = broken.entries()
  fixed.push(@mndocmove.Entry::new("a.bin", b"\x00\xFF"))
  fixed.push(@mndocmove.Entry::new("b.bin", b"B"))
  let tree = @mndocmove.DocTree::new(fixed)
  let audit = @mndocmove.audit_moves(tree, moves)
  let saved = @mndocmove.MovePlan::from_json_string(
    audit.plan().unwrap().to_json_string(),
  )
  assert_eq(
    saved.replay(tree).get("manual/a.md").unwrap().text(),
    "[missing](../a.bin)",
  )
  assert_eq(saved.restore(saved.replay(tree)).entries(), tree.entries())
  assert_true(blocked.plan() is None)
  assert_eq(blocked.diagnostics().length(), 2)
  assert_eq(broken.entries().length(), 2)
}

///|
test "audit no-op preserves invalid or unsupported Markdown without pretending to scan it" {
  for
    tree in [
      @mndocmove.DocTree::new([]),
      @mndocmove.DocTree::new([
        @mndocmove.Entry::new("a.md", b"\xFF"),
        @mndocmove.Entry::markdown("b.md", "[[wiki]]"),
        @mndocmove.Entry::new("empty.bin", b""),
      ]),
    ] {
    let audit = @mndocmove.audit_moves(tree, [])
    assert_true(audit.is_ready())
    assert_eq(audit.diagnostics(), [])
    let plan = audit.plan().unwrap()
    assert_eq(
      plan.to_json_string(),
      @mndocmove.plan_moves(tree, []).to_json_string(),
    )
    assert_eq(plan.replay(tree).entries(), tree.entries())
    let expected : Json = [
      "mndocmove-audit",
      1,
      "ready",
      "commonmark",
      Json(tree.entries().length()),
      0,
      [],
    ]
    assert_eq(@json.parse(audit.to_json_string()), expected)
  }
}

///|
test "audit bounds diagnostics at one per document through a maximal inventory" {
  let files = []
  for i in 0..<4096 {
    files.push(@mndocmove.Entry::new(i.to_string() + ".md", b"\xFF"))
  }
  let tree = @mndocmove.DocTree::new(files)
  let moves = [@mndocmove.Move::new("0.md", "manual/0.md")]
  let audit = @mndocmove.audit_moves(tree, moves)
  assert_eq(audit.diagnostics().length(), 4096)
  assert_eq(
    audit.diagnostics().map(fn(d) { d.path }),
    tree.entries().map(fn(e) { e.path() }),
  )
  assert_true(
    audit.diagnostics().all(fn(d) { d.code == "InvalidUtf8" && d.offset == -1 }),
  )
  assert_true(audit.plan() is None)
  assert_eq(tree.entries().length(), 4096)
}

///|
test "audit refuses successful rewrites exceeding the output file budget" {
  let prefix = "[x](a.bin)\n"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "r.md",
      prefix + "x".repeat(1048576 - prefix.length()),
    ),
    @mndocmove.Entry::new("a.bin", b"A"),
  ])
  let moves = [@mndocmove.Move::new("a.bin", "longer/a.bin")]
  expect_code(
    () => ignore(@mndocmove.audit_moves(tree, moves)),
    "MarkdownLimit",
  )
  expect_code(() => ignore(@mndocmove.plan_moves(tree, moves)), "MarkdownLimit")
  assert_eq(tree.get("r.md").unwrap().data().length(), 1048576)
  assert_true(@mndocmove.audit_moves(tree, []).is_ready())
}
