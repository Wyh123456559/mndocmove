///|
/// Immutable migration preflight. A complete plan exists only when every file
/// passed; failed audits retain diagnostics, never a partial result or edits.
struct MoveAudit {
  profile : Profile
  files : Int32
  checked : Int32
  problems : Array[Diagnostic]
  ready : MovePlan?
} derive(@debug.Debug)

///|
pub fn MoveAudit::is_ready(self : MoveAudit) -> Bool {
  self.ready is Some(_)
}

///|
/// First planner refusal per failing Markdown file, in inventory shortlex
/// order. Offsets/codes/messages have exactly the ordinary planner semantics.
pub fn MoveAudit::diagnostics(self : MoveAudit) -> Array[Diagnostic] {
  self.problems.copy()
}

///|
/// The complete ordinary pending plan, or None when any file refused. Replay
/// still verifies the full original snapshot. No partial plan can be retrieved.
pub fn MoveAudit::plan(self : MoveAudit) -> MovePlan? {
  self.ready
}

///|
/// Deterministic report-only JSON; not an executable plan and no source bytes.
/// ["mndocmove-audit",1,status,profile,file_count,checked_markdown_count,issues].
/// Each issue is [code,path,UTF16_offset,message]. No-op moves check zero files.
pub fn MoveAudit::to_json_string(self : MoveAudit) -> String {
  let issues : Array[Json] = self.problems.map(fn(d) {
    [Json(d.code), Json(d.path), Json(d.offset), Json(d.message)]
  })
  let value : Json = [
    "mndocmove-audit",
    1,
    Json(if self.is_ready() { "ready" } else { "blocked" }),
    Json(profile_name(self.profile)),
    Json(self.files),
    Json(self.checked),
    Json::array(issues),
  ]
  value.stringify()
}

///|
/// Preflight proposed simultaneous moves across the complete snapshot. Raises
/// structural/path/map/output-limit failures just like plan_moves. Otherwise
/// continues after each document's first content refusal, checking later files
/// against the SAME original tree/map. All Markdown is checked for nonempty
/// moves, including unmoved documents with incoming links. Empty moves preserve
/// bytes without parsing. A ready audit yields the complete ordinary plan.
pub fn audit_moves(
  tree : DocTree,
  requested : Array[Move],
  profile~ : Profile = CommonMark,
) -> MoveAudit raise MoveError {
  let moves = validated_moves(tree, requested)
  if moves.is_empty() {
    return {
      profile,
      files: tree.files.length(),
      checked: 0,
      problems: [],
      ready: Some(plan_moves(tree, [], profile~)),
    }
  }
  let output : Array[Entry] = []
  let edits : Array[Edit] = []
  let problems : Array[Diagnostic] = []
  let mut checked = 0
  for file in tree.files {
    if is_markdown(file.path) {
      checked += 1
      try {
        let (next, changes) = rewrite(file, tree, moves, profile)
        output.push(next)
        edits.append(changes)
      } catch {
        Refused(d) => problems.push(d)
      }
    } else {
      output.push(Entry::new(moved(file.path, moves), file.data))
    }
  }
  // Discard successful rewrites if ANY document failed. Failed bytes are never
  // skipped into an export, and no plans with an incomplete inventory escape.
  let ready = if problems.is_empty() {
    Some({
      original: tree,
      profile,
      moves,
      relinks: [],
      adopted_from: None,
      edits,
      result: DocTree::new(output),
    })
  } else {
    None
  }
  { profile, files: tree.files.length(), checked, problems, ready, }
}

///|
pub extend MoveAudit with @debug.Debug::{to_repr}
