///|
/// Immutable ordered migration stages. Later moves name paths in the previous
/// stage's result. The original inventory is retained for one final export and
/// exact restoration. At most eight stages / 128 MiB logical snapshot bytes.
struct MoveChain {
  plans : Array[MovePlan]
  snapshot_bytes : Int32
} derive(@debug.Debug)

///|
fn tree_bytes(tree : DocTree) -> Int32 {
  let mut total = 0
  for file in tree.files {
    total += file.data.length()
  }
  total
}

///|
fn chain_start(first : MovePlan) -> MoveChain {
  {
    plans: [first],
    snapshot_bytes: tree_bytes(first.original) + tree_bytes(first.result),
  }
}

///|
/// Append a complete stage without writing an intermediate directory. Syntax
/// defaults to the preceding stage's profile; explicit overrides are validated.
pub fn MovePlan::then_moves(
  self : MovePlan,
  moves : Array[Move],
  profile? : Profile,
) -> MoveChain raise MoveError {
  chain_start(self).then_moves(moves, profile?)
}

///|
pub fn MoveChain::then_moves(
  self : MoveChain,
  moves : Array[Move],
  profile? : Profile,
) -> MoveChain raise MoveError {
  if self.plans.length() >= 8 {
    refuse("ChainLimit", "", "Use at most eight ordered migration stages")
  }
  let previous = self.plans.last().unwrap()
  let next = plan_moves(
    previous.result,
    moves,
    profile=profile.unwrap_or(previous.profile),
  ) catch {
    Refused(d) =>
      raise Refused({
        code: d.code,
        path: d.path,
        offset: d.offset,
        message: "Stage " +
        (self.plans.length() + 1).to_string() +
        ": " +
        d.message,
      })
  }
  let extra = tree_bytes(next.result)
  if self.snapshot_bytes > 134217728 - extra {
    refuse(
      "ChainLimit", "", "Original plus all stage results exceed 128 MiB logical snapshot bytes; use a smaller documentation root",
    )
  }
  let plans = self.plans.copy()
  plans.push(next)
  { plans, snapshot_bytes: self.snapshot_bytes + extra, }
}

///|
/// Independent array of immutable verified stage plans, including the first.
pub fn MoveChain::stages(self : MoveChain) -> Array[MovePlan] {
  self.plans.copy()
}

///|
/// Check only the original source or final projected snapshot, never an
/// intermediate snapshot. Intermediate evidence remains available in stages().
pub fn MoveChain::check(
  self : MoveChain,
  current : DocTree,
  side~ : SnapshotSide = Source,
) -> SnapshotReport {
  let expected = match side {
    Source => self.plans[0].original
    Result => self.plans.last().unwrap().result
  }
  check_snapshot(expected, current, side)
}

///|
pub fn MoveChain::replay(
  self : MoveChain,
  current : DocTree,
) -> DocTree raise MoveError {
  ignore(self.plans[0].replay(current))
  { files: self.plans.last().unwrap().result.files.copy(), }
}

///|
pub fn MoveChain::restore(
  self : MoveChain,
  current : DocTree,
) -> DocTree raise MoveError {
  ignore(self.plans.last().unwrap().restore(current))
  { files: self.plans[0].original.files.copy(), }
}

///|
/// Review each stage in execution order. Paths/hunks belong to that stage's
/// input, not a flattened patch against the original tree.
pub fn MoveChain::review(
  self : MoveChain,
  context~ : Int32 = 3,
) -> String raise MoveError {
  if self.plans.length() == 1 {
    return self.plans[0].review(context~)
  }
  let out = StringBuilder()
  out.write_string(
    "mndocmove chain review v1\nStages: " +
    self.plans.length().to_string() +
    "\n",
  )
  for i, plan in self.plans {
    out.write_string(
      "\n=== Stage " +
      (i + 1).to_string() +
      " of " +
      self.plans.length().to_string() +
      " ===\n",
    )
    out.write_string(plan.review(context~))
  }
  out.to_string()
}

///|
pub extend MoveChain with @debug.Debug::{to_repr}
