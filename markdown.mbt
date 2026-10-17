///|
priv struct Destination {
  first : Int32
  last : Int32
  url : String
  html : Bool
}

///|
fn destinations(
  source : String,
  path : String,
  profile : Profile,
) -> Array[Destination] raise MoveError {
  let doc = @cmark.Doc::from_string(
    source,
    layout=true,
    locs=true,
    strict=true,
    file=path,
  )
  let found : Array[Destination] = []
  let problems : Array[Diagnostic] = []
  let html_ranges : Array[(Int32, Int32)] = []
  let add = fn(def : @cmark.LinkDefinition) {
    if def.dest is Some(dest) {
      let loc = dest.meta.loc
      found.push({
        first: loc.first_ccode,
        last: loc.last_ccode,
        url: dest.v,
        html: false,
      })
    }
  }
  let unsupported = fn(meta : @base.Meta, kind : String) {
    problems.push({
      code: "UnsupportedMarkdown",
      path,
      offset: meta.loc.first_ccode,
      message: kind +
      " requires an explicit supported profile; no partial move was produced",
    })
  }
  let folder : @cmark.Folder[Int32] = @cmark.Folder::new(
    inline=@cmark.FolderFn(fn(_, _, node) {
      match node {
        Link(link) | Image(link) =>
          match link.v.reference {
            Inline(def) => add(def.v)
            Ref(_, _, _) => ()
          }
        RawHtml(node) =>
          match profile {
            CommonMark => unsupported(node.meta, "Raw HTML")
            StaticHtml =>
              html_ranges.push(
                (node.meta.loc.first_ccode, node.meta.loc.last_ccode),
              )
          }
        Text(node) =>
          if node.v.contains("[[") || node.v.contains("{{") {
            unsupported(node.meta, "Wiki links or templates")
          }
        _ => ()
      }
      @cmark.FolderResult::Default
    }),
    block=@cmark.FolderFn(fn(_, _, node) {
      match node {
        LinkRefDefinition(def) => add(def.v)
        HtmlBlock(node) =>
          match profile {
            CommonMark => unsupported(node.meta, "HTML blocks")
            StaticHtml =>
              html_ranges.push(
                (node.meta.loc.first_ccode, node.meta.loc.last_ccode),
              )
          }
        _ => ()
      }
      @cmark.FolderResult::Default
    }),
  )
  ignore(folder.fold_doc(0, doc)) catch {
    _ =>
      refuse(
        "MarkdownTraversal", path, "The parser could not safely visit this document",
      )
  }
  if problems.length() > 0 {
    raise Refused(problems[0])
  }
  for (first, last) in html_ranges {
    found.append(html_destinations(source, path, first, last))
  }
  found.sort_by(fn(a, b) { a.first.compare(b.first) })
  let unique : Array[Destination] = []
  for dest in found {
    if !unique.any(fn(other) {
        other.first == dest.first &&
        other.last == dest.last &&
        other.url == dest.url
      }) {
      unique.push(dest)
    }
  }
  unique
}

///|
fn rewrite(
  file : Entry,
  tree : DocTree,
  moves : Array[Move],
  profile : Profile,
  targets? : Array[Move],
) -> (Entry, Array[Edit]) raise MoveError {
  let target_moves = targets.unwrap_or(moves)
  let source = file.text()
  let edits : Array[Edit] = []
  let next_path = moved(file.path, moves)
  let refs = destinations(source, file.path, profile)
  let expected = refs.map(fn(d) { d.url })
  for index = 0; index < refs.length(); index = index + 1 {
    let dest = refs[index]
    if dest.url.is_empty() {
      continue
    }
    if dest.first < 0 || dest.last < dest.first || dest.last >= source.length() {
      refuse(
        "SourcePosition",
        file.path,
        "Parser did not provide a reliable destination range",
      )
    }
    let raw = source[dest.first:dest.last + 1].to_owned()
    let clean = if dest.html {
      html_decode(raw, file.path, dest.first)
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
        file.path,
        "Destination range does not reproduce the parser value",
        offset=dest.first,
      )
    }
    if external_url(dest.url) {
      continue
    }
    let (url_path, suffix) = split_url(dest.url)
    if url_path.is_empty() {
      continue
    }
    let decoded = decode_url_path(url_path, file.path)
    let target = resolve_path(file.path, decoded)
    let target_exists = tree.files.any(fn(entry) { under(entry.path, target) })
    if !target_exists {
      refuse(
        "MissingTarget",
        file.path,
        "Include link target in the declared tree: " + target,
        offset=dest.first,
      )
    }
    let new_target = moved(target, target_moves)
    if !tree.files.any(fn(entry) { under(moved(entry.path, moves), new_target) }) {
      refuse(
        "MissingProjectedTarget",
        file.path,
        "Directory link loses all children; move the directory prefix explicitly: " +
        target,
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
    let current_target = Some(resolve_path(next_path, decoded)) catch {
      _ => None
    }
    if current_target == Some(new_target) {
      continue
    }
    let trailing = if url_path.has_suffix("/") { "/" } else { "" }
    let cooked = encode_url_path(relative_path(next_path, new_target)) +
      trailing +
      suffix
    expected[index] = cooked
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
      new_target,
    })
  }
  let output = StringBuilder()
  let mut offset = 0
  for edit in edits {
    if edit.start < offset {
      refuse(
        "OverlappingEdits",
        file.path,
        "Parser returned overlapping destinations",
      )
    }
    output.write_view(source[offset:edit.start])
    output.write_string(edit.after)
    offset = edit.end
  }
  output.write_view(source[offset:])
  let text = output.to_string()
  let actual = destinations(text, next_path, profile).map(fn(d) { d.url })
  if actual != expected {
    refuse(
      "RewriteInvariant",
      file.path,
      "Reparsed destinations differ from the intended URLs; no partial plan was produced",
    )
  }
  (Entry::markdown(next_path, text), edits)
}
