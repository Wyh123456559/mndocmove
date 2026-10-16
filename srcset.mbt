///|
// Decimal canonicalization keeps density equality exact across all backends.
// Bounds avoid browser overflow/underflow and never require Float parsing.
fn srcset_density(
  descriptor : String,
  path : String,
  offset : Int32,
) -> String raise MoveError {
  if descriptor.is_empty() {
    return "1"
  }
  if !descriptor.has_suffix("x") {
    html_fail(
      path, offset, "Srcset supports decimal x densities, not width or other descriptors",
    )
  }
  let number = descriptor[:descriptor.length() - 1].to_owned()
  let mut dot = -1
  for i in 0..<number.length() {
    if number[i] == 46 && dot < 0 {
      dot = i
    } else if number[i] < 48 || number[i] > 57 {
      html_fail(
        path,
        offset + i,
        "Use a positive decimal x density without signs or exponents",
      )
    }
  }
  let integer_end = if dot < 0 { number.length() } else { dot }
  let fraction_start = if dot < 0 { number.length() } else { dot + 1 }
  let fraction_size = number.length() - fraction_start
  if integer_end < 1 ||
    integer_end > 9 ||
    (dot >= 0 && (fraction_size < 1 || fraction_size > 6)) {
    html_fail(
      path, offset, "Srcset x densities need 1-9 integer digits and optionally 1-6 fractional digits",
    )
  }
  let mut first = 0
  while first + 1 < integer_end && number[first] == 48 {
    first += 1
  }
  let mut end = number.length()
  while end > fraction_start && number[end - 1] == 48 {
    end -= 1
  }
  let integer = number[first:integer_end].to_owned()
  let fraction = number[fraction_start:end].to_owned()
  if integer == "0" && fraction.is_empty() {
    html_fail(path, offset, "Srcset density must be greater than zero")
  }
  if fraction.is_empty() {
    integer
  } else {
    integer + "." + fraction
  }
}

///|
// Scan raw HTML so each URL retains its exact UTF-16 source span. Entities
// that could introduce a separator are refused after decoding that URL only.
// Descriptors, commas and whitespace never enter a replacement span.
fn srcset_destinations(
  raw : String,
  path : String,
  offset : Int32,
) -> (Array[Destination], Bool) raise MoveError {
  let result : Array[Destination] = []
  let densities : Set[String] = Set([])
  let mut width_mode : Bool? = None
  let mut i = 0
  while i < raw.length() && html_space(raw[i]) {
    i += 1
  }
  if i == raw.length() {
    html_fail(path, offset, "Srcset requires at least one image candidate")
  }
  while i < raw.length() {
    if result.length() >= 256 {
      html_fail(
        path,
        offset + i,
        "Use at most 256 candidates per srcset attribute",
      )
    }
    let start = i
    while i < raw.length() && !html_space(raw[i]) && raw[i] != 44 {
      i += 1
    }
    let end = i
    if end == start {
      html_fail(path, offset + i, "Empty srcset candidate")
    }
    let url = html_decode(raw[start:end].to_owned(), path, offset + start)
    if url.to_lower().has_prefix("data:") {
      html_fail(
        path,
        offset + start,
        "Data URLs in srcset are unsupported; use an inventory asset",
      )
    }
    for c in url.iter() {
      if c == ',' || (c.to_int() < 128 && html_space(c.to_int().to_uint16())) {
        html_fail(
          path,
          offset + start,
          "Srcset URL entities must not introduce commas or ASCII whitespace; use percent encoding for filename spaces",
        )
      }
    }
    while i < raw.length() && html_space(raw[i]) {
      i += 1
    }
    let descriptor_start = i
    while i < raw.length() && !html_space(raw[i]) && raw[i] != 44 {
      i += 1
    }
    let descriptor = raw[descriptor_start:i].to_owned()
    let width = descriptor.has_suffix("w")
    if width_mode is Some(previous) && previous != width {
      html_fail(
        path,
        offset + descriptor_start,
        "Do not mix w and x (including implicit 1x) srcset descriptors",
      )
    }
    width_mode = Some(width)
    let key = if width {
      srcset_width(descriptor, path, offset + descriptor_start)
    } else {
      srcset_density(descriptor, path, offset + descriptor_start)
    }
    if densities.contains(key) {
      html_fail(
        path,
        offset + descriptor_start,
        "Duplicate srcset width or density (an omitted descriptor is 1x)",
      )
    }
    densities.add(key)
    while i < raw.length() && html_space(raw[i]) {
      i += 1
    }
    if i < raw.length() && raw[i] != 44 {
      html_fail(
        path,
        offset + i,
        "Use one positive integer w or decimal x descriptor per srcset candidate",
      )
    }
    result.push({
      first: offset + start,
      last: offset + end - 1,
      url,
      html: true,
    })
    if i == raw.length() {
      break
    }
    i += 1
    if i == raw.length() || !html_space(raw[i]) {
      html_fail(
        path,
        offset + i,
        "Each srcset comma must be followed by ASCII whitespace and another candidate; comma URLs are unsupported",
      )
    }
    while i < raw.length() && html_space(raw[i]) {
      i += 1
    }
    if i == raw.length() {
      html_fail(path, offset + i, "Trailing srcset comma has no candidate")
    }
  }
  (result, width_mode.unwrap_or(false))
}

///|
fn srcset_width(
  descriptor : String,
  path : String,
  offset : Int32,
) -> String raise MoveError {
  let number = descriptor[:descriptor.length() - 1]
  if number.length() < 1 || number.length() > 9 {
    html_fail(
      path, offset, "Srcset widths need 1-9 decimal digits followed by w",
    )
  }
  for i in 0..<number.length() {
    if number[i] < 48 || number[i] > 57 {
      html_fail(path, offset + i, "Srcset widths must be positive integers")
    }
  }
  let mut first = 0
  while first + 1 < number.length() && number[first] == 48 {
    first += 1
  }
  let key = number[first:].to_owned()
  if key == "0" {
    html_fail(path, offset, "Srcset width must be greater than zero")
  }
  key
}
