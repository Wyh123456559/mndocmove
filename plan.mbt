///|
/// Plans simultaneous moves against the original inventory. Text is locally
/// patched, never rendered/serialized as Markdown. Raw HTML and extensions
/// are refused in this profile. Empty moves preserve all bytes without parsing.
pub fn plan_moves(
  tree : DocTree,
  requested : Array[Move],
) -> MovePlan raise MoveError {
  let moves = requested.copy()
  if moves.length() > 4096 {
    refuse("PlanLimit", "", "Use at most 4096 moves")
  }
  moves.sort_by(fn(a, b) { a.source.compare(b.source) })
  for i = 0; i < moves.length(); i = i + 1 {
    let change = moves[i]
    validate_path(change.source)
    validate_path(change.destination)
    if change.source == change.destination {
      refuse("IdentityMove", change.source, "Omit identity moves")
    }
    if !tree.files.any(fn(file) { under(file.path, change.source) }) {
      refuse("MissingSource", change.source, "Move source does not exist")
    }
    for j = 0; j < i; j = j + 1 {
      if under(change.source, moves[j].source) ||
        under(moves[j].source, change.source) {
        refuse(
          "OverlappingMoves",
          change.source,
          "Parent/child or duplicate source mappings are ambiguous",
        )
      }
    }
  }
  // Validate every output path before parsing or rewriting any source.
  let projected = tree.files.map(fn(file) {
    Entry::new(moved(file.path, moves), file.data)
  })
  ignore(DocTree::new(projected))
  if moves.is_empty() {
    return {
      original: tree,
      moves,
      edits: [],
      result: { files: tree.files.copy(), },
    }
  }
  let output : Array[Entry] = []
  let edits : Array[Edit] = []
  for file in tree.files {
    if is_markdown(file.path) {
      let (next, changes) = rewrite(file, tree, moves)
      output.push(next)
      edits.append(changes)
    } else {
      output.push(Entry::new(moved(file.path, moves), file.data))
    }
  }
  { original: tree, moves, edits, result: DocTree::new(output), }
}

///|
/// Deterministic derived preview. Preserve the full plan for replay.
pub fn MovePlan::preview(self : MovePlan) -> String {
  let moves : Array[Json] = self.moves.map(fn(change) {
    [Json(change.source), Json(change.destination)]
  })
  let edits : Array[Json] = self.edits.map(fn(e) {
    [
      Json(e.path),
      Json(e.start),
      Json(e.end),
      Json(e.before),
      Json(e.after),
      Json(e.old_target),
      Json(e.new_target),
    ]
  })
  let value : Json = [
    "mndocmove-preview",
    1,
    Json::array(moves),
    Json::array(edits),
  ]
  value.stringify()
}
