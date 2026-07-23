# CORS

Cross-Origin Resource Sharing (CORS) middleware for Crescent.

CORS is a browser security mechanism that restricts web pages from making
requests to a different origin (scheme + host + port) than the one that served
the page. Servers opt in by sending `Access-Control-Allow-*` headers. For
non-simple requests the browser first sends a preflight `OPTIONS` request; the
server must respond with the allowed methods, headers, and origin before the
real request proceeds.

This package provides:

- `handle_cors` — a ready-to-use middleware that handles both preflight and
  normal requests.
- `is_preflight_request` — detects whether a request is a CORS preflight.
- `append_cors_preflight_headers` / `append_cors_headers` — lower-level helpers
  for adding CORS headers manually.

## Install

This package is included with `bobzhang/crescent`. Import it directly:

```
import {
  "bobzhang/crescent/cors"
  ...
}
```

## Quick Start

Register `handle_cors` as middleware to enable CORS on all routes:

```moonbit nocheck
///|
async fn main {
  let app = @crescent.App()
  app.use_middleware(@cors.handle_cors())
  app.get("/api/data", _ => "hello")
  app.serve(port=4000)
}
```

All parameters are optional and have sensible defaults (`origin="*"`,
`methods="*"`, `allow_headers="*"`, `credentials=false`, `max_age=86400`).

## Restricting Origins

Pass explicit values to lock down which origins, methods, and headers are
allowed:

```moonbit nocheck
///|
fn _cors_restricted() -> @crescent.Middleware {
  @cors.handle_cors(
    origin="https://myapp.example",
    methods="GET, POST, PATCH",
    allow_headers="Content-Type, Authorization",
    expose_headers="X-Request-Id",
    credentials=true,
    max_age=7200,
  )
}
```

When `credentials=true` and `origin="*"`, the middleware automatically reflects
the request's `Origin` header instead (browsers reject `Access-Control-Allow-Origin: *`
with credentials) and sets `Vary: Origin` for correct caching.

## Preflight Detection

`is_preflight_request` returns `true` when the request is `OPTIONS` with both
`Origin` and `Access-Control-Request-Method` headers:

```mbt check
///|
test "detect preflight" {
  let event : @crescent.Event = {
    req: @crescent.HttpRequest(
      Options,
      "/resource",
      {
        "origin": "https://example.com",
        "access-control-request-method": "PUT",
      },
      raw_body=b"",
    ),
    res: @crescent.HttpResponse(status_code=OK),
    params: {},
  }
  debug_inspect(@cors.is_preflight_request(event), content="true")
}
```

A regular `OPTIONS` request without the CORS headers is not a preflight:

```mbt check
///|
test "regular options is not preflight" {
  let event : @crescent.Event = {
    req: @crescent.HttpRequest(
      Options,
      "/resource",
      { "origin": "https://example.com" },
      raw_body=b"",
    ),
    res: @crescent.HttpResponse(status_code=OK),
    params: {},
  }
  debug_inspect(@cors.is_preflight_request(event), content="false")
}
```

## Low-Level Header Helpers

For manual control, use `append_cors_preflight_headers` and
`append_cors_headers` directly on an `Event`:

```mbt check
///|
test "append cors headers" {
  let event : @crescent.Event = {
    req: @crescent.HttpRequest(
      Get,
      "/api",
      { "origin": "https://app.com" },
      raw_body=b"",
    ),
    res: @crescent.HttpResponse(status_code=OK),
    params: {},
  }
  @cors.append_cors_headers(
    event,
    origin="https://app.com",
    methods="GET, POST",
  )
  debug_inspect(
    event.res.headers.get("Access-Control-Allow-Origin"),
    content=(
      #|Some("https://app.com")
    ),
  )
  debug_inspect(
    event.res.headers.get("Access-Control-Allow-Methods"),
    content=(
      #|Some("GET, POST")
    ),
  )
}
```
