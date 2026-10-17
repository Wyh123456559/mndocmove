///|
test "incoming inventories exact raw destination spans including definitions and fragments" {
  let source = "\uFEFF😀 [inline](assets/a%20b.bin?q=1&amp;x=2#part%2Fone) [ref][a]\r\n\r\n[a]: assets/a%20b.bin#other \"Keep\"\r\n`[code](assets/a%20b.bin)`"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", source),
    @mndocmove.Entry::new("assets/a b.bin", b"\xFF\x00"),
  ])
  let report = tree.incoming("assets/a b.bin")
  let refs = report.references()
  assert_eq(refs.length(), 2)
  assert_eq(refs[0].fragment, Some("part/one"))
  assert_eq(refs[1].fragment, Some("other"))
  for r in refs {
    assert_eq(r.path, "r.md")
    assert_eq(r.target, "assets/a b.bin")
    assert_eq(source[r.start:r.end].to_owned(), r.raw)
  }
  assert_eq(refs[0].raw, "assets/a%20b.bin?q=1&amp;x=2#part%2Fone")
  assert_eq(refs[0].url, "assets/a%20b.bin?q=1&x=2#part%2Fone")
  refs.clear()
  assert_eq(report.references().length(), 2)
  assert_eq(tree.incoming("assets").references(), [])
  assert_eq(
    tree.incoming("assets", recursive=true).references(),
    report.references(),
  )
  expect_code(
    () => ignore(@mndocmove.MovePlan::from_json_string(report.to_json_string())),
    "InvalidPlan",
  )
}

///|
test "incoming resolves same document empty query and fragment only destinations" {
  let source = "[a](#intro) [b](?q=1#intro) [c](#) [d]() [e](?q=2)"
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("docs/r.md", source),
  ])
  let refs = tree.incoming("docs/r.md").references()
  assert_eq(refs.length(), 5)
  assert_eq(refs.map(fn(r) { r.fragment }), [
    Some("intro"),
    Some("intro"),
    Some(""),
    None,
    None,
  ])
  for r in refs {
    assert_eq(source[r.start:r.end].to_owned(), r.raw)
  }
}

///|
test "incoming root selectors distinguish directory references and descendants without URL inference" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown(
      "r.md", "[root](.) [dir](docs/) [file](docs/a.md#x) [ext](//host/docs/a.md)",
    ),
    @mndocmove.Entry::markdown("docs/a.md", "[root](..)"),
  ])
  assert_eq(tree.incoming(".").references().length(), 2)
  assert_eq(tree.incoming("docs").references().length(), 1)
  assert_eq(tree.incoming("docs", recursive=true).references().length(), 2)
  assert_eq(tree.incoming("", recursive=true).references().length(), 4)
  assert_eq(
    tree.incoming(".").to_json_string(),
    tree.incoming("").to_json_string(),
  )
  let empty = @mndocmove.DocTree::new([]).incoming(".")
  assert_eq(
    empty.to_json_string(),
    "[\"mndocmove-incoming\",1,\"commonmark\",\"\",false,[]]",
  )
}

///|
test "incoming static rooted media uses the same explicit profiles and URI source spans" {
  let text = "\uFEFF😀\r\n\r\n<video src='/assets/clip.webm' poster='/assets/poster.svg' controls></video>"
  let tree = media_tree(text)
  expect_code(() => ignore(tree.incoming("assets")), "UnsupportedMarkdown")
  expect_code(
    () => ignore(tree.incoming("assets", profile=StaticHtml)),
    "UnsupportedUrl",
  )
  let report = tree.incoming("assets", recursive=true, profile=StaticHtmlRoot)
  assert_eq(report.references().length(), 2)
  for r in report.references() {
    assert_eq(text[r.start:r.end].to_owned(), r.raw)
  }
  assert_true(report.to_json_string().contains("static-html-root"))
}

///|
test "incoming refuses incomplete unsafe or malformed input before exposing partial rows and recovers" {
  let valid = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[x](a.bin)"),
    @mndocmove.Entry::new("a.bin", b"A"),
  ])
  expect_code(() => ignore(valid.incoming("missing")), "MissingReferenceTarget")
  expect_code(() => ignore(valid.incoming("../a.bin")), "InvalidPath")
  for
    (text, code) in [
      ("[x](a.bin) [y](missing.bin)", "MissingTarget"),
      ("[x](a.bin#%FF)", "InvalidFragment"),
      ("[x](a.bin#%0A)", "InvalidFragment"),
      ("[x](a.bin#%ZZ)", "InvalidFragment"),
      ("[x](a.bin/)", "InvalidDirectoryTarget"),
      ("[x](../a.bin)", "OutsideRoot"),
      ("[x](a.bin) [[wiki]]", "UnsupportedMarkdown"),
    ] {
    let tree = @mndocmove.DocTree::new([
      @mndocmove.Entry::markdown("r.md", text),
      @mndocmove.Entry::new("a.bin", b"A"),
    ])
    expect_code(() => ignore(tree.incoming("a.bin")), code)
  }
  let invalid = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("r.md", b"\xFF"),
    @mndocmove.Entry::new("a.bin", b"A"),
  ])
  expect_code(() => ignore(invalid.incoming("a.bin")), "InvalidUtf8")
  assert_eq(valid.incoming("a.bin").references().length(), 1)
  for size in [4096, 4097] {
    let tree = @mndocmove.DocTree::new([
      @mndocmove.Entry::markdown("r.md", "[x](#" + "a".repeat(size) + ")"),
    ])
    if size == 4096 {
      assert_eq(
        tree.incoming("r.md").references()[0].fragment,
        Some("a".repeat(size)),
      )
    } else {
      expect_code(() => ignore(tree.incoming("r.md")), "InvalidFragment")
    }
  }
}

///|
test "incoming budgets count excluded local spans and refuse rather than truncate" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("r.md", "[a](a.bin) [b](b.bin)"),
    @mndocmove.Entry::new("a.bin", b"A"),
    @mndocmove.Entry::new("b.bin", b"B"),
  ])
  assert_eq(tree.incoming("a.bin", max_references=2).references().length(), 1)
  expect_code(
    () => ignore(tree.incoming("a.bin", max_references=1)),
    "ReferenceLimit",
  )
  expect_code(
    () => ignore(tree.incoming("a.bin", max_references=0)),
    "ReferenceLimit",
  )
  expect_code(
    () => ignore(tree.incoming("a.bin", max_references=65537)),
    "ReferenceLimit",
  )
  let files = tree.entries()
  files.sort_by(fn(a, b) { b.path().compare(a.path()) })
  assert_eq(
    @mndocmove.DocTree::new(files).incoming("a.bin").to_json_string(),
    tree.incoming("a.bin").to_json_string(),
  )
  assert_eq(tree.get("r.md").unwrap().text(), "[a](a.bin) [b](b.bin)")
}
