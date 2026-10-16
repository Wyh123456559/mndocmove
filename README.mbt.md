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

Review a saved migration before exporting:

```mbt check
///|
test "review includes source evidence and opaque resource moves" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[asset](a.txt)\n"),
    @mndocmove.Entry::new("a.txt", b"A"),
  ])
  let plan = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("a.txt", "b.txt"),
  ])
  let review = plan.review(context=0)
  assert_true(review.contains("-[asset](a.txt)\n+[asset](b.txt)\n"))
  assert_true(review.contains("[opaque asset]"))
}
```

Restore exact source bytes after verifying the migrated snapshot:

```mbt check
///|
test "restore from a saved plan without reverse URL rewriting" {
  let source = "\uFEFF[x](./a%2Etxt?x=1&amp;y=2)\r\n"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", source),
    @mndocmove.Entry::new("a.txt", b"\xFF\x00"),
  ])
  let plan = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("a.txt", "assets/a.txt"),
  ])
  let migrated = plan.replay(tree)
  let saved = @mndocmove.MovePlan::from_json_string(plan.to_json_string())
  let original = saved.restore(migrated)
  assert_eq(original.entries(), tree.entries())
  assert_eq(original.get("r.md").unwrap().text(), source)
}
```

Root-directory navigation follows a guide into a deeper folder:

```mbt check
///|
test "keep a navigation link attached to the inventory root" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("guide/NAV.md", "[Root](../?view=tree#docs)\r\n"),
  ])
  let plan = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("guide", "manual/deep"),
  ])
  let output = plan.replay(tree)
  assert_eq(
    output.get("manual/deep/NAV.md").unwrap().text(),
    "[Root](../../?view=tree#docs)\r\n",
  )
  assert_eq(plan.restore(output).entries(), tree.entries())
}
```

Responsive image URLs and the fallback migrate together:

```mbt check
///|
test "preserve responsive density descriptors during relocation" {
  let source = "<picture><source srcset='a.png 1x, b.png 1.5x'><img src='a.png'></picture>"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", source),
    @mndocmove.Entry::new("a.png", b"A"),
    @mndocmove.Entry::new("b.png", b"B"),
  ])
  let plan = @mndocmove.plan_moves(
    tree,
    [
      @mndocmove.Move::new("a.png", "images/a.png"),
      @mndocmove.Move::new("b.png", "images/b.png"),
    ],
    profile=StaticHtml,
  )
  assert_eq(
    plan.replay(tree).get("r.md").unwrap().text(),
    "<picture><source srcset='images/a.png 1x, images/b.png 1.5x'><img src='images/a.png'></picture>",
  )
  assert_eq(plan.edits().length(), 3)
}
```

Inspect all drift before replay or after export:

```mbt check
///|
test "report every snapshot change without applying a migration" {
  let tree = @mndocmove.DocTree::new([@mndocmove.Entry::new("a.bin", b"A")])
  let plan = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("a.bin", "b.bin"),
  ])
  let current = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("a.bin", b"B"),
    @mndocmove.Entry::new("extra.bin", b""),
  ])
  assert_eq(plan.check(current).changes(), [
    @mndocmove.Modified("a.bin", 1, 1),
    @mndocmove.Added("extra.bin", 0),
  ])
  assert_true(plan.check(plan.replay(tree), side=Result).is_match())
}
```
