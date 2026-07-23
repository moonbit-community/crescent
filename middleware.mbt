///|
/// The continuation function passed to middleware, calling the next handler in the chain.
pub(all) struct MiddlewareNext(async () -> &Responder noraise)

///|
/// A middleware function that receives a request event and a next continuation, and returns a response.
pub(all) struct Middleware(async (Event, MiddlewareNext) -> &Responder noraise)

///|
fn normalize_middleware_base_path(base_path : String) -> String {
  if base_path == "" {
    ""
  } else if base_path.length() > 1 && base_path[base_path.length() - 1:] == "/" {
    base_path[:base_path.length() - 1].to_owned()
  } else {
    base_path
  }
}

///|
test "normalize_middleware_base_path with empty string" {
  debug_inspect(
    normalize_middleware_base_path(""),
    content=(
      #|""
    ),
  )
}

///|
test "normalize_middleware_base_path with root slash" {
  debug_inspect(
    normalize_middleware_base_path("/"),
    content=(
      #|"/"
    ),
  )
}

///|
test "normalize_middleware_base_path strips trailing slash" {
  debug_inspect(
    normalize_middleware_base_path("/api/"),
    content=(
      #|"/api"
    ),
  )
}

///|
test "normalize_middleware_base_path keeps path without trailing slash" {
  debug_inspect(
    normalize_middleware_base_path("/api"),
    content=(
      #|"/api"
    ),
  )
}

///|
/// Adds a middleware to the app, optionally scoped to a base path prefix.
pub fn App::use_middleware(
  self : App,
  middleware : Middleware,
  base_path? : String,
) -> Unit {
  let base_path = normalize_middleware_base_path(
    base_path.unwrap_or(self.base_path),
  )
  // Store middleware together with path scope
  self.middlewares.push((base_path, middleware))
}

///|
// Execute middleware chain with path matching (onion model)
async fn execute_middlewares(
  middlewares : Array[(String, Middleware)],
  event : Event,
  final_handler : HttpHandler,
) -> &Responder noraise {
  // Fast path: no middleware registered
  if middlewares.is_empty() {
    return final_handler(event)
  }
  // Filter middlewares matching the request path
  let matched_middlewares = []
  let request_path = event.req.path()
  for mw in middlewares {
    let (base_path, middleware) = mw
    // Empty base_path means global middleware;
    // otherwise check if the request path matches the scope
    if base_path == "" || @httputil.path_scope_matches(base_path, request_path) {
      matched_middlewares.push(middleware)
    }
  }
  // Fast path: no middleware matched this path
  if matched_middlewares.is_empty() {
    return final_handler(event)
  }
  // Build middleware chain recursively (onion model)
  execute_middleware_chain(matched_middlewares, 0, event, final_handler)
}

///|
// Recursively execute middleware chain
async fn execute_middleware_chain(
  middlewares : Array[Middleware],
  index : Int,
  event : Event,
  final_handler : HttpHandler,
) -> &Responder noraise {
  if index >= middlewares.length() {
    // All middlewares executed: call the final handler
    final_handler(event)
  } else {
    // Execute current middleware
    let current_middleware = middlewares[index]
    let next = MiddlewareNext(() => {
      execute_middleware_chain(middlewares, index + 1, event, final_handler)
    })
    current_middleware(event, next)
  }
}

///|
async test "empty middleware list calls final handler directly" {
  let event = Event::{
    req: HttpRequest(Get, "/test", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let handler : HttpHandler = _ => "handler-result"
  let result = execute_middlewares([], event, handler)
  let buf = Buffer()
  result.output(buf)
  debug_inspect(
    @utf8.decode(buf.contents()),
    content=(
      #|"handler-result"
    ),
  )
}

///|
async test "single middleware wraps final handler" {
  let order : Array[String] = []
  let mw : Middleware = (_event, next) => {
    order.push("mw-before")
    let result = next()
    order.push("mw-after")
    result
  }
  let event = Event::{
    req: HttpRequest(Get, "/test", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let handler : HttpHandler = _ => {
    order.push("handler")
    "done"
  }
  let middlewares : Array[(String, Middleware)] = [("", mw)]
  ignore(execute_middlewares(middlewares, event, handler))
  debug_inspect(
    order,
    content=(
      #|["mw-before", "handler", "mw-after"]
    ),
  )
}

///|
async test "multiple middlewares execute in onion model order" {
  let order : Array[String] = []
  let mw1 : Middleware = (_event, next) => {
    order.push("mw1-before")
    let result = next()
    order.push("mw1-after")
    result
  }
  let mw2 : Middleware = (_event, next) => {
    order.push("mw2-before")
    let result = next()
    order.push("mw2-after")
    result
  }
  let event = Event::{
    req: HttpRequest(Get, "/test", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let handler : HttpHandler = _ => {
    order.push("handler")
    "done"
  }
  let middlewares : Array[(String, Middleware)] = [("", mw1), ("", mw2)]
  ignore(execute_middlewares(middlewares, event, handler))
  debug_inspect(
    order,
    content=(
      #|["mw1-before", "mw2-before", "handler", "mw2-after", "mw1-after"]
    ),
  )
}

///|
async test "path-scoped middleware skips non-matching request" {
  let order : Array[String] = []
  let mw : Middleware = (_event, next) => {
    order.push("api-mw")
    next()
  }
  let event = Event::{
    req: HttpRequest(Get, "/test", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let handler : HttpHandler = _ => {
    order.push("handler")
    "done"
  }
  let middlewares : Array[(String, Middleware)] = [("/api", mw)]
  ignore(execute_middlewares(middlewares, event, handler))
  debug_inspect(
    order,
    content=(
      #|["handler"]
    ),
  )
}

///|
async test "path-scoped middleware executes for matching request" {
  let order : Array[String] = []
  let mw : Middleware = (_event, next) => {
    order.push("api-mw")
    next()
  }
  let event = Event::{
    req: HttpRequest(Get, "/api/users", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let handler : HttpHandler = _ => {
    order.push("handler")
    "done"
  }
  let middlewares : Array[(String, Middleware)] = [("/api", mw)]
  ignore(execute_middlewares(middlewares, event, handler))
  debug_inspect(
    order,
    content=(
      #|["api-mw", "handler"]
    ),
  )
}
