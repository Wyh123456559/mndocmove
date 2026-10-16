///|
test "adopted chain budgeting counts the saved baseline rather than longer current paths" {
  let baseline = DocTree::new([
    Entry::markdown("汉😀.md", "[asset](a.bin)\r\n"),
    Entry::new("a.bin", b"\x00\xFF"),
  ])
  let pending = plan_moves(baseline, [
    Move::new("汉😀.md", "very long folder/汉😀.md"),
  ])
  let physical = pending.renamed_input()
  let adopted = pending.adopt(physical)
  let chain = adopted.then_moves(
    [Move::new("a.bin", "images/a.bin")],
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
    MoveChain::from_json_string(text).replay(physical).entries(),
    chain.replay(physical).entries(),
  )
  let single = MoveChain::from_json_string(adopted.to_json_string())
  assert_eq(single.wire_units(), single.to_json_string().length().to_int64())
}
