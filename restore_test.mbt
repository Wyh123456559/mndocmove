///|
fn restore_diagnostic(
  plan : @mndocmove.MovePlan,
  current : @mndocmove.DocTree,
) -> @mndocmove.Diagnostic {
  try {
    ignore(plan.restore(current))
    abort("Expected restoration refusal")
  } catch {
    @mndocmove.Refused(diagnostic) => diagnostic
  }
}

///|
test "CommonMark restoration recovers original bytes and URL spelling" {
  let source = "\uFEFF# 😀 Keep\r\n[asset](assets/%61.bin?x=1&amp;y=2#part)\r\nNo final newline"
  let original = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("README.md", source),
    @mndocmove.Entry::new("assets/a.bin", b"\x00\x80\xFF"),
  ])
  let plan = @mndocmove.plan_moves(original, [
    @mndocmove.Move::new("README.md", "manual/README.md"),
    @mndocmove.Move::new("assets", "payload"),
  ])
  let migrated = plan.replay(original)
  assert_eq(
    migrated.get("manual/README.md").unwrap().text(),
    source.replace(old="assets/%61.bin", new="../payload/a.bin"),
  )
  let restored = plan.restore(migrated)
  assert_true(restored.entries() == original.entries())
  assert_eq(restored.get("README.md").unwrap().text(), source)
  assert_eq(restored.get("assets/a.bin").unwrap().data(), b"\x00\x80\xFF")
  assert_true(plan.replay(restored).entries() == migrated.entries())
}

///|
test "static HTML restoration recovers entities quotes BOM and CRLF exactly" {
  let source = "\uFEFF😀 <a HREF='assets/%61.bin?x=&#39;q&#39;&amp;y=2#part' title=\"keep\">Asset</a>\r\n<img SRC=\"assets/%61.bin\" alt='keep' />"
  let original = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("README.md", source),
    @mndocmove.Entry::new("assets/a.bin", b"\xFF\x00\x80"),
  ])
  let plan = @mndocmove.plan_moves(
    original,
    [@mndocmove.Move::new("assets", "images")],
    profile=StaticHtml,
  )
  let migrated = plan.replay(original)
  assert_eq(
    migrated.get("README.md").unwrap().text(),
    "\uFEFF😀 <a HREF='images/a.bin?x=&#39;q&#39;&amp;y=2#part' title=\"keep\">Asset</a>\r\n<img SRC=\"images/a.bin\" alt='keep' />",
  )
  assert_true(plan.restore(migrated).entries() == original.entries())
  let loaded = @mndocmove.MovePlan::from_json_string(plan.to_json_string())
  assert_true(loaded.restore(migrated).entries() == original.entries())
}

///|
test "restoration refuses changed Markdown assets additions deletions and renames without consuming the plan" {
  let original = fixture()
  let plan = @mndocmove.plan_moves(original, [
    @mndocmove.Move::new("docs", "manual"),
    @mndocmove.Move::new("img", "media"),
  ])
  let migrated = plan.replay(original)
  let files = migrated.entries()
  let changed_markdown = files.map(fn(entry) {
    if entry.path() == "manual/guide.md" {
      @mndocmove.Entry::markdown(entry.path(), "post-migration edit")
    } else {
      entry
    }
  })
  let changed_asset = files.map(fn(entry) {
    if entry.path() == "media/a.png" {
      @mndocmove.Entry::new(entry.path(), b"changed")
    } else {
      entry
    }
  })
  let addition = files.copy()
  addition.push(@mndocmove.Entry::new("aaa.txt", b""))
  let deleted = files.filter(fn(entry) { entry.path() != "media/a.png" })
  let renamed = files.map(fn(entry) {
    if entry.path() == "media/a.png" {
      @mndocmove.Entry::new("renamed.png", entry.data())
    } else {
      entry
    }
  })
  for
    (entries, path) in [
      (changed_markdown, "manual/guide.md"),
      (changed_asset, "media/a.png"),
      (addition, "aaa.txt"),
      (deleted, "media/a.png"),
      (renamed, "media/a.png"),
    ] {
    let current = @mndocmove.DocTree::new(entries)
    let before = current.entries()
    let diagnostic = restore_diagnostic(plan, current)
    assert_eq(diagnostic.code, "RestoreMismatch")
    assert_eq(diagnostic.path, path)
    assert_true(diagnostic.message.contains("preserve"))
    assert_true(diagnostic.message.contains("merge"))
    assert_true(current.entries() == before)
    assert_true(plan.restore(migrated).entries() == original.entries())
  }
}

///|
test "saved plans restore simultaneous directory swaps without reverse rewriting" {
  let original = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "README.md", "[guide](a/x.md) [asset](b/%70.bin)\n",
    ),
    @mndocmove.Entry::markdown("a/x.md", "[asset](../b/%70.bin)"),
    @mndocmove.Entry::new("b/p.bin", b"\x00\xFF"),
  ])
  let plan = @mndocmove.plan_moves(original, [
    @mndocmove.Move::new("a", "b"),
    @mndocmove.Move::new("b", "a"),
  ])
  let migrated = plan.replay(original)
  assert_eq(
    migrated.get("README.md").unwrap().text(),
    "[guide](b/x.md) [asset](a/p.bin)\n",
  )
  assert_eq(migrated.get("a/p.bin").unwrap().data(), b"\x00\xFF")
  let encoded = plan.to_json_string()
  let loaded = @mndocmove.MovePlan::from_json_string(encoded)
  assert_true(loaded.restore(migrated).entries() == original.entries())
  assert_eq(loaded.to_json_string(), encoded)
  assert_true(loaded.replay(original).entries() == migrated.entries())
}

///|
test "empty plans restore opaque Markdown bytes and empty inventories" {
  let original = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("unparsed.md", b"\xFF\x00"),
    @mndocmove.Entry::new("zero.bin", b""),
  ])
  let plan = @mndocmove.plan_moves(original, [])
  assert_true(plan.restore(original).entries() == original.entries())
  let empty = @mndocmove.DocTree::new([])
  let empty_plan = @mndocmove.plan_moves(empty, [])
  assert_eq(empty_plan.restore(empty).entries().length(), 0)
  let diagnostic = restore_diagnostic(
    empty_plan,
    @mndocmove.DocTree::new([@mndocmove.Entry::new("extra.bin", b"")]),
  )
  assert_eq(diagnostic.code, "RestoreMismatch")
  assert_eq(diagnostic.path, "extra.bin")
  assert_eq(empty_plan.restore(empty).entries().length(), 0)
}

///|
test "restoration ignores inventory order and keeps returned arrays independent" {
  let original = fixture()
  let plan = @mndocmove.plan_moves(original, [
    @mndocmove.Move::new("docs", "manual"),
  ])
  let migrated = plan.replay(original)
  let files = migrated.entries()
  let reordered = @mndocmove.DocTree::new([files[2], files[0], files[1]])
  let restored = plan.restore(reordered)
  let exposed = restored.entries()
  exposed[0] = @mndocmove.Entry::new("replacement.bin", b"other")
  ignore(exposed.pop())
  files[0] = @mndocmove.Entry::new("replacement.bin", b"other")
  assert_true(restored.entries() == original.entries())
  assert_true(plan.restore(reordered).entries() == original.entries())
  assert_true(plan.replay(restored).entries() == migrated.entries())
}

///|
test "restoration reports the first differing path across both sorted inventories" {
  let original = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("b.bin", b""),
    @mndocmove.Entry::new("d.bin", b"D"),
  ])
  let plan = @mndocmove.plan_moves(original, [])
  for
    (entries, first_path) in [
      ([@mndocmove.Entry::new("c.bin", b"")], "b.bin"),
      ([@mndocmove.Entry::new("a.bin", b"")], "a.bin"),
      (
        [
          @mndocmove.Entry::new("b.bin", b"changed"),
          @mndocmove.Entry::new("c.bin", b""),
        ],
        "b.bin",
      ),
      ([], "b.bin"),
    ] {
    let diagnostic = restore_diagnostic(plan, @mndocmove.DocTree::new(entries))
    assert_eq(diagnostic.code, "RestoreMismatch")
    assert_eq(diagnostic.path, first_path)
  }
  assert_true(plan.restore(original).entries() == original.entries())
}
