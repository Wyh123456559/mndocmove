///|
test "root directory links follow documents through inward and outward moves" {
  for
    (path, destination, link, rewritten) in [
      ("r.md", "manual/deep/r.md", "./", "../../"),
      ("docs/r.md", "r.md", "../", "./"),
      ("docs/r.md", "manual/deep/r.md", "..", "../.."),
      ("r.md", "manual/r.md", ".", ".."),
      ("docs/r.md", "manual/r.md", "../", "../"),
    ] {
    let source = "\uFEFF# Root 😀\r\n[home](" +
      link +
      "?view=tree&amp;x=2#top)"
    let tree = @mndocmove.DocTree::new([
      @mndocmove.Entry::markdown(path, source),
      @mndocmove.Entry::new("asset.bin", b"\xFF\x00"),
    ])
    let plan = @mndocmove.plan_moves(tree, [
      @mndocmove.Move::new(path, destination),
    ])
    let output = plan.replay(tree)
    assert_eq(
      output.get(destination).unwrap().text(),
      source.replace(old=link + "?", new=rewritten + "?"),
    )
    for edit in plan.edits() {
      assert_eq(edit.old_target, "")
      assert_eq(edit.new_target, "")
    }
    let loaded = @mndocmove.MovePlan::from_json_string(plan.to_json_string())
    assert_eq(loaded.replay(tree).entries(), output.entries())
    assert_eq(loaded.restore(output).entries(), tree.entries())
  }
}

///|
test "root links in definitions and static HTML retain source layout" {
  let source = "# Home\r\n[go][home]\r\n\r\n[home]: ../?q=1&amp;x=2#top \"Keep title\"\r\n\r\n<a HREF='../#readme' title=\"Keep\">Root</a>"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("docs/r.md", source),
  ])
  let plan = @mndocmove.plan_moves(
    tree,
    [@mndocmove.Move::new("docs/r.md", "r.md")],
    profile=StaticHtml,
  )
  let output = plan.replay(tree)
  assert_eq(
    output.get("r.md").unwrap().text(),
    source.replace_all(old="../", new="./"),
  )
  assert_eq(plan.edits().length(), 2)
  assert_true(plan.review().contains("+[home]: ./?q=1&amp;x=2#top"))
  assert_eq(plan.restore(output).entries(), tree.entries())
}

///|
test "unchanged root references preserve noncanonical URL spellings" {
  let source = "[root](%2e/./?q=1#top) [empty]() [fragment](#top) [query](?q=1)"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", source),
    @mndocmove.Entry::new("a.bin", b"A"),
  ])
  let plan = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("a.bin", "b.bin"),
  ])
  assert_eq(plan.edits().length(), 0)
  assert_eq(plan.replay(tree).get("r.md").unwrap().text(), source)
}

///|
test "root targets remain fixed when whole directory prefixes swap" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("a/r.md", "[root](../) [other](../b/s.md)"),
    @mndocmove.Entry::markdown("b/s.md", "[root](../) [other](../a/r.md)"),
  ])
  let plan = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("a", "b"),
    @mndocmove.Move::new("b", "a"),
  ])
  let output = plan.replay(tree)
  assert_eq(
    output.get("b/r.md").unwrap().text(),
    "[root](../) [other](../a/s.md)",
  )
  assert_eq(
    output.get("a/s.md").unwrap().text(),
    "[root](../) [other](../b/r.md)",
  )
  assert_eq(plan.restore(output).entries(), tree.entries())
}

///|
test "root navigation still rejects escapes and root move operands" {
  for path in ["", "."] {
    expect_code(
      () => ignore(@mndocmove.DocTree::new([@mndocmove.Entry::new(path, b"")])),
      "InvalidPath",
    )
  }
  for link in ["../", "%2e%2e/", "a/../../", "/"] {
    let tree = @mndocmove.DocTree::new([
      @mndocmove.Entry::markdown("r.md", "[root](" + link + ")"),
    ])
    let code = if link == "/" { "UnsupportedUrl" } else { "OutsideRoot" }
    expect_code(
      () => {
        ignore(
          @mndocmove.plan_moves(tree, [
            @mndocmove.Move::new("r.md", "docs/r.md"),
          ]),
        )
      },
      code,
    )
  }
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[root](./)"),
  ])
  for
    (source, target) in [("", "new"), (".", "new"), ("r.md", ""), ("r.md", ".")] {
    expect_code(
      () => {
        ignore(
          @mndocmove.plan_moves(tree, [@mndocmove.Move::new(source, target)]),
        )
      },
      "InvalidPath",
    )
  }
  assert_eq(
    @mndocmove.plan_moves(tree, [@mndocmove.Move::new("r.md", "docs/r.md")])
    .replay(tree)
    .get("docs/r.md")
    .unwrap()
    .text(),
    "[root](../)",
  )
}
