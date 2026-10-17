///|
// Shared structural gate: content checks must never continue past an ambiguous
// move map, an output collision or a Markdown/opaque classification change.
fn validated_moves(
  tree : DocTree,
  requested : Array[Move],
) -> Array[Move] raise MoveError {
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
  for i = 0; i < tree.files.length(); i = i + 1 {
    if is_markdown(tree.files[i].path) != is_markdown(projected[i].path) {
      refuse(
        "FileKindChange",
        tree.files[i].path,
        "Keep Markdown files as .md and opaque assets as non-Markdown; content conversion needs a separate workflow",
      )
    }
  }
  moves
}

///|
/// Plans simultaneous moves against the original inventory. Text is locally
/// patched, never rendered/serialized as Markdown. CommonMark is the default;
/// static HTML requires opt-in. Empty moves preserve bytes without parsing.
pub fn plan_moves(
  tree : DocTree,
  requested : Array[Move],
  profile~ : Profile = CommonMark,
) -> MovePlan raise MoveError {
  let moves = validated_moves(tree, requested)
  if moves.is_empty() {
    return {
      original: tree,
      profile,
      moves,
      relinks: [],
      retargets: [],
      adopted_from: None,
      edits: [],
      result: { files: tree.files.copy(), },
    }
  }
  let output : Array[Entry] = []
  let edits : Array[Edit] = []
  for file in tree.files {
    if is_markdown(file.path) {
      let (next, changes) = rewrite(file, tree, moves, profile)
      output.push(next)
      edits.append(changes)
    } else {
      output.push(Entry::new(moved(file.path, moves), file.data))
    }
  }
  {
    original: tree,
    profile,
    moves,
    relinks: [],
    retargets: [],
    adopted_from: None,
    edits,
    result: DocTree::new(output),
  }
}

///|
/// Deterministic derived preview. Preserve the full plan for replay.
pub fn MovePlan::preview(self : MovePlan) -> String {
  let moves : Array[Json] = self
    .wire_intentions()
    .map(fn(change) { [Json(change.source), Json(change.destination)] })
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
    Json(
      if !self.retargets.is_empty() {
        "mndocmove-retarget-preview"
      } else if self.adopted_from is Some(_) {
        "mndocmove-adopt-preview"
      } else if self.relinks.is_empty() {
        "mndocmove-preview"
      } else {
        "mndocmove-relink-preview"
      },
    ),
    1,
    Json::array(moves),
    Json::array(edits),
  ]
  value.stringify()
}
