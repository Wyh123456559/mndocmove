///|
fn sarif_field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap()
    _ => abort("Expected JSON object")
  }
}

///|
fn sarif_items(value : Json) -> Array[Json] {
  match value {
    Array(items) => items
    _ => abort("Expected JSON array")
  }
}

///|
fn sarif_run(text : String) -> Json raise {
  sarif_items(sarif_field(@json.parse(text), "runs"))[0]
}

///|
test "SARIF retains every audit diagnostic and encodes repository relative artifact URIs" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("汉😀 #%.md", "[x](missing%7B0%7D.bin)"),
    @mndocmove.Entry::new("bad.md", b"\xFF"),
    @mndocmove.Entry::new("a.bin", b"A"),
  ])
  let audit = @mndocmove.audit_moves(tree, [
    @mndocmove.Move::new("a.bin", "b.bin"),
  ])
  let text = audit.to_sarif_string(root_prefix="doc space")
  let log = @json.parse(text)
  assert_eq(sarif_field(log, "version"), Json("2.1.0"))
  let run = sarif_run(text)
  assert_eq(sarif_field(run, "columnKind"), Json("utf16CodeUnits"))
  let results = sarif_items(sarif_field(run, "results"))
  let issues = audit.diagnostics()
  assert_eq(results.length(), issues.length())
  let rules = sarif_items(
    sarif_field(sarif_field(sarif_field(run, "tool"), "driver"), "rules"),
  )
  assert_eq(rules.length(), 2)
  for i, result in results {
    let d = issues[i]
    assert_eq(sarif_field(result, "ruleId"), Json(d.code))
    assert_eq(sarif_field(result, "level"), Json("error"))
    let message = sarif_field(result, "message")
    assert_eq(sarif_field(message, "text"), Json("{0}"))
    assert_eq(sarif_items(sarif_field(message, "arguments")), [Json(d.message)])
    assert_eq(
      sarif_field(sarif_field(result, "properties"), "sourcePath"),
      Json(d.path),
    )
    assert_eq(
      sarif_field(sarif_field(result, "properties"), "utf16Offset"),
      Json(d.offset),
    )
    let physical = sarif_field(
      sarif_items(sarif_field(result, "locations"))[0],
      "physicalLocation",
    )
    assert_eq(
      sarif_field(sarif_field(physical, "artifactLocation"), "uriBaseId"),
      Json("SRCROOT"),
    )
    if d.path == "bad.md" {
      assert_eq(
        sarif_field(sarif_field(physical, "artifactLocation"), "uri"),
        Json("doc%20space/bad.md"),
      )
      assert_true(physical is Object(fields) && !fields.contains("region"))
    } else {
      assert_eq(
        sarif_field(sarif_field(physical, "artifactLocation"), "uri"),
        Json("doc%20space/%E6%B1%89%F0%9F%98%80%20%23%25.md"),
      )
      assert_true(d.message.contains("{0}"))
    }
    let index = match sarif_field(result, "ruleIndex") {
      Number(n, ..) => n.to_int()
      _ => abort("Expected rule index")
    }
    assert_eq(sarif_field(rules[index], "id"), Json(d.code))
  }
  assert_true(!text.contains("[x]"))
  assert_true(!text.contains("file:///"))
  expect_code(
    () => ignore(@mndocmove.MovePlan::from_json_string(text)),
    "InvalidPlan",
  )
  assert_true(audit.plan() is None)
}

///|
test "SARIF position conversion ignores BOM and counts CRLF tabs and astral characters exactly" {
  for
    (prefix, line, column) in [
      ("\uFEFF", 1, 5),
      ("\uFEFF😀 ", 1, 8),
      ("\uFEFF# H\r\n\t😀 ", 2, 9),
      ("a\rb\n", 3, 5),
    ] {
    let tree = @mndocmove.DocTree::new([
      @mndocmove.Entry::markdown("r.md", prefix + "[x](missing.bin)"),
      @mndocmove.Entry::new("a.bin", b"A"),
    ])
    let audit = @mndocmove.audit_moves(tree, [
      @mndocmove.Move::new("a.bin", "b.bin"),
    ])
    let result = sarif_items(
        sarif_field(sarif_run(audit.to_sarif_string()), "results"),
      )[0]
    let physical = sarif_field(
      sarif_items(sarif_field(result, "locations"))[0],
      "physicalLocation",
    )
    let region = sarif_field(physical, "region")
    assert_eq(sarif_field(region, "startLine"), Json(line))
    assert_eq(sarif_field(region, "startColumn"), Json(column))
    assert_eq(sarif_field(region, "endColumn"), Json(column))
  }
}

///|
test "SARIF is deterministic after reordering inputs and retains the exact audited snapshot" {
  let entries = [
    @mndocmove.Entry::markdown("a.md", "[x](missing.bin)"),
    @mndocmove.Entry::markdown("b.md", "[[wiki]]"),
    @mndocmove.Entry::new("a.bin", b"A"),
  ]
  let tree = @mndocmove.DocTree::new(entries)
  let moves = [@mndocmove.Move::new("a.bin", "b.bin")]
  let audit = @mndocmove.audit_moves(tree, moves)
  let expected = audit.to_sarif_string()
  entries.clear()
  moves.clear()
  let issues = audit.diagnostics()
  issues.clear()
  let reversed = tree.entries()
  reversed.sort_by(fn(a, b) { b.path().compare(a.path()) })
  let other = @mndocmove.audit_moves(@mndocmove.DocTree::new(reversed), [
    @mndocmove.Move::new("a.bin", "b.bin"),
  ])
  assert_eq(other.to_sarif_string(), expected)
  assert_eq(audit.to_sarif_string(root_prefix="."), expected)
  assert_eq(audit.to_json_string(), other.to_json_string())
  for invalid in ["/docs", "../docs", "docs/", "C:\\docs", "docs/../x"] {
    expect_code(
      () => ignore(audit.to_sarif_string(root_prefix=invalid)),
      "InvalidPath",
    )
  }
  assert_eq(audit.to_sarif_string(), expected)
}

///|
test "ready and no-op SARIF reports contain no errors and preserve readiness semantics" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("invalid.md", b"\xFF"),
  ])
  let no_op = @mndocmove.audit_moves(tree, [], profile=StaticHtmlRoot)
  let run = sarif_run(no_op.to_sarif_string())
  assert_eq(sarif_items(sarif_field(run, "results")), [])
  assert_eq(sarif_field(sarif_field(run, "properties"), "ready"), Json(true))
  assert_eq(
    sarif_field(sarif_field(run, "properties"), "checkedMarkdown"),
    Json(0),
  )
  assert_eq(
    sarif_field(sarif_field(run, "properties"), "profile"),
    Json("static-html-root"),
  )
  assert_eq(no_op.plan().unwrap().replay(tree).entries(), tree.entries())
  let empty = @mndocmove.audit_moves(@mndocmove.DocTree::new([]), [])
  assert_eq(
    sarif_items(sarif_field(sarif_run(empty.to_sarif_string()), "results")),
    [],
  )
}

///|
test "SARIF deduplicates rule metadata while retaining every maximal-inventory result" {
  let files = []
  for i in 0..<4096 {
    files.push(@mndocmove.Entry::new(i.to_string() + ".md", b"\xFF"))
  }
  let audit = @mndocmove.audit_moves(@mndocmove.DocTree::new(files), [
    @mndocmove.Move::new("0.md", "manual/0.md"),
  ])
  let run = sarif_run(audit.to_sarif_string(root_prefix="docs"))
  assert_eq(sarif_items(sarif_field(run, "results")).length(), 4096)
  let driver = sarif_field(sarif_field(run, "tool"), "driver")
  assert_eq(sarif_items(sarif_field(driver, "rules")).length(), 1)
  assert_true(audit.plan() is None)
}
