///|
// Derive the physical intermediate tree from a pending plan's exact baseline.
// Ownership is known per original file, even when destination prefixes overlap.
fn MovePlan::renamed_input(self : MovePlan) -> DocTree raise MoveError {
  if !self.relinks.is_empty() ||
    !self.retargets.is_empty() ||
    self.adopted_from is Some(_) {
    refuse(
      "AdoptPlanKind", "", "Use the original pending move plan; repair/adopted plans already describe current paths",
    )
  }
  DocTree::new(
    self.original.files.map(fn(file) {
      Entry::new(moved(file.path, self.moves), file.data)
    }),
  )
}

///|
/// Compare every path and byte after ONLY the pending physical renames. The
/// report's Source side denotes the expected input to the adopted repair, not
/// the pending plan's pre-move source. No Markdown is parsed from current input.
/// Repair/adopted plans are refused with AdoptPlanKind; chains are not flattened.
pub fn MovePlan::check_renamed(
  self : MovePlan,
  current : DocTree,
) -> SnapshotReport raise MoveError {
  check_snapshot(self.renamed_input(), current, Source)
}

///|
// Caller has already verified the complete physical snapshot. Offsets still
// refer to unchanged old bytes, now at current paths. Never recompute intent
// from current text, which might otherwise hide an accidental concurrent edit.
fn MovePlan::adopt_verified(self : MovePlan, current : DocTree) -> MovePlan {
  if self.moves.is_empty() {
    return self
  }
  let edits = self.edits.map(fn(edit) {
    { ..edit, path: moved(edit.path, self.moves), }
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
    profile: self.profile,
    moves: [],
    relinks: self.moves,
    retargets: [],
    adopted_from: Some(self.original),
    edits,
    result: self.result,
  }
}

///|
/// Accept already-performed renames only when the complete current inventory
/// equals the original pending plan with paths moved and bytes unchanged.
/// Returns a link-only plan: replay keeps current paths; restore returns exact
/// pre-adoption bytes/current paths. Baseline ownership permits directory merges.
/// On mismatch, nothing is changed: inspect check_renamed for all differences.
pub fn MovePlan::adopt(
  self : MovePlan,
  current : DocTree,
) -> MovePlan raise MoveError {
  let report = self.check_renamed(current)
  if !report.is_match() {
    let path = match report.changes[0] {
      Added(path, _) | Removed(path, _) | Modified(path, _, _) => path
    }
    refuse(
      "AdoptionMismatch", path, "Current files must equal the saved baseline after only its physical renames; inspect check_renamed / check-renamed for every difference and restore unintended edits before retrying",
    )
  }
  self.adopt_verified(current)
}
