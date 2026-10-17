///|
fn is_markdown(path : String) -> Bool {
  path.to_lower().has_suffix(".md")
}

///|
fn validate_path(path : String) -> Unit raise MoveError {
  if path.is_empty() || path.length() > 4096 {
    refuse(
      "InvalidPath", path, "Use a nonempty root-relative path of at most 4096 units",
    )
  }
  for part in path.split("/") {
    if part.is_empty() ||
      part == "." ||
      part == ".." ||
      part.has_suffix(".") ||
      part.has_suffix(" ") {
      refuse(
        "InvalidPath", path, "Empty, dot, dot-dot and trailing dot/space components are unsupported",
      )
    }
    let stem = part.to_owned().split(".").next().unwrap().to_owned().to_lower()
    if [
        "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6",
        "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7",
        "lpt8", "lpt9",
      ].contains(stem) {
      refuse(
        "InvalidPath", path, "Windows device-name components are unsupported",
      )
    }
    for c in part.iter() {
      if c.to_int() < 32 ||
        c == '\\' ||
        c == ':' ||
        c == '*' ||
        c == '?' ||
        c == '<' ||
        c == '>' ||
        c == '|' ||
        c == '"' {
        refuse(
          "InvalidPath", path, "Use portable relative file components, not absolute paths or URI syntax",
        )
      }
    }
  }
}

///|
fn under(path : String, prefix : String) -> Bool {
  // The empty canonical link target denotes the inventory root. File names
  // and move prefixes still pass validate_path and may never be empty.
  prefix.is_empty() || path == prefix || path.has_prefix(prefix + "/")
}

///|
fn moved(path : String, moves : Array[Move]) -> String {
  for change in moves {
    if under(path, change.source) {
      return change.destination + path[change.source.length():].to_owned()
    }
  }
  path
}

///|
fn resolve_path(
  source : String,
  relative : String,
  from_root~ : Bool = false,
) -> String raise MoveError {
  let rooted = relative.has_prefix("/") && from_root
  if (relative.has_prefix("/") && !from_root) || relative.contains("\\") {
    refuse(
      "UnsupportedUrl", source, "Root-relative and backslash URLs need an explicit site profile",
    )
  }
  let parts = if rooted {
    []
  } else {
    let parts = source.split("/").map(fn(s) { s.to_owned() }).to_array()
    ignore(parts.pop())
    parts
  }
  for part in relative.split("/") {
    match part.to_owned() {
      "" | "." => ()
      ".." =>
        if parts.pop() is None {
          refuse(
            "OutsideRoot", source, "Link escapes the declared tree; include a wider root",
          )
        }
      value => parts.push(value)
    }
  }
  let result = parts.join("/")
  if !result.is_empty() {
    validate_path(result)
  }
  result
}

///|
fn relative_path(source : String, target : String) -> String {
  let from = source.split("/").map(fn(s) { s.to_owned() }).to_array()
  ignore(from.pop())
  let to = if target.is_empty() {
    []
  } else {
    target.split("/").map(fn(s) { s.to_owned() }).to_array()
  }
  let mut common = 0
  while common < from.length() &&
        common < to.length() &&
        from[common] == to[common] {
    common += 1
  }
  let result : Array[String] = []
  for i = common; i < from.length(); i = i + 1 {
    result.push("..")
  }
  for i = common; i < to.length(); i = i + 1 {
    result.push(to[i])
  }
  if result.is_empty() {
    "."
  } else {
    result.join("/")
  }
}

///|
fn hex_digit(value : Int32) -> String {
  "0123456789ABCDEF"[value:value + 1].to_owned()
}

///|
fn unhex(c : UInt16) -> Int32 {
  let n = c.to_int()
  if n >= 48 && n <= 57 {
    n - 48
  } else if n >= 65 && n <= 70 {
    n - 55
  } else if n >= 97 && n <= 102 {
    n - 87
  } else {
    -1
  }
}

///|
fn decode_url_path(path : String, source : String) -> String raise MoveError {
  let input = @utf8.encode(path)
  let output : Array[Byte] = []
  let mut i = 0
  while i < input.length() {
    if input[i] == b'%' {
      if i + 2 >= input.length() {
        refuse("InvalidEscape", source, "Incomplete percent escape")
      }
      let a = unhex(input[i + 1].to_int().to_uint16())
      let b = unhex(input[i + 2].to_int().to_uint16())
      if a < 0 || b < 0 {
        refuse("InvalidEscape", source, "Invalid percent escape")
      }
      let n = a * 16 + b
      if n == 0 || n == 47 || n == 92 {
        refuse(
          "AmbiguousEscape", source, "Encoded separators and NUL are refused",
        )
      }
      output.push(n.to_byte())
      i += 3
    } else {
      output.push(input[i])
      i += 1
    }
  }
  @utf8.decode(Bytes::from_array(output), ignore_bom=false) catch {
    _ => {
      refuse("InvalidEscape", source, "URL path must decode as UTF-8")
      ""
    }
  }
}

///|
fn encode_url_path(path : String) -> String {
  let output = StringBuilder()
  for b in @utf8.encode(path) {
    let n = b.to_int()
    if (n >= 65 && n <= 90) ||
      (n >= 97 && n <= 122) ||
      (n >= 48 && n <= 57) ||
      b == b'/' ||
      b == b'.' ||
      b == b'-' ||
      b == b'_' ||
      b == b'~' {
      output.write_char(n.to_char().unwrap())
    } else {
      output.write_string("%" + hex_digit(n / 16) + hex_digit(n % 16))
    }
  }
  output.to_string()
}

///|
fn split_url(url : String) -> (String, String) {
  for i = 0; i < url.length(); i = i + 1 {
    if url[i] == 35 || url[i] == 63 {
      return (url[:i].to_owned(), url[i:].to_owned())
    }
  }
  (url, "")
}

///|
fn external_url(url : String) -> Bool {
  let (path, _) = split_url(url)
  if path.has_prefix("//") {
    return true
  }
  for i = 0; i < path.length(); i = i + 1 {
    if path[i] == 47 {
      return false
    }
    if path[i] == 58 {
      return true
    }
  }
  false
}

///|
// Escape cooked destinations back into Markdown without changing their URL.
fn markdown_url(url : String) -> String {
  let output = StringBuilder()
  for c in url.iter() {
    match c {
      '&' => output.write_string("&amp;")
      '<' => output.write_string("&lt;")
      '>' => output.write_string("&gt;")
      '"' => output.write_string("&quot;")
      '\'' => output.write_string("&#39;")
      '\\' => output.write_string("\\\\")
      '(' => output.write_string("\\(")
      ')' => output.write_string("\\)")
      ' ' => output.write_string("&#32;")
      '\t' => output.write_string("&#9;")
      _ =>
        if c.to_int() < 32 {
          output.write_string("&#" + c.to_int().to_string() + ";")
        } else {
          output.write_char(c)
        }
    }
  }
  output.to_string()
}
