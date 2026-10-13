///|
/// The main application type that holds route mappings, middleware, and WebSocket handlers.
///
/// Routing state is split by access pattern:
/// - `static_routes` — `Map[method, Map[path, handler]]` for O(1) static lookup
/// - `dynamic_routes` — radix tree for O(path_length) dynamic lookup
/// - `route_keys` — flat list of `(method, path)` for introspection via `routes()`
pub struct App {
  /// Path prefix prepended to all routes in this app/group.
  priv base_path : String
  /// Flat list of `(method, path)` for introspection via `routes()`.
  priv route_keys : Array[(String, String)]
  /// Ordered middleware list; each entry is `(base_path_scope, middleware)`.
  priv middlewares : Array[(String, Middleware)]
  /// O(1) lookup for fixed paths: `Map[method, Map[path, handler]]`.
  priv static_routes : Map[String, Map[String, HttpHandler]]
  /// O(path_length) lookup for parameterized paths (`:param`, `*`, `**`).
  priv dynamic_routes : @router.RadixRouter[HttpHandler]
  /// O(1) lookup for fixed WebSocket paths.
  priv ws_static_routes : Map[String, @ws.WebSocketHandler]
  /// O(path_length) lookup for parameterized WebSocket paths.
  /// Uses `"WS"` as a synthetic method key for consistent precedence with HTTP routes.
  priv ws_dynamic_routes : @router.RadixRouter[@ws.WebSocketHandler]
  /// Unique ID scoping the native WebSocket hub for this app instance.
  priv ws_runtime_id : String
  /// Catch-all handler for URLs that match no registered route, set via
  /// `set_not_found_handler`. Tried after the scoped list below misses.
  priv mut not_found_handler : HttpHandler?
  /// Path-scoped not-found handlers contributed by `App::group` merges,
  /// stored as `(absolute_prefix, handler)`. At dispatch time the
  /// longest matching prefix wins, so `/api/v1` beats `/api` regardless
  /// of registration order.
  priv scoped_not_found_handlers : Array[(String, HttpHandler)]
}

///|
let app_instance_counter : Ref[Int32] = Ref(0)

///|
fn next_app_instance_id() -> String {
  app_instance_counter.val += 1
  "app-\{app_instance_counter.val}"
}

///|
/// Creates a new App application instance with an optional base path prefix.
pub fn App::App(base_path~ : String = "") -> App {
  {
    base_path,
    route_keys: [],
    middlewares: [],
    static_routes: {},
    dynamic_routes: RadixRouter(),
    ws_static_routes: {},
    ws_dynamic_routes: RadixRouter(),
    ws_runtime_id: next_app_instance_id(),
    not_found_handler: None,
    scoped_not_found_handlers: [],
  }
}

///|
/// Returns an iterator over the registered route keys as `(method, path)` pairs.
pub fn App::routes(self : App) -> Iter[(String, String)] {
  self.route_keys.iter()
}

///|
/// Registers a route handler for the given HTTP method and path.
pub fn App::on(
  self : App,
  http_method : String,
  path : String,
  handler : HttpHandler,
) -> Unit {
  let path = self.base_path + path
  self.route_keys.push((http_method, path))

  // Cache routes by path type for faster lookup
  if !path.contains(":") && !path.contains("*") {
    // Static path: cache directly
    if self.static_routes.get(http_method) is Some(method_routes) {
      method_routes.set(path, handler)
    } else {
      let new_routes : Map[String, HttpHandler] = Map::from_array([
        (path, handler),
      ])
      self.static_routes.set(http_method, new_routes)
    }
  } else {
    // Dynamic path: compile and insert into radix tree
    let compiled = @router.CompiledRoute(path)
    self.dynamic_routes.insert(http_method, compiled, handler)
  }
}

///|
/// Registers a noraise GET handler. For most use cases, prefer `get()`.
pub fn App::get_raw(self : App, path : String, handler : HttpHandler) -> Unit {
  self.on("GET", path, handler)
}

///|
/// Registers a noraise POST handler.
pub fn App::post_raw(self : App, path : String, handler : HttpHandler) -> Unit {
  self.on("POST", path, handler)
}

///|
/// Registers a noraise PATCH handler.
pub fn App::patch_raw(self : App, path : String, handler : HttpHandler) -> Unit {
  self.on("PATCH", path, handler)
}

///|
/// Registers a noraise CONNECT handler.
pub fn App::connect_raw(
  self : App,
  path : String,
  handler : HttpHandler,
) -> Unit {
  self.on("CONNECT", path, handler)
}

///|
/// Registers a noraise PUT handler.
pub fn App::put_raw(self : App, path : String, handler : HttpHandler) -> Unit {
  self.on("PUT", path, handler)
}

///|
/// Registers a noraise DELETE handler.
pub fn App::delete_raw(
  self : App,
  path : String,
  handler : HttpHandler,
) -> Unit {
  self.on("DELETE", path, handler)
}

///|
/// Registers a noraise HEAD handler.
pub fn App::head_raw(self : App, path : String, handler : HttpHandler) -> Unit {
  self.on("HEAD", path, handler)
}

///|
/// Registers a noraise OPTIONS handler.
pub fn App::options_raw(
  self : App,
  path : String,
  handler : HttpHandler,
) -> Unit {
  self.on("OPTIONS", path, handler)
}

///|
/// Registers a noraise TRACE handler.
pub fn App::trace_raw(self : App, path : String, handler : HttpHandler) -> Unit {
  self.on("TRACE", path, handler)
}

///|
/// Registers a noraise handler that matches all HTTP methods.
pub fn App::all_raw(self : App, path : String, handler : HttpHandler) -> Unit {
  self.on("*", path, handler)
}

///|
/// Creates a route group with a shared base path prefix, merging its routes and middleware into the app.
pub fn App::group(
  self : App,
  base_path : String,
  configure : (App) -> Unit,
) -> Unit {
  let group = App(base_path=self.base_path + base_path)
  configure(group)
  // Merge route keys for introspection
  self.route_keys.append(group.route_keys)
  // Merge static route tables
  for i in group.static_routes {
    let (http_method, group_routes) = i
    match self.static_routes.get(http_method) {
      Some(existing_routes) =>
        group_routes.iter().each(route => existing_routes.set(route.0, route.1))
      None => self.static_routes.set(http_method, group_routes)
    }
  }
  // Merge dynamic routes (radix tree)
  self.dynamic_routes.merge(group.dynamic_routes)
  group.ws_static_routes.iter().each(i => self.ws_static_routes.set(i.0, i.1))
  self.ws_dynamic_routes.merge(group.ws_dynamic_routes)
  // Merge middlewares
  self.middlewares.append(group.middlewares)
  // Merge scoped not_found handlers from the group, plus the group's own
  // not_found_handler if set. Each entry stores the absolute prefix so
  // the dispatcher can pick the longest match independent of registration
  // order: with /api and /api/v1 both registered, /api/v1/missing fires
  // the /api/v1 handler regardless of which group was merged first.
  for entry in group.scoped_not_found_handlers {
    self.scoped_not_found_handlers.push(entry)
  }
  if group.not_found_handler is Some(group_handler) {
    let group_prefix = normalize_middleware_base_path(group.base_path)
    self.scoped_not_found_handlers.push((group_prefix, group_handler))
  }
}

///|
/// Resolves the not-found handler for a request path: longest-matching
/// scoped handler wins, then the catch-all from `set_not_found_handler`,
/// then the framework default. Used by both live serving and synthetic
/// dispatch so the two stay aligned.
fn App::resolve_not_found_handler(self : App, path : String) -> HttpHandler {
  let mut best : (Int32, HttpHandler)? = None
  for entry in self.scoped_not_found_handlers {
    let (prefix, handler) = entry
    if @httputil.path_scope_matches(prefix, path) {
      let score = prefix.length()
      // Strict > so two groups at the same prefix follow later-wins
      // semantics (same as overwriting a key in a Map): the most recently
      // registered handler at that prefix takes precedence.
      match best {
        Some((best_score, _)) if best_score > score => ()
        _ => best = Some((score, handler))
      }
    }
  }
  match best {
    Some((_, handler)) => handler
    None =>
      match self.not_found_handler {
        Some(handler) => handler
        None => handle_not_found()
      }
  }
}

///|
/// Sets a custom handler for 404 Not Found responses.
pub fn App::set_not_found_handler(self : App, handler : HttpHandler) -> Unit {
  self.not_found_handler = Some(handler)
}

///|
/// Returns true if any custom not-found handler has been registered,
/// either as the catch-all via `set_not_found_handler` or via a group.
pub fn App::has_not_found_handler(self : App) -> Bool {
  self.not_found_handler is Some(_) ||
  !self.scoped_not_found_handlers.is_empty()
}

///|
/// Returns all WebSocket runtime IDs scoped to this App instance, in
/// the form `<app_id>/serve-<n>` (one per active `serve_on`/`serve`
/// invocation). Used in tests to verify runtime registration and
/// cleanup; production code should not need this.
pub fn App::ws_runtime_ids(self : App) -> Array[String] {
  let prefix = self.ws_runtime_id + "/"
  let result : Array[String] = []
  for runtime_id in @ws.registered_runtime_ids() {
    if runtime_id.has_prefix(prefix) {
      result.push(runtime_id)
    }
  }
  result
}

///|
/// Registers a WebSocket handler for the given path, matched regardless of HTTP method.
///
/// Dynamic patterns (`:param`, `*`, `**`) are inserted into the same radix
/// tree implementation used for HTTP routes, giving them consistent precedence:
/// static > param > wildcard > globstar. Re-registering the same path overrides
/// the previous handler.
pub fn App::ws(
  self : App,
  path : String,
  handler : @ws.WebSocketHandler,
) -> Unit {
  let path = self.base_path + path
  // Static path: direct map lookup
  if !path.contains(":") && !path.contains("*") {
    self.ws_static_routes.set(path, handler)
  } else {
    // Dynamic path: insert into radix tree (WS is a synthetic method key)
    let compiled = @router.CompiledRoute(path)
    self.ws_dynamic_routes.insert("WS", compiled, handler)
  }
}
