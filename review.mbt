///|
priv struct ReviewLine {
  first : Int32
  text : String
}

///|
priv struct LineChange {
  old_first : Int32
  old_end : Int32
  new_first : Int32
  new_end : Int32
}

///|
priv struct ReviewOp {
  prefix : String
  text : String
  old_before : Int32
  new_before : Int32
}

///|
fn review_lines(
  text : String,
  path : String,
) -> Array[ReviewLine] raise MoveError {
  let lines = []
  let mut first = 0
  for i in 0..<text.length() {
    let c = text[i]
    if (c < 32 && c != 9 && c != 10 && c != 13) ||
      (c >= 127 && c <= 159) ||
      (c == 13 && (i + 1 == text.length() || text[i + 1] != 10)) {
      refuse(
        "UnreviewableText",
        path,
        "Review text contains terminal controls or bare CR; use the escaped JSON preview instead",
        offset=i,
      )
    }
    if c == 10 {
      lines.push({ first, text: text[first:i + 1].to_owned(), })
      first = i + 1
    }
  }
  if first < text.length() {
    lines.push({ first, text: text[first:].to_owned(), })
  }
  lines
}

///|
fn line_at(lines : Array[ReviewLine], offset : Int32) -> Int32 {
  let mut low = 0
  let mut high = lines.length()
  while low < high {
    let mid = low + (high - low) / 2
    if lines[mid].first <= offset {
      low = mid + 1
    } else {
      high = mid
    }
  }
  (low - 1).max(0)
}

///|
// Derive changed lines from the verified source edits, without a quadratic
// generic text diff. Repeated equal lines cannot confuse their identity.
fn review_ops(
  before : Array[ReviewLine],
  after : Array[ReviewLine],
  edits : Array[Edit],
  path : String,
) -> Array[ReviewOp] raise MoveError {
  let changes : Array[LineChange] = []
  let mut delta = 0
  for edit in edits {
    let next_start = edit.start + delta
    let change = LineChange::{
      old_first: line_at(before, edit.start),
      old_end: line_at(before, edit.end - 1) + 1,
      new_first: line_at(after, next_start),
      new_end: line_at(after, next_start + edit.after.length() - 1) + 1,
    }
    if !changes.is_empty() &&
      change.old_first <= changes.last().unwrap().old_end {
      let previous = changes.pop().unwrap()
      changes.push({
        old_first: previous.old_first,
        old_end: previous.old_end.max(change.old_end),
        new_first: previous.new_first,
        new_end: previous.new_end.max(change.new_end),
      })
    } else {
      changes.push(change)
    }
    delta += edit.after.length() - (edit.end - edit.start)
  }
  let ops = []
  let mut old_pos = 0
  let mut new_pos = 0
  for change in changes {
    while old_pos < change.old_first {
      if new_pos >= after.length() ||
        before[old_pos].text != after[new_pos].text {
        refuse(
          "ReviewInvariant", path, "Unchanged review lines differ from the snapshot",
        )
      }
      ops.push({
        prefix: " ",
        text: before[old_pos].text,
        old_before: old_pos,
        new_before: new_pos,
      })
      old_pos += 1
      new_pos += 1
    }
    for i in old_pos..<change.old_end {
      ops.push({
        prefix: "-",
        text: before[i].text,
        old_before: i,
        new_before: new_pos,
      })
    }
    old_pos = change.old_end
    for i in new_pos..<change.new_end {
      ops.push({
        prefix: "+",
        text: after[i].text,
        old_before: old_pos,
        new_before: i,
      })
    }
    new_pos = change.new_end
  }
  while old_pos < before.length() {
    if new_pos >= after.length() || before[old_pos].text != after[new_pos].text {
      refuse(
        "ReviewInvariant", path, "Unchanged review lines differ from the snapshot",
      )
    }
    ops.push({
      prefix: " ",
      text: before[old_pos].text,
      old_before: old_pos,
      new_before: new_pos,
    })
    old_pos += 1
    new_pos += 1
  }
  if new_pos != after.length() {
    refuse("ReviewInvariant", path, "Unexpected extra output lines")
  }
  ops
}

///|
fn write_hunks(
  out : StringBuilder,
  ops : Array[ReviewOp],
  old_length : Int32,
  new_length : Int32,
  context : Int32,
) -> Unit {
  let hunks : Array[(Int32, Int32)] = []
  for i in 0..<ops.length() {
    if ops[i].prefix == " " {
      continue
    }
    let start = (i - context).max(0)
    let end = (i + context + 1).min(ops.length())
    if !hunks.is_empty() && start <= hunks.last().unwrap().1 {
      let (first, previous_end) = hunks.pop().unwrap()
      hunks.push((first, previous_end.max(end)))
    } else {
      hunks.push((start, end))
    }
  }
  for (start, end) in hunks {
    let old_before = ops[start].old_before
    let new_before = ops[start].new_before
    let old_count = (if end == ops.length() {
        old_length
      } else {
        ops[end].old_before
      }) -
      old_before
    let new_count = (if end == ops.length() {
        new_length
      } else {
        ops[end].new_before
      }) -
      new_before
    let old_start = old_before + (if old_count == 0 { 0 } else { 1 })
    let new_start = new_before + (if new_count == 0 { 0 } else { 1 })
    out.write_string(
      "@@ -" +
      old_start.to_string() +
      "," +
      old_count.to_string() +
      " +" +
      new_start.to_string() +
      "," +
      new_count.to_string() +
      " @@\n",
    )
    for i in start..<end {
      let op = ops[i]
      out.write_string(op.prefix + op.text)
      if !op.text.has_suffix("\n") {
        out.write_string("\n\\ No newline at end of file\n")
      }
    }
  }
}

///|
fn review_path(path : String) -> String {
  let out = StringBuilder()
  for c in Json(path).stringify().iter() {
    let n = c.to_int()
    if n >= 127 && n <= 159 {
      out.write_string("\\u00" + hex_digit(n / 16) + hex_digit(n % 16))
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// Human-readable, deterministic review of all file moves and Markdown edits.
/// Context is 0..=20. Hunk bodies retain CRLF and missing-final-newline markers.
/// This report includes opaque-asset moves as a manifest, not a runnable patch;
/// use replay for the complete migration. Controls/bare CR refuse text review.
pub fn MovePlan::review(
  self : MovePlan,
  context~ : Int32 = 3,
) -> String raise MoveError {
  if context < 0 || context > 20 {
    refuse(
      "InvalidContext", "", "Review context must be between 0 and 20 lines",
    )
  }
  let out = StringBuilder()
  out.write_string(
    "mndocmove review v1\nReview only; replay the saved plan to migrate the complete tree.\n",
  )
  out.write_string(
    "Files: " +
    self.original.files.length().to_string() +
    "; URL edits: " +
    self.edits.length().to_string() +
    "\n",
  )
  if self.adopted_from is Some(_) {
    out.write_string(
      "Verified move adoption: input paths and every byte match the saved baseline after physical renames.\n",
    )
  }
  if !self.anchors.is_empty() {
    out.write_string(
      "Anchor reference retargeting; every file remains at its original path.\n",
    )
    for a in self.anchors {
      out.write_string(
        "retarget-anchor " +
        review_path(a.source) +
        " " +
        review_path(a.fragment) +
        " -> " +
        review_path(a.destination) +
        " " +
        review_path(a.replacement) +
        "\n",
      )
    }
  }
  if !self.retargets.is_empty() {
    out.write_string(
      "Reference retargeting; every file remains at its original path.\n",
    )
    for change in self.retargets {
      out.write_string(
        "retarget " +
        review_path(change.source) +
        " -> " +
        review_path(change.destination) +
        "\n",
      )
    }
  }
  if !self.relinks.is_empty() {
    out.write_string(
      "Link-only repair; historical renames below are already present. Replay keeps current paths.\n",
    )
    for change in self.relinks {
      out.write_string(
        "already-renamed " +
        review_path(change.source) +
        " -> " +
        review_path(change.destination) +
        "\n",
      )
    }
  }
  for file in self.original.files {
    let next = moved(file.path, self.moves)
    if next != file.path {
      out.write_string(
        "move " +
        review_path(file.path) +
        " -> " +
        review_path(next) +
        (if is_markdown(file.path) {
          " [Markdown]\n"
        } else {
          " [opaque asset]\n"
        }),
      )
    }
  }
  let grouped : Map[String, Array[Edit]] = Map([])
  for edit in self.edits {
    match grouped.get(edit.path) {
      Some(items) => items.push(edit)
      None => grouped[edit.path] = [edit]
    }
  }
  for file in self.original.files {
    guard grouped.get(file.path) is Some(edits) else { continue }
    let next_path = moved(file.path, self.moves)
    let next = self.result.get(next_path).unwrap()
    let before = review_lines(file.text(), file.path)
    let after = review_lines(next.text(), next_path)
    let ops = review_ops(before, after, edits, file.path)
    out.write_string(
      "\n--- " +
      review_path(file.path) +
      "\n+++ " +
      review_path(next_path) +
      "\n",
    )
    write_hunks(out, ops, before.length(), after.length(), context)
  }
  out.to_string()
}
