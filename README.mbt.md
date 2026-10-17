# Library quick start

Import `Wyh123456559/mndocmove` as `@mndocmove`. These examples are executed by
`moon test`; see [README](README.md) for the real filesystem workflows.

Explicitly consolidate one section while preserving both pages:

```mbt check
///|
test "reassign a section then restore its exact original references" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("old.md", "# Old\n[self](#old)"),
    @mndocmove.Entry::markdown("manual/new.md", "# New\n"),
  ])
  let mappings = @mndocmove.anchor_retargets_from_json(
    "[[\"old.md\",\"old\",\"manual/new.md\",\"new\"]]",
  )
  let plan = @mndocmove.plan_anchor_retargets(tree, mappings)
  let saved = @mndocmove.MovePlan::from_json_string(plan.to_json_string())
  let result = saved.replay(tree)
  assert_eq(
    result.get("old.md").unwrap().text(),
    "# Old\n[self](manual/new.md#new)",
  )
  assert_eq(saved.restore(result).entries(), tree.entries())
}
```

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

Width sets preserve layout metadata while moving resources:

```mbt check
///|
test "relocate a width-based responsive image" {
  let source = "<img sizes='(max-width: 40em) 100vw, 800px' srcset='a.png 320w, b.png 640w'>"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", source),
    @mndocmove.Entry::new("a.png", b"A"),
    @mndocmove.Entry::new("b.png", b"B"),
  ])
  let plan = @mndocmove.plan_moves(
    tree,
    [@mndocmove.Move::new("r.md", "manual/r.md")],
    profile=StaticHtml,
  )
  let output = plan.replay(tree)
  assert_eq(
    output.get("manual/r.md").unwrap().text(),
    "<img sizes='(max-width: 40em) 100vw, 800px' srcset='../a.png 320w, ../b.png 640w'>",
  )
  assert_eq(plan.restore(output).entries(), tree.entries())
}
```

Embedded media uses the same guarded plans:

```mbt check
///|
test "relocate a video poster and caption track" {
  let source = "<video src='clip.webm' poster='poster.svg' controls><track src='captions.vtt' kind='captions' default></video>"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", source),
    @mndocmove.Entry::new("clip.webm", b"video"),
    @mndocmove.Entry::new("poster.svg", b"<svg/>"),
    @mndocmove.Entry::new("captions.vtt", b"WEBVTT\n"),
  ])
  let plan = @mndocmove.plan_moves(
    tree,
    [@mndocmove.Move::new("r.md", "manual/r.md")],
    profile=StaticHtml,
  )
  let saved = @mndocmove.MovePlan::from_json_string(plan.to_json_string())
  let output = saved.replay(tree)
  assert_eq(
    output.get("manual/r.md").unwrap().text(),
    "<video src='../clip.webm' poster='../poster.svg' controls><track src='../captions.vtt' kind='captions' default></video>",
  )
  assert_eq(saved.restore(output).entries(), tree.entries())
}
```

Combine independent plans from one shared snapshot:

```mbt check
///|
test "merge document and asset intentions" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[asset](a.bin)"),
    @mndocmove.Entry::new("a.bin", b"A"),
  ])
  let docs = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("r.md", "manual/r.md"),
  ])
  let assets = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("a.bin", "media/a.bin"),
  ])
  let merged = docs.merge(assets)
  assert_eq(
    merged.replay(tree).get("manual/r.md").unwrap().text(),
    "[asset](../media/a.bin)",
  )
  assert_eq(merged.to_json_string(), assets.merge(docs).to_json_string())
}
```

Git name-status bytes can replace handwritten move lists:

```mbt check
///|
test "import exact Git rename intent" {
  let moves = @mndocmove.moves_from_git_name_status(
    b"R100\x00docs/r.md\x00docs/manual/r.md\x00",
    root_prefix="docs",
  )
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "# Guide\n"),
  ])
  let plan = @mndocmove.plan_moves(tree, moves)
  assert_eq(plan.replay(tree).get("manual/r.md").unwrap().text(), "# Guide\n")
}
```

Repair unchanged link text after a physical rename:

```mbt check
///|
test "repair links at already-moved paths" {
  let current = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("manual/r.md", "[asset](a.bin)"),
    @mndocmove.Entry::new("media/a.bin", b"A"),
  ])
  let repair = @mndocmove.plan_relinks(current, [
    @mndocmove.Move::new("r.md", "manual/r.md"),
    @mndocmove.Move::new("a.bin", "media/a.bin"),
  ])
  assert_eq(repair.moves(), [])
  let saved = @mndocmove.MovePlan::from_json_string(repair.to_json_string())
  let output = saved.replay(current)
  assert_eq(
    output.get("manual/r.md").unwrap().text(),
    "[asset](../media/a.bin)",
  )
  assert_eq(saved.restore(output).entries(), current.entries())
}
```

Verify physical renames against a previously reviewed baseline before repairing:

```mbt check
///|
test "adopt the exact physically renamed snapshot" {
  let baseline = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[asset](a.bin)"),
    @mndocmove.Entry::new("a.bin", b"A"),
  ])
  let pending = @mndocmove.plan_moves(baseline, [
    @mndocmove.Move::new("r.md", "manual/r.md"),
  ])
  let physical = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("manual/r.md", "[asset](a.bin)"),
    @mndocmove.Entry::new("a.bin", b"A"),
  ])
  assert_true(pending.check_renamed(physical).is_match())
  let adopted = pending.adopt(physical)
  assert_eq(adopted.moves(), [])
  let loaded = @mndocmove.MovePlan::from_json_string(adopted.to_json_string())
  assert_eq(
    loaded.replay(physical).entries(),
    pending.replay(baseline).entries(),
  )
  assert_eq(
    loaded.restore(loaded.replay(physical)).entries(),
    physical.entries(),
  )
}
```

Find failing documents together before generating a migration:

```mbt check
///|
test "preflight continues across failing documents and recovers after fixes" {
  let broken = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("a.md", "[asset](a.bin)"),
    @mndocmove.Entry::markdown("b.md", "[asset](a.bin)"),
  ])
  let moves = [@mndocmove.Move::new("a.md", "manual/a.md")]
  let blocked = @mndocmove.audit_moves(broken, moves)
  assert_eq(blocked.diagnostics().length(), 2)
  assert_true(blocked.plan() is None)
  let files = broken.entries()
  files.push(@mndocmove.Entry::new("a.bin", b"A"))
  let fixed = @mndocmove.DocTree::new(files)
  let audit = @mndocmove.audit_moves(fixed, moves)
  assert_true(audit.is_ready())
  let plan = audit.plan().unwrap()
  assert_eq(
    plan.replay(fixed).get("manual/a.md").unwrap().text(),
    "[asset](../a.bin)",
  )
  assert_eq(plan.restore(plan.replay(fixed)).entries(), fixed.entries())
}
```

Replace an obsolete resource's references while retaining both resource files:

```mbt check
///|
test "retarget existing resources without removing the old file" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[asset](old.bin)"),
    @mndocmove.Entry::new("old.bin", b"OLD"),
    @mndocmove.Entry::new("new.bin", b"NEW"),
  ])
  let plan = @mndocmove.plan_retargets(tree, [
    @mndocmove.Move::new("old.bin", "new.bin"),
  ])
  let output = plan.replay(tree)
  assert_eq(output.get("r.md").unwrap().text(), "[asset](new.bin)")
  assert_eq(output.get("old.bin").unwrap().data(), b"OLD")
  assert_eq(plan.restore(output).entries(), tree.entries())
}
```

Keep leading-slash URLs rooted while relocating their target files:

```mbt check
///|
test "explicit root URL profile" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[asset](/a.bin)"),
    @mndocmove.Entry::new("a.bin", b"A"),
  ])
  let plan = @mndocmove.plan_moves(
    tree,
    [@mndocmove.Move::new("a.bin", "media/a.bin")],
    profile=CommonMarkRoot,
  )
  assert_eq(
    plan.replay(tree).get("r.md").unwrap().text(),
    "[asset](/media/a.bin)",
  )
  assert_eq(plan.restore(plan.replay(tree)).entries(), tree.entries())
}
```

Export a migration preflight for SARIF viewers:

```mbt check
///|
test "emit SARIF without exposing a partial migration plan" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[asset](missing.bin)"),
  ])
  let audit = @mndocmove.audit_moves(tree, [
    @mndocmove.Move::new("r.md", "manual/r.md"),
  ])
  let report = audit.to_sarif_string(root_prefix="docs")
  assert_true(report.contains("\"version\":\"2.1.0\""))
  assert_true(report.contains("\"uri\":\"docs/r.md\""))
  assert_true(audit.plan() is None)
}
```

Find the source destinations that reference a resource before changing it:

```mbt check
///|
test "find exact incoming source destinations" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[asset](a.bin#part)"),
    @mndocmove.Entry::new("a.bin", b"A"),
  ])
  let refs = tree.incoming("a.bin").references()
  assert_eq(refs.length(), 1)
  assert_eq(refs[0].raw, "a.bin#part")
  assert_eq(refs[0].fragment, Some("part"))
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

Plan the next stage against the preceding result without exporting it:

```mbt check
///|
test "chain a document move and a later resource move" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[asset](a.bin)\r\n"),
    @mndocmove.Entry::new("a.bin", b"\xFF"),
  ])
  let first = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("r.md", "manual/r.md"),
  ])
  let chain = first.then_moves([@mndocmove.Move::new("a.bin", "images/a.bin")])
  let saved = @mndocmove.MoveChain::from_json_string(chain.to_json_string())
  let output = saved.replay(tree)
  assert_eq(
    output.get("manual/r.md").unwrap().text(),
    "[asset](../images/a.bin)\r\n",
  )
  assert_eq(saved.restore(output).entries(), tree.entries())
}
```
