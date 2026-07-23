# URI

An RFC 3986 URI-reference parser for MoonBit.

A Uniform Resource Identifier is the generalisation of the URLs you already
know: a string that identifies a resource by combining up to five
components — `scheme`, `authority`, `path`, `query`, and `fragment`. RFC 3986
is the canonical reference. This package parses any conformant URI-reference
into a structured `Uri` value you can inspect, validate, and route on.

## Anatomy of a URI

```
  foo://user:pass@example.com:8042/over/there?name=ferret#nose
  \_/   \________/\__________/\__/\_________/ \_________/ \__/
   |        |          |       |      |           |        |
scheme  userinfo     host    port   path        query   fragment
          \_______________________/
                     |
                 authority
```

- **scheme** — the protocol name (`http`, `ftp`, `mailto`, ...). Always
  followed by `:` and, if an authority follows, by `//`.
- **authority** — optional. Contains an optional `userinfo@`, a `host`
  (either an IPv6 literal in brackets or a reg-name like `example.com`),
  and an optional `:port`.
- **path** — an array of segments, empty for authority-only references.
- **query** — everything after `?`, everything before `#`.
- **fragment** — everything after `#`. Never sent to the server; resolved
  by the client.

Any of these components except the path may be absent. A bare `/index.html`
is a valid URI-reference (scheme and authority are `None`, path is
`["index.html"]`), as is `#section-2` (only the fragment is set).

## Design Notes

**Zero-copy.** All of `Uri`'s string-valued fields are `StringView` slices
into the original input. `Uri(source)` does not allocate a new string for
any component — it records offset ranges. This matters at HTTP server
scale, where every request parses a fresh URI.

**Percent-encoding is preserved.** The parser does *not* decode `%20` into
a space or `%E4%BD%A0` into `你`. The returned path segments, query, and
fragment contain the original characters verbatim. If you need decoded text,
run it through `@httputil.url_decode_str` after pulling the slice out. Why?
Because decoding loses information — `/foo%2Fbar` (one segment containing a
slash) and `/foo/bar` (two segments) are meaningfully different.

**Segment boundaries are recorded, not split.** The `path` field is an
`Array[StringView]`, one entry per path segment. Empty segments from
trailing slashes are dropped (`/a/b/` parses to `["a", "b"]`).

## Install

This package is included with `bobzhang/crescent`. Import it directly:

```
import {
  "bobzhang/crescent/uri"
  ...
}
```

## Parsing a Full URI

`Uri(source)` takes a `StringView` and returns a fully populated `Uri`, or
raises a `ParseError` if the input does not conform to the RFC 3986 grammar.

```mbt check
///|
test "parse a full http URL" {
  let uri = @uri.Uri("http://example.com/path/to/resource?q=hello#frag")
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
      #|  query: Some(<StringView: "q=hello">),
      #|  fragment: Some(<StringView: "frag">),
      #|}
    ),
  )
}
```

## Authority: Userinfo, Host, Port

The authority component lives in `uri.authority` as an optional `Authority`
struct. `userinfo` is the optional `user:pass` prefix, `host` is an enum
(`IPv6Address` or `RegName`), and `port` is the optional numeric port.
Host is exposed as an enum you pattern-match on rather than a plain string,
so the IPv6-vs-reg-name distinction is never lost:

```mbt check
///|
test "parse authority with userinfo and port" {
  let uri = @uri.Uri("ftp://admin:secret@files.example.com:2121/pub")
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: Some(<StringView: "ftp">),
      #|  authority: Some(
      #|    {
      #|      userinfo: Some(<StringView: "admin:secret">),
      #|      host: RegName(<StringView: "files.example.com">),
      #|      port: Some(2121),
      #|    },
      #|  ),
      #|  path: [<StringView: "pub">],
      #|  query: None,
      #|  fragment: None,
      #|}
    ),
  )
}
```

### IPv6 literals

IPv6 addresses must be wrapped in `[...]` to avoid the colon ambiguity with
the port. They come back as the `IPv6Address` variant of `Host`, so a
downstream consumer that needs to pass the host to a socket library can
branch on the variant without any string inspection:

```mbt check
///|
test "parse an IPv6 literal host" {
  let uri = @uri.Uri("http://[2001:db8::1]:8080/api")
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
      #|  path: [<StringView: "api">],
      #|  query: None,
      #|  fragment: None,
      #|}
    ),
  )
}
```

## Relative References

A URI-reference doesn't have to start with a scheme. RFC 3986 also accepts:

- **Absolute paths** — `/absolute/path`
- **Relative paths** — `../path/file.txt` or `file.txt`
- **Query-only** — `?key=value`
- **Fragment-only** — `#section`

All of these parse into a `Uri` where the missing components are `None`.

```mbt check
///|
test "parse an absolute-path reference" {
  let uri = @uri.Uri("/absolute/path")
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
}
```

```mbt check
///|
test "parse a relative reference with .. segments" {
  // Dot segments are preserved in the path — they are not resolved by the
  // parser. Apply your own normalization if you need it.
  let uri = @uri.Uri("../path/file.txt")
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
}
```

```mbt check
///|
test "parse a fragment-only reference" {
  let uri = @uri.Uri("#section-2")
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: None,
      #|  authority: None,
      #|  path: [],
      #|  query: None,
      #|  fragment: Some(<StringView: "section-2">),
      #|}
    ),
  )
}
```

## Percent-Encoding

The parser **preserves** percent-encoded sequences in path, query, and
fragment positions; it does not decode them. A path segment that contains
`%20` comes out with `%20` intact. This is deliberate — if you decode too
early, you can no longer tell whether a `/` in a path segment was literal
or encoded:

```mbt check
///|
test "percent-encoded sequences are preserved verbatim" {
  let uri = @uri.Uri("http://example.com/hello%20world")
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
      #|  path: [<StringView: "hello%20world">],
      #|  query: None,
      #|  fragment: None,
      #|}
    ),
  )
}
```

However, invalid percent-encodings (e.g. `%GG`, where `G` is not a hex
digit) are rejected at parse time because they cannot be interpreted
later. This turns a subtle decoding bug into a loud parse failure:

```mbt check
///|
test "invalid percent-encoding is rejected" {
  @test.assert_raise(() => @uri.Uri("http://example.com/path%GG"))
}
```

## Errors

`ParseError` tells you *what* went wrong and *where* it happened (the
`StringView` payload is a slice of the remaining input at the point of
failure, which is useful for error reporting).

| Variant | Meaning |
| ------- | ------- |
| `MissingScheme` | Input ended before a scheme could be read. |
| `MissingColon` | A scheme was started but never terminated by `:`. |
| `InvalidScheme(rest)` | A scheme contained an illegal character at `rest`. |
| `InvalidHeirPart(rest)` | The authority is malformed (userinfo or host). |
| `InvalidSegment(rest)` | A path segment contains a non-pchar character. |
| `InvalidPercentEncoding(rest)` | A `%` was followed by fewer than two hex digits, or non-hex characters. |
| `InvalidSchemeOrSegment(rest)` | Ambiguous failure in the scheme-or-segment-nz-nc prefix. |
| `Invalid(rest)` | Trailing garbage after an otherwise successful parse. |

Wrap calls in `try ... catch` to convert raises into `Result`:

```mbt check
///|
test "ParseError surfaces as a Result" {
  let ok : Result[@uri.Uri, @uri.ParseError] = try
    @uri.Uri("https://example.com/") |> Ok
  catch {
    error => Err(error)
  }
  assert_true(ok is Ok(_))

  let bad : Result[@uri.Uri, @uri.ParseError] = try
    @uri.Uri("http://example.com/path%GG") |> Ok
  catch {
    error => Err(error)
  }
  assert_true(bad is Err(_))
}
```

## What This Package Doesn't Do

- **No URL building / serialization.** `Uri` has no `to_string()`. If you
  need to construct URLs, use a buffer and `@httputil.url_encode`.
- **No percent decoding.** Use `@httputil.url_decode_str` on the `StringView`
  slices once you're ready to consume them as text.
- **No reference resolution.** Relative references like `../foo` are
  parsed verbatim; applying them to a base URI (the §5.3 algorithm) is
  left to the caller.
- **No IDN handling.** Host names are stored as raw bytes; if you accept
  internationalized domain names you need to Punycode them yourself.

Each of these omissions is deliberate — the parser's job is to cleanly
structure the input without paying the cost of operations most callers
don't need.
