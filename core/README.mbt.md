# Core

The foundational HTTP types for Crescent: requests, responses, status codes,
methods, and the `Responder` trait that ties them together.

This package is a **pure data layer** -- it defines the types that flow through
the framework but performs no I/O, no routing, and no async work. That makes
it safe to import from any context: server handlers, middleware, fetch clients,
test assertions, or standalone scripts that construct HTTP values for
serialization.

The main `bobzhang/crescent` package re-exports everything in this package, so
application code can use either `@crescent.HttpResponse` or `@core.HttpResponse`
interchangeably. Sub-packages that want a lighter dependency (no App, no
server runtime) can import `bobzhang/crescent/core` directly.

This package provides:

- **HttpRequest** -- an incoming HTTP request (method, URL, headers, body) with
  helpers for path extraction, query parsing, cookie reading, and typed body
  deserialization.
- **HttpResponse** -- an outgoing HTTP response (status code, headers, cookies,
  body) with a fluent builder API and factory methods for common status codes.
- **StatusCode** -- a comprehensive enum covering every IANA-registered HTTP
  status code, plus a `Custom(Int)` escape hatch.
- **HttpMethod** -- an enum for standard HTTP methods (GET, POST, PUT, etc.)
  with string round-tripping.
- **Responder** -- a trait that any type can implement to become a valid
  response body. Built-in implementations for `String`, `Json`, `Bytes`,
  `HttpResponse`, `HttpRequest`, and `Html`.
- **BodyReader** -- a trait for deserializing request bodies into typed values.

## Install

This package is included with `bobzhang/crescent`. To use it directly for a
lighter dependency:

```
import {
  "bobzhang/crescent/core"
  ...
}
```

## HttpRequest

An `HttpRequest` bundles the HTTP method, URL, headers, and raw body bytes.
The framework constructs these from incoming TCP connections, but you can also
create them directly for testing or for building outgoing requests with
`@fetch.request`.

```mbt check
///|
test "construct and inspect a request" {
  let req = @core.HttpRequest(
    Get,
    "/users?page=2",
    { "Authorization": "Bearer token" },
    raw_body=b"",
  )
  debug_inspect(
    req,
    content=(
      #|{
      #|  http_method: Get,
      #|  url: "/users?page=2",
      #|  headers: { "Authorization": "Bearer token" },
      #|  raw_body: ...,
      #|  cached_path: None,
      #|  cached_query_params: None,
      #|}
    ),
  )
  assert_eq(req.path(), "/users")
  assert_eq(req.query_string(), Some("page=2"))
  assert_eq(req.get_query("page"), Some("2"))
  assert_eq(req.get_header("authorization"), Some("Bearer token"))
}
```

### Path and query parsing

`path()` extracts the URL path, stripping the query string and fragment.
`query_string()` returns the raw query portion. `get_query(key)` does a
decoded key lookup. All three cache their results so repeated calls are free.

```mbt check
///|
test "query parameters are percent-decoded" {
  let req = @core.HttpRequest(
      Get,
      "/search?q=hello%20world&lang=en",
      {},
      raw_body=b"",
    )
    |> x => { (x.get_query("q"), x.get_query("lang"), x.get_query("missing")) }
  debug_inspect(
    req,
    content=(
      #|(Some("hello world"), Some("en"), None)
    ),
  )
}
```

### Typed body reading

`req.body[T]()` deserializes the raw bytes into any type that implements the
`BodyReader` trait. Built-in readers exist for `String`, `Json`, `Bytes`,
`FixedArray[Byte]`, and `Array[Byte]`:

```mbt check
///|
test "read body as string" {
  let req = @core.HttpRequest(Post, "/", {}, raw_body=b"hello")
  let text : String = req.body()
  assert_eq(text, "hello")
}
```

```mbt check
///|
test "read body as JSON" {
  let req = @core.HttpRequest(Post, "/", {}, raw_body=b"{\"name\":\"Alice\"}")
  let body : Json = req.body()
  debug_inspect(
    body,
    content=(
      #|Object({ "name": String("Alice") })
    ),
  )
}
```

### JSON deserialization shorthand

`req.json[T]()` parses the body as JSON and deserializes into any
`FromJson` type in one step:

```mbt check
///|
#warnings("-unnecessary_annotation")
struct CoreDocUser {
  name : String
  age : Int
} derive(FromJson, Eq, Debug)

///|
test "json shorthand parses typed value" {
  let req = @core.HttpRequest(
    Post,
    "/",
    {},
    raw_body=b"{\"name\":\"Bob\",\"age\":30}",
  )
  let user : CoreDocUser = req.json()
  debug_inspect(
    user,
    content=(
      #|{ name: "Bob", age: 30 }
    ),
  )
}
```

### Cookie reading

`get_cookie(name)` parses the `Cookie` header (case-insensitive lookup) and
returns the matching `CookieItem`, or `None` if absent:

```mbt check
///|
test "read a cookie from the request" {
  let req = @core.HttpRequest(
    Get,
    "/",
    { "Cookie": "session=abc123; theme=dark" },
    raw_body=b"",
  )
  guard req.get_cookie("session") is Some(c) else {
    fail("expected session cookie")
  }
  assert_eq(c.value, "abc123")
  assert_eq(req.get_cookie("missing"), None)
}
```

## HttpResponse

An `HttpResponse` carries a status code, headers, cookies, and a body. Build
one with the constructor or the named factory methods, then chain `.body()`,
`.header()`, `.json()`, or `.json_value()` to finalize it.

### Factory methods

```mbt check
///|
test "factory methods set the right status code" {
  assert_eq(@core.HttpResponse::ok().status_code, OK)
  assert_eq(@core.HttpResponse::created().status_code, Created)
  assert_eq(@core.HttpResponse::not_found().status_code, NotFound)
  assert_eq(@core.HttpResponse::bad_request().status_code, BadRequest)
  assert_eq(
    @core.HttpResponse::internal_server_error().status_code,
    InternalServerError,
  )
}
```

### Fluent builder

```mbt check
///|
test "fluent response building" {
  let res = @core.HttpResponse::ok()
    .header("X-Request-Id", "abc-123")
    .body(@core.html("<h1>Hello</h1>"))
  assert_eq(res.status_code, OK)
  inspect(
    res.headers.get("Content-Type"),
    content="Some(\"text/html; charset=utf-8\")",
  )
  inspect(res.headers.get("X-Request-Id"), content="Some(\"abc-123\")")
}
```

### JSON responses

`json()` takes any `&ToJson` and `json_value()` takes a concrete `T : ToJson`.
Both set `Content-Type: application/json; charset=utf-8`:

```mbt check
///|
test "json response sets content type and body" {
  let res = @core.HttpResponse::ok().json(({ "status": "ok" } : Json))
  inspect(
    res.headers.get("Content-Type"),
    content="Some(\"application/json; charset=utf-8\")",
  )
}
```

### Redirects

```mbt check
///|
test "redirect helpers" {
  let r301 = @core.HttpResponse::redirect("/new")
  debug_inspect(
    r301,
    content=(
      #|{
      #|  status_code: MovedPermanently,
      #|  headers: { "Location": "/new" },
      #|  cookies: {},
      #|  raw_body: ...,
      #|}
    ),
  )

  let r302 = @core.HttpResponse::redirect_temporary("/temp")
  assert_eq(r302.status_code, Found)

  let r307 = @core.HttpResponse::redirect_307("/keep-method")
  assert_eq(r307.status_code, TemporaryRedirect)
}
```

### Cookies

`set_cookie` and `delete_cookie` manage response cookies with full attribute
support. The framework serializes them into `Set-Cookie` headers when sending
the response:

```mbt check
///|
test "set and delete cookies" {
  let res = @core.HttpResponse::ok()
  res.set_cookie("session", "xyz", path="/", http_only=true, secure=true)
  guard res.cookies.get("session") is Some(c) else {
    fail("expected session cookie")
  }
  assert_eq(c.value, "xyz")
  assert_eq(c.path, Some("/"))
  assert_eq(c.http_only, Some(true))

  // Deleting sets Max-Age=0
  res.delete_cookie("session")
  guard res.cookies.get("session") is Some(deleted) else {
    fail("expected deleted cookie")
  }
  assert_eq(deleted.max_age, Some(0))
}
```

### Error responses

`HttpResponse::error(status, message)` creates a JSON error body with the
status code and message, suitable for API error responses:

```mbt check
///|
test "error helper creates structured JSON body" {
  let res = @core.HttpResponse::error(BadRequest, "name is required")
  assert_eq(res.status_code, BadRequest)
  let body : String = res.read_body()
  assert_true(body.contains("name is required"))
  assert_true(body.contains("400"))
}
```

## StatusCode

A comprehensive enum covering every IANA-registered status code. Pattern match
on it directly -- no need to compare raw integers:

```mbt check
///|
test "status code round-trips through integer" {
  assert_eq(@core.StatusCode::from_int(200), OK)
  assert_eq(@core.StatusCode::from_int(404), NotFound)
  let ok : @core.StatusCode = OK
  assert_eq(ok.to_int(), 200)
  // Unknown codes become Custom
  assert_eq(@core.StatusCode::from_int(599), Custom(599))
}
```

## HttpMethod

```mbt check
///|
test "method round-trips through string" {
  assert_eq(@core.HttpMethod::from_string("GET"), Get)
  let get : @core.HttpMethod = Get
  assert_eq(get.to_method_string(), "GET")
  // Unknown methods use Other
  let custom = @core.HttpMethod::from_string("PURGE")
  assert_eq(custom.to_method_string(), "PURGE")
}
```

## Traits

This package defines two open traits that drive polymorphic request and
response handling: `Responder` (any value → HTTP response body) and
`BodyReader` (request/response bytes → typed value). Both are `pub(open)`,
so user code is free to add new implementations.

### trait Responder

```moonbit nocheck
///|
pub(open) trait Responder {
  fn options(Self, HttpResponse) -> Unit
  fn output(Self, Buffer) -> Unit
  fn output_bytes(Self) -> Bytes?
}
```

The `Responder` trait is the adapter between any MoonBit value and an HTTP
response body. Handlers return `&Responder`, and the framework calls three
methods on it:

| Method           | Purpose                                                         |
| ---------------- | --------------------------------------------------------------- |
| `options(res)`   | Set status code and headers (e.g. Content-Type) on the response |
| `output(buf)`    | Write the body bytes into a buffer                              |
| `output_bytes()` | Return pre-encoded bytes directly (fast path, avoids a copy)    |

Built-in implementations:

| Type                    | Content-Type                                        |
| ----------------------- | --------------------------------------------------- |
| `String` / `StringView` | `text/plain; charset=utf-8`                         |
| `Json` / `&ToJson`      | `application/json; charset=utf-8`                   |
| `Bytes`                 | `application/octet-stream`                          |
| `HttpResponse`          | Copies status, merges headers, forwards body        |
| `HttpRequest`           | Merges headers, forwards body (useful for proxying) |
| `Html` (via `html()`)   | `text/html; charset=utf-8`                          |

#### String as a responder

The simplest handler just returns a string -- Crescent wraps it in the
`Responder` impl that sets `text/plain`:

```mbt check
///|
test "string responder sets text/plain" {
  let res = @core.HttpResponse(status_code=OK)
  let responder : &@core.Responder = "hello"
  responder.options(res)
  debug_inspect(
    res.headers.get("Content-Type"),
    content="Some(\"text/plain; charset=utf-8\")",
  )
}
```

#### html() and text() helpers

`html()` creates an `Html` responder that sets `text/html; charset=utf-8`.
`text()` creates a plain-text responder. Both accept any `&Show` value:

```mbt check
///|
test "html helper sets text/html content type" {
  let res = @core.HttpResponse(status_code=OK)
  let responder = @core.html("<h1>Hello</h1>")
  responder.options(res)
  inspect(
    res.headers.get("Content-Type"),
    content="Some(\"text/html; charset=utf-8\")",
  )
  let buf = Buffer()
  responder.output(buf)
  assert_eq(buf.contents(), @utf8.encode("<h1>Hello</h1>"))
}
```

### trait BodyReader

```moonbit nocheck
///|
pub(open) trait BodyReader {
  fn from_request(HttpRequest) -> Self raise
}
```

The `BodyReader` trait powers typed body deserialization for both requests and
responses. Implement it for your own types to enable `req.body[MyType]()` and
`res.read_body[MyType]()`:

| Type               | Behavior                               |
| ------------------ | -------------------------------------- |
| `String`           | UTF-8 decode (raises on invalid bytes) |
| `Json`             | Parse as JSON value                    |
| `Bytes`            | Return raw bytes as-is                 |
| `FixedArray[Byte]` | Convert to fixed-size byte array       |
| `Array[Byte]`      | Convert to resizable byte array        |

```mbt check
///|
test "read response body as typed value" {
  let res = @core.HttpResponse(status_code=OK, raw_body=b"hello")
  let text : String = res.read_body()
  assert_eq(text, "hello")
}
```
