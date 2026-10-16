///|
test "Git exact rename bytes import deterministically with explicit root scope and saved-plan workflow" {
  let records = b"R100\x00docs/assets/a.bin\x00docs/media/a.bin\x00R100\x00docs/README.md\x00docs/manual/README.md\x00"
  let moves = @mndocmove.moves_from_git_name_status(records, root_prefix="docs")
  assert_eq(moves, [
    @mndocmove.Move::new("README.md", "manual/README.md"),
    @mndocmove.Move::new("assets/a.bin", "media/a.bin"),
  ])
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("README.md", "[asset](assets/a.bin)\r\n"),
    @mndocmove.Entry::new("assets/a.bin", b"\xFF\x00"),
  ])
  let plan = @mndocmove.plan_moves(tree, moves)
  let loaded = @mndocmove.MovePlan::from_json_string(plan.to_json_string())
  assert_eq(
    loaded.replay(tree).get("manual/README.md").unwrap().text(),
    "[asset](../media/a.bin)\r\n",
  )
  assert_eq(loaded.restore(loaded.replay(tree)).entries(), tree.entries())
  let reordered = b"R100\x00docs/README.md\x00docs/manual/README.md\x00R100\x00docs/assets/a.bin\x00docs/media/a.bin\x00"
  assert_eq(
    @mndocmove.moves_from_git_name_status(reordered, root_prefix="docs"),
    moves,
  )
  assert_eq(@mndocmove.moves_from_git_name_status(b""), [])
}

///|
test "Git paths retain spaces Unicode and literal percent names without shell quoting or URL decoding" {
  let data = "R100\u0000guide 中文.md\u0000manual/guide 中文.md\u0000R100\u0000a%20b.bin\u0000images/a%20b.bin\u0000"
  let moves = @mndocmove.moves_from_git_name_status(@utf8.encode(data))
  assert_true(
    moves.contains(
      @mndocmove.Move::new("guide 中文.md", "manual/guide 中文.md"),
    ),
  )
  assert_true(
    moves.contains(@mndocmove.Move::new("a%20b.bin", "images/a%20b.bin")),
  )
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("guide 中文.md", "[asset](a%2520b.bin)"),
    @mndocmove.Entry::new("a%20b.bin", b"A"),
  ])
  assert_eq(
    @mndocmove.plan_moves(tree, moves)
    .replay(tree)
    .get("manual/guide 中文.md")
    .unwrap()
    .text(),
    "[asset](../images/a%2520b.bin)",
  )
}

///|
test "Git importer refuses every unsupported status rather than dropping nonrename changes" {
  for
    status in [
      "A", "M", "D", "C100", "R099", "R99", "R50", "R101", "R0100", "R", "T", "U",
      "X", "", "\uFEFFR100",
    ] {
    let data = @utf8.encode(
      "R100\u0000a.bin\u0000b.bin\u0000" +
      status +
      "\u0000c.bin\u0000d.bin\u0000",
    )
    expect_code(
      () => ignore(@mndocmove.moves_from_git_name_status(data)),
      "UnsupportedGitChange",
    )
  }
  assert_eq(
    @mndocmove.moves_from_git_name_status(b"R100\x00a.bin\x00b.bin\x00").length(),
    1,
  )
}

///|
test "Git importer refuses truncation extra fields non-NUL formats and malformed UTF8" {
  for
    data in [
      b"R100", b"R100\x00", b"R100\x00a.bin", b"R100\x00a.bin\x00", b"R100\x00a.bin\x00b.bin",
      b"R100\ta\tb\n",
    ] {
    expect_code(
      () => ignore(@mndocmove.moves_from_git_name_status(data)),
      "InvalidGitDiff",
    )
  }
  expect_code(
    () => {
      ignore(
        @mndocmove.moves_from_git_name_status(b"R100\x00a.bin\x00b.bin\x00\x00"),
      )
    },
    "UnsupportedGitChange",
  )
  expect_code(
    () => {
      ignore(
        @mndocmove.moves_from_git_name_status(b"R100\x00\xFF\x00b.bin\x00"),
      )
    },
    "GitDiffUtf8",
  )
  expect_code(
    () => {
      ignore(
        @mndocmove.moves_from_git_name_status(b"R100\x00a.bin\x00\xC0\xAF\x00"),
      )
    },
    "GitDiffUtf8",
  )
}

///|
test "Git importer validates every portable endpoint root prefix and uniqueness without directory inference" {
  for
    path in [
      "", "/a.bin", "../a.bin", "a/../b.bin", "a\\b.bin", "a\tb.bin", "a\nb.bin",
      "CON.txt", "a?.bin", "a.bin ",
    ] {
    expect_code(
      () => {
        ignore(
          @mndocmove.moves_from_git_name_status(
            @utf8.encode("R100\u0000" + path + "\u0000ok.bin\u0000"),
          ),
        )
      },
      "InvalidPath",
    )
  }
  for
    data in [
      b"R100\x00docs/a.bin\x00other/b.bin\x00", b"R100\x00docs2/a.bin\x00docs/b.bin\x00",
      b"R100\x00docs\x00docs/b.bin\x00",
    ] {
    expect_code(
      () => {
        ignore(@mndocmove.moves_from_git_name_status(data, root_prefix="docs"))
      },
      "GitRootScope",
    )
  }
  expect_code(
    () => {
      ignore(@mndocmove.moves_from_git_name_status(b"", root_prefix="../docs"))
    },
    "InvalidPath",
  )
  expect_code(
    () => {
      ignore(
        @mndocmove.moves_from_git_name_status(b"R100\x00a.bin\x00a.bin\x00"),
      )
    },
    "IdentityMove",
  )
  for
    data in [
      b"R100\x00a.bin\x00b.bin\x00R100\x00a.bin\x00c.bin\x00", b"R100\x00a.bin\x00b.bin\x00R100\x00c.bin\x00b.bin\x00",
      b"R100\x00a.bin\x00b.bin\x00R100\x00A.BIN\x00c.bin\x00",
    ] {
    expect_code(
      () => ignore(@mndocmove.moves_from_git_name_status(data)),
      "GitRenameConflict",
    )
  }
  let moves = @mndocmove.moves_from_git_name_status(
    b"R100\x00docs/a.bin\x00manual/a.bin\x00R100\x00docs/b.bin\x00manual/b.bin\x00",
  )
  assert_eq(moves.length(), 2)
  assert_true(!moves.contains(@mndocmove.Move::new("docs", "manual")))
}

///|
test "Git parser count byte and field limits refuse oversized input and recover" {
  let data = StringBuilder()
  for i in 0..<4096 {
    data.write_string(
      "R100\u0000a" +
      i.to_string() +
      ".bin\u0000b" +
      i.to_string() +
      ".bin\u0000",
    )
  }
  let valid = @utf8.encode(data.to_string())
  assert_eq(@mndocmove.moves_from_git_name_status(valid).length(), 4096)
  expect_code(
    () => {
      ignore(
        @mndocmove.moves_from_git_name_status(
          valid + b"R100\x00last.bin\x00extra.bin\x00",
        ),
      )
    },
    "GitDiffLimit",
  )
  expect_code(
    () => {
      ignore(@mndocmove.moves_from_git_name_status(Bytes::make(16777217, b'A')))
    },
    "GitDiffLimit",
  )
  expect_code(
    () => {
      ignore(
        @mndocmove.moves_from_git_name_status(
          b"R100\x00" + Bytes::make(16385, b'A') + b"\x00b.bin\x00",
        ),
      )
    },
    "GitDiffLimit",
  )
  assert_eq(@mndocmove.moves_from_git_name_status(valid).length(), 4096)
}

///|
test "Git portable path length boundary is measured in UTF16 after strict UTF8 decoding" {
  let path = StringBuilder()
  for _ in 0..<4092 {
    path.write_string("a")
  }
  path.write_string(".bin")
  let accepted = @utf8.encode(
    "R100\u0000" + path.to_string() + "\u0000b.bin\u0000",
  )
  assert_eq(
    @mndocmove.moves_from_git_name_status(accepted)[0].source().length(),
    4096,
  )
  let refused = @utf8.encode(
    "R100\u0000a" + path.to_string() + "\u0000b.bin\u0000",
  )
  expect_code(
    () => ignore(@mndocmove.moves_from_git_name_status(refused)),
    "InvalidPath",
  )
}
