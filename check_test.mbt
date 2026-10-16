///|
test "snapshot check selects exact source or projected result without changing either" {
  let tree = fixture()
  let plan = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("docs", "manual"),
  ])
  let output = plan.replay(tree)
  assert_true(plan.check(tree).is_match())
  assert_true(plan.check(output, side=Result).is_match())
  assert_true(!plan.check(tree, side=Result).is_match())
  assert_true(!plan.check(output).is_match())
  assert_eq(plan.restore(output).entries(), tree.entries())
}

///|
test "snapshot check merges all additions removals and equal-length byte changes in path order" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("b.bin", b"\x00\xFF"),
    @mndocmove.Entry::new("d.bin", b"old"),
    @mndocmove.Entry::new("f.bin", b"same"),
    @mndocmove.Entry::new("h.bin", b""),
  ])
  let plan = @mndocmove.plan_moves(tree, [])
  let current = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("a.bin", b"A"),
    @mndocmove.Entry::new("b.bin", b"\xFF\x00"),
    @mndocmove.Entry::new("f.bin", b"same"),
    @mndocmove.Entry::new("z.bin", b"ZZ"),
  ])
  let report = plan.check(current)
  assert_eq(report.changes(), [
    @mndocmove.Added("a.bin", 1),
    @mndocmove.Modified("b.bin", 2, 2),
    @mndocmove.Removed("d.bin", 3),
    @mndocmove.Removed("h.bin", 0),
    @mndocmove.Added("z.bin", 2),
  ])
  assert_eq(
    report.to_json_string(),
    "[\"mndocmove-check\",1,\"source\",4,4,[[\"added\",\"a.bin\",1],[\"modified\",\"b.bin\",2,2],[\"removed\",\"d.bin\",3],[\"removed\",\"h.bin\",0],[\"added\",\"z.bin\",2]]]",
  )
  expect_code(() => ignore(plan.replay(current)), "StaleSnapshot")
  expect_code(() => ignore(plan.restore(current)), "RestoreMismatch")
  assert_true(plan.check(tree).is_match())
}

///|
test "snapshot JSON is deterministic after plan wire round trip and inventory reorder" {
  let empty_plan = @mndocmove.plan_moves(@mndocmove.DocTree::new([]), [])
  let ordered = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("aa", b""),
    @mndocmove.Entry::new("z", b""),
  ])
  assert_eq(empty_plan.check(ordered).changes(), [
    @mndocmove.Added("z", 0),
    @mndocmove.Added("aa", 0),
  ])
  let tree = fixture()
  let plan = @mndocmove.plan_moves(tree, [@mndocmove.Move::new("img", "media")])
  let files = tree.entries()
  let current = @mndocmove.DocTree::new([
    files[2],
    @mndocmove.Entry::new("新 😀.bin", b"\xFF"),
    files[0],
  ])
  let loaded = @mndocmove.MovePlan::from_json_string(plan.to_json_string())
  assert_eq(
    loaded.check(current).to_json_string(),
    plan.check(current).to_json_string(),
  )
  assert_eq(
    loaded.check(current, side=Result).to_json_string(),
    plan.check(current, side=Result).to_json_string(),
  )
  let text = plan.check(current).to_json_string()
  assert_eq(@json.parse(text).stringify(), text)
}

///|
test "snapshot reports return independent arrays and never consume a plan" {
  let tree = fixture()
  let plan = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("docs", "manual"),
  ])
  let report = plan.check(@mndocmove.DocTree::new([]))
  let before = report.to_json_string()
  let exposed = report.changes()
  exposed[0] = @mndocmove.Added("fake.bin", 123)
  ignore(exposed.pop())
  assert_eq(report.to_json_string(), before)
  assert_eq(plan.check(@mndocmove.DocTree::new([])).to_json_string(), before)
  assert_true(plan.check(plan.replay(tree), side=Result).is_match())
}

///|
test "snapshot comparison handles empty trees zero-byte files and unparsed Markdown bytes" {
  let empty = @mndocmove.DocTree::new([])
  let empty_plan = @mndocmove.plan_moves(empty, [])
  assert_eq(
    empty_plan.check(empty).to_json_string(),
    "[\"mndocmove-check\",1,\"source\",0,0,[]]",
  )
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("r.md", b"\xFF\x00"),
    @mndocmove.Entry::new("zero.bin", b""),
  ])
  let plan = @mndocmove.plan_moves(tree, [])
  assert_true(plan.check(tree).is_match())
  assert_true(plan.check(tree, side=Result).is_match())
  assert_eq(empty_plan.check(tree).changes(), [
    @mndocmove.Added("r.md", 2),
    @mndocmove.Added("zero.bin", 0),
  ])
  assert_eq(plan.check(empty).changes(), [
    @mndocmove.Removed("r.md", 2),
    @mndocmove.Removed("zero.bin", 0),
  ])
}

///|
test "snapshot comparison reports every difference at the maximum inventory boundary" {
  let expected = @mndocmove.DocTree::new(
    Array::makei(4096, fn(i) {
      @mndocmove.Entry::new("a" + i.to_string() + ".bin", b"A")
    }),
  )
  let actual = @mndocmove.DocTree::new(
    Array::makei(4096, fn(i) {
      @mndocmove.Entry::new("z" + i.to_string() + ".bin", b"B")
    }),
  )
  let plan = @mndocmove.plan_moves(expected, [])
  let report = plan.check(actual)
  assert_eq(report.changes().length(), 8192)
  assert_true(!report.is_match())
  assert_true(plan.check(expected).is_match())
}
