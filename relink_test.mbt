///|
fn renamed_tree(
  original : @mndocmove.DocTree,
  moves : Array[@mndocmove.Move],
) -> @mndocmove.DocTree raise @mndocmove.MoveError {
  @mndocmove.DocTree::new(
    original
    .entries()
    .map(fn(entry) {
      let mut path = entry.path()
      for change in moves {
        if path == change.source() || path.has_prefix(change.source() + "/") {
          path = change.destination() +
            path[change.source().length():].to_owned()
          break
        }
      }
      @mndocmove.Entry::new(path, entry.data())
    }),
  )
}

///|
test "repair already moved files rewrites incoming outgoing and reference URLs without pending file moves" {
  let original = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "README.md", "[guide](docs/a.md) ![asset](assets/a.bin)\r\n",
    ),
    @mndocmove.Entry::markdown(
      "docs/a.md", "😀 [Home](../README.md) [asset][asset]\r\n\r\n[asset]: ../assets/a.bin \"Keep\"",
    ),
    @mndocmove.Entry::new("assets/a.bin", b"\xFF\x00"),
  ])
  let moves = [
    @mndocmove.Move::new("docs", "manual/start"),
    @mndocmove.Move::new("assets", "media"),
  ]
  let current = renamed_tree(original, moves)
  let plan = @mndocmove.plan_relinks(current, moves)
  let output = plan.replay(current)
  let ordinary = @mndocmove.plan_moves(original, moves)
  assert_eq(output.entries(), ordinary.replay(original).entries())
  assert_eq(plan.moves(), [])
  assert_eq(plan.relinks(), ordinary.moves())
  assert_eq(plan.edits().length(), 4)
  for edit in plan.edits() {
    let before = current.get(edit.path).unwrap().text()
    assert_eq(before[edit.start:edit.end].to_owned(), edit.before)
  }
  assert_eq(plan.restore(output).entries(), current.entries())
  assert_true(
    plan.review().contains("already-renamed \"docs\" -> \"manual/start\""),
  )
  assert_true(plan.review().contains("Link-only repair"))
  assert_true(!plan.review().contains("\nmove "))
  assert_true(plan.check(current).is_match())
  assert_true(plan.check(output, side=Result).is_match())
  assert_true(plan.preview().has_prefix("[\"mndocmove-relink-preview\",1,"))
  let saved = @mndocmove.MovePlan::from_json_string(plan.to_json_string())
  assert_eq(saved.to_json_string(), plan.to_json_string())
  assert_eq(saved.edits(), plan.edits())
  assert_eq(saved.replay(current).entries(), output.entries())
}

///|
test "repair static media responsive candidates and root navigation preserves BOM CRLF and exact bytes" {
  let text = "\uFEFF# 😀\r\n\r\n[Root](.?view=1#top)\r\n\r\n<video src='assets/clip.webm' poster='assets/poster.svg' controls></video>\r\n\r\n<img sizes='100vw' srcset='assets/a.png 320w, assets/b.png 640w'>"
  let files = media_tree(text).entries()
  files.push(@mndocmove.Entry::new("assets/a.png", b"\x89PNG\x00"))
  files.push(@mndocmove.Entry::new("assets/b.png", b"\x00\xFF"))
  let original = @mndocmove.DocTree::new(files)
  let moves = [
    @mndocmove.Move::new("README.md", "manual/r.md"),
    @mndocmove.Move::new("assets", "art"),
  ]
  let current = renamed_tree(original, moves)
  let plan = @mndocmove.plan_relinks(current, moves, profile=StaticHtml)
  let output = plan.replay(current)
  assert_eq(
    output.get("manual/r.md").unwrap().text(),
    text
    .replace(old="(.?view", new="(..?view")
    .replace_all(old="assets/", new="../art/"),
  )
  assert_eq(
    output.entries(),
    @mndocmove.plan_moves(original, moves, profile=StaticHtml)
    .replay(original)
    .entries(),
  )
  assert_eq(plan.restore(output).entries(), current.entries())
  expect_code(
    () => ignore(@mndocmove.plan_relinks(current, moves)),
    "UnsupportedMarkdown",
  )
}

///|
test "repair simultaneous swaps and encoded filenames remain exact with no physical reverse move" {
  let original = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("a.md", "A [B](b.md) [asset](space%20name.bin)"),
    @mndocmove.Entry::markdown("b.md", "B [A](a.md)"),
    @mndocmove.Entry::new("space name.bin", b"\xFF"),
  ])
  let moves = [
    @mndocmove.Move::new("a.md", "b.md"),
    @mndocmove.Move::new("b.md", "a.md"),
    @mndocmove.Move::new("space name.bin", "images/中文.bin"),
  ]
  let current = renamed_tree(original, moves)
  let plan = @mndocmove.plan_relinks(current, moves)
  assert_eq(
    plan.replay(current).get("b.md").unwrap().text(),
    "A [B](a.md) [asset](images/%E4%B8%AD%E6%96%87.bin)",
  )
  assert_eq(plan.restore(plan.replay(current)).entries(), current.entries())
  let entries = current.entries()
  entries.clear()
  let copied = plan.relinks()
  copied.clear()
  assert_eq(plan.relinks().length(), 3)
  assert_eq(plan.replay(current).entries().length(), 3)
}

///|
test "repair rejects absent partially performed ambiguous and wrong-kind historical renames" {
  let current = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("new/a.bin", b"A"),
    @mndocmove.Entry::new("new/b.bin", b"B"),
  ])
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_relinks(current, [
          @mndocmove.Move::new("old", "missing"),
        ]),
      )
    },
    "MissingRenamedTarget",
  )
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_relinks(current, [
          @mndocmove.Move::new("old", "new"),
          @mndocmove.Move::new("other", "new/a.bin"),
        ]),
      )
    },
    "RelinkAmbiguity",
  )
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_relinks(current, [
          @mndocmove.Move::new("new/a.bin", "new/a.bin"),
        ]),
      )
    },
    "IdentityMove",
  )
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_relinks(current, [@mndocmove.Move::new("../old", "new")]),
      )
    },
    "InvalidPath",
  )
  let partial = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("a.bin", b"A"),
    @mndocmove.Entry::new("b.bin", b"B"),
  ])
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_relinks(partial, [
          @mndocmove.Move::new("a.bin", "b.bin"),
        ]),
      )
    },
    "RelinkAmbiguity",
  )
  let markdown = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("new.md", "# Hi"),
  ])
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_relinks(markdown, [
          @mndocmove.Move::new("old.bin", "new.md"),
        ]),
      )
    },
    "FileKindChange",
  )
  assert_eq(
    @mndocmove.plan_relinks(current, [@mndocmove.Move::new("old", "new")])
    .replay(current)
    .entries(),
    current.entries(),
  )
}

///|
test "repair never falls back to the current namespace when old-coordinate resolution fails" {
  let current = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("manual/r.md", "[asset](../images/a.bin)"),
    @mndocmove.Entry::new("images/a.bin", b"A"),
  ])
  let moves = [
    @mndocmove.Move::new("r.md", "manual/r.md"),
    @mndocmove.Move::new("a.bin", "images/a.bin"),
  ]
  expect_code(
    () => ignore(@mndocmove.plan_relinks(current, moves)),
    "OutsideRoot",
  )
  assert_eq(
    current.get("manual/r.md").unwrap().text(),
    "[asset](../images/a.bin)",
  )
}

///|
test "repair source and result guards preserve later changes and remain reusable after errors" {
  let current = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("manual/r.md", "[asset](a.bin)"),
    @mndocmove.Entry::new("media/a.bin", b"A"),
  ])
  let plan = @mndocmove.plan_relinks(current, [
    @mndocmove.Move::new("r.md", "manual/r.md"),
    @mndocmove.Move::new("a.bin", "media/a.bin"),
  ])
  let result = plan.replay(current)
  let entries = current.entries()
  entries.push(@mndocmove.Entry::new("extra.bin", b""))
  let changed = @mndocmove.DocTree::new(entries)
  expect_code(() => ignore(plan.replay(changed)), "StaleSnapshot")
  expect_code(() => ignore(plan.restore(changed)), "RestoreMismatch")
  assert_eq(plan.restore(result).entries(), current.entries())
  assert_eq(changed.get("extra.bin").unwrap().data(), b"")
}

///|
test "repair chains retain historical intent in compact wire and reject parallel merge misuse" {
  let current = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("manual/r.md", "[asset](a.bin)"),
    @mndocmove.Entry::new("media/a.bin", b"A"),
  ])
  let plan = @mndocmove.plan_relinks(current, [
    @mndocmove.Move::new("r.md", "manual/r.md"),
    @mndocmove.Move::new("a.bin", "media/a.bin"),
  ])
  let chain = plan.then_moves([@mndocmove.Move::new("media", "images")])
  let loaded = @mndocmove.MoveChain::from_json_string(chain.to_json_string())
  assert_eq(loaded.to_json_string(), chain.to_json_string())
  assert_eq(loaded.stages()[0].relinks(), plan.relinks())
  assert_eq(
    loaded.replay(current).get("manual/r.md").unwrap().text(),
    "[asset](../images/a.bin)",
  )
  assert_eq(loaded.restore(loaded.replay(current)).entries(), current.entries())
  let ordinary = @mndocmove.plan_moves(current, [])
  expect_code(() => ignore(plan.merge(ordinary)), "MergeRelink")
  expect_code(() => ignore(ordinary.merge(plan)), "MergeRelink")
}

///|
test "repair wire refuses unknown schema version profiles extra or forged records without dropping data" {
  for
    wire in [
      "[\"mndocmove-relink\",2,\"commonmark\",[],[]]", "[\"mndocmove-relink\",1,\"future\",[],[]]",
      "[\"mndocmove-relink\",1,\"commonmark\",[],[],[]]", "[\"mndocmove-relink\",1,\"commonmark\",[],[[\"old\",\"new\"]]]",
      "[\"mndocmove-relink\",1,\"commonmark\",[[\"a.bin\",\"0\"]],[]]", "[\"mndocmove-relink\",1,\"commonmark\",[[\"a.bin\",\"00\",\"extra\"]],[]]",
    ] {
    let refused = try {
      ignore(@mndocmove.MovePlan::from_json_string(wire))
      false
    } catch {
      @mndocmove.Refused(_) => true
    }
    assert_true(refused)
  }
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "{{ unsupported but no-op }}"),
  ])
  let empty = @mndocmove.plan_relinks(tree, [])
  assert_eq(empty.relinks(), [])
  assert_eq(
    empty.to_json_string(),
    @mndocmove.plan_moves(tree, []).to_json_string(),
  )
  assert_eq(empty.restore(empty.replay(tree)).entries(), tree.entries())
}

///|
test "repair count limit and prefix ambiguity are checked without partial state" {
  let current = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("new/a.bin", b"A"),
  ])
  let moves = []
  for _ in 0..<4097 {
    moves.push(@mndocmove.Move::new("old", "new"))
  }
  expect_code(
    () => ignore(@mndocmove.plan_relinks(current, moves)),
    "PlanLimit",
  )
  let valid = @mndocmove.plan_relinks(current, [
    @mndocmove.Move::new("old", "new"),
  ])
  assert_eq(valid.replay(current).entries(), current.entries())
}

///|
test "repair accepts all 4096 distinct historical file renames at the inventory limit" {
  let files = []
  let moves = []
  for i in 0..<4096 {
    let name = "a" + i.to_string() + ".bin"
    files.push(@mndocmove.Entry::new("new/" + name, b""))
    moves.push(@mndocmove.Move::new("old/" + name, "new/" + name))
  }
  let current = @mndocmove.DocTree::new(files)
  let plan = @mndocmove.plan_relinks(current, moves)
  assert_eq(plan.relinks().length(), 4096)
  assert_eq(plan.moves(), [])
  assert_eq(plan.restore(plan.replay(current)).entries(), current.entries())
}
