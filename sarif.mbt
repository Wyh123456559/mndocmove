///|
// Fixed key ordering makes output independent of map iteration/backend.
fn sarif_json(value : Json) -> String {
  match value {
    Object(fields) => {
      let entries : Array[(String, Json)] = []
      for key, item in fields {
        entries.push((key, item))
      }
      entries.sort_by(fn(a, b) { a.0.compare(b.0) })
      "{" +
      entries
      .map(fn(pair) { Json(pair.0).stringify() + ":" + sarif_json(pair.1) })
      .join(",") +
      "}"
    }
    Array(items) => "[" + items.map(sarif_json).join(",") + "]"
    _ => value.stringify()
  }
}

///|
// SARIF text coordinates ignore a leading BOM. Count UTF-16 units (including
// tabs/surrogate pairs), treating CRLF as one newline; bare CR is a newline.
fn sarif_region(text : String, offset : Int32) -> Json? raise MoveError {
  if offset < 0 {
    return None
  }
  if offset > text.length() {
    refuse(
      "SarifPosition", "", "Diagnostic offset lies outside its retained source snapshot",
    )
  }
  let bom = if text.has_prefix("\uFEFF") { 1 } else { 0 }
  let mut line = 1
  let mut column = 1
  let mut i = bom
  while i < offset {
    match text[i] {
      13 => {
        line += 1
        column = 1
        i += 1
        if i < offset && text[i] == 10 {
          i += 1
        }
      }
      10 => {
        line += 1
        column = 1
        i += 1
      }
      _ => {
        column += 1
        i += 1
      }
    }
  }
  // No invented location on a newline. Raw offsets remain in result.properties.
  if offset < text.length() && (text[offset] == 13 || text[offset] == 10) {
    return None
  }
  Some(
    Json::object({
      "startLine": Json(line),
      "startColumn": Json(column),
      "endColumn": Json(column),
    }),
  )
}

///|
/// SARIF 2.1.0 from this audit's retained exact snapshot. root_prefix is the
/// tree's portable repository path (""/"." = root), not an OS path. Unknown
/// positions keep file locations without invented regions. No source contents,
/// fixes or executable plan are embedded. The consumer resolves SRCROOT.
pub fn MoveAudit::to_sarif_string(
  self : MoveAudit,
  root_prefix~ : String = "",
) -> String raise MoveError {
  let prefix = if root_prefix == "." { "" } else { root_prefix }
  if !prefix.is_empty() {
    validate_path(prefix)
  }
  let codes : Array[String] = []
  for d in self.problems {
    if !codes.contains(d.code) {
      codes.push(d.code)
    }
  }
  codes.sort_by(fn(a, b) { a.compare(b) })
  let rules : Array[Json] = codes.map(fn(code) {
    Json::object({
      "id": Json(code),
      "shortDescription": Json::object({
        "text": Json("Migration preflight: " + code),
      }),
    })
  })
  let results : Array[Json] = []
  for d in self.problems {
    let uri = encode_url_path(
      if prefix.is_empty() {
        d.path
      } else {
        prefix + "/" + d.path
      },
    )
    let physical : Map[String, Json] = {
      "artifactLocation": Json::object({
        "uri": Json(uri),
        "uriBaseId": "SRCROOT",
      }),
    }
    if d.offset >= 0 {
      let file = self.original.get(d.path).unwrap()
      if sarif_region(file.text(), d.offset) is Some(region) {
        physical["region"] = region
      }
    }
    let mut rule_index = 0
    for i, code in codes {
      if code == d.code {
        rule_index = i
        break
      }
    }
    results.push(
      Json::object({
        "ruleId": Json(d.code),
        "ruleIndex": Json(rule_index),
        "level": "error",
        // Fixed template: braces in diagnostic arguments cannot become placeholders.
        "message": Json::object({
          "text": "{0}",
          "arguments": [Json(d.message)],
        }),
        "locations": [
          Json::object({ "physicalLocation": Json::object(physical) }),
        ],
        "properties": Json::object({
          "sourcePath": Json(d.path),
          "utf16Offset": Json(d.offset),
        }),
      }),
    )
  }
  let report = Json::object({
    "$schema": "https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json",
    "version": "2.1.0",
    "runs": [
      Json::object({
        "tool": Json::object({
          "driver": Json::object({
            "name": "mndocmove",
            "semanticVersion": "0.1.0",
            "informationUri": "https://github.com/Wyh123456559/mndocmove",
            "rules": Json::array(rules),
          }),
        }),
        "columnKind": "utf16CodeUnits",
        "defaultEncoding": "utf-8",
        "newlineSequences": ["\r\n", "\n", "\r"],
        "originalUriBaseIds": Json::object({
          "SRCROOT": Json::object({
            "description": Json::object({
              "text": "Repository checkout root supplied by the SARIF consumer",
            }),
          }),
        }),
        "results": Json::array(results),
        "properties": Json::object({
          "profile": Json(profile_name(self.profile)),
          "checkedMarkdown": Json(self.checked),
          "sourceFiles": Json(self.files),
          "ready": Json(self.is_ready()),
        }),
      }),
    ],
  })
  sarif_json(report)
}
