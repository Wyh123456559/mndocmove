# Library quick start

Import `Wyh123456559/mndocmove` as `@mndocmove`. This example is executed by
`moon test`; see [README](README.md) for the real filesystem workflow.

```mbt check
///|
test "move a guide while updating its incoming link" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("README.md", "[Install](docs/install.md)\n"),
    @mndocmove.Entry::markdown("docs/install.md", "Install the compiler.\n"),
  ])
  let plan = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("docs/install.md", "manual/start.md"),
  ])
  let output = plan.replay(tree)
  assert_eq(
    output.get("README.md").unwrap().text(),
    "[Install](manual/start.md)\n",
  )
  let restored = @mndocmove.MovePlan::from_json_string(plan.to_json_string())
  assert_eq(restored.preview(), plan.preview())
}
```

HTML support is explicitly selected and saved in the plan:

```mbt check
///|
test "static HTML image relocation" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("README.md", "<img src='logo.svg' alt='Logo'>\n"),
    @mndocmove.Entry::new("logo.svg", b"<svg/>"),
  ])
  let plan = @mndocmove.plan_moves(
    tree,
    [@mndocmove.Move::new("logo.svg", "assets/logo.svg")],
    profile=StaticHtml,
  )
  assert_eq(
    plan.replay(tree).get("README.md").unwrap().text(),
    "<img src='assets/logo.svg' alt='Logo'>\n",
  )
}
```
