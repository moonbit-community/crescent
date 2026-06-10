///|
fn App::find_route_for_method(
  self : App,
  http_method : String,
  path : String,
) -> (HttpHandler, Map[String, StringView])? {
  if self.static_routes.get(http_method) is Some(method_routes) {
    if method_routes.get(path) is Some(handler) {
      return Some((handler, {}))
    }
  }
  match self.dynamic_routes.search(http_method, path) {
    Some((handler, params)) => return Some((handler, params))
    None => ()
  }
  None
}

///|
test "find_route_for_method hits static route" {
  let app = App()
  app.get("/users", _ => "users")
  inspect(app.find_route_for_method("GET", "/users") is Some(_), content="true")
}

///|
test "find_route_for_method misses nonexistent path" {
  let app = App()
  app.get("/users", _ => "users")
  inspect(
    app.find_route_for_method("GET", "/posts") is Some(_),
    content="false",
  )
}

///|
test "find_route_for_method misses wrong method" {
  let app = App()
  app.get("/users", _ => "users")
  inspect(
    app.find_route_for_method("POST", "/users") is Some(_),
    content="false",
  )
}

///|
test "find_route_for_method dynamic route extracts params" {
  let app = App()
  app.get("/users/:id", _ => "user")
  guard app.find_route_for_method("GET", "/users/123")
    is Some((_, { "id": "123", .. })) else {
    fail("expected route match")
  }
}

///|
test "find_route_for_method dynamic route with multiple params" {
  let app = App()
  app.get("/users/:userId/posts/:postId", _ => "user_post")
  guard app.find_route_for_method("GET", "/users/42/posts/99")
    is Some((_, { "userId": "42", "postId": "99", .. })) else {
    fail("expected route match")
  }
}

///|
fn App::has_route_for_method(
  self : App,
  http_method : String,
  path : String,
) -> Bool {
  self.find_route_for_method(http_method, path) is Some(_)
}

///|
test "has_route_for_method returns true for registered route" {
  let app = App()
  app.get("/users", _ => "users")
  inspect(
    app.has_route_for_method("GET", "/users") |> @debug.to_repr,
    content="true",
  )
}

///|
test "has_route_for_method returns false for missing route" {
  let app = App()
  app.get("/users", _ => "users")
  inspect(
    app.has_route_for_method("GET", "/posts") |> @debug.to_repr,
    content="false",
  )
}

///|
test "has_route_for_method returns false for wrong method" {
  let app = App()
  app.get("/users", _ => "users")
  inspect(
    app.has_route_for_method("DELETE", "/users") |> @debug.to_repr,
    content="false",
  )
}

///|
test "has_route_for_method matches dynamic route" {
  let app = App()
  app.get("/users/:id", _ => "user")
  inspect(
    app.has_route_for_method("GET", "/users/456") |> @debug.to_repr,
    content="true",
  )
}

///|
fn App::allowed_methods(
  self : App,
  path : String,
  include_implicit_options : Bool,
) -> Array[String] {
  let allowed : Array[String] = []
  let supports_get = self.has_route_for_method("GET", path)
  let supports_head = self.has_route_for_method("HEAD", path)
  if supports_get {
    allowed.push("GET")
  }
  if supports_head || supports_get {
    allowed.push("HEAD")
  }
  for http_method in ["POST", "PUT", "PATCH", "DELETE"] {
    if self.has_route_for_method(http_method, path) {
      allowed.push(http_method)
    }
  }
  let supports_options = self.has_route_for_method("OPTIONS", path)
  if supports_options || (include_implicit_options && !allowed.is_empty()) {
    allowed.push("OPTIONS")
  }
  for http_method in ["TRACE", "CONNECT"] {
    if self.has_route_for_method(http_method, path) {
      allowed.push(http_method)
    }
  }
  allowed
}

///|
test "allowed_methods includes HEAD for GET route" {
  let app = App()
  app.get("/test", _ => "ok")
  let methods = app.allowed_methods("/test", false)
  inspect(@debug.to_repr(methods), content="[\"GET\", \"HEAD\"]")
}

///|
test "allowed_methods with implicit OPTIONS" {
  let app = App()
  app.get("/test", _ => "ok")
  let methods = app.allowed_methods("/test", true)
  inspect(@debug.to_repr(methods), content="[\"GET\", \"HEAD\", \"OPTIONS\"]")
}

///|
test "allowed_methods multiple methods on same path" {
  let app = App()
  app.get("/users", _ => "list")
  app.post("/users", _ => "create")
  app.delete("/users", _ => "remove")
  let methods = app.allowed_methods("/users", false)
  inspect(
    @debug.to_repr(methods),
    content="[\"GET\", \"HEAD\", \"POST\", \"DELETE\"]",
  )
}

///|
test "allowed_methods with explicit OPTIONS handler" {
  let app = App()
  app.get("/test", _ => "ok")
  app.options_raw("/test", _ => "opts")
  let methods = app.allowed_methods("/test", false)
  inspect(@debug.to_repr(methods), content="[\"GET\", \"HEAD\", \"OPTIONS\"]")
}

///|
test "allowed_methods returns empty for unknown path" {
  let app = App()
  app.get("/test", _ => "ok")
  let methods = app.allowed_methods("/unknown", false)
  inspect(@debug.to_repr(methods), content="[]")
}

///|
test "allowed_methods no implicit OPTIONS when empty" {
  let app = App()
  let methods = app.allowed_methods("/nothing", true)
  inspect(@debug.to_repr(methods), content="[]")
}

///|
// Find matching route and parameters
fn App::find_route(
  self : App,
  http_method : String,
  path : String,
) -> (HttpHandler, Map[String, StringView])? {
  if self.find_route_for_method(http_method, path) is Some(route) {
    return Some(route)
  }
  if self.static_routes.get("*") is Some(wildcard_routes) {
    if wildcard_routes.get(path) is Some(handler) {
      return Some((handler, {}))
    }
  }
  match self.dynamic_routes.search("*", path) {
    Some((handler, params)) => return Some((handler, params))
    None => ()
  }
  None
}

///|
test "find_route returns method-specific route first" {
  let app = App()
  app.get("/test", _ => "get")
  app.all_raw("/test", _ => "all")
  inspect(app.find_route("GET", "/test") is Some(_), content="true")
}

///|
test "find_route falls back to wildcard when method not matched" {
  let app = App()
  app.all_raw("/any", _ => "any")
  inspect(app.find_route("DELETE", "/any") is Some(_), content="true")
}

///|
test "find_route returns None when no route matches" {
  let app = App()
  app.get("/users", _ => "users")
  inspect(app.find_route("GET", "/missing") is Some(_), content="false")
}

///|
test "find_route wildcard dynamic route with params" {
  let app = App()
  app.all_raw("/items/:id", _ => "item")
  guard app.find_route("PATCH", "/items/77") is Some((_, { "id": "77", .. })) else {
    fail("expected wildcard dynamic route match")
  }
}

///|
fn App::find_ws_route(
  self : App,
  path : String,
) -> (WebSocketHandler, Map[String, StringView])? {
  if self.ws_static_routes.get(path) is Some(handler) {
    return Some((handler, {}))
  }
  self.ws_dynamic_routes.search("WS", path)
}

///|
test "find_ws_route static hit" {
  let app = App()
  app.ws("/ws", _ => ())
  inspect(app.find_ws_route("/ws") is Some(_), content="true")
}

///|
test "find_ws_route dynamic hit" {
  let app = App()
  app.ws("/ws/:room", _ => ())
  inspect(app.find_ws_route("/ws/lobby") is Some(_), content="true")
}

///|
test "find_ws_route extracts params from dynamic path" {
  let app = App()
  app.ws("/ws/:room", _ => ())
  guard app.find_ws_route("/ws/lobby") is Some((_, { "room": "lobby", .. })) else {
    fail("expected route match")
  }
}

///|
test "find_ws_route extracts multiple params" {
  let app = App()
  app.ws("/ws/:room/user/:id", _ => ())
  guard app.find_ws_route("/ws/lobby/user/42")
    is Some((_, { "room": "lobby", "id": "42", .. })) else {
    fail("expected route match")
  }
}

///|
test "find_ws_route static returns empty params" {
  let app = App()
  app.ws("/ws", _ => ())
  guard app.find_ws_route("/ws") is Some((_, params)) && params.is_empty() else {
    fail("expected route match with empty params")
  }
}

///|
test "find_ws_route duplicate path overrides handler" {
  // Before the radix tree refactor, re-registering the same dynamic path
  // silently added a second entry and the first-registered handler won.
  // Now re-registration overrides the previous handler.
  let calls : Array[String] = []
  let app = App()
  app.ws("/ws/:room", _ => calls.push("first"))
  app.ws("/ws/:room", _ => calls.push("second"))
  guard app.find_ws_route("/ws/lobby") is Some((handler, _)) else {
    fail("expected route match")
  }
  handler(Open(WebSocketPeer(connection_id="test")))
  assert_eq(calls, ["second"])
}

///|
test "find_ws_route static beats param" {
  // Precedence: when a URL could match both a static route and a param
  // route, the static route wins regardless of registration order.
  let calls : Array[String] = []
  let app = App()
  app.ws("/ws/:room", _ => calls.push("param"))
  app.ws("/ws/lobby", _ => calls.push("static"))
  guard app.find_ws_route("/ws/lobby") is Some((handler, _)) else {
    fail("expected route match")
  }
  handler(Open(WebSocketPeer(connection_id="test")))
  // Static routes are stored separately and checked first
  assert_eq(calls, ["static"])
}

///|
test "find_ws_route param beats wildcard" {
  // :name should be preferred over * for the same position
  let calls : Array[String] = []
  let app = App()
  app.ws("/ws/*", _ => calls.push("wildcard"))
  app.ws("/ws/:room", _ => calls.push("param"))
  guard app.find_ws_route("/ws/lobby") is Some((handler, _)) else {
    fail("expected route match")
  }
  handler(Open(WebSocketPeer(connection_id="test")))
  assert_eq(calls, ["param"])
}

///|
test "find_ws_route miss" {
  let app = App()
  app.ws("/ws", _ => ())
  inspect(app.find_ws_route("/other") is Some(_), content="false")
}
