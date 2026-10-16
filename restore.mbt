///|
/// Restores exact original paths and bytes only when current equals the entire
/// planned result. This is snapshot restoration, not reverse URL rewriting or
/// a merge of post-migration edits. The saved plan already contains all original
/// bytes; no reverse move list or additional wire format is required.
///
/// Raises RestoreMismatch at the first differing path in sorted order. Keep
/// later edits separately before selecting an unmodified migrated snapshot.
pub fn MovePlan::restore(
  self : MovePlan,
  current : DocTree,
) -> DocTree raise MoveError {
  let expected = self.result.files
  let actual = current.files
  let guidance = "; preserve later edits separately and use an unmodified migrated snapshot. Restore does not merge changes"
  for i in 0..<actual.length().min(expected.length()) {
    let found = actual[i]
    let wanted = expected[i]
    if found.path < wanted.path {
      refuse("RestoreMismatch", found.path, "Unexpected file" + guidance)
    }
    if found.path > wanted.path {
      refuse("RestoreMismatch", wanted.path, "Missing file" + guidance)
    }
    if found.data != wanted.data {
      refuse("RestoreMismatch", found.path, "File bytes changed" + guidance)
    }
  }
  if actual.length() > expected.length() {
    refuse(
      "RestoreMismatch",
      actual[expected.length()].path,
      "Unexpected file" + guidance,
    )
  }
  if actual.length() < expected.length() {
    refuse(
      "RestoreMismatch",
      expected[actual.length()].path,
      "Missing file" + guidance,
    )
  }
  { files: self.original.files.copy(), }
}
