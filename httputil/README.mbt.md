# httputil

Low-level HTTP building blocks: case-insensitive headers, URL encoding,
form parsing, RFC-7231 dates, multipart bodies, and request-target
dissection.

This is the toolbox that Crescent uses to *implement* HTTP — it deliberately
does no I/O, no routing, and no state. Each function is a pure transform
over bytes, strings, or maps, which makes it easy to reuse outside the
framework (in tests, in custom protocol adapters, in scripts) and safe to
call anywhere without worrying about lifecycles.

This package provides:

- **Case-insensitive header helpers** — HTTP header field names are
  case-insensitive per RFC 9110, but `Map[String, String]` is case-sensitive.
  These helpers bridge the gap without allocating a lowercased key on every
  lookup.
- **URL encoding / form data** — percent-encoding, percent-decoding, and
  `application/x-www-form-urlencoded` parse/serialize.
- **HTTP-date formatting** — the exact format required by `Date`,
  `Last-Modified`, `Expires`, `If-Modified-Since`, and `If-Unmodified-Since`.
- **`multipart/form-data` parsing** — a streaming walker that decodes each
  part into a `MultipartFormValue` (optional filename, optional content
  type, body bytes).
- **Request-target parsing** — pull the path and query string out of any of
  the four request-target forms defined by RFC 7230 §5.3 (origin,
  absolute, authority, asterisk).

## Install

This package is included with `bobzhang/crescent`. Import it directly:

```
import {
  "bobzhang/crescent/httputil"
  ...
}
```

## Case-Insensitive Headers

HTTP header names like `Content-Type`, `content-type`, and `CONTENT-TYPE`
are the same header, but a `Map[String, String]` treats them as three
different keys. Calling `.get("Content-Type")` on a map that happens to
store `"content-type"` returns `None`, and a naive `headers.get(name)`
will silently miss headers set by a different middleware or a different
HTTP client.

These helpers do case-insensitive lookups, sets, and merges without
allocating a lowercased copy of the key on every call (they compare byte
by byte, skipping the ASCII case bit).

```mbt check
///|
test "get_header_case_insensitive tolerates any casing" {
  let headers : Map[String, String] = { "Content-Type": "application/json" }
  assert_eq(
    @httputil.get_header_case_insensitive(headers, "content-type"),
    Some("application/json"),
  )
  assert_eq(
    @httputil.get_header_case_insensitive(headers, "CONTENT-TYPE"),
    Some("application/json"),
  )
  assert_eq(@httputil.get_header_case_insensitive(headers, "Accept"), None)
}
```

### Setting without duplicates

`set_header_case_insensitive` replaces any existing entry that matches
case-insensitively, so the map never ends up holding both `Content-Type`
*and* `content-type` after two writes with different casing.

```mbt check
///|
test "set_header_case_insensitive replaces existing entry" {
  let headers : Map[String, String] = { "Content-Type": "text/html" }
  @httputil.set_header_case_insensitive(
    headers, "content-type", "application/json",
  )
  assert_eq(headers.length(), 1)
  assert_eq(
    @httputil.get_header_case_insensitive(headers, "Content-Type"),
    Some("application/json"),
  )
}
```

### Set-only-if-missing

`set_missing_header_case_insensitive` is the "first writer wins" variant —
useful for middleware that wants to provide a default without clobbering a
value the handler already set:

```mbt check
///|
test "set_missing_header_case_insensitive does not overwrite" {
  let headers : Map[String, String] = { "Content-Type": "text/html" }
  @httputil.set_missing_header_case_insensitive(
    headers, "Content-Type", "application/json",
  )
  // original value preserved
  assert_eq(
    @httputil.get_header_case_insensitive(headers, "Content-Type"),
    Some("text/html"),
  )
}
```

### Appending to `Vary`-style headers

Some headers (`Vary`, `Accept-Encoding`, `Connection`) hold a
comma-separated list of tokens. `append_token_case_insensitive` adds a
token to such a header exactly once — if the token is already present, it
is a no-op, and if the header doesn't exist yet, it is created.

```mbt check
///|
test "append_token_case_insensitive deduplicates" {
  let headers : Map[String, String] = Map([])
  @httputil.append_token_case_insensitive(headers, "Vary", "Origin")
  @httputil.append_token_case_insensitive(headers, "Vary", "Origin") // duplicate, ignored
  @httputil.append_token_case_insensitive(headers, "Vary", "Accept-Encoding")
  assert_eq(
    @httputil.get_header_case_insensitive(headers, "Vary"),
    Some("Origin, Accept-Encoding"),
  )
}
```

## URL Encoding and Form Data

`url_encode` percent-encodes every byte that is not an RFC 3986 *unreserved*
character (`A-Z a-z 0-9 - _ . ~`). It's the right helper for building query
strings and form bodies:

```mbt check
///|
test "url_encode escapes reserved characters" {
  assert_eq(@httputil.url_encode("hello world"), "hello%20world")
  assert_eq(@httputil.url_encode("a+b=c"), "a%2Bb%3Dc")
  assert_eq(@httputil.url_encode("safe-._~"), "safe-._~")
}
```

`url_decode` is its inverse, and additionally converts `+` to space so it
accepts both query-string (`key=hello+world`) and percent-encoded (`%20`)
inputs:

```mbt check
///|
test "url_decode handles both + and %20" {
  assert_eq(@httputil.url_decode(@utf8.encode("hello+world")[:]), "hello world")
  assert_eq(
    @httputil.url_decode(@utf8.encode("hello%20world")[:]),
    "hello world",
  )
}
```

`url_decode` is byte-oriented because percent-encoded URLs are byte streams
(the encoded form `%E4%BD%A0` represents three raw UTF-8 bytes that *together*
make `你`). For callers that already hold a `StringView` — query strings,
URI path segments, route params — `url_decode_str` is a one-line wrapper that
re-encodes once and dispatches to `url_decode`:

```mbt check
///|
test "url_decode_str takes a StringView directly" {
  assert_eq(@httputil.url_decode_str("hello%20world"), "hello world")
  // RFC 3986 mandates non-ASCII bytes are percent-escaped, so the wrapper
  // round-trips multi-byte sequences correctly:
  assert_eq(@httputil.url_decode_str("%E4%BD%A0%E5%A5%BD"), "你好")
}
```

`parse_form_data` splits an `application/x-www-form-urlencoded` body into a
map; `form_encode` is the inverse:

```mbt check
///|
test "parse_form_data parses key=value pairs" {
  let body = @utf8.encode("name=alice&city=New%20York")
  let form = @httputil.parse_form_data(body[:])
  assert_eq(form.get("name"), Some("alice"))
  assert_eq(form.get("city"), Some("New York"))
}
```

`parse_form_data_str` is the matching `StringView` wrapper for callers that
have a query string in hand (e.g. from a parsed URI):

```mbt check
///|
test "parse_form_data_str takes a StringView" {
  let form = @httputil.parse_form_data_str("name=alice&city=New%20York")
  assert_eq(form.get("name"), Some("alice"))
  assert_eq(form.get("city"), Some("New York"))
}
```

## HTTP Date Format

The HTTP-date format defined in RFC 7231 is slightly different from any
calendar library you might already have — it always uses GMT, always uses
the RFC 1123 format (`"Sun, 06 Nov 1994 08:49:37 GMT"`), and insists on
fixed-width day numbers. `format_http_date` takes a Unix epoch timestamp
(seconds) and produces exactly that string:

```mbt check
///|
test "format_http_date produces RFC 1123 output" {
  assert_eq(@httputil.format_http_date(0L), "Thu, 01 Jan 1970 00:00:00 GMT")
  assert_eq(
    @httputil.format_http_date(1_709_251_199L),
    "Thu, 29 Feb 2024 23:59:59 GMT",
  )
}
```

`parse_http_date` is the inverse, and is strict about the format: any
deviation returns `None` rather than trying to guess. This matters for
`If-Modified-Since` handling, where a malformed date should be treated as
"no precondition" instead of a silently wrong timestamp:

```mbt check
///|
test "parse_http_date rejects invalid input" {
  assert_eq(
    @httputil.parse_http_date("Thu, 01 Jan 1970 00:00:00 GMT"),
    Some(0L),
  )
  // 31 Feb is not a real day
  assert_eq(@httputil.parse_http_date("Thu, 31 Feb 2024 00:00:00 GMT"), None)
  // random garbage
  assert_eq(@httputil.parse_http_date("yesterday"), None)
}
```

## Multipart Form Data

`parse_multipart` walks a `multipart/form-data` body and returns a
`Map[String, Array[MultipartFormValue]]`. Each value carries the raw bytes
plus an optional filename and content type. The returned map stores
**arrays** because a single field name can legally appear multiple times
(e.g. a form with several `<input name="tag">` fields).

```mbt check
///|
test "parse_multipart extracts fields and files" {
  let body = "--B\r\n" +
    "Content-Disposition: form-data; name=\"field1\"\r\n\r\n" +
    "hello\r\n" +
    "--B\r\n" +
    "Content-Disposition: form-data; name=\"avatar\"; filename=\"a.png\"\r\n" +
    "Content-Type: image/png\r\n\r\n" +
    "PNGDATA\r\n" +
    "--B--"
  let bytes = @utf8.encode(body)
  let parts = @httputil.parse_multipart(bytes[:], "B")

  // Simple text field
  guard @httputil.first_multipart_value(parts, "field1") is Some(field1) else {
    fail("expected field1")
  }
  assert_eq(field1.filename, None)
  assert_eq(@utf8.decode(field1.data) catch { _ => "" }, "hello")

  // File upload
  guard @httputil.first_multipart_value(parts, "avatar") is Some(avatar) else {
    fail("expected avatar")
  }
  assert_eq(avatar.filename, Some("a.png"))
  assert_eq(avatar.content_type, Some("image/png"))
  assert_eq(@utf8.decode(avatar.data) catch { _ => "" }, "PNGDATA")
}
```

Use `first_multipart_value` when you know a field occurs at most once —
it's a convenience wrapper over `parts.get(name).and_then(arr => arr[0])`.
For fields that can repeat, iterate the array directly.

### Tricky cases the parser handles

- **Quoted semicolons** — `name="a;b"` is one name, not two fields.
- **Colons in content types** — `Content-Type: application/foo; bar=a:b`
  preserves the inner colon instead of treating it as a new header.
- **Unquoted disposition values** — `name=field1` (no quotes) is parsed the
  same as `name="field1"`.

## Request-Target Parsing

HTTP servers see request lines like `GET /search?q=hello#frag HTTP/1.1` —
but RFC 7230 actually defines *four* request-target forms:

| Form | Example | When |
| ---- | ------- | ---- |
| origin-form | `/search?q=hello` | normal requests |
| absolute-form | `http://example.com/search?q=hello` | proxy requests, HTTP/1.0 |
| authority-form | `example.com:443` | `CONNECT` tunnels |
| asterisk-form | `*` | `OPTIONS *` (server-wide) |

`request_target_path` and `request_target_query_string` hide that
complexity behind two pure functions that work on any form:

```mbt check
///|
test "request_target_path handles every form" {
  // origin-form
  assert_eq(@httputil.request_target_path("/search?q=hello"), "/search")
  // absolute-form (proxy / HTTP/1.0)
  assert_eq(
    @httputil.request_target_path("http://example.com/users/42"),
    "/users/42",
  )
  // absolute-form with no path
  assert_eq(@httputil.request_target_path("http://example.com"), "/")
  // query and fragment are both stripped from the path
  assert_eq(@httputil.request_target_path("/page?q=1#frag"), "/page")
}
```

```mbt check
///|
test "request_target_query_string separates the query" {
  assert_eq(
    @httputil.request_target_query_string("/search?q=hello"),
    Some("q=hello"),
  )
  // no query
  assert_eq(@httputil.request_target_query_string("/"), None)
  // fragment after query is stripped
  assert_eq(@httputil.request_target_query_string("/a?x=1#frag"), Some("x=1"))
}
```

### Path normalization

`normalize_path` collapses consecutive `/` characters in a URL path to a
single slash. This is what `request_target_path` uses internally to turn
`/a//b` into `/a/b` — important for dispatch, because routing tables are
defined with single slashes and clients sometimes construct paths by
string-concatenating prefixes:

```mbt check
///|
test "normalize_path collapses double slashes" {
  assert_eq(@httputil.normalize_path("/a/b"), "/a/b")
  assert_eq(@httputil.normalize_path("/a//b"), "/a/b")
  assert_eq(@httputil.normalize_path("//foo"), "/foo")
  assert_eq(@httputil.normalize_path("/a///b////c"), "/a/b/c")
}
```

### Scope matching

`path_scope_matches` tests whether a request path falls under a
**directory-like** scope path. Unlike a plain `has_prefix` check, it
requires the match to end on a segment boundary — so `/api` matches
`/api/users` but *not* `/apiX`, which is how mounted sub-apps avoid
accidentally handling a sibling route:

```mbt check
///|
test "path_scope_matches respects segment boundaries" {
  assert_true(@httputil.path_scope_matches("/api", "/api"))
  assert_true(@httputil.path_scope_matches("/api", "/api/users"))
  // '/apiX' is NOT under '/api' — different segment
  assert_false(@httputil.path_scope_matches("/api", "/apiX"))
  // the root scope matches everything
  assert_true(@httputil.path_scope_matches("/", "/anything"))
}
```
