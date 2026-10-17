///|
/// A refusal with a stable code, source path and UTF-16 offset (-1 if absent).
pub(all) struct Diagnostic {
  code : String
  path : String
  offset : Int32
  message : String
} derive(Eq, @debug.Debug)

///|
pub(all) suberror MoveError {
  Refused(Diagnostic)
} derive(@debug.Debug)

///|
fn refuse(
  code : String,
  path : String,
  message : String,
  offset~ : Int32 = -1,
) -> Unit raise MoveError {
  raise Refused({ code, path, offset, message, })
}

///|
/// Immutable file bytes. Text is never decoded with replacement characters.
struct Entry {
  path : String
  data : Bytes
} derive(Eq, @debug.Debug)

///|
pub fn Entry::new(path : String, data : Bytes) -> Entry {
  { path, data, }
}

///|
pub fn Entry::markdown(path : String, text : String) -> Entry {
  { path, data: @utf8.encode(text), }
}

///|
pub fn Entry::path(self : Entry) -> String {
  self.path
}

///|
pub fn Entry::data(self : Entry) -> Bytes {
  self.data
}

///|
pub fn Entry::text(self : Entry) -> String raise MoveError {
  @utf8.decode(self.data, ignore_bom=false) catch {
    _ => {
      refuse(
        "InvalidUtf8",
        self.path,
        "Markdown must be valid UTF-8; convert it explicitly before planning",
      )
      ""
    }
  }
}

///|
struct DocTree {
  files : Array[Entry]
} derive(@debug.Debug)

///|
/// Validates the complete inventory. Limits: 4096 files, 64 MiB total,
/// 1 MiB per Markdown file. ASCII case aliases and file/directory conflicts
/// are refused. This is not a complete filesystem portability checker.
pub fn DocTree::new(entries : Array[Entry]) -> DocTree raise MoveError {
  if entries.length() > 4096 {
    refuse("FileLimit", "", "Use at most 4096 files")
  }
  let files = entries.copy()
  files.sort_by(fn(a, b) { a.path.compare(b.path) })
  let names : Map[String, String] = Map([])
  let mut total = 0
  for file in files {
    validate_path(file.path)
    let key = file.path.to_lower()
    if names.contains(key) {
      refuse("PathCollision", file.path, "Duplicate path or ASCII case alias")
    }
    names[key] = file.path
    if file.data.length() > 67108864 - total {
      refuse("ByteLimit", file.path, "Tree exceeds 64 MiB")
    }
    total += file.data.length()
    if is_markdown(file.path) && file.data.length() > 1048576 {
      refuse("MarkdownLimit", file.path, "Markdown file exceeds 1 MiB")
    }
  }
  for file in files {
    let parts = file.path.to_lower().split("/").to_array()
    let mut prefix = ""
    for i = 0; i + 1 < parts.length(); i = i + 1 {
      prefix = if i == 0 {
        parts[i].to_owned()
      } else {
        prefix + "/" + parts[i].to_owned()
      }
      if names.contains(prefix) {
        refuse("PathCollision", file.path, "A parent component is a file")
      }
    }
  }
  { files, }
}

///|
pub fn DocTree::entries(self : DocTree) -> Array[Entry] {
  self.files.copy()
}

///|
pub fn DocTree::get(self : DocTree, path : String) -> Entry? {
  for file in self.files {
    if file.path == path {
      return Some(file)
    }
  }
  None
}

///|
struct Move {
  source : String
  destination : String
} derive(Eq, @debug.Debug)

///|
/// Paths name an existing file or a directory prefix, without trailing slash.
pub fn Move::new(source : String, destination : String) -> Move {
  { source, destination, }
}

///|
pub fn Move::source(self : Move) -> String {
  self.source
}

///|
pub fn Move::destination(self : Move) -> String {
  self.destination
}

///|
/// A replacement in the original Markdown, with an exclusive UTF-16 end.
/// An empty old_target/new_target denotes the inventory root directory;
/// File/move operands remain nonempty at validated inventory/plan boundaries.
/// In a relink plan, path/offset name the current input file; old_target refers
/// to its declared logical old namespace and new_target to the current namespace.
pub(all) struct Edit {
  path : String
  start : Int32
  end : Int32
  before : String
  after : String
  old_target : String
  new_target : String
} derive(Eq, @debug.Debug)

///|
struct MovePlan {
  original : DocTree
  profile : Profile
  moves : Array[Move]
  relinks : Array[Move]
  retargets : Array[Move]
  adopted_from : DocTree?
  edits : Array[Edit]
  result : DocTree
} derive(@debug.Debug)

///|
pub fn MovePlan::edits(self : MovePlan) -> Array[Edit] {
  self.edits.copy()
}

///|
/// Explicit syntax policy. StaticHtml adds a conservative HTML subset.
/// Root variants additionally bind leading-slash URLs to the inventory root.
pub(all) enum Profile {
  CommonMark
  StaticHtml
  CommonMarkRoot
  StaticHtmlRoot
} derive(@debug.Debug)

///|
fn Profile::allows_root(self : Profile) -> Bool {
  self is CommonMarkRoot || self is StaticHtmlRoot
}

///|
pub extend Profile with @debug.Debug::{to_repr}

///|
pub fn MovePlan::profile(self : MovePlan) -> Profile {
  self.profile
}

///|
pub fn MovePlan::moves(self : MovePlan) -> Array[Move] {
  self.moves.copy()
}

///|
/// Historical old-to-current renames for a link-only repair plan. Ordinary
/// migration plans return []; repair plans have no pending file moves().
pub fn MovePlan::relinks(self : MovePlan) -> Array[Move] {
  self.relinks.copy()
}

///|
/// Simultaneous existing-file reference substitutions. All file paths/opaque
/// bytes are retained; these are neither pending moves nor historical renames.
pub fn MovePlan::retargets(self : MovePlan) -> Array[Move] {
  self.retargets.copy()
}

///|
/// Returns an independent inventory only after the complete source snapshot
/// (including new/deleted files and all asset bytes) is unchanged.
pub fn MovePlan::replay(
  self : MovePlan,
  current : DocTree,
) -> DocTree raise MoveError {
  if current.files != self.original.files {
    refuse(
      "StaleSnapshot", "", "Files or bytes changed after preview; generate a new plan",
    )
  }
  { files: self.result.files.copy(), }
}

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend MoveError with @debug.Debug::{to_repr}

///|
pub extend Entry with Eq::{equal, not_equal}

///|
pub extend Entry with @debug.Debug::{to_repr}

///|
pub extend DocTree with @debug.Debug::{to_repr}

///|
pub extend Move with Eq::{equal, not_equal}

///|
pub extend Move with @debug.Debug::{to_repr}

///|
pub extend Edit with Eq::{equal, not_equal}

///|
pub extend Edit with @debug.Debug::{to_repr}

///|
pub extend MovePlan with @debug.Debug::{to_repr}
