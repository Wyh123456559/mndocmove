///|
fn hex_bytes(data : Bytes) -> String {
  let out = StringBuilder()
  for byte in data {
    out.write_string(
      hex_digit(byte.to_int() / 16) + hex_digit(byte.to_int() % 16),
    )
  }
  out.to_string()
}

///|
fn parse_hex(text : String) -> Bytes raise MoveError {
  if text.length() % 2 != 0 {
    refuse(
      "InvalidPlan", "", "Byte strings require pairs of hexadecimal digits",
    )
  }
  let bytes : Array[Byte] = []
  for i = 0; i < text.length(); i = i + 2 {
    let a = unhex(text[i])
    let b = unhex(text[i + 1])
    if a < 0 || b < 0 {
      refuse("InvalidPlan", "", "Invalid hexadecimal byte string")
    }
    bytes.push((a * 16 + b).to_byte())
  }
  Bytes::from_array(bytes)
}

///|
fn parse_wire(text : String) -> Json raise MoveError {
  if text.length() > 200000000 {
    refuse("PlanLimit", "", "Plan exceeds wire size limit")
  }
  let mut depth = 0
  let mut quoted = false
  let mut escaped = false
  for c in text.iter() {
    if quoted {
      if escaped {
        escaped = false
      } else if c == '\\' {
        escaped = true
      } else if c == '"' {
        quoted = false
      }
    } else {
      match c {
        '"' => quoted = true
        '[' => {
          depth += 1
          if depth > 16 {
            refuse("PlanLimit", "", "JSON nesting exceeds 16")
          }
        }
        ']' => depth -= 1
        '{' | '}' =>
          refuse(
            "InvalidPlan", "", "Only array-based wire data is accepted; objects are unsupported",
          )
        _ => ()
      }
    }
  }
  @json.parse(text) catch {
    _ => {
      refuse(
        "InvalidPlan", "", "Expected valid versioned JSON arrays; see docs/wire.md",
      )
      null
    }
  }
}

///|
/// Strict array-of-pairs input: [["old/path", "new/path"], ...].
/// Objects are deliberately not accepted: no duplicate JSON fields can be lost.
pub fn moves_from_json(text : String) -> Array[Move] raise MoveError {
  decode_moves(parse_wire(text))
}

///|
fn decode_moves(value : Json) -> Array[Move] raise MoveError {
  match value {
    Array(items) => {
      if items.length() > 4096 {
        refuse("PlanLimit", "", "Use at most 4096 moves")
      }
      let result : Array[Move] = []
      for item in items {
        match item {
          [String(source), String(destination)] =>
            result.push(Move::new(source, destination))
          _ =>
            refuse(
              "InvalidPlan", "", "Each move must contain exactly two strings",
            )
        }
      }
      result
    }
    _ => {
      refuse("InvalidPlan", "", "Moves must be a JSON array of path pairs")
      []
    }
  }
}

///|
/// Serializes the complete original bytes and moves, never trusted edit offsets.
/// Array order and uppercase hex make output deterministic on all backends.
pub fn MovePlan::to_json_string(self : MovePlan) -> String {
  let files : Array[Json] = self.original.files.map(fn(e) {
    [Json(e.path), Json(hex_bytes(e.data))]
  })
  let moves : Array[Json] = self.moves.map(fn(m) {
    [Json(m.source), Json(m.destination)]
  })
  let value : Json = [
    "mndocmove",
    1,
    Json(
      match self.profile {
        CommonMark => "commonmark"
        StaticHtml => "static-html"
      },
    ),
    Json::array(files),
    Json::array(moves),
  ]
  value.stringify()
}

///|
/// Parses a bounded versioned plan and recomputes every edit from original bytes.
/// Unknown versions/profiles, extra elements and malformed bytes are refused.
pub fn MovePlan::from_json_string(text : String) -> MovePlan raise MoveError {
  match parse_wire(text) {
    [
      String("mndocmove"),
      Number(1, ..),
      String(profile_name),
      Array(files),
      moves,
    ] => {
      let profile = match profile_name {
        "commonmark" => CommonMark
        "static-html" => StaticHtml
        _ => {
          refuse("InvalidPlan", "", "Unknown syntax profile")
          abort("unreachable")
        }
      }
      if files.length() > 4096 {
        refuse("FileLimit", "", "Use at most 4096 files")
      }
      let entries : Array[Entry] = []
      for file in files {
        match file {
          [String(path), String(data)] =>
            entries.push(Entry::new(path, parse_hex(data)))
          _ =>
            refuse(
              "InvalidPlan", "", "Each file must be exactly [path, hexadecimal bytes]",
            )
        }
      }
      plan_moves(DocTree::new(entries), decode_moves(moves), profile~)
    }
    _ => {
      refuse(
        "InvalidPlan", "", "Unknown plan schema, version, profile or extra elements",
      )
      abort("unreachable")
    }
  }
}
