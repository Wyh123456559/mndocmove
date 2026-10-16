///|
fn srcset_tree(source : String) -> @mndocmove.DocTree raise {
  @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("README.md", source),
    @mndocmove.Entry::new("assets/a.png", b"\x89PNG\x00\xFF"),
    @mndocmove.Entry::new("assets/b.png", b"\x00\x80\xFF"),
    @mndocmove.Entry::new("assets/space name.png", b"space image"),
    @mndocmove.Entry::new("assets/中文.png", b"unicode image"),
  ])
}

///|
test "responsive implicit density comma layout and encoded filename separators are preserved" {
  for
    (value, expected) in [
      ("assets/a.png, \tassets/b.png 2x", "images/a.png, \timages/b.png 2x"),
      (
        "assets/a.png 1x ,\n assets/b.png 2x", "images/a.png 1x ,\n images/b.png 2x",
      ),
      (
        "assets/a%2Cb.png 1x, assets/𐀠.png 2x", "images/a%2Cb.png 1x, images/%F0%90%80%A0.png 2x",
      ),
    ] {
    let source = "<source srcset='" + value + "'>"
    let entries = srcset_tree(source).entries()
    entries.push(@mndocmove.Entry::new("assets/a,b.png", b"comma"))
    entries.push(@mndocmove.Entry::new("assets/𐀠.png", b"astral"))
    let tree = @mndocmove.DocTree::new(entries)
    let plan = @mndocmove.plan_moves(
      tree,
      [@mndocmove.Move::new("assets", "images")],
      profile=StaticHtml,
    )
    let output = plan.replay(tree)
    assert_eq(plan.edits().length(), 2)
    assert_eq(
      output.get("README.md").unwrap().text(),
      "<source srcset='" + expected + "'>",
    )
    assert_eq(plan.restore(output).entries(), tree.entries())
  }
}

///|
fn srcset_diagnostic(source : String) -> @mndocmove.Diagnostic raise {
  let tree = srcset_tree(source)
  try {
    ignore(
      @mndocmove.plan_moves(
        tree,
        [@mndocmove.Move::new("assets", "images")],
        profile=StaticHtml,
      ),
    )
    abort("Expected responsive image refusal")
  } catch {
    @mndocmove.Refused(diagnostic) => diagnostic
  }
}

///|
test "responsive source and img candidates relocate with fallback and descriptor layout intact" {
  let source = "<picture>\n  <source media='(prefers-color-scheme: dark)' type='image/png' srcset='assets/a.png 1x,\tassets/b.png 02.500000x'>\n  <img src=\"assets/a.png\" srcset=\"assets/a.png 01.000x, assets/b.png 3x\" alt='Keep' />\n</picture>\n"
  let original = srcset_tree(source)
  let plan = @mndocmove.plan_moves(
    original,
    [
      @mndocmove.Move::new("README.md", "manual/README.md"),
      @mndocmove.Move::new("assets", "images"),
    ],
    profile=StaticHtml,
  )
  let migrated = plan.replay(original)
  assert_eq(plan.edits().length(), 5)
  assert_eq(
    migrated.get("manual/README.md").unwrap().text(),
    source.replace_all(old="assets/", new="../images/"),
  )
  assert_eq(migrated.get("images/a.png").unwrap().data(), b"\x89PNG\x00\xFF")
  assert_eq(migrated.get("images/b.png").unwrap().data(), b"\x00\x80\xFF")
  assert_eq(original.get("README.md").unwrap().text(), source)
}

///|
test "responsive spans preserve BOM emoji CRLF multiline separators mixed Markdown and literal examples" {
  let source = "\uFEFF# 😀 Images\r\n\r\n<picture>\r\n  <source srcset=\"assets/a.png 1x,\r\n    assets/b.png 2x\">\r\n  <img src='assets/a.png' alt='😀'>\r\n</picture>\r\n\r\n[Markdown](assets/a.png)\r\n\r\n<!-- <source srcset='missing.png 1x'> -->\r\n\r\n`<img srcset='missing.png 1x'>`\r\n\r\n```html\r\n<source srcset='missing.png 1x'>\r\n```"
  let original = srcset_tree(source)
  let plan = @mndocmove.plan_moves(
    original,
    [@mndocmove.Move::new("assets", "images")],
    profile=StaticHtml,
  )
  assert_eq(plan.edits().length(), 4)
  for edit in plan.edits() {
    assert_eq(source[edit.start:edit.end].to_owned(), edit.before)
  }
  assert_eq(
    plan.replay(original).get("README.md").unwrap().text(),
    source.replace_all(old="assets/", new="images/"),
  )
}

///|
test "responsive candidate query entities quotes and external URLs keep decoded semantics" {
  let source = "<picture><source srcset='assets/&#97;.png?x=&#39;q&#39;&amp;y=2#part 1x, assets/b.png?x=&quot;q&quot;&amp;y=3#part 2x, https://example.com/image.png?x=1&amp;y=2 3x'><img src='assets/a.png'></picture>"
  let original = srcset_tree(source)
  let plan = @mndocmove.plan_moves(
    original,
    [@mndocmove.Move::new("assets", "images")],
    profile=StaticHtml,
  )
  assert_eq(plan.edits().length(), 3)
  assert_eq(
    plan.replay(original).get("README.md").unwrap().text(),
    "<picture><source srcset='images/a.png?x=&#39;q&#39;&amp;y=2#part 1x, images/b.png?x=&quot;q&quot;&amp;y=3#part 2x, https://example.com/image.png?x=1&amp;y=2 3x'><img src='images/a.png'></picture>",
  )
}

///|
test "responsive image directories percent paths and decimal densities retain exact nonURL spelling" {
  let source = "<picture><source srcset='assets/space%20name.png 000000001.500000x, assets/%E4%B8%AD%E6%96%87.png 0.000001x'><img src='assets/space%20name.png'></picture>"
  let original = srcset_tree(source)
  let plan = @mndocmove.plan_moves(
    original,
    [
      @mndocmove.Move::new("README.md", "guides/start/README.md"),
      @mndocmove.Move::new("assets", "media/资源"),
    ],
    profile=StaticHtml,
  )
  let migrated = plan.replay(original)
  assert_eq(
    migrated.get("guides/start/README.md").unwrap().text(),
    source.replace_all(old="assets/", new="../../media/%E8%B5%84%E6%BA%90/"),
  )
  assert_eq(
    migrated.get("media/资源/space name.png").unwrap().data(),
    b"space image",
  )
  assert_eq(
    migrated.get("media/资源/中文.png").unwrap().data(),
    b"unicode image",
  )
}

///|
test "responsive plans round trip deterministically review and restore exact original source" {
  let source = "<picture>\n<source srcset='assets/&#97;.png 1.00x, assets/b.png 2x'>\n<img src='assets/a.png'>\n</picture>\n"
  let original = srcset_tree(source)
  let moves = [@mndocmove.Move::new("assets", "images")]
  let plan = @mndocmove.plan_moves(original, moves, profile=StaticHtml)
  let wire = plan.to_json_string()
  let loaded = @mndocmove.MovePlan::from_json_string(wire)
  assert_eq(loaded.to_json_string(), wire)
  assert_eq(loaded.preview(), plan.preview())
  assert_eq(loaded.review(context=1), plan.review(context=1))
  assert_true(loaded.review().contains("URL edits: 3"))
  assert_true(loaded.review().contains("images/a.png 1.00x, images/b.png 2x"))
  assert_eq(
    @mndocmove.plan_moves(original, moves, profile=StaticHtml).to_json_string(),
    wire,
  )
  let migrated = loaded.replay(original)
  assert_true(loaded.restore(migrated).entries() == original.entries())
  assert_eq(loaded.restore(migrated).get("README.md").unwrap().text(), source)
  let later = @mndocmove.DocTree::new(
    migrated
    .entries()
    .map(fn(entry) {
      if entry.path() == "images/a.png" {
        @mndocmove.Entry::new(entry.path(), b"later image edit")
      } else {
        entry
      }
    }),
  )
  expect_code(() => ignore(loaded.restore(later)), "RestoreMismatch")
  assert_true(loaded.restore(migrated).entries() == original.entries())
}

///|
test "responsive HTML remains opt in and missing or escaping candidates refuse the whole plan" {
  let source = "<picture><source srcset='assets/a.png'><img src='assets/a.png'></picture>"
  let original = srcset_tree(source)
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_moves(original, [
          @mndocmove.Move::new("assets", "images"),
        ]),
      )
    },
    "UnsupportedMarkdown",
  )
  assert_eq(
    @mndocmove.plan_moves(original, [], profile=StaticHtml)
    .replay(original)
    .get("README.md")
    .unwrap()
    .text(),
    source,
  )
  for
    (url, code) in [
      ("missing.png", "MissingTarget"),
      ("../outside.png", "OutsideRoot"),
      ("/assets/a.png", "UnsupportedUrl"),
      ("assets/a%2F.png", "AmbiguousEscape"),
      ("assets/a%Q0.png", "InvalidEscape"),
    ] {
    let diagnostic = srcset_diagnostic(
      "<source srcset='assets/a.png 1x, " + url + " 2x'>",
    )
    assert_eq(diagnostic.code, code)
    assert_eq(diagnostic.path, "README.md")
  }
  assert_eq(
    @mndocmove.plan_moves(
      original,
      [@mndocmove.Move::new("assets", "images")],
      profile=StaticHtml,
    )
    .edits()
    .length(),
    2,
  )
}

///|
test "responsive malformed candidate grammars return positioned diagnostics and do not poison later plans" {
  for
    value in [
      "", " ", ", assets/a.png 1x", "assets/a.png 1x,", "assets/a.png 1x, ", "assets/a.png 1x,, assets/b.png 2x",
      "assets/a.png 1x,assets/b.png 2x", "assets/a.png 0x", "assets/a.png 0.000000x",
      "assets/a.png -1x", "assets/a.png +1x", "assets/a.png .5x", "assets/a.png 1.x",
      "assets/a.png 1e2x", "assets/a.png 1X", "assets/a.png 1000000000x", "assets/a.png 0.0000001x",
      "assets/a.png 1x 2x", "assets/a.png 0w", "assets/a.png 1h", "assets/a.png 1x, assets/b.png 01.000000x",
      "assets/a.png, assets/b.png 1x", "assets/a.png 1.500x, assets/b.png 01.5x",
      "assets/a,b.png 1x", "assets/a&#44;b.png 1x", "assets/a&#32;b.png 1x", "assets/a&Tab;b.png 1x",
      "assets/a.png&#32;1x", "assets/a.png 1&#120;", "data:image/png;base64, AAAA 1x",
      "DATA:image/png;base64,AAAA 1x",
    ] {
    let source = "😀 <source srcset=\"" + value + "\">"
    let diagnostic = srcset_diagnostic(source)
    assert_eq(diagnostic.code, "UnsupportedHtml")
    assert_eq(diagnostic.path, "README.md")
    assert_true(diagnostic.offset >= 3 && diagnostic.offset < source.length())
    assert_true(!diagnostic.message.is_empty())
    assert_eq(srcset_tree(source).get("README.md").unwrap().text(), source)
  }
  for
    source in [
      "<source srcset='assets/a.png' SRCSET='assets/b.png'>", "<source src='assets/a.png' srcset='assets/b.png'>",
      "<img srcset='assets/a.png 1x' sizes='100vw'>", "<source srcset='assets/a.png 1x' sizes='100vw'>",
      "<source srcset=assets/a.png>", "<a srcset='assets/a.png 1x'>Image</a>",
    ] {
    assert_eq(srcset_diagnostic(source).code, "UnsupportedHtml")
  }
  let valid = srcset_tree(
    "<source srcset='assets/a.png 000000001x, assets/b.png 999999999.999999x'>",
  )
  assert_eq(
    @mndocmove.plan_moves(
      valid,
      [@mndocmove.Move::new("assets", "images")],
      profile=StaticHtml,
    )
    .edits()
    .length(),
    2,
  )
}

///|
test "responsive candidate count accepts exactly 256 and refuses 257 without a partial result" {
  let value = StringBuilder()
  for i in 0..<256 {
    if i > 0 {
      value.write_string(", ")
    }
    value.write_string("assets/a.png " + (i + 1).to_string() + "x")
  }
  let source = "<img srcset='" + value.to_string() + "'>"
  let original = srcset_tree(source)
  let plan = @mndocmove.plan_moves(
    original,
    [@mndocmove.Move::new("assets", "images")],
    profile=StaticHtml,
  )
  assert_eq(plan.edits().length(), 256)
  assert_eq(
    plan.replay(original).get("README.md").unwrap().text(),
    source.replace_all(old="assets/", new="images/"),
  )
  let oversized = "<img srcset='" + value.to_string() + ", assets/a.png 257x'>"
  assert_eq(srcset_diagnostic(oversized).code, "UnsupportedHtml")
  assert_eq(plan.edits().length(), 256)
  assert_eq(original.get("README.md").unwrap().text(), source)
}
