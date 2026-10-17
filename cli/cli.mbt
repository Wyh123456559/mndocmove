///|
priv suberror CliError {
  CliError(String)
}

///|
priv suberror ExportFailure {
  ExportFailure(String, String)
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
  let normalized = output.replace_all(old="\\", new="/")
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
  let source = @fs.realpath(root).replace_all(old="\\", new="/").to_lower()
  let canonical_parent = parent.replace_all(old="\\", new="/").to_lower()
  let source_prefix = if source.has_suffix("/") { source } else { source + "/" }
  if canonical_parent == source || canonical_parent.has_prefix(source_prefix) {
    stop("OutputInsideRoot: output must be outside source inventory")
  }
  let target = parent + "/" + leaf
  target
}

///|
// The original directory is read-only. The final path is published only after
// byte-for-byte readback of a separately reserved sibling staging directory.
async fn export_tree(
  root : String,
  output : String,
  tree : @lib.DocTree,
) -> Unit {
  let target = outside_path(root, output)
  if @fs.exists(target) {
    stop("OutputExists: choose an unused output directory")
  }
  let stage = reserve_stage(target)
  let marker = stage + "/.mndocmove-incomplete"
  let payload = stage + "/tree"
  try {
    @fs.write_file(
      marker,
      "Staging export. Source unchanged; final path is not yet published.\n",
      create_mode=CreateNew,
    )
    @fs.mkdir(payload)
    for entry in tree.entries() {
      let components = entry
        .path()
        .split("/")
        .map(fn(s) { s.to_owned() })
        .to_array()
      ignore(components.pop())
      if !components.is_empty() {
        @fs.mkdir(
          payload + "/" + components.join("/"),
          recursive=true,
          allow_exist=true,
        )
      }
      @fs.write_file(
        payload + "/" + entry.path(),
        entry.data(),
        create_mode=CreateNew,
      )
    }
    publish_staged(payload, target, tree)
  } catch {
    error => raise ExportFailure(stage, @debug.to_string(error))
  }
  // Publication already succeeded. Failure to remove our empty staging shell
  // is a cleanup warning, never a false report that the migration failed.
  try {
    @fs.remove(marker)
    @fs.rmdir(stage, recursive=false)
  } catch {
    _ =>
      println(
        "CleanupWarning: verified export published; staging metadata remains at " +
        stage,
      )
  }
  println(
    "Exported " + tree.entries().length().to_string() + " files to " + target,
  )
}

///|
async fn extend_saved(
  root : String,
  saved : String,
  moves : String,
  output : String,
  profile : @lib.Profile?,
) -> Unit {
  let chain = @lib.MoveChain::from_json_string(read_text(saved))
  ignore(chain.replay(read_tree(root)))
  let next = chain.then_moves(@lib.moves_from_json(read_text(moves)), profile?)
  @fs.write_file(
    outside_path(root, output),
    next.to_json_string(),
    create_mode=CreateNew,
  )
  println("Saved chain with " + next.stages().length().to_string() + " stages")
}

///|
async fn read_git_moves(path : String, prefix : String) -> Array[@lib.Move] {
  if @fs.file_size(path) > 16777216L {
    stop("GitDiffLimit: name-status input exceeds 16 MiB")
  }
  @lib.moves_from_git_name_status(
    @fs.read_file(path).binary(),
    root_prefix=if prefix == "." { "" } else { prefix },
  )
}

///|
async fn plan_git(
  root : String,
  status : String,
  prefix : String,
  output : String,
  profile : @lib.Profile,
) -> Unit {
  let plan = @lib.plan_moves(
    read_tree(root),
    read_git_moves(status, prefix),
    profile~,
  )
  @fs.write_file(
    outside_path(root, output),
    plan.to_json_string(),
    create_mode=CreateNew,
  )
  println(plan.preview())
}

///|
async fn save_relinks(
  root : String,
  moves : Array[@lib.Move],
  output : String,
  profile : @lib.Profile,
) -> Unit {
  let plan = @lib.plan_relinks(read_tree(root), moves, profile~)
  @fs.write_file(
    outside_path(root, output),
    plan.to_json_string(),
    create_mode=CreateNew,
  )
  println(plan.preview())
}

///|
async fn audit_tree(
  root : String,
  moves : String,
  profile : @lib.Profile,
) -> Int32 {
  let audit = @lib.audit_moves(
    read_tree(root),
    @lib.moves_from_json(read_text(moves)),
    profile~,
  )
  println(audit.to_json_string())
  if audit.is_ready() {
    0
  } else {
    1
  }
}

///|
async fn save_retargets(
  root : String,
  pairs : String,
  output : String,
  profile : @lib.Profile,
) -> Unit {
  let plan = @lib.plan_retargets(
    read_tree(root),
    @lib.moves_from_json(read_text(pairs)),
    profile~,
  )
  @fs.write_file(
    outside_path(root, output),
    plan.to_json_string(),
    create_mode=CreateNew,
  )
  println(plan.preview())
}

///|
async fn save_anchors(
  root : String,
  pairs : String,
  output : String,
  profile : @lib.Profile,
) -> Unit {
  let plan = @lib.plan_anchor_retargets(
    read_tree(root),
    @lib.anchor_retargets_from_json(read_text(pairs)),
    profile~,
  )
  @fs.write_file(
    outside_path(root, output),
    plan.to_json_string(),
    create_mode=CreateNew,
  )
  println(plan.preview())
}

///|
fn named_profile(name : String) -> @lib.Profile raise {
  match name {
    "commonmark" => CommonMark
    "static-html" => StaticHtml
    "commonmark-root" => CommonMarkRoot
    "static-html-root" => StaticHtmlRoot
    _ => {
      stop(
        "InvalidProfile: use commonmark, static-html, commonmark-root or static-html-root",
      )
      abort("unreachable")
    }
  }
}

///|
async fn save_moves(
  root : String,
  moves : String,
  output : String,
  profile : @lib.Profile,
) -> Unit {
  let plan = @lib.plan_moves(
    read_tree(root),
    @lib.moves_from_json(read_text(moves)),
    profile~,
  )
  @fs.write_file(
    outside_path(root, output),
    plan.to_json_string(),
    create_mode=CreateNew,
  )
  println(plan.preview())
}

///|
async fn audit_sarif(
  root : String,
  moves : String,
  prefix : String,
  output : String,
  profile : @lib.Profile,
) -> Int32 {
  let audit = @lib.audit_moves(
    read_tree(root),
    @lib.moves_from_json(read_text(moves)),
    profile~,
  )
  let report = audit.to_sarif_string(root_prefix=prefix)
  @fs.write_file(outside_path(root, output), report, create_mode=CreateNew)
  println(
    "SARIF report written; " +
    (if audit.is_ready() {
      "ready"
    } else {
      "blocked; no migration plan produced"
    }),
  )
  if audit.is_ready() {
    0
  } else {
    1
  }
}

///|
/// Plans, reviews, replays or restores a migration. All filesystem outputs
/// require unused paths; source inventories are never modified.
pub async fn run(args : Array[String]) -> Int32 {
  try {
    match args[:] {
      ["incoming", root, target] =>
        println(read_tree(root).incoming(target).to_json_string())
      ["incoming", root, target, "--recursive"] =>
        println(
          read_tree(root).incoming(target, recursive=true).to_json_string(),
        )
      ["incoming", root, target, "--profile", name] =>
        println(
          read_tree(root)
          .incoming(target, profile=named_profile(name))
          .to_json_string(),
        )
      ["incoming", root, target, "--recursive", "--profile", name] =>
        println(
          read_tree(root)
          .incoming(target, recursive=true, profile=named_profile(name))
          .to_json_string(),
        )
      ["audit-sarif", root, moves, prefix, output] =>
        return audit_sarif(root, moves, prefix, output, CommonMark)
      ["audit-sarif", root, moves, prefix, output, "--profile", name] =>
        return audit_sarif(root, moves, prefix, output, named_profile(name))
      ["plan", root, moves, output, "--profile", name] =>
        save_moves(root, moves, output, named_profile(name))
      ["retarget", root, pairs, output, "--profile", name] =>
        save_retargets(root, pairs, output, named_profile(name))
      ["retarget-anchors", root, pairs, output] =>
        save_anchors(root, pairs, output, CommonMark)
      ["retarget-anchors", root, pairs, output, "--profile", name] =>
        save_anchors(root, pairs, output, named_profile(name))
      ["relink", root, moves, output, "--profile", name] =>
        save_relinks(
          root,
          @lib.moves_from_json(read_text(moves)),
          output,
          named_profile(name),
        )
      ["plan-git", root, status, prefix, output, "--profile", name] =>
        plan_git(root, status, prefix, output, named_profile(name))
      ["relink-git", root, status, prefix, output, "--profile", name] =>
        save_relinks(
          root,
          read_git_moves(status, prefix),
          output,
          named_profile(name),
        )
      ["audit", root, moves, "--profile", name] =>
        return audit_tree(root, moves, named_profile(name))
      ["extend", root, saved, moves, output, "--profile", name] =>
        extend_saved(root, saved, moves, output, Some(named_profile(name)))
      ["retarget", root, pairs, output] =>
        save_retargets(root, pairs, output, CommonMark)
      ["retarget", root, pairs, output, "--static-html"] =>
        save_retargets(root, pairs, output, StaticHtml)
      ["audit", root, moves] => return audit_tree(root, moves, CommonMark)
      ["audit", root, moves, "--static-html"] =>
        return audit_tree(root, moves, StaticHtml)
      ["check-renamed", root, saved] => {
        let report = @lib.MovePlan::from_json_string(read_text(saved)).check_renamed(
          read_tree(root),
        )
        println(report.to_json_string())
        return if report.is_match() { 0 } else { 1 }
      }
      ["adopt", root, saved, output] => {
        let plan = @lib.MovePlan::from_json_string(read_text(saved)).adopt(
          read_tree(root),
        )
        @fs.write_file(
          outside_path(root, output),
          plan.to_json_string(),
          create_mode=CreateNew,
        )
        println(plan.preview())
      }
      ["relink", root, moves, output] =>
        save_relinks(
          root,
          @lib.moves_from_json(read_text(moves)),
          output,
          CommonMark,
        )
      ["relink", root, moves, output, "--static-html"] =>
        save_relinks(
          root,
          @lib.moves_from_json(read_text(moves)),
          output,
          StaticHtml,
        )
      ["relink-git", root, status, prefix, output] =>
        save_relinks(root, read_git_moves(status, prefix), output, CommonMark)
      ["relink-git", root, status, prefix, output, "--static-html"] =>
        save_relinks(root, read_git_moves(status, prefix), output, StaticHtml)
      ["plan-git", root, status, prefix, output] =>
        plan_git(root, status, prefix, output, CommonMark)
      ["plan-git", root, status, prefix, output, "--static-html"] =>
        plan_git(root, status, prefix, output, StaticHtml)
      ["merge", root, left, right, output] => {
        let first = @lib.MovePlan::from_json_string(read_text(left))
        let second = @lib.MovePlan::from_json_string(read_text(right))
        let merged = first.merge(second)
        ignore(merged.replay(read_tree(root)))
        @fs.write_file(
          outside_path(root, output),
          merged.to_json_string(),
          create_mode=CreateNew,
        )
        println(merged.preview())
      }
      ["extend", root, saved, moves, output] =>
        extend_saved(root, saved, moves, output, None)
      ["extend", root, saved, moves, output, "--static-html"] =>
        extend_saved(root, saved, moves, output, Some(StaticHtml))
      ["extend", root, saved, moves, output, "--commonmark"] =>
        extend_saved(root, saved, moves, output, Some(CommonMark))
      ["check", root, plan_file] => {
        let report = @lib.MoveChain::from_json_string(read_text(plan_file)).check(
          read_tree(root),
        )
        println(report.to_json_string())
        return if report.is_match() { 0 } else { 1 }
      }
      ["check", root, plan_file, "--result"] => {
        let report = @lib.MoveChain::from_json_string(read_text(plan_file)).check(
          read_tree(root),
          side=Result,
        )
        println(report.to_json_string())
        return if report.is_match() { 0 } else { 1 }
      }
      ["review", plan_file] =>
        println(@lib.MoveChain::from_json_string(read_text(plan_file)).review())
      ["review", plan_file, context_text] => {
        let mut context = -1
        for i in 0..<=20 {
          if context_text == i.to_string() {
            context = i
            break
          }
        }
        if context < 0 {
          stop("InvalidContext: use an integer from 0 to 20")
        }
        println(
          @lib.MoveChain::from_json_string(read_text(plan_file)).review(
            context~,
          ),
        )
      }
      ["plan", root, moves, output, "--static-html"] => {
        let tree = read_tree(root)
        let plan = @lib.plan_moves(
          tree,
          @lib.moves_from_json(read_text(moves)),
          profile=StaticHtml,
        )
        @fs.write_file(
          outside_path(root, output),
          plan.to_json_string(),
          create_mode=CreateNew,
        )
        println(plan.preview())
      }
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
        let plan = @lib.MoveChain::from_json_string(read_text(plan_file))
        let tree = plan.replay(read_tree(root))
        export_tree(root, output, tree)
      }
      ["restore", root, plan_file, output] => {
        let plan = @lib.MoveChain::from_json_string(read_text(plan_file))
        let tree = plan.restore(read_tree(root))
        export_tree(root, output, tree)
      }
      _ => {
        println(
          "Usage: mndocmove audit ROOT MOVES_JSON [--static-html]\n       mndocmove plan ROOT MOVES_JSON NEW_PLAN_JSON [--static-html]\n       mndocmove plan-git OLD_ROOT NAME_STATUS_Z ROOT_PREFIX NEW_PLAN_JSON [--static-html]\n       mndocmove relink CURRENT_ROOT ALREADY_RENAMED_JSON NEW_PLAN_JSON [--static-html]\n       mndocmove relink-git CURRENT_ROOT NAME_STATUS_Z ROOT_PREFIX NEW_PLAN_JSON [--static-html]\n       mndocmove check-renamed CURRENT_ROOT PENDING_PLAN_JSON\n       mndocmove adopt CURRENT_ROOT PENDING_PLAN_JSON NEW_REPAIR_PLAN_JSON\n       mndocmove retarget ROOT PAIRS_JSON NEW_PLAN_JSON [--static-html]\n       mndocmove merge ROOT LEFT_PLAN RIGHT_PLAN NEW_PLAN_JSON\n       mndocmove extend ROOT SAVED_PLAN MOVES_JSON NEW_CHAIN_JSON [--static-html|--commonmark]\n       mndocmove check ROOT PLAN_JSON [--result]\n       mndocmove review PLAN_JSON [CONTEXT_LINES]\n       mndocmove replay ROOT PLAN_JSON NEW_OUTPUT_DIRECTORY\n       mndocmove restore MIGRATED_ROOT PLAN_JSON NEW_OUTPUT_DIRECTORY",
        )
        println(
          "Planning commands also accept --profile NAME: commonmark, static-html, commonmark-root or static-html-root (see docs/rooted-urls.md).",
        )
        println(
          "       mndocmove audit-sarif ROOT MOVES_JSON ROOT_PREFIX NEW_SARIF [--profile NAME]",
        )
        println(
          "       mndocmove incoming ROOT TARGET [--recursive] [--profile NAME]",
        )
        println(
          "       mndocmove retarget-anchors ROOT MAP_JSON NEW_PLAN_JSON [--profile NAME]",
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
    ExportFailure(stage, reason) => {
      println(
        "ExportFailed: final output was not published; staging retained at " +
        stage +
        "\nCause: " +
        reason +
        "\nFix the cause and replay to an unused output path. Source files are unchanged.",
      )
      1
    }
    error => {
      println("IoError: " + @debug.to_string(error))
      1
    }
  }
}
