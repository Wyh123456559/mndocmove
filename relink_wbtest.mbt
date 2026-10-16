///|
test "repair wire budgeting counts historical intentions and longer magic exactly before allocation" {
  let tree = DocTree::new([
    Entry::markdown("manual/汉😀.md", "[asset](a.bin)\r\n"),
    Entry::new("media/a.bin", b"\xFF\x00"),
  ])
  let plan = plan_relinks(tree, [
    Move::new("汉😀.md", "manual/汉😀.md"),
    Move::new("a.bin", "media/a.bin"),
  ])
  let chain = plan.then_moves(
    [Move::new("media", "images")],
    profile=StaticHtml,
  )
  let text = chain.to_json_string()
  assert_eq(chain.wire_units(), text.length().to_int64())
  assert_eq(chain.encode_with_limit(text.length().to_int64()), text)
  let refused = try {
    ignore(chain.encode_with_limit(text.length().to_int64() - 1))
    false
  } catch {
    Refused(d) => d.code == "PlanLimit"
  }
  assert_true(refused)
  assert_eq(
    MoveChain::from_json_string(text).replay(tree).entries(),
    chain.replay(tree).entries(),
  )
}
