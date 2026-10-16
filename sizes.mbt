///|
fn sizes_trim(raw : String) -> String {
  let mut first = 0
  let mut end = raw.length()
  while first < end && html_space(raw[first]) {
    first += 1
  }
  while end > first && html_space(raw[end - 1]) {
    end -= 1
  }
  raw[first:end].to_owned()
}

///|
// A deliberately small CSS length grammar. No functions, escapes, URLs or
// browser recovery are interpreted. Accepted source text is never rewritten.
fn sizes_length(
  raw : String,
  media : Bool,
  path : String,
  offset : Int32,
) -> Unit raise MoveError {
  let value = sizes_trim(raw)
  if value == "0" {
    return
  }
  let mut end = 0
  let mut dot = -1
  while end < value.length() &&
        ((value[end] >= 48 && value[end] <= 57) || value[end] == 46) {
    if value[end] == 46 {
      if dot >= 0 {
        html_fail(path, offset + end, "Sizes lengths allow one decimal point")
      }
      dot = end
    }
    end += 1
  }
  let integer = if dot < 0 { end } else { dot }
  if integer < 1 ||
    integer > 9 ||
    (dot >= 0 && (end - dot - 1 < 1 || end - dot - 1 > 6)) {
    html_fail(
      path, offset, "Sizes lengths require 1-9 integer digits and optionally 1-6 fractional digits",
    )
  }
  let unit = value[end:].to_owned().to_lower()
  let units = if media {
    ["px", "em", "rem"]
  } else {
    ["px", "em", "rem", "vw", "vh", "vmin", "vmax"]
  }
  if !units.contains(unit) {
    html_fail(
      path,
      offset + end,
      "Unsupported sizes unit or expression; use static px/em/rem lengths or viewport lengths for source sizes",
    )
  }
}

///|
fn validate_sizes(
  raw : String,
  path : String,
  offset : Int32,
) -> Unit raise MoveError {
  if raw.length() > 4096 {
    html_fail(path, offset, "Use at most 4096 UTF-16 units in sizes")
  }
  for i in 0..<raw.length() {
    let c = raw[i]
    if (c < 32 && !html_space(c)) || (c >= 127 && c <= 159) {
      html_fail(path, offset + i, "Control characters in sizes are unsupported")
    }
  }
  let mut count = 0
  let mut start = 0
  for end in 0..<=raw.length() {
    if end != raw.length() && raw[end] != 44 {
      continue
    }
    count += 1
    if count > 32 {
      html_fail(path, offset + start, "Use at most 32 sizes entries")
    }
    let mut first = start
    while first < end && html_space(raw[first]) {
      first += 1
    }
    let item = sizes_trim(raw[first:end].to_owned())
    if item.is_empty() {
      html_fail(path, offset + first, "Sizes entries must not be empty")
    }
    if item.has_prefix("(") {
      let mut close = 1
      while close < item.length() && item[close] != 41 {
        close += 1
      }
      if close == item.length() ||
        close + 1 == item.length() ||
        !html_space(item[close + 1]) {
        html_fail(
          path,
          offset + first,
          "Use (min-width: LENGTH) SIZE or (max-width: LENGTH) SIZE",
        )
      }
      let condition = sizes_trim(item[1:close].to_owned()).to_lower()
      let mut colon = 0
      while colon < condition.length() && condition[colon] != 58 {
        colon += 1
      }
      let feature = sizes_trim(condition[:colon].to_owned())
      if colon == condition.length() ||
        (feature != "min-width" && feature != "max-width") {
        html_fail(
          path,
          offset + first,
          "Sizes conditions support only min-width and max-width",
        )
      }
      sizes_length(
        condition[colon + 1:].to_owned(),
        true,
        path,
        offset + first + 1 + colon + 1,
      )
      sizes_length(
        item[close + 1:].to_owned(),
        false,
        path,
        offset + first + close + 1,
      )
      if end == raw.length() {
        html_fail(
          path,
          offset + first,
          "End sizes with an unconditional fallback length",
        )
      }
    } else {
      sizes_length(item, false, path, offset + first)
      if end != raw.length() {
        html_fail(
          path,
          offset + first,
          "An unconditional sizes entry must be last",
        )
      }
    }
    start = end + 1
  }
}
