// HTTP-header logic for static asset serving: Accept-Encoding parsing,
// ETag / If-None-Match / If-Modified-Since validation, and the header
// maps that go on 200 OK and 304 Not Modified responses.

/// Parses a single Accept-Encoding token, returning the encoding name
/// or `None` if the q-value is 0 (meaning the client explicitly refuses it).
/// Examples:
///   "gzip"           -> Some("gzip")
///   "gzip; q=0.8"    -> Some("gzip")
///   "gzip;q=0"       -> None
///   "br;q=0.0"       -> None

///|
fn parse_accept_encoding_token(token : StringView) -> String? {
  let (name, rest) = match token.find(";") {
    Some(index) =>
      (
        token[:index].trim(chars=" ").to_owned().to_lower(),
        Some(token[index + 1:]),
      )
    None => (token.trim(chars=" ").to_owned().to_lower(), None)
  }
  // Check q-value — if explicitly 0, refuse this encoding.
  match rest {
    Some(params) =>
      for param in params.split(";") {
        let trimmed = param.trim(chars=" ")
        if trimmed.has_prefix("q=") || trimmed.has_prefix("Q=") {
          let qval = trimmed[2:].trim(chars=" ").to_owned()
          // q=0, q=0.0, q=0.00, etc. means refused.
          if qval == "0" || qval == "0.0" || qval == "0.00" || qval == "0.000" {
            return None
          }
        }
      }
    None => ()
  }
  Some(name)
}

///|
test "parse_accept_encoding_token strips whitespace and lowercases" {
  debug_inspect(parse_accept_encoding_token("gzip"), content="Some(\"gzip\")")
  debug_inspect(
    parse_accept_encoding_token("  gzip  "),
    content="Some(\"gzip\")",
  )
  debug_inspect(
    parse_accept_encoding_token("gzip;q=0.8"),
    content="Some(\"gzip\")",
  )
  debug_inspect(parse_accept_encoding_token("BR"), content="Some(\"br\")")
}

///|
test "parse_accept_encoding_token rejects q=0" {
  debug_inspect(parse_accept_encoding_token("gzip;q=0"), content="None")
  debug_inspect(parse_accept_encoding_token("gzip; q=0.0"), content="None")
  debug_inspect(parse_accept_encoding_token("br;q=0.00"), content="None")
  // Non-zero q-values are accepted
  debug_inspect(
    parse_accept_encoding_token("gzip;q=0.5"),
    content="Some(\"gzip\")",
  )
  debug_inspect(
    parse_accept_encoding_token("gzip;q=1.0"),
    content="Some(\"gzip\")",
  )
}

///|
fn normalize_etag_token(token : StringView) -> String {
  let trimmed = token.trim(chars=" ")
  if trimmed.length() >= 2 &&
    (trimmed.has_prefix("W/") || trimmed.has_prefix("w/")) {
    trimmed[2:].trim(chars=" ").to_owned()
  } else {
    trimmed.to_owned()
  }
}

///|
test "normalize_etag_token strips weak prefix and whitespace" {
  debug_inspect(
    normalize_etag_token("\"abc\""),
    content=(
      #|"\"abc\""
    ),
  )
  debug_inspect(
    normalize_etag_token("W/\"abc\""),
    content=(
      #|"\"abc\""
    ),
  )
  debug_inspect(
    normalize_etag_token("w/\"abc\""),
    content=(
      #|"\"abc\""
    ),
  )
  debug_inspect(
    normalize_etag_token("  \"abc\"  "),
    content=(
      #|"\"abc\""
    ),
  )
}

///|
fn if_none_match_matches(header_value : String, etag : String) -> Bool {
  for token in header_value.split(",") {
    let normalized = normalize_etag_token(token)
    if normalized == "*" || normalized == etag {
      return true
    }
  }
  false
}

///|
test "if_none_match_matches checks single, wildcard, list, and weak etag" {
  // single match
  assert_eq(if_none_match_matches("\"abc\"", "\"abc\""), true)
  // wildcard
  assert_eq(if_none_match_matches("*", "\"abc\""), true)
  // comma-separated list with match
  assert_eq(if_none_match_matches("\"aaa\", \"abc\", \"zzz\"", "\"abc\""), true)
  // no match
  assert_eq(if_none_match_matches("\"aaa\", \"bbb\"", "\"abc\""), false)
  // weak etag in list
  assert_eq(if_none_match_matches("W/\"aaa\", W/\"abc\"", "\"abc\""), true)
}

///|
fn static_asset_headers(
  provider : &ServeStaticProvider,
  id : String,
  meta : StaticAssetMeta,
) -> Map[String, String] {
  let headers : Map[String, String] = {}
  match meta.etag {
    Some(etag) => headers.set("ETag", etag)
    None => ()
  }
  match meta.mtime {
    Some(mtime) =>
      headers.set("Last-Modified", @httputil.format_http_date(mtime))
    None => ()
  }
  match meta.asset_type {
    Some(t) => headers.set("Content-Type", t)
    None => {
      let parts = id.split(".").collect()
      if parts.length() > 1 {
        match provider.get_type(parts[parts.length() - 1].to_owned()) {
          Some(t) => headers.set("Content-Type", t)
          None => ()
        }
      }
    }
  }
  match meta.encoding {
    Some(enc) => headers.set("Content-Encoding", enc)
    None => ()
  }
  match meta.size {
    Some(size) => headers.set("Content-Length", size.to_string())
    None => ()
  }
  headers
}

///|
fn static_not_modified_headers(
  response_headers : Map[String, String],
  meta : StaticAssetMeta,
) -> Map[String, String] {
  let headers = @httputil.copy_headers(response_headers)
  match meta.etag {
    Some(etag) => headers.set("ETag", etag)
    None => ()
  }
  match meta.mtime {
    Some(mtime) =>
      headers.set("Last-Modified", @httputil.format_http_date(mtime))
    None => ()
  }
  headers
}

///|
fn if_modified_since_matches(header_value : String, mtime : Int64) -> Bool {
  match @httputil.parse_http_date(header_value) {
    Some(if_modified_since) => if_modified_since >= mtime
    None => false
  }
}
