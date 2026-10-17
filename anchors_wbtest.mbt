///|
test "anchor chain preflight counts four field escaped Unicode intentions exactly" {
  let tree = DocTree::new([Entry::markdown("汉😀.md", "[x](#old)")])
  let plan = plan_anchor_retargets(tree, [
    {
      source: "汉😀.md",
      fragment: "old",
      destination: "汉😀.md",
      replacement: "中/\"😀",
    },
  ])
  let chain = plan.then_moves([Move::new("汉😀.md", "manual/汉😀.md")])
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
