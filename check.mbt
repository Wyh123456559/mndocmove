///|
/// Which complete saved-plan snapshot should match the supplied tree.
pub(all) enum SnapshotSide {
  Source
  Result
} derive(Eq, @debug.Debug)

///|
/// Paths use the inventories' shortlex order (UTF-16 length, then code units).
/// Modified includes equal-length
/// byte changes; sizes describe the files without exposing their contents.
pub(all) enum SnapshotChange {
  Added(String, Int32)
  Removed(String, Int32)
  Modified(String, Int32, Int32)
} derive(Eq, @debug.Debug)

///|
struct SnapshotReport {
  side : SnapshotSide
  expected_files : Int32
  actual_files : Int32
  changes : Array[SnapshotChange]
} derive(@debug.Debug)

///|
pub fn SnapshotReport::is_match(self : SnapshotReport) -> Bool {
  self.changes.is_empty()
}

///|
pub fn SnapshotReport::changes(self : SnapshotReport) -> Array[SnapshotChange] {
  self.changes.copy()
}

///|
/// Deterministic report-only JSON. It is not an executable migration plan.
/// ["mndocmove-check",1,side,expected_count,actual_count,changes].
/// Added/removed rows carry one size; modified rows carry old/new sizes.
pub fn SnapshotReport::to_json_string(self : SnapshotReport) -> String {
  let changes : Array[Json] = self.changes.map(fn(change) {
    match change {
      Added(path, size) => [Json("added"), Json(path), Json(size)]
      Removed(path, size) => [Json("removed"), Json(path), Json(size)]
      Modified(path, before, after) =>
        [Json("modified"), Json(path), Json(before), Json(after)]
    }
  })
  let side = match self.side {
    Source => "source"
    Result => "result"
  }
  let value : Json = [
    Json("mndocmove-check"),
    Json(1),
    Json(side),
    Json(self.expected_files),
    Json(self.actual_files),
    Json::array(changes),
  ]
  value.stringify()
}

///|
// Merge sorted validated inventories. Every byte is compared; sizes/hashes
// are never used as a substitute for snapshot equality.
fn check_snapshot(
  expected : DocTree,
  current : DocTree,
  side : SnapshotSide,
) -> SnapshotReport {
  let changes = []
  for i = 0, j = 0; i < expected.files.length() || j < current.files.length(); {
    if i == expected.files.length() {
      let file = current.files[j]
      changes.push(Added(file.path, file.data.length()))
      continue i, j + 1
    }
    if j == current.files.length() {
      let file = expected.files[i]
      changes.push(Removed(file.path, file.data.length()))
      continue i + 1, j
    }
    let before = expected.files[i]
    let after = current.files[j]
    if before.path < after.path {
      changes.push(Removed(before.path, before.data.length()))
      continue i + 1, j
    }
    if before.path > after.path {
      changes.push(Added(after.path, after.data.length()))
      continue i, j + 1
    }
    if before.data != after.data {
      changes.push(
        Modified(before.path, before.data.length(), after.data.length()),
      )
    }
    continue i + 1, j + 1
  }
  {
    side,
    expected_files: expected.files.length(),
    actual_files: current.files.length(),
    changes,
  }
}

///|
/// Read-only full comparison against the original source (default) or planned
/// result. Reports all differences without consuming the plan or applying edits.
pub fn MovePlan::check(
  self : MovePlan,
  current : DocTree,
  side~ : SnapshotSide = Source,
) -> SnapshotReport {
  let expected = match side {
    Source => self.original
    Result => self.result
  }
  check_snapshot(expected, current, side)
}

///|
pub extend SnapshotSide with Eq::{equal, not_equal}

///|
pub extend SnapshotSide with @debug.Debug::{to_repr}

///|
pub extend SnapshotChange with Eq::{equal, not_equal}

///|
pub extend SnapshotChange with @debug.Debug::{to_repr}

///|
pub extend SnapshotReport with @debug.Debug::{to_repr}
