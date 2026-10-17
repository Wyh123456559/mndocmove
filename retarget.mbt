///|
/// Repoints references between existing files without moving or deleting ANY
/// file. Pairs are simultaneous one-hop substitutions, not chained redirects.
/// Directories are refused: ownership and fragment semantics are not inferred.
/// All Markdown is checked/reparsed using the ordinary source-span invariants.
pub fn plan_retargets(
  tree : DocTree,
  requested : Array[Move],
  profile~ : Profile = CommonMark,
) -> MovePlan raise MoveError {
  if requested.length() > 4096 {
    refuse("PlanLimit", "", "Use at most 4096 reference substitutions")
  }
  if requested.is_empty() {
    return plan_moves(tree, [], profile~)
  }
  let targets = requested.copy()
  targets.sort_by(fn(a, b) { a.source.compare(b.source) })
  for i, change in targets {
    validate_path(change.source)
    validate_path(change.destination)
    if change.source == change.destination {
      refuse(
        "IdentityMove",
        change.source,
        "Omit identity reference substitutions",
      )
    }
    if i > 0 && targets[i - 1].source == change.source {
      refuse(
        "RetargetConflict",
        change.source,
        "Declare exactly one replacement per source file",
      )
    }
    if tree.get(change.source) is None {
      refuse(
        "MissingRetargetSource",
        change.source,
        "Reference source must be an existing file; directories and absent files are unsupported",
      )
    }
    if tree.get(change.destination) is None {
      refuse(
        "MissingRetargetTarget",
        change.destination,
        "Replacement must be an existing file in the complete tree; directories and absent files are unsupported",
      )
    }
  }
  let output = []
  let edits = []
  for file in tree.files {
    if is_markdown(file.path) {
      let (next, changes) = rewrite(file, tree, [], profile, targets~)
      output.push(next)
      edits.append(changes)
    } else {
      output.push(file)
    }
  }
  {
    original: tree,
    profile,
    moves: [],
    relinks: [],
    retargets: targets,
    adopted_from: None,
    edits,
    result: DocTree::new(output),
  }
}
