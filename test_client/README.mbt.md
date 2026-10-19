# TestClient

An in-process HTTP test client for Crescent — drive your app with
synthetic requests, assert on the response, no network involved.

Integration tests that spin up a real TCP listener are slow, flaky under
parallel execution, and depend on port availability. `TestClient` skips
all of that: it calls the same `App::dispatch(...)` entry point the
real server uses, runs the full middleware chain and handler pipeline,
and returns a `TestResponse` you can pattern-match on. A typical test
finishes in microseconds.

```moonbit nocheck
  let app = @crescent.App()
  app.get("/hello", _ => "world")

  let client = @test_client.TestClient(app)
  let res = client.get("/hello")
  assert_eq(res.status, OK)
  assert_eq(res.body_text(), "world")
```

This package provides:

- **`TestClient`** — wraps an `App`. One verb per HTTP method
  (`get`, `post`, `put`, `delete`) plus a generic `request` for anything
  else. Each call goes through routing + middleware + handler in the
  same order a real request would.
- **`TestResponse`** — the captured response: `status`, `headers`,
  `body_bytes`. Helpers `body_text()` decodes as UTF-8 and
  `body_json[T]()` parses into any `FromJson` type.

## Install

This package is included with `bobzhang/crescent`. Import it directly:

```
import {
  "bobzhang/crescent/test_client"
  ...
}
```

Because it exists solely for test code, most packages pull it in under a
`for "test"` import so it doesn't appear in their production build graph:

```
import {
  "bobzhang/crescent/test_client",
} for "test"
```

## Sending Requests

The four convenience verbs each take a path and optional `headers`:

```mbt check
///|
async test "verb methods hit the right route" {
  let app = @crescent.App()
  app.get("/users", _ => "list")
  app.post("/users", _ => "created")
  app.put("/users/1", _ => "replaced")
  app.delete("/users/1", _ => "gone")
  let client = @test_client.TestClient(app)
  assert_eq(client.get("/users").body_text(), "list")
  assert_eq(client.post("/users").body_text(), "created")
  assert_eq(client.put("/users/1").body_text(), "replaced")
  assert_eq(client.delete("/users/1").body_text(), "gone")
}
```

### Sending a body

`post` and `put` accept an optional `body` of `Bytes`. Pair it with
`raw_body=` when building a request on the handler side for symmetric
tests:

```mbt check
///|
async test "post with a JSON body round-trips" {
  let app = @crescent.App()
  app.post("/echo", event => {
    let s : String = event.req.body()
    s
  })
  let client = @test_client.TestClient(app)
  let res = client.post("/echo", body=b"{\"hi\":1}")
  assert_eq(res.status, OK)
  assert_eq(res.body_text(), "{\"hi\":1}")
}
```

### Custom headers

All verbs take an optional `headers` map — useful for asserting
middleware that reads request headers, or for supplying auth tokens:

```mbt check
///|
async test "headers reach the handler" {
  let app = @crescent.App()
  app.get("/whoami", event => {
    match event.req.get_header("Authorization") {
      Some(tok) => "tok:\{tok}"
      None => "anon"
    }
  })
  let client = @test_client.TestClient(app)
  let res = client.get("/whoami", headers={ "Authorization": "Bearer k" })
  assert_eq(res.body_text(), "tok:Bearer k")
}
```

### Generic `request`

For any other HTTP method (`PATCH`, `OPTIONS`, custom verbs), go through
`request` directly:

```mbt check
///|
async test "request handles arbitrary methods" {
  let app = @crescent.App()
  app.patch("/todos/1", _ => "patched")
  let client = @test_client.TestClient(app)
  let res = client.request("PATCH", "/todos/1", headers={}, body=b"")
  assert_eq(res.body_text(), "patched")
}
```

## Inspecting the Response

`TestResponse` exposes the raw pieces — `status : StatusCode`,
`headers : Map[String, String]`, `body_bytes : Bytes` — plus two
decoders.

### Text body

```mbt check
///|
async test "body_text decodes UTF-8" {
  let app = @crescent.App()
  app.get("/greet", _ => "héllo")
  let client = @test_client.TestClient(app)
  assert_eq(client.get("/greet").body_text(), "héllo")
}
```

`body_text()` returns an empty string on invalid UTF-8 rather than
raising, so test assertions stay simple.

### Typed JSON body

`body_json[T]()` parses the body as JSON and deserializes into any
`FromJson` type in a single step — the natural counterpart to
`json_value` on the server side:

```mbt check
///|
#warnings("-unnecessary_annotation")
struct Echo {
  name : String
  count : Int32
} derive(FromJson, ToJson)

///|
async test "body_json decodes a typed struct" {
  let app = @crescent.App()
  app.post("/echo", event => {
    let input : Echo = event.json()
    @crescent.HttpResponse::ok().json_value(input)
  })
  let client = @test_client.TestClient(app)
  let res = client.post("/echo", body=b"{\"name\":\"a\",\"count\":7}")
  let got : Echo = res.body_json()
  assert_eq(got.name, "a")
  assert_eq(got.count, 7)
}
```

### Headers and status

Use `status` for the `StatusCode` variant and `headers.get(name)` for
header lookup. Map pattern matching is a compact way to assert several
headers at once:

```mbt check
///|
async test "assert status and multiple headers" {
  let app = @crescent.App()
  app.get("/", _ => {
    @crescent.HttpResponse::ok().header("X-Custom", "v").body("ok")
  })
  let client = @test_client.TestClient(app)
  let res = client.get("/")
  assert_eq(res.status, OK)
  guard res.headers is { "X-Custom": "v", .. } else {
    fail("missing X-Custom header")
  }
}
```

## What Gets Exercised

Every `TestClient` request goes through the same dispatch path as a live
request:

1. Path + query parsing
2. Route matching (including radix-tree dynamic segments)
3. The full middleware chain in onion order
4. The matched handler (or the not-found handler)
5. Response serialization (status code, headers, body, cookies)

The only thing that *isn't* exercised is the socket I/O layer —
connection handling, keep-alive, and HTTP framing live in
`serve_async.mbt` and are out of scope here. For coverage of
those, see the integration tests that start a real listener.
