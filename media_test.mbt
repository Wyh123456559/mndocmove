///|
fn media_tree(source : String) -> @mndocmove.DocTree raise {
  @mndocmove.DocTree::new([
    @mndocmove.Entry::markdown("README.md", source),
    @mndocmove.Entry::new("assets/clip.webm", b"\x1A\x45\xDF\xA3\x00\xFF"),
    @mndocmove.Entry::new("assets/clip.mp4", b"\x00\x00\x00\x18ftyp"),
    @mndocmove.Entry::new("assets/sound.mp3", b"\xFF\xFB\x00"),
    @mndocmove.Entry::new("assets/poster.svg", b"<svg/>"),
    @mndocmove.Entry::new(
      "assets/captions.vtt", b"WEBVTT\r\n\r\n00:00.000 --> 00:01.000\r\nassets/ stays literal\r\n",
    ),
  ])
}

///|
fn media_plan(
  tree : @mndocmove.DocTree,
) -> @mndocmove.MovePlan raise @mndocmove.MoveError {
  @mndocmove.plan_moves(
    tree,
    [
      @mndocmove.Move::new("README.md", "manual/README.md"),
      @mndocmove.Move::new("assets", "media"),
    ],
    profile=StaticHtml,
  )
}

///|
test "media sources poster tracks fallbacks and audio relocate as one preserved-source plan" {
  let source = "\uFEFF# 😀 Video\r\n\r\n<VIDEO controls PlaysInline muted='' loop='LOOP' preload='metadata' crossorigin='anonymous' poster='assets/poster.svg'>\r\n<source src='assets/clip.webm' type='video/webm'>\r\n<source SRC=\"assets/clip.mp4\" type='video/mp4'>\r\n<track default kind='captions' src='assets/captions.vtt' srclang='en' label='English'>\r\n<a href='assets/clip.webm'>Download</a>\r\n</VIDEO>\r\n\r\n<audio src='assets/sound.mp3' controls='controls' autoplay preload='none'></audio>"
  let tree = media_tree(source)
  let plan = media_plan(tree)
  assert_eq(plan.edits().length(), 6)
  for edit in plan.edits() {
    assert_eq(source[edit.start:edit.end].to_owned(), edit.before)
  }
  let wire = plan.to_json_string()
  let loaded = @mndocmove.MovePlan::from_json_string(wire)
  assert_eq(loaded.to_json_string(), wire)
  assert_eq(loaded.preview(), plan.preview())
  let output = loaded.replay(tree)
  assert_eq(
    output.get("manual/README.md").unwrap().text(),
    source.replace_all(old="assets/", new="../media/"),
  )
  for entry in tree.entries() {
    if entry.path().has_prefix("assets/") {
      assert_eq(
        output
        .get(entry.path().replace(old="assets/", new="media/"))
        .unwrap()
        .data(),
        entry.data(),
      )
    }
  }
  assert_true(loaded.review(context=0).contains("../media/captions.vtt"))
  assert_true(loaded.check(output, side=Result).is_match())
  assert_eq(loaded.restore(output).entries(), tree.entries())
  assert_eq(tree.get("README.md").unwrap().text(), source)
}

///|
test "direct video audio source URLs share percent entity fragment and external semantics" {
  let source = "<video src='assets/clip.mp4?start=1&amp;end=2#t=1,2' poster='assets/poster.svg' controls></video>\n\n<audio controls><source src='assets/sound.mp3' type='audio/mpeg'><source src='https://example.com/sound.ogg?x=1&amp;y=2'></audio>"
  let tree = media_tree(source)
  let plan = @mndocmove.plan_moves(
    tree,
    [@mndocmove.Move::new("assets", "new media/中文")],
    profile=StaticHtml,
  )
  assert_eq(plan.edits().length(), 3)
  assert_eq(
    plan.replay(tree).get("README.md").unwrap().text(),
    source.replace_all(old="assets/", new="new%20media/%E4%B8%AD%E6%96%87/"),
  )
  assert_eq(plan.restore(plan.replay(tree)).entries(), tree.entries())
}

///|
test "media selection metadata and all supported boolean forms remain literal" {
  for
    flags in [
      "controls autoplay loop muted playsinline", "controls='' autoplay='AUTOPLAY' loop=\"loop\" muted='' playsinline='playsinline'",
    ] {
    let source = "<video " +
      flags +
      " preload='' crossorigin='use-credentials' src='assets/clip.webm'><track default='DEFAULT' kind='subtitles' src='assets/captions.vtt' srclang='zh-TW' label='字幕'></video>"
    let tree = media_tree(source)
    assert_eq(
      media_plan(tree).replay(tree).get("manual/README.md").unwrap().text(),
      source.replace_all(old="assets/", new="../media/"),
    )
  }
  for preload in ["none", "metadata", "AUTO"] {
    let tree = media_tree(
      "<audio controls preload='" +
      preload +
      "' crossorigin='' src='assets/sound.mp3'></audio>",
    )
    assert_eq(media_plan(tree).edits().length(), 1)
  }
  for kind in ["subtitles", "captions", "descriptions", "chapters", "metadata"] {
    assert_eq(
      media_plan(
        media_tree("<track kind='" + kind + "' src='assets/captions.vtt'>"),
      )
      .edits()
      .length(),
      1,
    )
  }
}

///|
test "dynamic ambiguous and malformed media attributes refuse before any output then recover" {
  for
    source in [
      "<video src='assets/clip.webm' SRC='assets/clip.mp4'></video>", "<video src=assets/clip.webm></video>",
      "<video controls='false' src='assets/clip.webm'></video>", "<video autoplay='1'></video>",
      "<video preload='maybe'></video>", "<audio crossorigin='credentials'></audio>",
      "<video src=''></video>", "<video poster=''></video>", "<source src=''>", "<track src=''>",
      "<video src='{{clip}}'></video>", "<video onerror='handler()' src='assets/clip.webm'></video>",
      "<source src='assets/clip.webm' srcset='assets/clip.mp4 2x'>", "<source srcset='assets/clip.mp4 320w' src='assets/clip.webm' sizes='100vw'>",
      "<video srcset='assets/clip.webm 1x'></video>", "<track default='false' src='assets/captions.vtt'>",
      "<track kind='unknown' src='assets/captions.vtt'>", "<audio playsinline></audio>",
      "<audio poster='assets/poster.svg'></audio>", "<source controls src='assets/clip.webm'>",
      "<track kind src='assets/captions.vtt'>", "<video preload></video>", "<video style='background:url(assets/poster.svg)'></video>",
    ] {
    let tree = media_tree(source)
    expect_code(() => ignore(media_plan(tree)), "UnsupportedHtml")
    assert_eq(tree.get("README.md").unwrap().text(), source)
  }
  assert_eq(
    media_plan(media_tree("<video src='assets/clip.webm' controls></video>"))
    .edits()
    .length(),
    1,
  )
}

///|
test "media missing escaping and malformed URLs refuse while examples and comments stay literal" {
  for
    (url, code) in [
      ("missing.webm", "MissingTarget"),
      ("../outside.webm", "OutsideRoot"),
      ("/assets/clip.webm", "UnsupportedUrl"),
      ("assets/clip%2Fpart.webm", "AmbiguousEscape"),
    ] {
    let tree = media_tree("<video src='" + url + "' controls></video>")
    expect_code(() => ignore(media_plan(tree)), code)
  }
  let source = "`<video src='missing.webm' controls>`\n\n```html\n<audio src='missing.mp3'></audio>\n```\n\n<!-- <track src='missing.vtt'> -->\n\n<video src='assets/clip.webm' controls></video>"
  let tree = media_tree(source)
  expect_code(
    () => {
      ignore(
        @mndocmove.plan_moves(tree, [@mndocmove.Move::new("assets", "media")]),
      )
    },
    "UnsupportedMarkdown",
  )
  assert_eq(media_plan(tree).edits().length(), 1)
  assert_eq(
    media_plan(tree).replay(tree).get("manual/README.md").unwrap().text(),
    source.replace(old="src='assets/", new="src='../media/"),
  )
}

///|
test "media workflows compose and reject changed binary results before exact restoration" {
  let tree = media_tree(
    "<video src='assets/clip.webm' poster='assets/poster.svg' controls></video>",
  )
  let first = media_plan(tree)
  let chain = first.then_moves([@mndocmove.Move::new("media", "published")])
  let saved = @mndocmove.MoveChain::from_json_string(chain.to_json_string())
  let output = saved.replay(tree)
  assert_eq(
    output.get("manual/README.md").unwrap().text(),
    "<video src='../published/clip.webm' poster='../published/poster.svg' controls></video>",
  )
  let later = output
    .entries()
    .filter(fn(entry) { entry.path() != "published/clip.webm" })
  later.push(@mndocmove.Entry::new("published/clip.webm", b"later video edit"))
  let changed = @mndocmove.DocTree::new(later)
  assert_true(!saved.check(changed, side=Result).is_match())
  expect_code(() => ignore(saved.restore(changed)), "RestoreMismatch")
  assert_eq(
    changed.get("published/clip.webm").unwrap().data(),
    b"later video edit",
  )
  assert_eq(saved.restore(output).entries(), tree.entries())
}
