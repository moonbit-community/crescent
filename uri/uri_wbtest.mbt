///|
test "RFC 3986 URI Reference Parsing" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(
    parse_uri_reference(
      "http://example.com/path/to/resource?query=parameter#fragment", uri,
    ),
    "",
  )
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: Some(<StringView: "http">),
      #|  authority: Some(
      #|    {
      #|      userinfo: None,
      #|      host: RegName(<StringView: "example.com">),
      #|      port: None,
      #|    },
      #|  ),
      #|  path: [<StringView: "path">, <StringView: "to">, <StringView: "resource">],
      #|  query: Some(<StringView: "query=parameter">),
      #|  fragment: Some(<StringView: "fragment">),
      #|}
    ),
  )
  // assert_eq(uri.scheme, Some("http"))
  // assert_eq(
  //   uri.authority,
  //   Some({ userinfo: None, host: RegName("example.com"), port: None }),
  // )
  // assert_eq(uri.path, ["path", "to", "resource"])
  // assert_eq(uri.query, Some("query=parameter"))
  // assert_eq(uri.fragment, Some("fragment"))
}

///|
test "RFC 3986 Authority with Userinfo and Port" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(
    parse_uri_reference("ftp://user:pass@ftp.example.com:21/path", uri),
    "",
  )
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: Some(<StringView: "ftp">),
      #|  authority: Some(
      #|    {
      #|      userinfo: Some(<StringView: "user:pass">),
      #|      host: RegName(<StringView: "ftp.example.com">),
      #|      port: Some(21),
      #|    },
      #|  ),
      #|  path: [<StringView: "path">],
      #|  query: None,
      #|  fragment: None,
      #|}
    ),
  )
  // assert_eq(uri.scheme, Some("ftp"))
  // assert_eq(
  //   uri.authority,
  //   Some({
  //     userinfo: Some("user:pass"),
  //     host: RegName("ftp.example.com"),
  //     port: Some(21),
  //   }),
  // )
  // assert_eq(uri.path, ["path"])
}

///|
test "RFC 3986 IPv6 Literal" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(parse_uri_reference("http://[2001:db8::1]:8080/", uri), "")
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: Some(<StringView: "http">),
      #|  authority: Some(
      #|    {
      #|      userinfo: None,
      #|      host: IPv6Address(<StringView: "2001:db8::1">),
      #|      port: Some(8080),
      #|    },
      #|  ),
      #|  path: [],
      #|  query: None,
      #|  fragment: None,
      #|}
    ),
  )
  // assert_eq(uri.scheme, Some("http"))
  // assert_eq(
  //   uri.authority,
  //   Some({ userinfo: None, host: IPv6Address("2001:db8::1"), port: Some(8080) }),
  // )
  // assert_eq(uri.path, [])
}

///|
test "RFC 3986 Percent Encoding Preservation" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(parse_uri_reference("http://example.com/hello%20world", uri), "")
  assert_eq(uri.scheme, Some("http"))
  assert_eq(uri.path, ["hello%20world"]) // preserved, not decoded
}

///|
test "RFC 3986 Relative Reference" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(parse_uri_reference("../path/file.txt", uri), "")
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: None,
      #|  authority: None,
      #|  path: [<StringView: "..">, <StringView: "path">, <StringView: "file.txt">],
      #|  query: None,
      #|  fragment: None,
      #|}
    ),
  )
  // assert_eq(uri.scheme, None)
  // assert_eq(uri.authority, None)
  // assert_eq(uri.path, ["..", "path", "file.txt"])
}

///|
test "RFC 3986 Absolute Path" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(parse_uri_reference("/absolute/path", uri), "")
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: None,
      #|  authority: None,
      #|  path: [<StringView: "absolute">, <StringView: "path">],
      #|  query: None,
      #|  fragment: None,
      #|}
    ),
  )
  // assert_eq(uri.scheme, None)
  // assert_eq(uri.authority, None)
  // assert_eq(uri.path, ["absolute", "path"])
}

///|
test "RFC 3986 Query Only" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(parse_uri_reference("?key=value&foo=bar", uri), "")
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: None,
      #|  authority: None,
      #|  path: [],
      #|  query: Some(<StringView: "key=value&foo=bar">),
      #|  fragment: None,
      #|}
    ),
  )
  // assert_eq(uri.scheme, None)
  // assert_eq(uri.authority, None)
  // assert_eq(uri.path, [])
  // assert_eq(uri.query, Some("key=value&foo=bar"))
}

///|
test "RFC 3986 Fragment Only" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(parse_uri_reference("#section1", uri), "")
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: None,
      #|  authority: None,
      #|  path: [],
      #|  query: None,
      #|  fragment: Some(<StringView: "section1">),
      #|}
    ),
  )
  // assert_eq(uri.scheme, None)
  // assert_eq(uri.authority, None)
  // assert_eq(uri.path, [])
  // assert_eq(uri.fragment, Some("section1"))
}

///|
test "RFC 3986 Character Classification" {
  // Test unreserved characters
  assert_eq(is_unreserved('A'), true)
  assert_eq(is_unreserved('z'), true)
  assert_eq(is_unreserved('0'), true)
  assert_eq(is_unreserved('-'), true)
  assert_eq(is_unreserved('.'), true)
  assert_eq(is_unreserved('_'), true)
  assert_eq(is_unreserved('~'), true)
  assert_eq(is_unreserved('!'), false)

  // Test gen-delims
  assert_eq(is_gen_delim(':'), true)
  assert_eq(is_gen_delim('/'), true)
  assert_eq(is_gen_delim('?'), true)
  assert_eq(is_gen_delim('#'), true)
  assert_eq(is_gen_delim('['), true)
  assert_eq(is_gen_delim(']'), true)
  assert_eq(is_gen_delim('@'), true)

  // Test sub-delims
  assert_eq(is_sub_delim('!'), true)
  assert_eq(is_sub_delim('$'), true)
  assert_eq(is_sub_delim('&'), true)
  assert_eq(is_sub_delim('\''), true)
  assert_eq(is_sub_delim('('), true)
  assert_eq(is_sub_delim(')'), true)
  assert_eq(is_sub_delim('*'), true)
  assert_eq(is_sub_delim('+'), true)
  assert_eq(is_sub_delim(','), true)
  assert_eq(is_sub_delim(';'), true)
  assert_eq(is_sub_delim('='), true)
}

///|
test "RFC 3986 Dot Segment Removal" {
  let path1 : Array[StringView] = ["a", "b", "c", ".", "..", "..", "g"]
  let result1 = remove_dot_segments(path1)
  assert_eq(result1, ["a", "g"])
  let path2 : Array[StringView] = ["..", "..", "a", "b"]
  let result2 = remove_dot_segments(path2)
  assert_eq(result2, ["a", "b"])
  let path3 : Array[StringView] = [".", "a", ".", "b", "."]
  let result3 = remove_dot_segments(path3)
  assert_eq(result3, ["a", "b"])
}

///|
test "parse_percent_encoding accepts only hex digits" {
  // Valid hex digits
  let ok1 : Result[StringView, ParseError] = try
    parse_percent_encoding("20 rest")
  catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  assert_true(ok1 is Ok(_))
  let ok2 : Result[StringView, ParseError] = try
    parse_percent_encoding("FF end")
  catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  assert_true(ok2 is Ok(_))
  let ok3 : Result[StringView, ParseError] = try
    parse_percent_encoding("ab end")
  catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  assert_true(ok3 is Ok(_))
  // Invalid: non-hex letters
  let bad1 : Result[StringView, ParseError] = try
    parse_percent_encoding("GG end")
  catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  assert_true(bad1 is Err(_))
  let bad2 : Result[StringView, ParseError] = try
    parse_percent_encoding("xz end")
  catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  assert_true(bad2 is Err(_))
  let bad3 : Result[StringView, ParseError] = try
    parse_percent_encoding("ZZ end")
  catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  assert_true(bad3 is Err(_))
}

///|
test "parse rejects URI with invalid percent encoding" {
  let bad : Result[Uri, ParseError] = try
    Uri("http://example.com/path%GG")
  catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  assert_true(bad is Err(_))
}

///|
test "parse accepts percent-encoded query" {
  // Regression test for percent-encoding bug in parse_query_then_fragment
  let ok : Result[Uri, ParseError] = try
    Uri("http://example.com/?q=a%20b")
  catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  assert_true(ok is Ok(_))
}

///|
test "parse accepts percent-encoded fragment" {
  // Regression test for percent-encoding bug in parse_fragment
  let ok : Result[Uri, ParseError] = try
    Uri("http://example.com/#sec%20tion")
  catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  assert_true(ok is Ok(_))
}

///|
test "parse accepts percent-encoded host" {
  // Regression test for percent-encoding bug in parse_reg_name
  let ok : Result[Uri, ParseError] = try Uri("http://ex%C3%A4mple.com/") catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  assert_true(ok is Ok(_))
}

///|
test "parse accepts bare relative reference" {
  // Regression test: previously "foo" raised InvalidSchemeOrSegment at EOF
  let ok1 : Result[Uri, ParseError] = try Uri("foo") catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  assert_true(ok1 is Ok(_))
  let ok2 : Result[Uri, ParseError] = try Uri(".") catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  assert_true(ok2 is Ok(_))
  let ok3 : Result[Uri, ParseError] = try Uri("..") catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  assert_true(ok3 is Ok(_))
}

///|
test "parse relative ref with fragment puts value in fragment, not query" {
  // Regression test: "foo#bar" previously put "bar" in query field
  let uri = Uri("foo#bar")
  assert_eq(uri.query, None)
  assert_eq(uri.fragment, Some("bar"))
}

///|
test "RFC 3986 Absolute URI Parsing" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(
    parse_absolute_uri(
      "http://example.com/path/to/resource?query=parameter", uri,
    ),
    "",
  )
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: Some(<StringView: "http">),
      #|  authority: Some(
      #|    {
      #|      userinfo: None,
      #|      host: RegName(<StringView: "example.com">),
      #|      port: None,
      #|    },
      #|  ),
      #|  path: [<StringView: "path">, <StringView: "to">, <StringView: "resource">],
      #|  query: Some(<StringView: "query=parameter">),
      #|  fragment: None,
      #|}
    ),
  )
  // assert_eq(uri.scheme, Some("http"))
  // assert_eq(
  //   uri.authority,
  //   Some({ userinfo: None, host: RegName("example.com"), port: None }),
  // )
  // assert_eq(uri.path, ["path", "to", "resource"])
  // assert_eq(uri.query, Some("query=parameter"))
  // assert_eq(uri.fragment, None)
}
