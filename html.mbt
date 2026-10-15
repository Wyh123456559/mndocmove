///|
fn html_space(c : UInt16) -> Bool {
  c == 32 || c == 9 || c == 10 || c == 13 || c == 12
}

///|
fn html_name(c : UInt16) -> Bool {
  let n = c.to_int()
  (n >= 65 && n <= 90) ||
  (n >= 97 && n <= 122) ||
  (n >= 48 && n <= 57) ||
  c == 45 ||
  c == 58
}

///|
fn html_fail(
  path : String,
  offset : Int32,
  message : String,
) -> Unit raise MoveError {
  refuse(
    "UnsupportedHtml",
    path,
    message + "; use supported static HTML or keep CommonMark-only input",
    offset~,
  )
}

///|
// Require semicolon-terminated recognized entities. This deliberately refuses
// browser-specific legacy entity recovery, rather than guessing URL semantics.
fn html_decode(
  raw : String,
  path : String,
  offset : Int32,
) -> String raise MoveError {
  let mut i = 0
  while i < raw.length() {
    if raw[i] == 38 {
      let start = i
      i += 1
      while i < raw.length() && raw[i] != 59 && i - start < 40 {
        i += 1
      }
      if i >= raw.length() || raw[i] != 59 {
        html_fail(
          path,
          offset + start,
          "URL entities require a semicolon; encode query ampersands as &amp;",
        )
      }
      let entity = raw[start:i + 1].to_owned()
      let decoded = @mdchar.utf_16_clean_unref(
        StringBuilder(),
        entity,
        first=0,
        last=entity.length() - 1,
      )
      if decoded == entity || decoded.contains("\uFFFD") {
        html_fail(path, offset + start, "Unknown or invalid HTML URL entity")
      }
    }
    i += 1
  }
  let result = @mdchar.utf_16_clean_unref(
    StringBuilder(),
    raw,
    first=0,
    last=raw.length() - 1,
  )
  for c in result.iter() {
    if c.to_int() < 32 || (c.to_int() >= 127 && c.to_int() <= 159) {
      html_fail(path, offset, "Control characters in HTML URLs are unsupported")
    }
  }
  if result.has_prefix(" ") ||
    result.has_suffix(" ") ||
    result.contains("{{") ||
    result.contains("${") ||
    result.contains("<%") {
    html_fail(
      path, offset, "URL whitespace trimming and templates are unsupported",
    )
  }
  result
}

///|
fn html_encode(url : String) -> String {
  let out = StringBuilder()
  for c in url.iter() {
    match c {
      '&' => out.write_string("&amp;")
      '"' => out.write_string("&quot;")
      '\'' => out.write_string("&#39;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
// Scans only regions cmark classified as HTML; code examples never reach here.
// It is a strict lexical subset, not an HTML renderer or browser DOM parser.
fn html_destinations(
  source : String,
  path : String,
  first : Int32,
  last : Int32,
) -> Array[Destination] raise MoveError {
  if first < 0 || last < first || last >= source.length() {
    html_fail(path, first, "Missing reliable HTML source range")
  }
  let result : Array[Destination] = []
  let mut i = first
  while i <= last {
    if source[i:].has_prefix("{{") ||
      source[i:].has_prefix("${") ||
      source[i:].has_prefix("<%") {
      html_fail(path, i, "Template content in HTML blocks is unsupported")
    }
    if source[i] != 60 {
      i += 1
      continue
    }
    if source[i:].has_prefix("<!--") {
      i += 4
      while i <= last && !source[i:].has_prefix("-->") {
        if source[i:].has_prefix("--") {
          html_fail(path, i, "Malformed HTML comment")
        }
        i += 1
      }
      if i + 2 > last {
        html_fail(path, i, "Unterminated HTML comment")
      }
      i += 3
      continue
    }
    i += 1
    let closing = i <= last && source[i] == 47
    if closing {
      i += 1
    }
    let tag_start = i
    while i <= last && html_name(source[i]) {
      i += 1
    }
    let tag = source[tag_start:i].to_owned().to_lower()
    if ![
        "a", "img", "p", "div", "span", "details", "summary", "br", "hr", "figure",
        "figcaption", "table", "thead", "tbody", "tr", "td", "th", "ul", "ol", "li",
        "h1", "h2", "h3", "h4", "h5", "h6", "strong", "em", "b", "i", "code", "pre",
        "blockquote", "sup", "sub", "kbd", "samp",
      ].contains(tag) {
      html_fail(path, tag_start, "Unsupported HTML tag: " + tag)
    }
    let attributes : Set[String] = Set([])
    let mut ended = false
    while i <= last {
      let before_space = i
      while i <= last && html_space(source[i]) {
        i += 1
      }
      if i > last {
        break
      }
      if source[i] == 62 {
        i += 1
        ended = true
        break
      }
      if !closing && source[i] == 47 && i + 1 <= last && source[i + 1] == 62 {
        i += 2
        ended = true
        break
      }
      if closing || i == before_space {
        html_fail(
          path, i, "Attributes require whitespace; closing tags cannot carry attributes",
        )
      }
      let start = i
      while i <= last && html_name(source[i]) {
        i += 1
      }
      if i == start {
        html_fail(path, i, "Invalid HTML attribute name")
      }
      let attr = source[start:i].to_owned().to_lower()
      if attributes.contains(attr) {
        html_fail(path, start, "Duplicate HTML attribute: " + attr)
      }
      attributes.add(attr)
      let is_url = (tag == "a" && attr == "href") ||
        (tag == "img" && attr == "src")
      let safe = [
          "id", "class", "title", "alt", "width", "height", "align", "role", "target",
          "rel", "loading", "decoding", "border", "colspan", "rowspan", "open",
        ].contains(attr) ||
        attr.has_prefix("aria-")
      if !is_url && !safe {
        html_fail(
          path,
          start,
          "Unsupported attribute (may contain another URL grammar): " + attr,
        )
      }
      let after_name = i
      while i <= last && html_space(source[i]) {
        i += 1
      }
      if i > last || source[i] != 61 {
        if attr != "open" || tag != "details" {
          html_fail(
            path, start, "Only details/open may omit an attribute value",
          )
        }
        i = after_name
        continue
      }
      i += 1
      while i <= last && html_space(source[i]) {
        i += 1
      }
      if i > last || (source[i] != 34 && source[i] != 39) {
        html_fail(path, i, "Use single or double quoted HTML attribute values")
      }
      let quote = source[i]
      i += 1
      let value_start = i
      while i <= last && source[i] != quote {
        i += 1
      }
      if i > last {
        html_fail(path, value_start, "Unterminated HTML attribute")
      }
      let raw = source[value_start:i].to_owned()
      if raw.contains("{{") || raw.contains("${") || raw.contains("<%") {
        html_fail(path, value_start, "Template attributes are unsupported")
      }
      if is_url && !raw.is_empty() {
        result.push({
          first: value_start,
          last: i - 1,
          url: html_decode(raw, path, value_start),
          html: true,
        })
      }
      i += 1
    }
    if !ended {
      html_fail(path, tag_start, "Unterminated HTML tag")
    }
  }
  result
}
