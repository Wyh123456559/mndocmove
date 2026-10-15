///|
fn review_plan(
  source : String,
) -> (@mndocmove.MovePlan, @mndocmove.DocTree) raise {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("README.md", source),
    @mndocmove.Entry::new("a.png", b"\xFF\x00"),
  ])
  (
    @mndocmove.plan_moves(tree, [@mndocmove.Move::new("a.png", "assets/b.png")]),
    tree,
  )
}

///|
test "review shows context plus complete asset move inventory" {
  let (plan, _) = review_plan("Heading\n[logo](a.png)\nAfter\n")
  assert_eq(
    plan.review(context=1),
    "mndocmove review v1\nReview only; replay the saved plan to migrate the complete tree.\nFiles: 2; URL edits: 1\nmove \"a.png\" -> \"assets/b.png\" [opaque asset]\n\n--- \"README.md\"\n+++ \"README.md\"\n@@ -1,3 +1,3 @@\n Heading\n-[logo](a.png)\n+[logo](assets/b.png)\n After\n",
  )
}

///|
test "same-line edits coalesce and nearby changed lines share a hunk" {
  let (p, _) = review_plan("[x](a.png) ![y](a.png)\nunchanged\n[z](a.png)\n")
  let review = p.review(context=1)
  assert_eq(review.split("@@ -").count(), 2)
  assert_true(
    review.contains(
      "-[x](a.png) ![y](a.png)\n+[x](assets/b.png) ![y](assets/b.png)\n unchanged\n-[z](a.png)\n+[z](assets/b.png)\n",
    ),
  )
}

///|
test "zero context separates distinct changed lines" {
  let (p, _) = review_plan("[x](a.png)\nunchanged\n[z](a.png)\n")
  let review = p.review(context=0)
  assert_true(review.contains("@@ -1,1 +1,1 @@\n"))
  assert_true(review.contains("@@ -3,1 +3,1 @@\n"))
  assert_true(!review.contains(" unchanged"))
}

///|
test "CRLF emoji and missing final newline are visible without changing the plan" {
  let (p, tree) = review_plan("😀 Header\r\n[x](a.png)")
  let wire = p.to_json_string()
  assert_true(
    p
    .review()
    .contains(
      " 😀 Header\r\n-[x](a.png)\n\\ No newline at end of file\n+[x](assets/b.png)\n\\ No newline at end of file\n",
    ),
  )
  assert_eq(p.to_json_string(), wire)
  assert_eq(
    p.replay(tree).get("README.md").unwrap().text(),
    "😀 Header\r\n[x](assets/b.png)",
  )
}

///|
test "review persists across plan reload and file rename manifests are explicit" {
  let tree = @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("a b.md", "[x](a.png)"),
    @mndocmove.Entry::new("a.png", b"\xFF"),
  ])
  let p = @mndocmove.plan_moves(tree, [
    @mndocmove.Move::new("a b.md", "docs/中文.md"),
  ])
  assert_true(
    p.review().contains("move \"a b.md\" -> \"docs/中文.md\" [Markdown]"),
  )
  assert_true(p.review().contains("--- \"a b.md\"\n+++ \"docs/中文.md\""))
  assert_eq(
    @mndocmove.MovePlan::from_json_string(p.to_json_string()).review(),
    p.review(),
  )
}

///|
test "invalid context and terminal controls refuse review but preserve JSON and replay" {
  let (p, _) = review_plan("[x](a.png)\n")
  expect_code(() => ignore(p.review(context=-1)), "InvalidContext")
  expect_code(() => ignore(p.review(context=21)), "InvalidContext")
  assert_true(p.review(context=20).contains("@@ -1,1 +1,1 @@"))
  for control in ["\u001B[31m", "\r", "\u0000", "\u007F", "\u009B"] {
    let (bad, tree) = review_plan(control + "[x](a.png)\n")
    expect_code(() => ignore(bad.review()), "UnreviewableText")
    assert_true(bad.preview().contains("assets/b.png"))
    assert_true(
      bad.replay(tree).get("README.md").unwrap().text().contains(control),
    )
  }
}

///|
fn decimal(text : StringView) -> Int32 {
  let mut n = 0
  for c in text.iter() {
    n = n * 10 + c.to_int() - 48
  }
  n
}

///|
fn test_lines(text : String) -> Array[String] {
  let result = []
  let mut start = 0
  for i in 0..<text.length() {
    if text[i] == 10 {
      result.push(text[start:i + 1].to_owned())
      start = i + 1
    }
  }
  if start < text.length() {
    result.push(text[start:].to_owned())
  }
  result
}

///|
// Independently consume the public hunk grammar. Check counts, source evidence,
// unchanged gaps and exact reconstructed output, rather than internal ranges.
fn apply_review(report : String, original : String) -> String raise {
  let source = test_lines(original)
  let rows = report.split("\n").to_array()
  let out = StringBuilder()
  let mut old_pos = 0
  let mut new_pos = 0
  let mut i = 0
  while i < rows.length() {
    if !rows[i].has_prefix("@@ ") {
      i += 1
      continue
    }
    let fields = rows[i].split(" ").to_array()
    let old_range = fields[1][1:].split(",").to_array()
    let new_range = fields[2][1:].split(",").to_array()
    let old_start = decimal(old_range[0]) - 1
    while old_pos < old_start {
      out.write_string(source[old_pos])
      old_pos += 1
      new_pos += 1
    }
    assert_eq(new_pos, decimal(new_range[0]) - 1)
    let mut old_left = decimal(old_range[1])
    let mut new_left = decimal(new_range[1])
    i += 1
    while old_left > 0 || new_left > 0 {
      let row = rows[i]
      let unterminated = i + 1 < rows.length() &&
        rows[i + 1] == "\\ No newline at end of file"
      let text = row[1:].to_owned() + (if unterminated { "" } else { "\n" })
      if row[0] == 32 || row[0] == 45 {
        assert_eq(source[old_pos], text)
        old_pos += 1
        old_left -= 1
      }
      if row[0] == 32 || row[0] == 43 {
        out.write_string(text)
        new_pos += 1
        new_left -= 1
      }
      assert_true(old_left >= 0 && new_left >= 0)
      i += if unterminated { 2 } else { 1 }
    }
  }
  while old_pos < source.length() {
    out.write_string(source[old_pos])
    old_pos += 1
  }
  out.to_string()
}

///|
test "generated review hunks reconstruct replay output across sparse dense and repeated lines" {
  for stride in [1, 2, 3, 7, 25] {
    for final_newline in [true, false] {
      let lines = Array::makei(80, fn(i) {
        if i % stride == 0 {
          "[logo](a.png) ![same](a.png)"
        } else {
          "Repeated context"
        }
      })
      let source = lines.join("\n") + (if final_newline { "\n" } else { "" })
      let (p, tree) = review_plan(source)
      for context in [0, 1, 3, 20] {
        assert_eq(
          apply_review(p.review(context~), source),
          p.replay(tree).get("README.md").unwrap().text(),
        )
      }
    }
  }
}

///|
test "rename-only and empty plans need no text hunk and never decode opaque assets" {
  let unusual = @mndocmove.DocTree::new([
    @mndocmove.Entry::new("\u009B.png", b"A"),
  ])
  let quoted = @mndocmove.plan_moves(unusual, [
    @mndocmove.Move::new("\u009B.png", "b.png"),
  ]).review()
  assert_true(quoted.contains("move \"\\u009B.png\""))
  assert_true(!quoted.contains("\u009B"))
  let tree = @mndocmove.DocTree::new([@mndocmove.Entry::new("a.bin", b"\xFF")])
  let p = @mndocmove.plan_moves(tree, [@mndocmove.Move::new("a.bin", "b.bin")])
  assert_true(p.review().contains("[opaque asset]"))
  assert_true(!p.review().contains("@@"))
  assert_eq(
    @mndocmove.plan_moves(tree, []).review(),
    "mndocmove review v1\nReview only; replay the saved plan to migrate the complete tree.\nFiles: 1; URL edits: 0\n",
  )
}
