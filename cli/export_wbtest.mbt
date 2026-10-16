///|
async test "staging reservation is unique and stays beside the destination" {
  let tmp = @fs.tmpdir(prefix="mndocmove-stage-test-")
  let first = reserve_stage(tmp + "/output")
  let second = reserve_stage(tmp + "/output")
  assert_true(first != second)
  assert_true(first.has_prefix(tmp + "/.mndocmove-stage-"))
  assert_true(second.has_prefix(tmp + "/.mndocmove-stage-"))
  assert_true(!@fs.exists(tmp + "/output"))
}

///|
async test "publication rechecks exact bytes and protects the final path on mismatch" {
  let tmp = @fs.tmpdir(prefix="mndocmove-verify-test-")
  let payload = tmp + "/payload"
  let target = tmp + "/output"
  @fs.mkdir(payload)
  @fs.write_file(payload + "/a.bin", b"wrong", create_mode=CreateNew)
  let expected = @lib.DocTree::new([@lib.Entry::new("a.bin", b"\xFF\x00")])
  let refused = try {
    publish_staged(payload, target, expected)
    false
  } catch {
    CliError(message) => message.has_prefix("StagingMismatch")
    _ => false
  }
  assert_true(refused)
  assert_true(!@fs.exists(target))
  assert_eq(@fs.read_file(payload + "/a.bin").binary(), b"wrong")
  // Recovery uses the same publisher after correcting the staged content.
  @fs.write_file(payload + "/a.bin", b"\xFF\x00", create_mode=TruncateExisting)
  publish_staged(payload, target, expected)
  assert_true(!@fs.exists(payload))
  assert_eq(@fs.read_file(target + "/a.bin").binary(), b"\xFF\x00")
}

///|
async test "extra and missing staged files refuse publication" {
  let tmp = @fs.tmpdir(prefix="mndocmove-inventory-test-")
  let payload = tmp + "/payload"
  let target = tmp + "/output"
  @fs.mkdir(payload)
  let expected = @lib.DocTree::new([@lib.Entry::new("a.bin", b"A")])
  let missing = try {
    publish_staged(payload, target, expected)
    false
  } catch {
    CliError(message) => message.has_prefix("StagingMismatch")
    _ => false
  }
  assert_true(missing)
  @fs.write_file(payload + "/a.bin", b"A", create_mode=CreateNew)
  @fs.write_file(payload + "/extra.bin", b"extra", create_mode=CreateNew)
  let extra = try {
    publish_staged(payload, target, expected)
    false
  } catch {
    CliError(message) => message.has_prefix("StagingMismatch")
    _ => false
  }
  assert_true(extra)
  assert_true(!@fs.exists(target))
}

///|
async test "empty staged directories refuse publication and can be removed for recovery" {
  let tmp = @fs.tmpdir(prefix="mndocmove-empty-stage-test-")
  let payload = tmp + "/payload"
  let target = tmp + "/output"
  let expected = @lib.DocTree::new([@lib.Entry::new("a.bin", b"\xFF\x00")])
  @fs.mkdir(payload)
  @fs.write_file(payload + "/a.bin", b"\xFF\x00", create_mode=CreateNew)
  @fs.mkdir(payload + "/empty")
  let refused = try {
    publish_staged(payload, target, expected)
    false
  } catch {
    CliError(message) => message.has_prefix("EmptyDirectory:")
    _ => false
  }
  assert_true(refused)
  assert_true(!@fs.exists(target))
  assert_true(@fs.exists(payload + "/empty"))
  assert_eq(@fs.read_file(payload + "/a.bin").binary(), b"\xFF\x00")
  @fs.rmdir(payload + "/empty", recursive=false)
  publish_staged(payload, target, expected)
  assert_true(!@fs.exists(payload))
  assert_true(read_tree(target).entries() == expected.entries())
}

///|
async test "no-replace publication preserves both an existing empty directory and file" {
  let tmp = @fs.tmpdir(prefix="mndocmove-no-replace-test-")
  let payload = tmp + "/payload"
  let expected = @lib.DocTree::new([@lib.Entry::new("a.bin", b"A")])
  @fs.mkdir(payload)
  @fs.write_file(payload + "/a.bin", b"A", create_mode=CreateNew)
  @fs.mkdir(tmp + "/existing-directory")
  let directory_refused = try {
    publish_staged(payload, tmp + "/existing-directory", expected)
    false
  } catch {
    _ => true
  }
  assert_true(directory_refused)
  assert_eq(@fs.readdir(tmp + "/existing-directory").length(), 0)
  @fs.write_file(tmp + "/existing-file", b"keep", create_mode=CreateNew)
  let file_refused = try {
    publish_staged(payload, tmp + "/existing-file", expected)
    false
  } catch {
    _ => true
  }
  assert_true(file_refused)
  assert_eq(@fs.read_file(tmp + "/existing-file").binary(), b"keep")
  assert_eq(@fs.read_file(payload + "/a.bin").binary(), b"A")
}

///|
async test "full export preserves reserved-looking user paths and removes only staging metadata" {
  let tmp = @fs.tmpdir(prefix="mndocmove-export-test-")
  let root = tmp + "/source"
  let target = tmp + "/output"
  @fs.mkdir(root)
  let tree = @lib.DocTree::new([
    @lib.Entry::new(".mndocmove-incomplete", b"user data"),
    @lib.Entry::new("asset.bin", b"\xFF\x00"),
    @lib.Entry::markdown("docs/r.md", "UTF-8 中文\r\n"),
  ])
  export_tree(root, target, tree)
  assert_true(read_tree(target).entries() == tree.entries())
  assert_true(
    !@fs.readdir(tmp, include_hidden=true).any(fn(name) {
      name.has_prefix(".mndocmove-stage-")
    }),
  )
  assert_eq(@fs.readdir(root).length(), 0)
}

///|
async test "output containment normalizes every separator in absolute paths" {
  let tmp = @fs.tmpdir(prefix="mndocmove-separators-test-")
  let root = tmp + "/source"
  @fs.mkdir(root + "/nested/deep", recursive=true)
  @fs.write_file(
    root + "/nested/deep/asset.bin",
    b"\x00\x80\xFF",
    create_mode=CreateNew,
  )
  let original = read_tree(root)
  let inside = root + "/nested/deep/out"
  for output in [inside, inside.replace_all(old="/", new="\\")] {
    let refused = try {
      ignore(outside_path(root, output))
      false
    } catch {
      CliError(message) => message.has_prefix("OutputInsideRoot:")
      _ => false
    }
    assert_true(refused)
  }
  assert_true(!@fs.exists(inside))
  let target = tmp + "/outside-output"
  let backslash_target = target.replace_all(old="/", new="\\")
  export_tree(root, backslash_target, original)
  assert_true(read_tree(target).entries() == original.entries())
  assert_eq(
    @fs.read_file(target + "/nested/deep/asset.bin").binary(),
    b"\x00\x80\xFF",
  )
  assert_true(read_tree(root).entries() == original.entries())
}
