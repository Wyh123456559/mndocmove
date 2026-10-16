///|
/// Combines parallel move intentions against one byte-identical source snapshot
/// and syntax profile. Identical intentions coalesce; conflicts refuse the whole
/// operation. All URL edits are recomputed together, never concatenated patches.
/// This is not a content merge or an ordered migration stage.
pub fn MovePlan::merge(
  self : MovePlan,
  other : MovePlan,
) -> MovePlan raise MoveError {
  if profile_name(self.profile) != profile_name(other.profile) {
    refuse(
      "MergeProfile", "", "Parallel plans must use the same syntax profile; regenerate one plan with the intended policy",
    )
  }
  let differences = check_snapshot(self.original, other.original, Source).changes
  if !differences.is_empty() {
    let path = match differences[0] {
      Added(path, _) | Removed(path, _) | Modified(path, _, _) => path
    }
    refuse(
      "MergeSnapshot", path, "Parallel plans must contain exactly the same source files and bytes; regenerate against one shared snapshot",
    )
  }
  let combined : Array[Move] = []
  for i = 0, j = 0; i < self.moves.length() || j < other.moves.length(); {
    if i == self.moves.length() {
      combined.push(other.moves[j])
      continue i, j + 1
    }
    if j == other.moves.length() {
      combined.push(self.moves[i])
      continue i + 1, j
    }
    let left = self.moves[i]
    let right = other.moves[j]
    if left.source < right.source {
      combined.push(left)
      continue i + 1, j
    }
    if left.source > right.source {
      combined.push(right)
      continue i, j + 1
    }
    if left.destination != right.destination {
      refuse(
        "MergeConflict",
        left.source,
        "The same source has different destinations: " +
        review_path(left.destination) +
        " and " +
        review_path(right.destination),
      )
    }
    combined.push(left)
    continue i + 1, j + 1
  }
  // The planner enforces union limits, prefix ambiguity, projected path/type
  // safety and reference invariants; neither individual result is trusted.
  plan_moves(self.original, combined, profile=self.profile) catch {
    Refused(d) =>
      raise Refused({ ..d, message: "Merged intentions refused: " + d.message, })
  }
}
