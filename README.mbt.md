# Crescent

A web framework for MoonBit. Type-safe and AI-agent friendly.

> Hard fork of [oboard/mocket](https://github.com/oboard/mocket) by
> [oboard](https://github.com/oboard). [Credits](#credits) at the bottom.

> **Targets:** native and wasm1 (`--target wasm`). The HTTP server, fetch,
> WebSocket, and static-file packages use `moonbitlang/async` on both targets.
> JS and wasm-gc are not supported. Native remains the preferred target in
> `moon.mod`.

## Install

```bash
moon add bobzhang/crescent
```

## Hello World

```moonbit nocheck
///|
async fn main {
  let app = @crescent.App()
  app.get("/", _ => "Hello, Crescent!")
  app.serve(port=4000)
}
```

```bash
moon run . --target native
# Visit http://localhost:4000
```

---

## Building a Todo API

This walkthrough builds a complete REST API step by step.

### Define your types

Types with `derive(ToJson, FromJson)` are your API contract. The same types
compile to native (backend) and JS (frontend) — no code generation needed.

```moonbit nocheck
///|
struct Todo {
  id : Int
  title : String
  done : Bool
} derive(ToJson, FromJson)

///|
struct CreateTodo {
  title : String
} derive(FromJson)
```

```mbt check
///|
#warnings("-unnecessary_annotation")
struct JsonDemoUser {
  name : String
  age : Int
} derive(ToJson, FromJson, Eq)

///|
test "json_value sets content-type and serializes body" {
  let user = JsonDemoUser::{ name: "Alice", age: 30 }
  let res = HttpResponse::ok().json_value(user)
  debug_inspect(
    res,
    content=(
      #|{
      #|  status_code: OK,
      #|  headers: { "Content-Type": "application/json; charset=utf-8" },
      #|  cookies: {},
      #|  raw_body: ...,
      #|}
    ),
  )

  debug_inspect(
    @utf8.decode(res.raw_body),
    content=(
      #|"{\"name\":\"Alice\",\"age\":30}"
    ),
  )
}
```

### Wire up the routes

All handlers automatically map errors to JSON — bad JSON returns 400,
`raise HttpError(...)` returns a structured error, anything else returns 500.
You never write error-handling boilerplate.

```moonbit check
///|
#warnings("-unused_value")
fn build_app() -> @crescent.App {
  let app = @crescent.App()
  let todos : Array[Todo] = [{ id: 1, title: "Learn MoonBit", done: false }]
  let next_id = Ref::Ref(2)

  // List all
  app.get("/api/todos", _ => HttpResponse::ok().json_value(todos))

  // Get by ID — require_param_int auto-returns 400 for "abc"
  app.get("/api/todos/:id", event => {
    let id = event.require_param_int("id")
    for todo in todos {
      if todo.id == id {
        return HttpResponse::ok().json_value(todo)
      }
    }
    raise HttpError::HttpError(NotFound, "todo \{id} not found")
  })

  // Create — event.json() auto-returns 400 for invalid JSON
  app.post("/api/todos", event => {
    let input : CreateTodo = event.json()
    let todo = Todo::{ id: next_id.val, title: input.title, done: false }
    next_id.val += 1
    todos.push(todo)
    HttpResponse::created().json_value(todo)
  })

  // Health check — get_raw for handlers that never raise
  app.get_raw("/health", _ => "ok")

  app
}
```

### Add middleware

Register middleware before routes. They execute in onion order (first registered
= outermost layer).

```moonbit check
///|
fn _build_app() -> @crescent.App {
  let app = @crescent.App()

  // Security headers on every response
  app.use_middleware(@middleware.security_headers())

  // Unique request ID for distributed tracing
  app.use_middleware(@middleware.request_id())

  // Request logging
  app.use_middleware((event, next) => {
    let start = @async.now()
    let res = next()
    let ms = @async.now() - start
    println("\{event.req.http_method} \{event.req.url} \{ms}ms")
    res
  })

  // Auth only on /api routes
  app.use_middleware(
    (event, next) => {
      match event.req.get_header("Authorization") {
        Some(_) => next()
        None => HttpResponse::unauthorized()
      }
    },
    base_path="/api",
  )

  // ... register routes ...
  app
}
```

```mbt check
///|
async test "security headers middleware" {
  let app = @crescent.App()
  app.use_middleware(@middleware.security_headers())
  app.get_raw("/test", fn(_) noraise { "ok" })
  let client = @test_client.TestClient(app)
  let res = client.get("/test")
  guard res.headers
    is { "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY", .. } else {
    fail("missing expected security headers")
  }
}

///|
async test "request ID middleware" {
  let app = @crescent.App()
  app.use_middleware(@middleware.request_id())
  app.get_raw("/test", fn(_) noraise { "ok" })
  let client = @test_client.TestClient(app)
  let res = client.get("/test")
  assert_true(res.headers.get("X-Request-Id") is Some(_))
}
```

### Test without a network

`TestClient` dispatches requests in-process. No ports, no sockets, fast CI.

```moonbit nocheck
///|
async test "create a todo" {
  let app = build_app()
  let client = @test_client.TestClient(app)

  let res = client.post("/api/todos", body=b"{\"title\":\"Write tests\"}")
  assert_eq(res.status, Created)

  let todo : Todo = res.body_json()
  assert_eq(todo.title, "Write tests")
  assert_eq(todo.done, false)
}

///|
async test "invalid ID returns 400" {
  let client = @test_client.TestClient(build_app())
  let res = client.get("/api/todos/abc")
  assert_eq(res.status, BadRequest)
}

///|
async test "missing todo returns 404" {
  let client = @test_client.TestClient(build_app())
  let res = client.get("/api/todos/999")
  assert_eq(res.status, NotFound)
}

///|
async test "bad JSON returns 400" {
  let client = @test_client.TestClient(build_app())
  let res = client.post("/api/todos", body=b"not json")
  assert_eq(res.status, BadRequest)
}

///|
async test "security headers are present" {
  let client = @test_client.TestClient(build_app())
  let res = client.get("/health")
  assert_eq(res.headers.get("X-Content-Type-Options"), Some("nosniff"))
}
```

```mbt check
///|
#warnings("-unnecessary_annotation")
struct TodoInput {
  title : String
} derive(FromJson, ToJson)

///|
async test "typed handler auto-maps errors" {
  let app = @crescent.App()
  app.post("/todos", event => {
    let input : TodoInput = event.json()
    HttpResponse::created().json_value(input)
  })
  let client = @test_client.TestClient(app)

  // Valid request
  let res = client.post("/todos", body=b"{\"title\":\"Learn MoonBit\"}")
  assert_eq(res.status, Created)

  // Invalid JSON -> automatic 400
  let res2 = client.post("/todos", body=b"not json")
  assert_eq(res2.status, BadRequest)
}
```

### Start the server

```moonbit nocheck
///|
async fn main {
  let app = build_app()
  println("Listening on http://localhost:4000")
  app.serve(port=4000)
}
```

Try it:

```bash
curl localhost:4000/api/todos
curl -X POST localhost:4000/api/todos -d '{"title":"Write docs"}'
curl localhost:4000/api/todos/1
curl localhost:4000/api/todos/abc       # 400: must be a valid integer
curl -X POST localhost:4000/api/todos -d 'not json'  # 400: parse error
curl localhost:4000/health              # "ok"
```

---

## CRUD with resource()

When your API follows REST conventions, register all 5 routes in one call:

```moonbit nocheck
  app.resource("/api/todos", ResourceConfig(
    list   = fn(_) { HttpResponse::ok().json_value(all_todos()) },
    get    = fn(e) {
      let id = e.require_param_int("id")
      HttpResponse::ok().json_value(find_todo(id))
    },
    create = fn(e) {
      let input : CreateTodo = e.json()
      HttpResponse::created().json_value(insert_todo(input))
    },
    update = fn(e) {
      let id = e.require_param_int("id")
      let input : CreateTodo = e.json()
      HttpResponse::ok().json_value(update_todo(id, input))
    },
    delete = fn(e) {
      let id = e.require_param_int("id")
      delete_todo(id)
      HttpResponse::no_content()
    },
  ))
```

This registers `GET /api/todos`, `GET /api/todos/:id`, `POST /api/todos`,
`PUT /api/todos/:id`, `DELETE /api/todos/:id`. All handlers omitted from
`ResourceConfig(...)` are simply not registered.

```mbt check
///|
#warnings("-unnecessary_annotation")
struct ResItem {
  id : Int
  name : String
} derive(ToJson, FromJson, Eq, Debug)

///|
#warnings("-unnecessary_annotation")
struct CreateResItem {
  name : String
} derive(FromJson, ToJson)

///|
async test "resource CRUD" {
  let items : Array[ResItem] = [{ id: 1, name: "Alpha" }]
  let app = @crescent.App()
  app.resource(
    "/items",
    ResourceConfig(
      list=_ => HttpResponse::ok().json_value(items),
      get=event => {
        let id = event.require_param_int("id")
        for item in items {
          if item.id == id {
            return HttpResponse::ok().json_value(item)
          }
        }
        raise HttpError::HttpError(NotFound, "not found")
      },
      create=event => {
        let input : CreateResItem = event.json()
        let item = ResItem::{ id: 2, name: input.name }
        items.push(item)
        HttpResponse::created().json_value(item)
      },
    ),
  )
  let client = @test_client.TestClient(app)

  // List
  let res = client.get("/items")
  assert_eq(res.status, OK)
  let list : Array[ResItem] = res.body_json()
  assert_eq(list.length(), 1)

  // Create
  let res2 = client.post("/items", body=b"{\"name\":\"Beta\"}")
  assert_eq(res2.status, Created)
  let created : ResItem = res2.body_json()
  assert_eq(created.name, "Beta")

  // Get by ID
  let res3 = client.get("/items/1")
  assert_eq(res3.status, OK)
  let item : ResItem = res3.body_json()
  // TODO(upstream): change the bound of `assert_eq` from `Show` to `Debug`
  debug_inspect(
    item,
    content=(
      #|{ id: 1, name: "Alpha" }
    ),
  )

  // Not found
  let res4 = client.get("/items/999")
  assert_eq(res4.status, NotFound)
}
```

---

## Route Groups

Share a path prefix and middleware across related routes:

```moonbit nocheck
  app.group("/api/v1", fn(api) {
    api.use_middleware(require_auth())

    api.get("/users", _ => HttpResponse::ok().json_value(users))
    api.get("/users/:id", fn(event) {
      let id = event.require_param_int("id")
      HttpResponse::ok().json_value(find_user(id))
    })
    api.post("/users", fn(event) {
      let user : CreateUser = event.json()
      HttpResponse::created().json_value(save_user(user))
    })
  })
  // Routes: GET /api/v1/users, GET /api/v1/users/:id, POST /api/v1/users
  // require_auth() only runs for /api/v1/* requests
```

## Route Patterns

| Pattern | Example URL | Captures |
|---------|-------------|----------|
| `/users` | `/users` | (exact match) |
| `/users/:id` | `/users/42` | `event.param("id")` = `"42"` |
| `/users/:id/posts/:pid` | `/users/1/posts/99` | two params |
| `/files/*` | `/files/readme.txt` | one segment in `_` |
| `/static/**` | `/static/css/main.css` | any depth in `_` |

Matching uses a radix tree — O(path length), not O(number of routes).

```mbt check
///|
test "compiled route matching" {
  let route = @router.CompiledRoute("/users/:id/posts/:postId")
  assert_eq(
    route.match_path("/users/42/posts/99"),
    Some({ "id": "42", "postId": "99" }),
  )
  assert_eq(route.match_path("/users/42"), None)
}

///|
test "static routes are flagged" {
  let static_route = @router.CompiledRoute("/api/health")
  assert_true(static_route.is_static)
  let dynamic_route = @router.CompiledRoute("/api/:version")
  assert_true(dynamic_route.is_static == false)
}
```

---

## WebSocket

```moonbit nocheck
  app.ws("/chat", fn(event) {
    match event {
      Open(peer) => {
        println("Connected: \{peer.to_string()}")
        peer.subscribe("chat-room")
      }
      Message(peer, Text(msg)) =>
        peer.publish("chat-room", msg)  // broadcast to all subscribers
      Message(peer, Binary(data)) =>
        peer.binary(data)               // echo binary back
      Close(peer) =>
        println("Disconnected: \{peer.to_string()}")
    }
  })
```

`WebSocketPeer` methods: `text(msg)`, `binary(data)`, `subscribe(channel)`,
`unsubscribe(channel)`, `publish(channel, msg)`.

## Static Files

```moonbit nocheck
  app.static_assets("/assets", @static_file.StaticFileProvider(path="./public"))
```

Features: ETag caching, `If-Modified-Since` / `If-None-Match` support,
`Accept-Encoding` content negotiation, path traversal protection,
directory index fallback (`index.html`, `index.htm`, ...).

### trait ServeStaticProvider

```moonbit nocheck
///|
pub(open) trait ServeStaticProvider {
  async fn get_meta(Self, String) -> StaticAssetMeta?
  async fn get_contents(Self, String) -> &Responder
  fn get_type(Self, String) -> String?
  fn get_encodings(Self) -> Map[String, String]
  fn get_index_names(Self) -> Array[String]
  fn get_fallthrough(Self) -> Bool
}
```

`static_assets` accepts any type that implements `ServeStaticProvider`. The
bundled `@static_file.StaticFileProvider` serves from the filesystem, but custom
providers can pull from S3, an embedded asset bundle, a zip file, a CDN cache,
etc. The path argument to each method is the asset's URL path (already stripped
of the mount prefix and resolved against any index filenames).

| Method             | Purpose                                                        |
| ------------------ | -------------------------------------------------------------- |
| `get_meta`         | Resolve the path to asset metadata (size, mtime, ETag); `None` means "not found" |
| `get_contents`     | Produce the response body for the resolved asset               |
| `get_type`         | Return the `Content-Type` for the path (`None` skips the header) |
| `get_encodings`    | Provider-wide `Content-Encoding` → variant suffix map (e.g. `gzip` → `.gz`) |
| `get_index_names`  | Filenames to try when the request points at a directory        |
| `get_fallthrough`  | If `true`, a miss falls through to the next route instead of 404 |

## Cookies

```moonbit nocheck
  // Set with attributes
  event.res.set_cookie("session", "abc123",
    max_age=3600, http_only=true, same_site=Lax)

  // Read
  let user = match event.req.get_cookie("session") {
    Some(cookie) => find_user_by_session(cookie.value)
    None => anonymous_user()
  }

  // Delete (sets Max-Age=0)
  event.res.delete_cookie("session")
```

```mbt check
///|
test "set and format cookie" {
  let res = @crescent.HttpResponse(status_code=OK)
  res.set_cookie(
    "session",
    "abc123",
    max_age=3600,
    http_only=true,
    same_site=Lax,
  )
  assert_true(res.cookies.get("session") is Some(_))
}
```

## HTTP Client (Fetch)

Make outbound HTTP requests from your handlers:

```moonbit nocheck
  app.get("/api/weather/:city", fn(event) {
    let city = event.require_param("city")
    let res = @fetch.get("https://api.weather.example/v1/\{city}")
    let weather : WeatherData = res.read_body()
    HttpResponse::ok().json_value(weather)
  })
```

Methods: `@fetch.get`, `@fetch.post`, `@fetch.put`, `@fetch.patch`,
`@fetch.delete`, `@fetch.head`. All accept optional `data`, `headers`,
`credentials`, and `mode` parameters.

## CORS

```moonbit nocheck
  // Allow all origins (default)
  app.use_middleware(@cors.handle_cors())

  // Restrict to specific origin
  app.use_middleware(@cors.handle_cors(
    origin="https://myapp.com",
    methods="GET,POST",
    credentials=true,
    max_age=3600,
  ))
```

## Server Configuration

### Request limits

```moonbit nocheck
  app.serve(port=4000, options=NativeServeOptions(
    max_connections=1000,               // concurrent connection limit
    max_request_body_bytes=1_048_576,   // 1MB body size limit (413 if exceeded)
    request_body_read_timeout_ms=5000,  // 5s read timeout (408 if exceeded)
  ))
```

### WebSocket options

```moonbit nocheck
  app.serve(port=4000, options=NativeServeOptions(
    websocket_max_message_bytes=65536,         // max inbound message size
    websocket_outgoing_queue_capacity=100,     // outbound buffer per connection
    websocket_overflow_policy=DropOldest,      // or DropLatest
    websocket_read_timeout_ms=30000,           // close idle connections after 30s
  ))
```

### Graceful shutdown

```moonbit nocheck
  let shutdown = @async.Queue()

  // In another task: shutdown.put(()) to stop the server
  app.serve(port=4000, shutdown~)
```

### Serve on an existing server

```moonbit nocheck
  let addr = @socket.Addr::parse("0.0.0.0:4000")
  let server = @http.Server(addr, reuse_addr=true)
  app.serve_on(server)
```

---

## Response Helpers

```moonbit nocheck
  HttpResponse::ok()                           // 200
  HttpResponse::created()                      // 201
  HttpResponse::no_content()                   // 204
  HttpResponse::bad_request()                  // 400
  HttpResponse::unauthorized()                 // 401
  HttpResponse::forbidden()                    // 403
  HttpResponse::not_found()                    // 404
  HttpResponse::error(BadRequest, "message")   // JSON error body
  HttpResponse::redirect("/new-path")          // 301
  HttpResponse::redirect_temporary("/temp")    // 302
  HttpResponse::redirect_307("/preserve")      // 307 (preserves method)
  HttpResponse::redirect_308("/permanent")     // 308 (permanent, preserves method)

  // Fluent chaining
  HttpResponse::ok()
    .header("Cache-Control", "max-age=3600")
    .json_value(data)
```

```mbt check
///|
test "response helpers" {
  let ok = HttpResponse::ok()
  assert_eq(ok.status_code, OK)

  let created = HttpResponse::created()
  assert_eq(created.status_code, Created)

  let not_found = HttpResponse::not_found()
  assert_eq(not_found.status_code, NotFound)

  let no_content = HttpResponse::no_content()
  assert_eq(no_content.status_code, NoContent)

  let bad_request = HttpResponse::bad_request()
  assert_eq(bad_request.status_code, BadRequest)
}

///|
test "fluent response building" {
  let res = HttpResponse::ok()
    .header("X-Custom", "value")
    .header("Cache-Control", "max-age=3600")
  guard res.headers
    is { "X-Custom": "value", "Cache-Control": "max-age=3600", .. } else {
    fail("expected fluent headers to be set")
  }
}

///|
test "redirect helpers" {
  let r301 = HttpResponse::redirect("/new")
  assert_eq(r301.status_code, MovedPermanently)
  assert_eq(r301.headers.get("Location"), Some("/new"))

  let r302 = HttpResponse::redirect_temporary("/temp")
  assert_eq(r302.status_code, Found)
}
```

## Error Handling

All `get`/`post`/`put`/`patch`/`delete` handlers catch errors automatically:

| What you write | What the client gets |
|----------------|---------------------|
| `raise HttpError(BadRequest, "invalid email")` | 400 `{"error":{"status":400,"message":"invalid email"}}` |
| `raise HttpError(NotFound, "not found")` | 404 with JSON body |
| `event.json()` on bad input | 400 with parse error message |
| `event.require_param_int("id")` on `"abc"` | 400 `"must be a valid integer"` |
| Any unhandled error | 500 Internal Server Error |

For handlers that should never raise (health checks, plain text), use `get_raw`:

```moonbit nocheck
  app.get_raw("/health", fn(_) noraise { "ok" })
```

For custom error responses, use `try_json`:

```moonbit nocheck
  app.post("/users", fn(event) {
    match event.try_json() {
      Ok(user) => HttpResponse::ok().json_value(user)
      Err(msg) => HttpResponse::error(BadRequest, "Invalid user: \{msg}")
    }
  })
```

## Built-in Middleware

Middleware implementations live in the `bobzhang/crescent/middleware` sub-package.

| Middleware | What it does |
|-----------|-------------|
| `@middleware.security_headers()` | `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `X-XSS-Protection: 0`, `Referrer-Policy: strict-origin-when-cross-origin` |
| `@middleware.request_id()` | Adds `X-Request-Id` header; preserves incoming IDs for distributed tracing. Access via `event.request_id()` |
| `@middleware.rate_limit(requests_per_window~, window_ms~)` | Fixed-window rate limiter. Returns `429 Too Many Requests` with a `Retry-After` header when the limit is exceeded. |
| `@cors.handle_cors()` | Full CORS support: preflight `OPTIONS` handling, configurable origins/methods/credentials |

Writing custom middleware:

```moonbit nocheck
///|
fn rate_limiter() -> Middleware {
  let count = Ref(0)
  fn(event, next) {
    count.val += 1
    if count.val > 100 {
      return HttpResponse::error(TooManyRequests, "slow down")
    }
    next()
  }
}
```

---

## API Quick Reference

### Parameters

| Method | Returns | On missing/invalid |
|--------|---------|-------------------|
| `event.param("name")` | `String?` | `None` |
| `event.param_int("id")` | `Int?` | `None` |
| `event.param_int64("id")` | `Int64?` | `None` |
| `event.require_param("name")` | `String` | raises 400 |
| `event.require_param_int("id")` | `Int` | raises 400 |
| `event.require_param_int64("id")` | `Int64` | raises 400 |

```mbt check
///|
test "param and param_int" {
  let event = Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: { "id": "42", "name": "alice" },
  }
  assert_eq(event.param("name"), Some("alice"))
  assert_eq(event.param_int("id"), Some(42))
  assert_eq(event.param("missing"), None)
}

///|
test "require_param raises on missing" {
  let event = Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  @test.assert_raise(() => event.require_param_int("id"))
}
```

### Body & Query

| Method | Returns | Notes |
|--------|---------|-------|
| `event.json[T]()` | `T` | Raises on invalid JSON |
| `event.try_json[T]()` | `Result[T, String]` | For custom error handling |
| `event.req.body[T]()` | `T` | Via `BodyReader` trait (`String`, `Bytes`, `Json`) |
| `event.req.get_query("key")` | `String?` | URL-decoded, cached |
| `event.req.query_params()` | `Map[String, String]` | All query params, cached |
| `event.req.path()` | `String` | Path without query string, cached |
| `event.req.content_type()` | `String?` | Content-Type header value |
| `event.request_id()` | `String?` | Requires `@middleware.request_id()` middleware |

```mbt check
///|
#warnings("-unnecessary_annotation")
struct ReadmeCreateUser {
  name : String
  age : Int
} derive(FromJson)

///|
test "json parsing from request body" {
  let req = @crescent.HttpRequest(
    Post,
    "/users",
    {},
    raw_body=b"{\"name\":\"Bob\",\"age\":25}",
  )
  let user : ReadmeCreateUser = req.json()
  assert_eq(user.name, "Bob")
  assert_eq(user.age, 25)
}

///|
test "try_json returns Result" {
  let req = @crescent.HttpRequest(Post, "/", {}, raw_body=b"not json")
  let result : Result[ReadmeCreateUser, String] = req.try_json()
  assert_true(result is Err(_))
}

///|
test "path extracts from request target" {
  let req = @crescent.HttpRequest(Get, "/api/users?q=test", {}, raw_body=b"")
  let path = req.path()
  assert_eq(path, "/api/users")
}

///|
test "query_params cached and decoded" {
  let req = @crescent.HttpRequest(
    Get,
    "/search?q=hello%20world&lang=en",
    {},
    raw_body=b"",
  )
  assert_eq(req.get_query("q"), Some("hello world"))
  assert_eq(req.get_query("lang"), Some("en"))
  assert_eq(req.get_query("missing"), None)
}
```

### HttpMethod Enum

Pattern match on the request method — no string comparisons:

```moonbit nocheck
  match event.req.http_method {
    Get => "read"
    Post | Put | Patch => "write"
    Delete => "delete"
    _ => "other"
  }
```

```mbt check
///|
test "HttpMethod round-trip" {
  let meth : HttpMethod = Post
  assert_eq(meth.to_method_string(), "POST")
  assert_eq(HttpMethod::from_string("POST"), Post)
}

///|
test "HttpMethod pattern matching" {
  let req = @crescent.HttpRequest(Get, "/", {}, raw_body=b"")
  let label = match req.http_method {
    Get => "read"
    Post => "write"
    _ => "other"
  }
  assert_eq(label, "read")
}
```

## Performance

- **Radix tree routing** — O(path length) dynamic route lookup
- **Pre-compiled patterns** — route templates parsed at registration, not per request
- **Cached parsing** — path and query string parsed once per request
- **Zero-alloc headers** — case-insensitive ASCII comparison without string allocation
- **Direct byte output** — `Bytes` and `HttpResponse` skip the intermediate buffer

## Packages

```
bobzhang/crescent             — Core: routing, middleware, serving, WebSocket
bobzhang/crescent/httputil    — HTTP protocol: headers, dates, URL encoding
bobzhang/crescent/cors        — CORS middleware
bobzhang/crescent/fetch       — HTTP client
bobzhang/crescent/static_file — Static file provider (filesystem)
bobzhang/crescent/test_client — In-process test client (no network I/O)
bobzhang/crescent/uri         — RFC 3986 URI parser
```

## Credits

Crescent is a hard fork of [oboard/mocket](https://github.com/oboard/mocket) by
[oboard](https://github.com/oboard). The original framework established the core
architecture: Express-style routing, onion middleware, WebSocket support, static
file serving, and the async-native design built on `moonbitlang/async`.

## License

Apache-2.0
