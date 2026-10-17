///|
test "root profile chain wire preflight counts both explicit policy names" {
  let tree = DocTree::new([
    Entry::markdown("汉😀.md", "[A](/a.bin)"),
    Entry::new("a.bin", b"\xFF"),
  ])
  let chain = plan_moves(
    tree,
    [Move::new("a.bin", "media/a.bin")],
    profile=CommonMarkRoot,
  ).then_moves(
    [Move::new("汉😀.md", "manual/汉😀.md")],
    profile=StaticHtmlRoot,
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
}
