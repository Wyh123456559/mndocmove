///|
/// A local URL destination span (UTF-16, exclusive end). Reference-style links
/// are represented by their definition, not each rendered use. Fragment is
/// decoded, without '#'; None differs from an explicit empty fragment.
pub(all) struct Reference {
  path : String
  start : Int32
  end : Int32
  raw : String
  url : String
  target : String
  fragment : String?
} derive(Eq, @debug.Debug)

///|
struct IncomingReferences {
  target : String
  recursive : Bool
  profile : Profile
  refs : Array[Reference]
} derive(@debug.Debug)

///|
pub fn IncomingReferences::references(
  self : IncomingReferences,
) -> Array[Reference] {
  self.refs.copy()
}

///|
/// Deterministic report, not an executable plan. Rows contain source path,
/// start/end, exact raw URL, cooked URL, resolved target and decoded fragment.
pub fn IncomingReferences::to_json_string(self : IncomingReferences) -> String {
  let rows : Array[Json] = self.refs.map(fn(r) {
    [
      Json(r.path),
      Json(r.start),
      Json(r.end),
      Json(r.raw),
      Json(r.url),
      Json(r.target),
      match r.fragment {
        Some(value) => Json(value)
        None => null
      },
    ]
  })
  let report : Json = [
    "mndocmove-incoming",
    1,
    Json(profile_name(self.profile)),
    Json(self.target),
    Json(self.recursive),
    Json::array(rows),
  ]
  report.stringify()
}

///|
// Fragment identifiers are opaque Unicode identifiers, not inferred headings.
// Unlike paths, percent-encoded '/' is permitted; control characters are not.
fn decode_fragment(text : String, source : String) -> String raise MoveError {
  let bytes = @utf8.encode(text)
  let output : Array[Byte] = []
  let mut i = 0
  while i < bytes.length() {
    if bytes[i] == b'%' {
      if i + 2 >= bytes.length() {
        refuse("InvalidFragment", source, "Incomplete fragment percent escape")
      }
      let a = unhex(bytes[i + 1].to_int().to_uint16())
      let b = unhex(bytes[i + 2].to_int().to_uint16())
      if a < 0 || b < 0 {
        refuse("InvalidFragment", source, "Malformed fragment percent escape")
      }
      output.push((a * 16 + b).to_byte())
      i += 3
    } else {
      output.push(bytes[i])
      i += 1
    }
  }
  let value = @utf8.decode(Bytes::from_array(output), ignore_bom=false) catch {
    _ => {
      refuse("InvalidFragment", source, "Fragment must decode as UTF-8")
      ""
    }
  }
  validate_fragment(value, source)
  value
}

///|
fn validate_fragment(value : String, source : String) -> Unit raise MoveError {
  if value.length() > 4096 ||
    value.iter().any(fn(c) { c.to_int() < 32 || c.to_int() == 127 }) {
    refuse(
      "InvalidFragment", source, "Use a fragment of at most 4096 UTF-16 units without control characters",
    )
  }
}

///|
fn reference_parts(
  url : String,
  source : String,
  profile : Profile,
) -> (String, String, String?, String) raise MoveError {
  let (path, suffix) = split_url(url)
  let mut query = suffix
  let mut fragment = None
  for i in 0..<suffix.length() {
    if suffix[i] == 35 {
      query = suffix[:i].to_owned()
      fragment = Some(decode_fragment(suffix[i + 1:].to_owned(), source))
      break
    }
  }
  let target = if path.is_empty() {
    source
  } else {
    resolve_path(
      source,
      decode_url_path(path, source),
      from_root=profile.allows_root(),
    )
  }
  (path, query, fragment, target)
}

///|
fn reference_raw(
  source : String,
  path : String,
  dest : Destination,
) -> String raise MoveError {
  let end = dest.last + 1
  if dest.first < 0 || end < dest.first || end > source.length() {
    refuse(
      "SourcePosition", path, "Parser did not provide a reliable destination range",
    )
  }
  let raw = source[dest.first:end].to_owned()
  let clean = if dest.html {
    html_decode(raw, path, dest.first)
  } else if raw.is_empty() {
    ""
  } else {
    @mdchar.utf_16_clean_unesc_unref(
      StringBuilder(),
      raw,
      first=0,
      last=raw.length() - 1,
    )
  }
  if clean != dest.url {
    refuse(
      "SourcePosition",
      path,
      "Destination range does not reproduce the parser value",
      offset=dest.first,
    )
  }
  raw
}

///|
/// Locate incoming local destination spans before changing a file/directory.
/// '.'/'' select the inventory root; recursive includes descendant targets.
/// The entire Markdown tree is validated; broken/unsupported input refuses the
/// complete report. max_references (1..65536) bounds ALL scanned local spans,
/// not just selected rows; excess refuses without truncating the report.
pub fn DocTree::incoming(
  self : DocTree,
  target : String,
  recursive~ : Bool = false,
  profile~ : Profile = CommonMark,
  max_references~ : Int32 = 65536,
) -> IncomingReferences raise MoveError {
  if max_references < 1 || max_references > 65536 {
    refuse("ReferenceLimit", "", "Use a local-reference budget from 1 to 65536")
  }
  let selected = if target == "." { "" } else { target }
  if !selected.is_empty() {
    validate_path(selected)
    if !self.files.any(fn(file) { under(file.path, selected) }) {
      refuse(
        "MissingReferenceTarget", selected, "Select an existing file/directory in the complete inventory, or '.' for the root",
      )
    }
  }
  let refs = []
  let mut scanned = 0
  for file in self.files {
    if !is_markdown(file.path) {
      continue
    }
    let source = file.text()
    for dest in destinations(source, file.path, profile) {
      if external_url(dest.url) {
        continue
      }
      scanned += 1
      if scanned > max_references {
        refuse(
          "ReferenceLimit",
          file.path,
          "Local destination count exceeds the budget; use a smaller complete documentation root or raise max_references up to 65536",
        )
      }
      let raw = reference_raw(source, file.path, dest)
      let (url_path, _, fragment, resolved) = reference_parts(
        dest.url,
        file.path,
        profile,
      )
      if !self.files.any(fn(entry) { under(entry.path, resolved) }) {
        refuse(
          "MissingTarget",
          file.path,
          "Include link target in the declared tree: " + resolved,
          offset=dest.first,
        )
      }
      if url_path.has_suffix("/") && self.get(resolved) is Some(_) {
        refuse(
          "InvalidDirectoryTarget",
          file.path,
          "Trailing slash names a file instead of a directory",
          offset=dest.first,
        )
      }
      if resolved == selected || (recursive && under(resolved, selected)) {
        refs.push({
          path: file.path,
          start: dest.first,
          end: dest.last + 1,
          raw,
          url: dest.url,
          target: resolved,
          fragment,
        })
      }
    }
  }
  { target: selected, recursive, profile, refs, }
}

///|
pub extend Reference with Eq::{equal, not_equal}

///|
pub extend Reference with @debug.Debug::{to_repr}

///|
pub extend IncomingReferences with @debug.Debug::{to_repr}
