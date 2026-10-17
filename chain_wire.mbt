///|
/// Original bytes occur only in the first plan; later stages store profiles
/// and move pairs. Loading recomputes all stage edits and intermediate trees.
pub fn MoveChain::to_json_string(self : MoveChain) -> String raise MoveError {
  self.encode_with_limit(200000000L)
}

///|
fn profile_name(profile : Profile) -> String {
  match profile {
    CommonMark => "commonmark"
    StaticHtml => "static-html"
    CommonMarkRoot => "commonmark-root"
    StaticHtmlRoot => "static-html-root"
  }
}

///|
fn json_string_units(text : String) -> Int64 {
  Json(text).stringify().length().to_int64()
}

///|
fn moves_wire_units(moves : Array[Move]) -> Int64 {
  let mut units = 2L
  for i, change in moves {
    if i > 0 {
      units += 1
    }
    units += 3 +
      json_string_units(change.source) +
      json_string_units(change.destination)
  }
  units
}

///|
// Count the exact wire size before allocating hexadecimal snapshot strings.
// Json measures each small path's escaping; array punctuation is counted here.
fn MoveChain::wire_units(self : MoveChain) -> Int64 {
  let first = self.plans[0]
  let mut files = 2L
  for i, file in first.wire_input().files {
    if i > 0 {
      files += 1
    }
    files += json_string_units(file.path) +
      2L * file.data.length().to_int64() +
      5
  }
  let first_units = 6L +
    json_string_units(first.wire_magic()) +
    1 +
    json_string_units(profile_name(first.profile)) +
    files +
    moves_wire_units(first.wire_intentions())
  let mut steps = 2L
  for i in 1..<self.plans.length() {
    if i > 1 {
      steps += 1
    }
    let plan = self.plans[i]
    steps += 3 +
      json_string_units(profile_name(plan.profile)) +
      moves_wire_units(plan.moves)
  }
  5L + json_string_units("mndocmove-chain") + 1 + first_units + steps
}

///|
fn MoveChain::encode_with_limit(
  self : MoveChain,
  max_units : Int64,
) -> String raise MoveError {
  if self.wire_units() > max_units {
    refuse(
      "PlanLimit", "", "Chain exceeds the 200000000-unit wire limit; use fewer stages or a smaller documentation root",
    )
  }
  let steps : Array[Json] = []
  for i in 1..<self.plans.length() {
    let plan = self.plans[i]
    let profile = profile_name(plan.profile)
    let moves : Array[Json] = plan.moves.map(fn(change) {
      [Json(change.source), Json(change.destination)]
    })
    steps.push([Json(profile), Json::array(moves)])
  }
  let value : Json = [
    "mndocmove-chain",
    1,
    self.plans[0].wire_json(),
    Json::array(steps),
  ]
  value.stringify()
}

///|
/// Accepts chain version 1 or an existing single-plan version 1 as one stage.
/// Re-encoding always produces the canonical chain envelope. Objects, unknown
/// profiles, extra tuple fields, nesting/size excesses and invalid stages fail.
pub fn MoveChain::from_json_string(text : String) -> MoveChain raise MoveError {
  match parse_wire(text) {
    [String("mndocmove-chain"), Number(1, ..), first, Array(steps)] => {
      if steps.length() >= 8 {
        refuse("ChainLimit", "", "Use at most eight ordered migration stages")
      }
      let mut chain = chain_start(decode_plan(first))
      for step in steps {
        match step {
          [String(profile), moves] =>
            chain = chain.then_moves(
              decode_moves(moves),
              profile=wire_profile(profile),
            )
          _ =>
            refuse(
              "InvalidPlan", "", "Each additional stage must be exactly [profile, move_pairs]",
            )
        }
      }
      chain
    }
    value => chain_start(decode_plan(value))
  }
}
