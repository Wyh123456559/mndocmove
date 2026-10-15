///|
priv suberror CliError {
  CliError(String)
}

///|
fn stop(message : String) -> Unit raise {
  raise CliError(message)
}

///|
async fn inventory(
  root : String,
  relative : String,
  entries : Array[@lib.Entry],
  total : Ref[Int64],
  directories : Ref[Int32],
) -> Unit {
  let absolute = if relative.is_empty() { root } else { root + "/" + relative }
  let before = entries.length()
  for
    name in @fs.readdir(
      absolute,
      include_hidden=true,
      include_special=true,
      sort=true,
    ) {
    if name == "." || name == ".." {
      continue
    }
    let path = if relative.is_empty() { name } else { relative + "/" + name }
    let full = root + "/" + path
    match @fs.kind(full, follow_symlink=false) {
      Directory => {
        directories.val += 1
        if directories.val > 4096 || path.split("/").count() > 64 {
          stop(
            "DirectoryLimit: root has too many/deep directories; select a smaller documentation root",
          )
        }
        inventory(root, path, entries, total, directories)
      }
      Regular => {
        let size = @fs.file_size(full)
        if size > 67108864L - total.val || entries.length() >= 4096 {
          stop("TreeLimit: use at most 4096 files / 64 MiB")
        }
        total.val += size
        entries.push(@lib.Entry::new(path, @fs.read_file(full).binary()))
      }
      _ =>
        stop("UnsupportedFile: symlinks and special files are refused: " + path)
    }
  }
  if entries.length() == before && !relative.is_empty() {
    stop(
      "EmptyDirectory: file inventories cannot preserve empty directories: " +
      relative,
    )
  }
}

///|
async fn read_tree(root : String) -> @lib.DocTree {
  if @fs.kind(root, follow_symlink=false) != Directory {
    stop("RootDirectory: select a real directory without symlinks")
  }
  let entries = []
  inventory(root, "", entries, Ref(0L), Ref(0))
  @lib.DocTree::new(entries)
}

///|
async fn read_text(path : String) -> String {
  if @fs.file_size(path) > 400000000L {
    stop("PlanLimit: JSON file is too large")
  }
  @fs.read_file(path).text()
}

///|
async fn outside_path(root : String, output : String) -> String {
  let normalized = output.replace(old="\\", new="/")
  let parts = normalized.split("/").map(fn(s) { s.to_owned() }).to_array()
  let leaf = parts.pop().unwrap_or("")
  if leaf.is_empty() || leaf == "." || leaf == ".." {
    stop("OutputPath: use a new directory name")
  }
  let parent_path = if parts.is_empty() {
    "."
  } else if parts.length() == 1 &&
    (parts[0].is_empty() || parts[0].has_suffix(":")) {
    parts[0] + "/"
  } else {
    parts.join("/")
  }
  let parent = @fs.realpath(parent_path)
  let source = @fs.realpath(root).replace(old="\\", new="/").to_lower()
  let canonical_parent = parent.replace(old="\\", new="/").to_lower()
  let source_prefix = if source.has_suffix("/") { source } else { source + "/" }
  if canonical_parent == source || canonical_parent.has_prefix(source_prefix) {
    stop("OutputInsideRoot: output must be outside source inventory")
  }
  let target = parent + "/" + leaf
  target
}

///|
// The output is a new directory export. The source is never written.
// On I/O failure the reserved output directory is retained with its marker.
async fn export_tree(
  root : String,
  output : String,
  tree : @lib.DocTree,
) -> Unit {
  let target = outside_path(root, output)
  if @fs.exists(target) {
    stop("OutputExists: choose an unused output directory")
  }
  if tree
    .entries()
    .any(fn(e) {
      e.path() == ".mndocmove-incomplete" ||
      e.path().has_prefix(".mndocmove-incomplete/")
    }) {
    stop("ReservedPath: .mndocmove-incomplete is reserved by the exporter")
  }
  @fs.mkdir(target)
  let marker = target + "/.mndocmove-incomplete"
  @fs.write_file(
    marker,
    "Export incomplete. Source files have not been modified.\n",
    create_mode=CreateNew,
  )
  for entry in tree.entries() {
    let components = entry
      .path()
      .split("/")
      .map(fn(s) { s.to_owned() })
      .to_array()
    ignore(components.pop())
    if !components.is_empty() {
      @fs.mkdir(
        target + "/" + components.join("/"),
        recursive=true,
        allow_exist=true,
      )
    }
    @fs.write_file(
      target + "/" + entry.path(),
      entry.data(),
      create_mode=CreateNew,
    )
  }
  @fs.remove(marker)
  println(
    "Exported " + tree.entries().length().to_string() + " files to " + target,
  )
}

///|
/// Runs plan ROOT MOVES_JSON PLAN_JSON or replay ROOT PLAN_JSON NEW_OUTPUT.
pub async fn run(args : Array[String]) -> Int32 {
  try {
    match args[:] {
      ["plan", root, moves, output] => {
        let tree = read_tree(root)
        let plan = @lib.plan_moves(tree, @lib.moves_from_json(read_text(moves)))
        @fs.write_file(
          outside_path(root, output),
          plan.to_json_string(),
          create_mode=CreateNew,
        )
        println(plan.preview())
      }
      ["replay", root, plan_file, output] => {
        let plan = @lib.MovePlan::from_json_string(read_text(plan_file))
        let tree = plan.replay(read_tree(root))
        export_tree(root, output, tree)
      }
      _ => {
        println(
          "Usage: mndocmove plan ROOT MOVES_JSON NEW_PLAN_JSON\n       mndocmove replay ROOT PLAN_JSON NEW_OUTPUT_DIRECTORY",
        )
        return 2
      }
    }
    0
  } catch {
    @lib.Refused(d) => {
      println(
        d.code + ": " + d.path + ":" + d.offset.to_string() + ": " + d.message,
      )
      1
    }
    CliError(message) => {
      println(message)
      1
    }
    error => {
      println("IoError: " + @debug.to_string(error))
      1
    }
  }
}
