///|
test "ordered stages equal explicit sequential migrations and restore the original snapshot" {
  let tree = fixture()
  let first = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("docs", "manual"),
  ])
  let second_moves = [@mndocmove.Move::new("img", "media")]
  let third_moves = [@mndocmove.Move::new("README.md", "guides/README.md")]
  let middle = first.replay(tree)
  let second = @mndocmove.plan_moves(middle, second_moves)
  let after_second = second.replay(middle)
  let third = @mndocmove.plan_moves(after_second, third_moves)
  let chain = first.then_moves(second_moves).then_moves(third_moves)
  let output = chain.replay(tree)
  assert_eq(chain.stages().length(), 3)
  assert_eq(output.entries(), third.replay(after_second).entries())
  assert_eq(output.get("media/a.png").unwrap().data(), b"\x00\xFF\x01")
  assert_eq(chain.restore(output).entries(), tree.entries())
  assert_true(chain.check(tree).is_match())
  assert_true(chain.check(output, side=Result).is_match())
  assert_true(!chain.check(middle, side=Result).is_match())
  expect_code(() => ignore(chain.replay(middle)), "StaleSnapshot")
  expect_code(() => ignore(chain.restore(middle)), "RestoreMismatch")
}

///|
test "later move sources name the previous result and cancellation retains both stages" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "\uFEFF[x](a.bin)\r\n"),
    @mndocmove.Entry::new("a.bin", b"\x00\xFF"),
  ])
  let first = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("a.bin", "b.bin"),
  ])
  expect_code(
    () => ignore(first.then_moves([@mndocmove.Move::new("a.bin", "c.bin")])),
    "MissingSource",
  )
  let chain = first.then_moves([@mndocmove.Move::new("b.bin", "a.bin")])
  assert_eq(chain.replay(tree).entries(), tree.entries())
  assert_eq(chain.stages().length(), 2)
  let review = chain.review(context=0)
  assert_true(review.contains("=== Stage 1 of 2 ==="))
  assert_true(review.contains("=== Stage 2 of 2 ==="))
  assert_true(review.contains("move \"a.bin\" -> \"b.bin\""))
  assert_true(review.contains("move \"b.bin\" -> \"a.bin\""))
  expect_code(() => ignore(chain.review(context=21)), "InvalidContext")
  assert_eq(chain.restore(chain.replay(tree)).entries(), tree.entries())
}

///|
test "chain profiles inherit explicitly and unsupported overrides refuse without changing a plan" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "r.md", "<picture><source srcset='a.bin 1x'><img src='a.bin'></picture>",
    ),
    @mndocmove.Entry::new("a.bin", b"\xFF"),
  ])
  let first = @mndocmove.plan_moves(
    tree,
    [@mndocmove.Move::new("a.bin", "b.bin")],
    profile=StaticHtml,
  )
  let chain = first.then_moves([@mndocmove.Move::new("r.md", "manual/r.md")])
  assert_true(chain.stages()[1].profile() is StaticHtml)
  assert_true(
    chain
    .replay(tree)
    .get("manual/r.md")
    .unwrap()
    .text()
    .contains("../b.bin 1x"),
  )
  expect_code(
    () => {
      ignore(
        first.then_moves(
          [@mndocmove.Move::new("r.md", "manual/r.md")],
          profile=CommonMark,
        ),
      )
    },
    "UnsupportedMarkdown",
  )
  let unparsed = @mndocmove.plan_moves(tree, [])
  let opted_in = unparsed.then_moves(
    [@mndocmove.Move::new("a.bin", "b.bin")],
    profile=StaticHtml,
  )
  assert_true(opted_in.stages()[0].profile() is CommonMark)
  assert_true(opted_in.stages()[1].profile() is StaticHtml)
  assert_eq(opted_in.restore(opted_in.replay(tree)).entries(), tree.entries())
}

///|
test "chain wire stores one original snapshot and recomputes ordered stages deterministically" {
  let tree = fixture()
  let first = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("docs", "manual"),
  ])
  let chain = first.then_moves([@mndocmove.Move::new("manual", "guides")])
  let text = chain.to_json_string()
  let loaded = @mndocmove.MoveChain::from_json_string(text)
  assert_eq(loaded.to_json_string(), text)
  assert_eq(loaded.review(), chain.review())
  assert_eq(loaded.replay(tree).entries(), chain.replay(tree).entries())
  assert_eq(loaded.restore(loaded.replay(tree)).entries(), tree.entries())
  let expected : Json = [
    "mndocmove-chain",
    1,
    @json.parse(first.to_json_string()),
    [["commonmark", [["manual", "guides"]]]],
  ]
  assert_eq(@json.parse(text), expected)
  expect_code(
    () => ignore(@mndocmove.MovePlan::from_json_string(text)),
    "InvalidPlan",
  )
  let legacy = @mndocmove.MoveChain::from_json_string(first.to_json_string())
  assert_eq(legacy.stages().length(), 1)
  assert_eq(legacy.review(), first.review())
  assert_eq(legacy.replay(tree).entries(), first.replay(tree).entries())
  assert_eq(
    @mndocmove.MoveChain::from_json_string(legacy.to_json_string()).to_json_string(),
    legacy.to_json_string(),
  )
}

///|
test "chain decoding refuses unknown or truncated schemas rather than ignoring stage data" {
  let tree = @mndocmove.DocTree::new([@mndocmove.Entry::new("a.bin", b"A")])
  let first = @mndocmove.plan_moves(tree, [])
  let base = @json.parse(first.to_json_string())
  let invalid : Array[Json] = [
    ["mndocmove-chain", 2, base, []],
    ["mndocmove-chain", 1, base, [], "extra"],
    ["mndocmove-chain", 1, base],
    ["mndocmove-chain", 1, base, [["unknown", []]]],
    ["mndocmove-chain", 1, base, [["commonmark", [], "extra"]]],
    ["mndocmove-chain", 1, base, [["commonmark"]]],
    ["mndocmove-chain", 1, ["mndocmove-chain", 1, base, []], []],
  ]
  for value in invalid {
    expect_code(
      () => ignore(@mndocmove.MoveChain::from_json_string(value.stringify())),
      "InvalidPlan",
    )
  }
  expect_code(
    () => ignore(@mndocmove.MoveChain::from_json_string("{}")),
    "InvalidPlan",
  )
  let missing : Json = [
    "mndocmove-chain",
    1,
    base,
    [["commonmark", [["missing.bin", "z.bin"]]]],
  ]
  expect_code(
    () => ignore(@mndocmove.MoveChain::from_json_string(missing.stringify())),
    "MissingSource",
  )
  assert_eq(first.replay(tree).entries(), tree.entries())
}

///|
test "chain stage arrays move inputs and failed append remain independent" {
  let tree = fixture()
  let first = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("docs", "manual"),
  ])
  let requested = [@mndocmove.Move::new("img", "media")]
  let chain = first.then_moves(requested)
  let before = chain.to_json_string()
  requested[0] = @mndocmove.Move::new("img", "wrong")
  let exposed = chain.stages()
  exposed[0] = @mndocmove.plan_moves(tree, [])
  ignore(exposed.pop())
  expect_code(
    () => ignore(chain.then_moves([@mndocmove.Move::new("absent", "other")])),
    "MissingSource",
  )
  assert_eq(chain.to_json_string(), before)
  assert_eq(chain.stages().length(), 2)
  assert_true(chain.replay(tree).get("media/a.png") is Some(_))
}

///|
test "chain stage limit accepts eight and rejects the ninth including wire input" {
  let tree = @mndocmove.DocTree::new([@mndocmove.Entry::new("a.bin", b"")])
  let first = @mndocmove.plan_moves(tree, [])
  let mut chain = first.then_moves([])
  for _ in 0..<6 {
    chain = chain.then_moves([])
  }
  assert_eq(chain.stages().length(), 8)
  let encoded = chain.to_json_string()
  assert_eq(
    @mndocmove.MoveChain::from_json_string(encoded).stages().length(),
    8,
  )
  expect_code(() => ignore(chain.then_moves([])), "ChainLimit")
  let ninth : Json = [
    "mndocmove-chain",
    1,
    @json.parse(first.to_json_string()),
    Json::array(
      Array::makei(8, fn(_) {
        let step : Json = ["commonmark", []]
        step
      }),
    ),
  ]
  expect_code(
    () => ignore(@mndocmove.MoveChain::from_json_string(ninth.stringify())),
    "ChainLimit",
  )
  assert_eq(chain.to_json_string(), encoded)
}

///|
test "chain logical snapshot budget has an exact 128 MiB boundary and refusal is recoverable" {
  let bytes = Bytes::from_array(Array::make(33554432, b'x'))
  let tree = @mndocmove.DocTree::new([@mndocmove.Entry::new("large.bin", bytes)])
  let first = @mndocmove.plan_moves(tree, [])
  let chain = first.then_moves([]).then_moves([])
  assert_eq(chain.stages().length(), 3)
  expect_code(() => ignore(chain.then_moves([])), "ChainLimit")
  assert_true(chain.check(tree).is_match())
  assert_eq(chain.restore(chain.replay(tree)).entries(), tree.entries())
}
