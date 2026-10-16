///|
// A fixed-length name avoids overflowing the destination leaf's component
// length. Exclusive mkdir reserves each unpredictable sibling directory.
async fn reserve_stage(target : String) -> String {
  let mut slash = -1
  for i in 0..<target.length() {
    if target[i] == 47 {
      slash = i
    }
  }
  if slash < 0 {
    stop("OutputPath: staging requires a resolved absolute destination")
  }
  let parent = target[:slash].to_owned()
  for _ in 0..<8 {
    let entropy = match @env.rand(16) {
      Some(bytes) => bytes
      None => {
        stop(
          "EntropyUnavailable: cannot reserve a staging directory on this host",
        )
        b""
      }
    }
    let suffix = StringBuilder()
    for byte in entropy {
      let value = byte.to_int()
      suffix.write_view("0123456789abcdef"[value / 16:value / 16 + 1])
      suffix.write_view("0123456789abcdef"[value % 16:value % 16 + 1])
    }
    let stage = parent + "/.mndocmove-stage-" + suffix.to_string()
    if @fs.exists(stage) {
      continue
    }
    @fs.mkdir(stage, permission=0o700)
    return stage
  }
  stop(
    "StagingCollision: could not reserve a fresh directory after eight attempts",
  )
  abort("unreachable")
}

///|
// replace=false uses the dependency's no-replace rename primitive. A target
// created after the early existence check is still protected at publication.
async fn publish_staged(
  payload : String,
  target : String,
  expected : @lib.DocTree,
) -> Unit {
  let actual = read_tree(payload)
  if actual.entries() != expected.entries() {
    stop(
      "StagingMismatch: file inventory or bytes differ from the planned output",
    )
  }
  @fs.rename(payload, target, replace=false)
}
