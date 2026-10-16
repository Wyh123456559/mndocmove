///|
fn media_tag(tag : String) -> Bool {
  tag == "video" || tag == "audio"
}

///|
fn html_url_attribute(tag : String, attr : String) -> Bool {
  (tag == "a" && attr == "href") ||
  (tag == "img" && attr == "src") ||
  (media_tag(tag) && attr == "src") ||
  (tag == "video" && attr == "poster") ||
  ((tag == "source" || tag == "track") && attr == "src")
}

///|
fn html_boolean_attribute(tag : String, attr : String) -> Bool {
  (tag == "details" && attr == "open") ||
  (media_tag(tag) && ["controls", "autoplay", "loop", "muted"].contains(attr)) ||
  (tag == "video" && attr == "playsinline") ||
  (tag == "track" && attr == "default")
}

///|
fn media_attribute(tag : String, attr : String) -> Bool {
  html_boolean_attribute(tag, attr) ||
  (media_tag(tag) && (attr == "preload" || attr == "crossorigin")) ||
  (tag == "track" && ["kind", "srclang", "label"].contains(attr))
}

///|
// Enumerated/boolean forms are checked without normalizing accepted source.
// Language labels remain opaque metadata; this is not a BCP47/DOM validator.
fn validate_media_attribute(
  tag : String,
  attr : String,
  raw : String,
  path : String,
  offset : Int32,
) -> Unit raise MoveError {
  let value = raw.to_lower()
  if html_boolean_attribute(tag, attr) && tag != "details" {
    if !raw.is_empty() && value != attr {
      html_fail(
        path, offset, "Boolean media values must be empty or the attribute name; false does not disable a boolean attribute",
      )
    }
  } else if media_tag(tag) && attr == "preload" {
    if !["", "none", "metadata", "auto"].contains(value) {
      html_fail(path, offset, "Use preload='', none, metadata or auto")
    }
  } else if media_tag(tag) && attr == "crossorigin" {
    if !["", "anonymous", "use-credentials"].contains(value) {
      html_fail(
        path, offset, "Use crossorigin='', anonymous or use-credentials",
      )
    }
  } else if tag == "track" && attr == "kind" {
    if !["subtitles", "captions", "descriptions", "chapters", "metadata"].contains(
        value,
      ) {
      html_fail(
        path, offset, "Use a supported track kind: subtitles, captions, descriptions, chapters or metadata",
      )
    }
  }
}
