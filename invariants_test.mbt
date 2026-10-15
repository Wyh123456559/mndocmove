///|
test "path encoding roundtrips and unchanged text survives multiple moves" {
  for
    name in [
      "space name", "中文😀", "a(b)", "a&b", "a#b", "a%b", "a+b", "a'b",
    ] {
    let source = "\uFEFF# Keep\r\n[x](asset.txt?x=1&amp;y=2#part)\r\n"
    let tree = @mndocmove.DocTree::new([
      @mndocmove.Entry::markdown("README.md", source),
      @mndocmove.Entry::new("asset.txt", b"\x00\x80\xFF"),
    ])
    let target = "assets/" + name + ".txt"
    let first = @mndocmove.plan_moves(tree, [
      @mndocmove.Move::new("asset.txt", target),
    ])
    let next = first.replay(tree)
    // Reparse the generated Markdown and resolve it again in the reverse move.
    let second = @mndocmove.plan_moves(next, [
      @mndocmove.Move::new(target, "asset.txt"),
    ])
    assert_eq(second.replay(next).get("README.md").unwrap().text(), source)
    assert_eq(next.get(target).unwrap().data(), b"\x00\x80\xFF")
    assert_eq(
      @mndocmove.MovePlan::from_json_string(first.to_json_string()).preview(),
      first.preview(),
    )
  }
}

///|
test "directory links preserve slash and refuse disappearing implicit directories" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[d](d/)"),
    @mndocmove.Entry::new("d/a", b"A"),
  ])
  let p = @mndocmove.plan_moves(tree, [@mndocmove.Move::new("d", "e")])
  assert_eq(p.replay(tree).get("r.md").unwrap().text(), "[d](e/)")
  expect_code(
    () => {
      ignore(@mndocmove.plan_moves(tree, [@mndocmove.Move::new("d/a", "e/a")]))
    },
    "MissingProjectedTarget",
  )
}

///|
test "empty destinations fragments queries and unused definitions" {
  let text = "[empty]() [fragment](#x) [query](?x=1)\n\n[unused]: a.txt\n"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", text),
    @mndocmove.Entry::new("a.txt", b"A"),
  ])
  let p = @mndocmove.plan_moves(tree, [@mndocmove.Move::new("a.txt", "b.txt")])
  assert_eq(
    p.replay(tree).get("r.md").unwrap().text(),
    "[empty]() [fragment](#x) [query](?x=1)\n\n[unused]: b.txt\n",
  )
}

///|
test "size limits have exact accepted and refused boundaries" {
  let max = Bytes::from_array(Array::make(1048576, b'x'))
  let too_big = Bytes::from_array(Array::make(1048577, b'x'))
  assert_eq(
    @mndocmove.DocTree::new([@mndocmove.Entry::new("big.md", max)])
    .entries()
    .length(),
    1,
  )
  expect_code(
    () => {
      ignore(
        @mndocmove.DocTree::new([@mndocmove.Entry::new("big.md", too_big)]),
      )
    },
    "MarkdownLimit",
  )
  let files = Array::makei(4096, fn(i) {
    @mndocmove.Entry::new(i.to_string() + ".bin", b"")
  })
  assert_eq(@mndocmove.DocTree::new(files).entries().length(), 4096)
  files.push(@mndocmove.Entry::new("overflow.bin", b""))
  expect_code(() => ignore(@mndocmove.DocTree::new(files)), "FileLimit")
  expect_code(
    () => {
      ignore(@mndocmove.moves_from_json("[[[[[[[[[[[[[[[[[0]]]]]]]]]]]]]]]]]"))
    },
    "PlanLimit",
  )
}
