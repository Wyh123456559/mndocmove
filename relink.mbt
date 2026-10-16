///|
/// Repairs URLs after declared renames were already performed, with Markdown
/// bytes still using OLD coordinates. Reconstructs and validates a unique logical
/// old tree, then uses the normal source-span rewrite/reparse invariants. Replay
/// changes only text at CURRENT paths. Restore returns the exact pre-repair input,
/// including its current paths; it does not undo the historical physical renames.
pub fn plan_relinks(
  current : DocTree,
  renamed : Array[Move],
  profile~ : Profile = CommonMark,
) -> MovePlan raise MoveError {
  if renamed.is_empty() {
    return plan_moves(current, [], profile~)
  }
  if renamed.length() > 4096 {
    refuse("PlanLimit", "", "Use at most 4096 historical renames")
  }
  let declared = renamed.copy()
  declared.sort_by(fn(a, b) { a.source.compare(b.source) })
  for i, change in declared {
    validate_path(change.source)
    validate_path(change.destination)
    if change.source == change.destination {
      refuse("IdentityMove", change.source, "Omit identity renames")
    }
    if !current.files.any(fn(file) { under(file.path, change.destination) }) {
      refuse(
        "MissingRenamedTarget",
        change.destination,
        "Expected this already-renamed file or directory in the current tree; use plan_moves when files have not been moved",
      )
    }
    let destination = change.destination.to_lower()
    for j in 0..<i {
      let previous = declared[j].destination.to_lower()
      if under(destination, previous) || under(previous, destination) {
        refuse(
          "RelinkAmbiguity",
          change.destination,
          "Historical destination prefixes overlap; supply nonoverlapping prefixes or explicit individual file renames so the old namespace can be reconstructed uniquely",
        )
      }
    }
  }
  let inverse = declared.map(fn(change) {
    Move::new(change.destination, change.source)
  })
  let logical = DocTree::new(
    current.files.map(fn(file) {
      Entry::new(moved(file.path, inverse), file.data)
    }),
  ) catch {
    Refused(d) =>
      raise Refused({
        ..d,
        code: "RelinkAmbiguity",
        message: "Cannot reconstruct a unique old inventory; check that the declared renames were fully performed: " +
        d.message,
      })
  }
  let forward = plan_moves(logical, declared, profile~) catch {
    Refused(d) =>
      raise Refused({
        ..d,
        path: if logical.get(d.path) is Some(_) {
          moved(d.path, declared)
        } else {
          d.path
        },
        message: "Relink validation in declared old coordinates: " + d.message,
      })
  }
  for i, file in current.files {
    if forward.result.files[i].path != file.path {
      refuse(
        "RelinkAmbiguity",
        file.path,
        "Historical renames do not reconstruct the complete current inventory; provide the full simultaneous old-to-current mapping",
      )
    }
  }
  let edits = forward.edits.map(fn(edit) {
    { ..edit, path: moved(edit.path, forward.moves), }
  })
  edits.sort_by(fn(a, b) {
    if a.path == b.path {
      a.start - b.start
    } else {
      a.path.compare(b.path)
    }
  })
  {
    original: current,
    profile,
    moves: [],
    relinks: forward.moves,
    adopted_from: None,
    edits,
    result: forward.result,
  }
}
