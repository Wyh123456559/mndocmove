///|
/// An explicit file/fragment substitution. Fragments are decoded identifiers
/// without a leading '#', not heading text. All four fields are case-sensitive.
pub(all) struct AnchorRetarget {
  source : String
  fragment : String
  destination : String
  replacement : String
} derive(Eq, @debug.Debug)

///|
pub extend AnchorRetarget with Eq::{equal, not_equal}

///|
pub extend AnchorRetarget with @debug.Debug::{to_repr}

///|
pub fn MovePlan::anchor_retargets(self : MovePlan) -> Array[AnchorRetarget] {
  self.anchors.copy()
}

///|
/// Strict [[source_file, decoded_fragment, destination_file, decoded_replacement]].
/// Objects, extra fields, non-strings and more than 4096 mappings are refused.
/// File existence and fragment validity are checked by plan_anchor_retargets.
pub fn anchor_retargets_from_json(
  text : String,
) -> Array[AnchorRetarget] raise MoveError {
  decode_anchors(parse_wire(text))
}

///|
fn decode_anchors(value : Json) -> Array[AnchorRetarget] raise MoveError {
  guard value is Array(items) else {
    refuse(
      "InvalidPlan", "", "Anchor mappings must be an array of four-string tuples",
    )
    abort("unreachable")
  }
  if items.length() > 4096 {
    refuse("PlanLimit", "", "Use at most 4096 anchor substitutions")
  }
  let result = []
  for item in items {
    match item {
      [
        String(source),
        String(fragment),
        String(destination),
        String(replacement),
      ] => result.push({ source, fragment, destination, replacement, })
      _ =>
        refuse(
          "InvalidPlan", "", "Each anchor mapping must contain exactly four strings",
        )
    }
  }
  result
}

///|
/// Reassign only explicitly named local file/fragment references. Every file
/// remains at its original path. Substitutions are simultaneous, one-hop and
/// never infer heading slugs or change headings. Queries are preserved.
/// Empty mappings preserve all bytes without parsing, like ordinary no-op plans.
pub fn plan_anchor_retargets(
  tree : DocTree,
  requested : Array[AnchorRetarget],
  profile~ : Profile = CommonMark,
) -> MovePlan raise MoveError {
  if requested.length() > 4096 {
    refuse("PlanLimit", "", "Use at most 4096 anchor substitutions")
  }
  if requested.is_empty() {
    return plan_moves(tree, [], profile~)
  }
  let anchors = requested.copy()
  anchors.sort_by(fn(a, b) {
    if a.source == b.source {
      a.fragment.compare(b.fragment)
    } else {
      a.source.compare(b.source)
    }
  })
  for i, a in anchors {
    validate_path(a.source)
    validate_path(a.destination)
    validate_fragment(a.fragment, a.source)
    validate_fragment(a.replacement, a.destination)
    if a.source == a.destination && a.fragment == a.replacement {
      refuse("IdentityAnchor", a.source, "Omit identity anchor substitutions")
    }
    if i > 0 &&
      anchors[i - 1].source == a.source &&
      anchors[i - 1].fragment == a.fragment {
      refuse(
        "AnchorConflict",
        a.source,
        "Declare exactly one replacement per source file/fragment",
      )
    }
    if tree.get(a.source) is None {
      refuse(
        "MissingAnchorSource",
        a.source,
        "Anchor source must be an existing file; directories are unsupported",
      )
    }
    if tree.get(a.destination) is None {
      refuse(
        "MissingAnchorTarget",
        a.destination,
        "Anchor replacement must be an existing file; directories are unsupported",
      )
    }
  }
  let output = []
  let edits = []
  for file in tree.files {
    if is_markdown(file.path) {
      let (next, changes) = rewrite_anchor_references(
        file, tree, anchors, profile,
      )
      output.push(next)
      edits.append(changes)
    } else {
      output.push(file)
    }
  }
  {
    original: tree,
    profile,
    moves: [],
    relinks: [],
    retargets: [],
    anchors,
    adopted_from: None,
    edits,
    result: DocTree::new(output),
  }
}

///|
fn rewrite_anchor_references(
  file : Entry,
  tree : DocTree,
  anchors : Array[AnchorRetarget],
  profile : Profile,
) -> (Entry, Array[Edit]) raise MoveError {
  let source = file.text()
  let refs = destinations(source, file.path, profile)
  let expected = refs.map(fn(d) { d.url })
  let edits = []
  for i, dest in refs {
    if external_url(dest.url) {
      continue
    }
    let raw = reference_raw(source, file.path, dest)
    let (url_path, query, fragment, target) = reference_parts(
      dest.url,
      file.path,
      profile,
    )
    if !tree.files.any(fn(entry) { under(entry.path, target) }) {
      refuse(
        "MissingTarget",
        file.path,
        "Include link target in the declared tree: " + target,
        offset=dest.first,
      )
    }
    if url_path.has_suffix("/") && tree.get(target) is Some(_) {
      refuse(
        "InvalidDirectoryTarget",
        file.path,
        "Trailing slash names a file instead of a directory",
        offset=dest.first,
      )
    }
    guard fragment is Some(id) else { continue }
    guard anchors
      .iter()
      .find_first(fn(a) { a.source == target && a.fragment == id })
      is Some(a) else {
      continue
    }
    let path = if a.destination == target {
      url_path
    } else if url_path.has_prefix("/") && profile.allows_root() {
      "/" + encode_url_path(a.destination)
    } else {
      encode_url_path(relative_path(file.path, a.destination))
    }
    let cooked = path + query + "#" + encode_url_path(a.replacement)
    expected[i] = cooked
    let after = if dest.html {
      html_encode(cooked)
    } else {
      markdown_url(cooked)
    }
    edits.push({
      path: file.path,
      start: dest.first,
      end: dest.last + 1,
      before: raw,
      after,
      old_target: target,
      new_target: a.destination,
    })
  }
  // Check anchor expansion before allocating/reparsing the full output. Keep
  // ordinary migration/audit error classification unchanged.
  let mut output_bytes = file.data.length().to_int64()
  for edit in edits {
    output_bytes += @utf8.encode(edit.after).length().to_int64() -
      @utf8.encode(edit.before).length().to_int64()
  }
  if output_bytes > 1048576L {
    refuse(
      "MarkdownLimit",
      file.path,
      "Rewritten Markdown exceeds 1 MiB; split the document or use shorter replacement identifiers",
    )
  }
  finish_rewrite(file, profile, edits, expected, file.path)
}
