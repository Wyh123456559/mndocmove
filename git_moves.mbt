///|
fn git_field(
  data : Bytes,
  start : Int32,
  limit : Int32,
) -> (String, Int32) raise MoveError {
  let mut end = start
  while end < data.length() && data[end] != b'\x00' {
    if end - start >= limit {
      refuse(
        "GitDiffLimit",
        "",
        "Git field too large at byte " +
        start.to_string() +
        "; select a smaller portable documentation scope",
      )
    }
    end += 1
  }
  if end == data.length() {
    refuse(
      "InvalidGitDiff",
      "",
      "Missing NUL-terminated field at byte " +
      start.to_string() +
      "; use git diff --name-status -z --find-renames=100%",
    )
  }
  let value = @utf8.decode(data[start:end], ignore_bom=false) catch {
    _ => {
      refuse(
        "GitDiffUtf8",
        "",
        "Git paths must be strict UTF-8; invalid field at byte " +
        start.to_string(),
      )
      abort("unreachable")
    }
  }
  (value, end + 1)
}

///|
fn git_relative_path(
  path : String,
  root_prefix : String,
) -> String raise MoveError {
  validate_path(path)
  if root_prefix.is_empty() {
    return path
  }
  if !path.has_prefix(root_prefix + "/") {
    refuse(
      "GitRootScope",
      path,
      "Every rename endpoint must be below the exact Git root prefix " +
      review_path(root_prefix) +
      "; choose a complete documentation scope, without filtering individual records",
    )
  }
  let relative = path[root_prefix.length() + 1:].to_owned()
  validate_path(relative)
  relative
}

///|
/// Imports only complete exact-renames (R100) from Git --name-status -z bytes.
/// No unsupported record is skipped. Paths are portable strict UTF-8; an optional
/// repository-relative root prefix is stripped from both endpoints. File moves
/// remain explicit (no inferred directory moves). Git is not a library dependency.
pub fn moves_from_git_name_status(
  data : Bytes,
  root_prefix~ : String = "",
) -> Array[Move] raise MoveError {
  if data.length() > 16777216 {
    refuse("GitDiffLimit", "", "Git name-status input exceeds 16 MiB")
  }
  if !root_prefix.is_empty() {
    validate_path(root_prefix)
  }
  let result : Array[Move] = []
  let sources : Set[String] = Set([])
  let destinations : Set[String] = Set([])
  let mut offset = 0
  while offset < data.length() {
    if result.length() >= 4096 {
      refuse("GitDiffLimit", "", "Use at most 4096 Git rename records")
    }
    let (status, after_status) = git_field(data, offset, 16)
    if status != "R100" {
      refuse(
        "UnsupportedGitChange",
        "",
        "Expected only R100 exact file renames, found " +
        review_path(status) +
        " at byte " +
        offset.to_string() +
        "; content/mode changes, copies, additions and deletions need a separate workflow",
      )
    }
    let (old_path, after_old) = git_field(data, after_status, 16384)
    let (new_path, next) = git_field(data, after_old, 16384)
    let source = git_relative_path(old_path, root_prefix)
    let destination = git_relative_path(new_path, root_prefix)
    if source == destination {
      refuse("IdentityMove", source, "Git rename endpoints must differ")
    }
    // Match the DocTree portability key; do not infer Unicode case folding.
    let source_key = source.to_lower()
    let destination_key = destination.to_lower()
    if sources.contains(source_key) || destinations.contains(destination_key) {
      refuse(
        "GitRenameConflict", source, "Git rename sources and destinations must each be unique, including ASCII case aliases",
      )
    }
    sources.add(source_key)
    destinations.add(destination_key)
    result.push(Move::new(source, destination))
    offset = next
  }
  result.sort_by(fn(a, b) { a.source.compare(b.source) })
  result
}
