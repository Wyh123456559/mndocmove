///|
test "chain wire size preflight matches encoded Unicode paths profiles and empty arrays at the boundary" {
  let tree = DocTree::new([
    Entry::markdown("汉😀.md", "[x](a.bin)\r\n"),
    Entry::new("a.bin", b"\x00\xFF"),
  ])
  let first = plan_moves(tree, [Move::new("a.bin", "long name.bin")])
  let chain = first
    .then_moves(
      [Move::new("汉😀.md", "manual/汉😀.md")],
      profile=StaticHtml,
    )
    .then_moves([])
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
  assert_eq(chain.to_json_string(), text)
  assert_eq(
    MoveChain::from_json_string(text).replay(tree).entries(),
    chain.replay(tree).entries(),
  )
  let empty = MoveChain::from_json_string(
    plan_moves(DocTree::new([]), []).to_json_string(),
  )
  assert_eq(empty.wire_units(), empty.to_json_string().length().to_int64())
}
