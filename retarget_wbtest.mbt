///|
test "retarget chain wire preflight counts replacement intents exactly" {
  let tree = DocTree::new([
    Entry::markdown("汉😀.md", "[A](a.bin)"),
    Entry::new("a.bin", b"A"),
    Entry::new("b.bin", b"B"),
  ])
  let plan = plan_retargets(tree, [Move::new("a.bin", "b.bin")])
  let chain = plan.then_moves([Move::new("b.bin", "media/b.bin")])
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
}
