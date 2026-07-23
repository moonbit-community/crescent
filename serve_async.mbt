///|
fn request_method_to_string(meth : @http.RequestMethod) -> String {
  match meth {
    Get => "GET"
    Head => "HEAD"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
    Connect => "CONNECT"
    Options => "OPTIONS"
    Trace => "TRACE"
    Patch => "PATCH"
  }
}

///|
test "request_method_to_string converts all HTTP methods" {
  debug_inspect(
    request_method_to_string(Get),
    content=(
      #|"GET"
    ),
  )
  debug_inspect(
    request_method_to_string(Head),
    content=(
      #|"HEAD"
    ),
  )
  debug_inspect(
    request_method_to_string(Post),
    content=(
      #|"POST"
    ),
  )
  debug_inspect(
    request_method_to_string(Put),
    content=(
      #|"PUT"
    ),
  )
  debug_inspect(
    request_method_to_string(Delete),
    content=(
      #|"DELETE"
    ),
  )
  debug_inspect(
    request_method_to_string(Connect),
    content=(
      #|"CONNECT"
    ),
  )
  debug_inspect(
    request_method_to_string(Options),
    content=(
      #|"OPTIONS"
    ),
  )
  debug_inspect(
    request_method_to_string(Trace),
    content=(
      #|"TRACE"
    ),
  )
  debug_inspect(
    request_method_to_string(Patch),
    content=(
      #|"PATCH"
    ),
  )
}

/// Copies request headers from the async runtime.
/// Uses Map::from_iter for efficient bulk construction instead of
/// per-key insertion.

///|
fn copy_async_headers(headers : Map[String, String]) -> Map[String, String] {
  Map::from_iter(headers.iter())
}

///|
let ws_serve_runtime_counter : Ref[Int] = Ref(0)

///|
fn next_ws_serve_runtime_id(app : App) -> String {
  ws_serve_runtime_counter.val += 1
  "\{app.ws_runtime_id}/serve-\{ws_serve_runtime_counter.val}"
}

///|
fn header_contains_token_case_insensitive(
  headers : Map[String, String],
  header_name : String,
  token_name : String,
) -> Bool {
  let normalized_token_name = token_name.to_lower()
  match @httputil.get_header_case_insensitive(headers, header_name) {
    Some(value) => {
      for token in value.split(",") {
        if token.trim().to_lower() == normalized_token_name {
          return true
        }
      }
      false
    }
    None => false
  }
}

///|
test "header_contains_token_case_insensitive finds token in comma-separated list" {
  let headers : Map[String, String] = { "Connection": "keep-alive, Upgrade" }
  debug_inspect(
    header_contains_token_case_insensitive(headers, "Connection", "upgrade"),
    content="true",
  )
}

///|
test "header_contains_token_case_insensitive returns false when token not found" {
  let headers : Map[String, String] = { "Connection": "keep-alive" }
  debug_inspect(
    header_contains_token_case_insensitive(headers, "Connection", "upgrade"),
    content="false",
  )
}

///|
test "header_contains_token_case_insensitive is case insensitive on header name" {
  let headers : Map[String, String] = { "CONNECTION": "Upgrade" }
  debug_inspect(
    header_contains_token_case_insensitive(headers, "connection", "upgrade"),
    content="true",
  )
}

///|
test "header_contains_token_case_insensitive returns false for missing header" {
  let headers : Map[String, String] = {}
  debug_inspect(
    header_contains_token_case_insensitive(headers, "Connection", "upgrade"),
    content="false",
  )
}

///|
fn @http.Request::is_websocket_upgrade_request(request : Self) -> Bool {
  let has_connection_upgrade = header_contains_token_case_insensitive(
    request.headers,
    "connection",
    "upgrade",
  )
  let has_websocket_upgrade = match
    @httputil.get_header_case_insensitive(request.headers, "upgrade") {
    Some(value) => value.trim().to_lower() == "websocket"
    None => false
  }
  has_connection_upgrade && has_websocket_upgrade
}

///|
test "is_websocket_upgrade_request returns true with both headers" {
  let request : @http.Request = {
    meth: Get,
    path: "/",
    headers: { "Connection": "upgrade", "Upgrade": "websocket" },
  }
  debug_inspect(request.is_websocket_upgrade_request(), content="true")
}

///|
test "is_websocket_upgrade_request returns false without Connection header" {
  let request : @http.Request = {
    meth: Get,
    path: "/",
    headers: { "Upgrade": "websocket" },
  }
  debug_inspect(request.is_websocket_upgrade_request(), content="false")
}

///|
test "is_websocket_upgrade_request returns false without Upgrade header" {
  let request : @http.Request = {
    meth: Get,
    path: "/",
    headers: { "Connection": "upgrade" },
  }
  debug_inspect(request.is_websocket_upgrade_request(), content="false")
}

///|
test "is_websocket_upgrade_request returns false with empty headers" {
  let request : @http.Request = { meth: Get, path: "/", headers: {} }
  debug_inspect(request.is_websocket_upgrade_request(), content="false")
}

///|
fn looks_like_websocket_handshake_request(request : @http.Request) -> Bool {
  let websocket_upgrade_header = match
    @httputil.get_header_case_insensitive(request.headers, "upgrade") {
    Some(value) => value.trim().to_lower() == "websocket"
    None => false
  }
  for pair in request.headers {
    let (key, _) = pair
    if key.to_lower().has_prefix("sec-websocket-") {
      return true
    }
  }
  request.is_websocket_upgrade_request() || websocket_upgrade_header
}

///|
priv enum HttpRouteLookup {
  Found(HttpHandler, Map[String, StringView])
  MethodNotAllowed(String)
  Options(String)
  NotFound
}

///|
fn allow_header_value(methods : Array[String]) -> String {
  methods.join(", ")
}

///|
test "allow_header_value joins methods with comma and space" {
  debug_inspect(
    allow_header_value(["GET", "POST", "PUT"]),
    content=(
      #|"GET, POST, PUT"
    ),
  )
}

///|
test "allow_header_value with single method" {
  debug_inspect(
    allow_header_value(["GET"]),
    content=(
      #|"GET"
    ),
  )
}

///|
test "allow_header_value with empty array" {
  debug_inspect(
    allow_header_value([]),
    content=(
      #|""
    ),
  )
}

///|
fn method_not_allowed_handler(allow : String) -> HttpHandler {
  HttpHandler(event => {
    event.res.headers.set("Allow", allow)
    HttpResponse(status_code=MethodNotAllowed).body("Method Not Allowed")
  })
}

///|
fn options_handler(allow : String) -> HttpHandler {
  HttpHandler(event => {
    event.res.headers.set("Allow", allow)
    HttpResponse(status_code=NoContent)
  })
}

///|
fn App::lookup_http_route(
  self : App,
  http_method : String,
  request_path : String,
) -> HttpRouteLookup {
  match self.find_route(http_method, request_path) {
    Some((handler, params)) => return Found(handler, params)
    None => ()
  }
  if http_method == "HEAD" {
    match self.find_route_for_method("GET", request_path) {
      Some((handler, params)) => return Found(handler, params)
      None => ()
    }
  }
  let allow = self.allowed_methods(request_path, http_method == "OPTIONS")
  if allow.is_empty() {
    NotFound
  } else if http_method == "OPTIONS" {
    Options(allow_header_value(allow))
  } else {
    MethodNotAllowed(allow_header_value(allow))
  }
}

///|
/// Dispatches one inbound HTTP request through the App pipeline.
///
/// Called per-request by `run_native_server` (and by the graceful-shutdown
/// accept loop in `serve_on`). Runs to completion once per request: this
/// function does not itself loop, keep-alive reuse is driven by the caller.
///
/// Pipeline phases, in order:
///
///   1. **WebSocket dispatch.** If the request looks like a WS handshake AND
///      a matching `ws` route exists, hand off to `@ws.handle_route_async`
///      and return (the response is sent inside the WS handler). A strict
///      upgrade request with no matching route yields `404`. A non-strict
///      lookalike with no match falls through to the HTTP pipeline.
///   2. **Body reading.** Skipped entirely for bodyless methods
///      (GET/HEAD/DELETE/OPTIONS/TRACE) unless Content-Length > 0 or
///      Transfer-Encoding: chunked — chunked bodies MUST still be consumed
///      to keep the keep-alive stream in sync. Otherwise reads up to
///      `max_request_body_bytes` with `request_body_read_timeout_ms`; on
///      violation the helper sends `413` or `408` and we return early.
///   3. **Route lookup.** `lookup_http_route` returns one of:
///      `Found` (normal), `MethodNotAllowed` (synthesize 405),
///      `Options` (synthesize 204 + Allow for CORS-style preflight), or
///      `NotFound` (user's `not_found_handler` if set, else default 404).
///   4. **Handler + middleware execution.** Run the onion chain, optionally
///      wrapped in `with_timeout_opt(handler_timeout_ms)`. The timeout covers
///      handler execution only, NOT response transmission — otherwise a late
///      timeout could tear down a partially-sent response and corrupt the
///      keep-alive framing. A timed-out handler yields `504 Gateway Timeout`.
///   5. **Response transmission.** `send_response_async` finalizes headers
///      (cookies, Date) and writes to the socket.
///
/// The function does not raise; transport/IO errors surface through
/// `send_response_async`'s early returns and are caught by the keep-alive
/// loop in `serve_on` (which closes the connection on error).
async fn App::handle_request(
  self : App,
  ws_runtime_id : String,
  request : @http.Request,
  body_reader : &@io.Reader,
  conn : @http.ServerConnection,
  options : NativeServeOptions,
) -> Unit {
  // Target is the path *without* query string; query-string parsing happens
  // lazily inside the handler via Event helpers.
  let request_path = @httputil.request_target_path(request.path)

  // -------------------------------------------------------------------------
  // Phase 1: WebSocket upgrade dispatch
  // -------------------------------------------------------------------------
  // Two-tier detection: a "strict" check that the upgrade headers are
  // well-formed, and a cheaper "looks-like" heuristic. We only run the
  // heuristic when the app actually has WS routes registered — otherwise
  // every HTTP request would pay for handshake inspection.
  let strict_websocket_upgrade = request.is_websocket_upgrade_request()
  let has_ws_routes = !self.ws_static_routes.is_empty() ||
    !self.ws_dynamic_routes.is_empty()
  let websocket_like_request = if strict_websocket_upgrade {
    true
  } else if has_ws_routes {
    looks_like_websocket_handshake_request(request)
  } else {
    false
  }
  if websocket_like_request {
    // Resolve WS option defaults here (not in the handler) so per-connection
    // settings are captured once before entering the peer loop.
    let websocket_max_message_bytes = options.websocket_max_message_bytes
    let websocket_outgoing_queue_capacity = options.websocket_outgoing_queue_capacity.unwrap_or(
      @ws.DEFAULT_OUTGOING_QUEUE_CAPACITY,
    )
    let websocket_overflow_policy = options.websocket_overflow_policy.unwrap_or(
      DropOldest,
    )
    let websocket_read_timeout_ms = options.websocket_read_timeout_ms
    match self.find_ws_route(request_path) {
      Some((ws_handler, route_params)) => {
        // Copy StringView params into owned Strings: the peer outlives the
        // request buffer, so borrowed views would dangle.
        let ws_params : Map[String, String] = {}
        route_params.each((k, v) => ws_params.set(k, v.to_owned()))
        @ws.handle_route_async(
          ws_runtime_id, request, conn, ws_handler, ws_params, websocket_max_message_bytes,
          websocket_outgoing_queue_capacity, websocket_overflow_policy, websocket_read_timeout_ms,
        )
        return
      }
      // Strict upgrade with no matching route: client asked for WS explicitly,
      // we refuse with 404 (and connection close, inside send_not_found_async).
      None if strict_websocket_upgrade => {
        send_not_found_async(request, conn)
        return
      }
      // Non-strict lookalike with no match: treat as a plain HTTP request,
      // fall through to the normal pipeline below.
      None => ()
    }
  }

  // -------------------------------------------------------------------------
  // Phase 2: Request body reading
  // -------------------------------------------------------------------------
  let http_method_text = request_method_to_string(request.meth)
  // Skip body reading for methods that typically have no body, UNLESS:
  //   - Content-Length > 0 (client explicitly sent a body), or
  //   - Transfer-Encoding: chunked (chunked bodies MUST be consumed, even
  //     on GET/HEAD/etc., or the next request on this keep-alive connection
  //     will parse the chunk trailer as a new request line).
  let has_content_length = request_content_length(request) is Some(len) &&
    len > 0
  let is_chunked = header_contains_token_case_insensitive(
    request.headers,
    "transfer-encoding",
    "chunked",
  )
  let has_body_hint = has_content_length || is_chunked
  let request_body : Bytes = if !has_body_hint &&
    request.meth is (Get | Head | Delete | Options | Trace) {
    b""
  } else {
    let max_request_body_bytes = options.max_request_body_bytes
    let request_body_read_timeout_ms = options.request_body_read_timeout_ms
    // read_request_body_with_policy_async handles both limits and sends the
    // appropriate 413/408 response itself; we just early-return if rejected.
    match
      read_request_body_with_policy_async(
        request, body_reader, conn, max_request_body_bytes, request_body_read_timeout_ms,
      ) {
      Body(request_body) => request_body
      RequestRejected => return
    }
  }

  // -------------------------------------------------------------------------
  // Phase 3: Route lookup
  // -------------------------------------------------------------------------
  // lookup_http_route distinguishes four outcomes. Only `Found` uses the
  // user's handler; the others synthesize framework-level responses:
  //   - MethodNotAllowed: path matches *some* method, but not this one (405)
  //   - Options: CORS-style preflight — synthesize 204 + Allow header
  //   - NotFound: no path match — prefer user's not_found_handler if set
  let (params, handler) = match
    self.lookup_http_route(http_method_text, request_path) {
    Found(matched_handler, matched_params) => (matched_params, matched_handler)
    MethodNotAllowed(allow) => ({}, method_not_allowed_handler(allow))
    Options(allow) => ({}, options_handler(allow))
    NotFound => ({}, self.resolve_not_found_handler(request_path))
  }

  // -------------------------------------------------------------------------
  // Phase 4: Handler execution (with optional timeout)
  // -------------------------------------------------------------------------
  // Build the user-facing event. `res` starts as 200 OK; the handler mutates
  // it (status_code, headers, cookies) and returns a Responder for the body.
  let event = {
    req: HttpRequest::from_method_string(
      http_method_text,
      request.path,
      copy_async_headers(request.headers),
      request_body,
    ),
    res: HttpResponse(status_code=OK),
    params,
  }
  match options.handler_timeout_ms {
    Some(timeout_ms) =>
      // IMPORTANT: the timeout wraps only the handler+middleware chain, not
      // send_response_async. If transmission were inside the timeout and the
      // timeout fired mid-write, we'd leave a truncated response on the wire
      // and desync the keep-alive stream. Timing out strictly before any
      // bytes are sent lets us fall back to a clean 504 response.
      match
        @async.with_timeout_opt(timeout_ms, () => {
          execute_middlewares(self.middlewares, event, handler)
        }) {
        Some(responder) =>
          send_response_async(request, conn, event.res, responder)
        None => send_gateway_timeout_async(request, conn)
      }
    None => {
      // No timeout: run handler, then transmit. Phase 5 happens inline here.
      let responder = execute_middlewares(self.middlewares, event, handler)
      send_response_async(request, conn, event.res, responder)
    }
  }
}

///|
async fn run_native_server(
  app : App,
  ws_runtime_id : String,
  server : @http.Server,
  options : NativeServeOptions,
) -> Unit {
  match options.max_connections {
    Some(max_connections) =>
      server.run_forever(allow_failure=true, max_connections~, (
        request,
        body_reader,
        conn,
      ) => {
        app.handle_request(ws_runtime_id, request, body_reader, conn, options)
      })
    None =>
      server.run_forever(allow_failure=true, (request, body_reader, conn) => {
        app.handle_request(ws_runtime_id, request, body_reader, conn, options)
      })
  }
}

///|
async fn wait_for_shutdown_signal(shutdown : @async.Queue[Unit]) -> Unit {
  shutdown.get() catch {
    _ => ()
  }
}

///|
/// Starts serving HTTP requests on the given server.
/// `max_connections`, if present, limits the number of client connections
/// handled in parallel by the underlying `@http.Server`.
/// `max_request_body_bytes`, if present, rejects oversized request bodies
/// with `413 Request Entity Too Large`.
/// `request_body_read_timeout_ms`, if present, rejects slow request bodies
/// with `408 Request Timeout`.
/// `websocket_max_message_bytes`, if present, closes websocket connections
/// with `1009 MessageTooBig` when an inbound message exceeds that many bytes.
/// `websocket_outgoing_queue_capacity`, if present, bounds buffered outbound
/// websocket messages per connection.
/// `websocket_overflow_policy`, if present, chooses whether a full outbound
/// websocket queue drops the oldest or latest message.
/// `websocket_read_timeout_ms`, if present, closes websocket connections
/// after that many milliseconds waiting for the next inbound message.
/// When `shutdown` is supplied, serving stops once the queue receives a unit
/// or is closed. `shutdown.put(())` wakes one waiter; `shutdown.close()`
/// broadcasts to all waiters. When `shutdown_timeout_ms` is set, shutdown is
/// graceful: the server stops accepting new connections and waits up to that
/// many milliseconds for in-flight requests to complete before force-cancelling.
/// Otherwise shutdown is cancellation-based (active requests are aborted
/// immediately).
pub async fn App::serve_on(
  self : App,
  server : @http.Server,
  shutdown? : @async.Queue[Unit],
  options? : NativeServeOptions = NativeServeOptions(),
) -> Unit {
  let ws_runtime_id = next_ws_serve_runtime_id(self)
  defer @ws.cleanup_runtime(ws_runtime_id)
  match shutdown {
    None => run_native_server(self, ws_runtime_id, server, options)
    Some(shutdown) =>
      match options.shutdown_timeout_ms {
        Some(timeout_ms) => {
          // Graceful shutdown with manual accept loop.
          // Architecture: inner task group tracks handler tasks; outer group
          // provides the cancellation boundary for the hard timeout.
          //
          // Timeline:
          // 1. Accept loop runs, spawning handler tasks into inner group.
          // 2. Shutdown signal → set draining flag, close server.
          // 3. Accept loop exits (accept fails after close).
          // 4. Inner group waits for handler tasks to finish current requests.
          // 5. Hard timeout (started AFTER shutdown) cancels everything.
          let sem : @async.Semaphore? = match options.max_connections {
            Some(n) => Some(Semaphore(n))
            None => None
          }
          let draining : Ref[Bool] = Ref(false)
          let handlers_drained : @async.Queue[Unit] = Queue(kind=Unbounded)
          @async.with_task_group(outer => {
            // Inner group: accept loop + handler tasks
            outer.spawn_bg(no_wait=true, allow_failure=true, () => {
              @async.with_task_group(inner => {
                // Accept loop is the main function of inner group.
                // When it exits, inner group waits for handler children.
                for ;; {
                  let (conn, _addr) = server.accept() catch {
                    _ => break // server closed, stop accepting
                  }
                  match sem {
                    Some(s) => s.acquire()
                    None => ()
                  }
                  inner.spawn_bg(allow_failure=true, () => {
                    defer (match sem {
                      Some(s) => s.release()
                      None => ()
                    })
                    // Keep-alive loop: check draining after each request
                    for ;; {
                      let request = conn.read_request() catch {
                        _ => {
                          conn.close()
                          break
                        }
                      }
                      let body_reader : &@io.Reader = conn
                      self.handle_request(
                        ws_runtime_id, request, body_reader, conn, options,
                      ) catch {
                        _ => {
                          conn.close()
                          break
                        }
                      }
                      if draining.val {
                        conn.close()
                        break
                      }
                    }
                  })
                }
              })
              // Inner group done: all handlers have finished
              handlers_drained.put(())
            })
            // Outer main: wait for shutdown, then drain with timeout
            wait_for_shutdown_signal(shutdown)
            draining.val = true
            server.close()
            // Timeout starts NOW (after shutdown signal, not from boot)
            @async.any([
              () => handlers_drained.get() catch { _ => () },
              () => @async.sleep(timeout_ms),
            ])
            // Outer main returns → outer group cancels inner (no_wait=true)
          })
        }
        None =>
          // Default: cancellation-based (abort active requests)
          @async.any([
            () => run_native_server(self, ws_runtime_id, server, options),
            () => wait_for_shutdown_signal(shutdown),
          ])
      }
  }
}

///|
/// Starts serving HTTP requests on the given port.
/// `max_connections`, if present, limits the number of client connections
/// handled in parallel by the underlying `@http.Server`.
/// `max_request_body_bytes`, if present, rejects oversized request bodies
/// with `413 Request Entity Too Large`.
/// `request_body_read_timeout_ms`, if present, rejects slow request bodies
/// with `408 Request Timeout`.
/// `websocket_max_message_bytes`, if present, closes websocket connections
/// with `1009 MessageTooBig` when an inbound message exceeds that many bytes.
/// `websocket_outgoing_queue_capacity`, if present, bounds buffered outbound
/// websocket messages per connection.
/// `websocket_overflow_policy`, if present, chooses whether a full outbound
/// websocket queue drops the oldest or latest message.
/// `websocket_read_timeout_ms`, if present, closes websocket connections
/// after that many milliseconds waiting for the next inbound message.
/// When `shutdown` is supplied, serving stops once the queue receives a unit
/// or is closed. See `serve_on` for shutdown semantics.
pub async fn App::serve(
  self : App,
  port~ : Int,
  shutdown? : @async.Queue[Unit],
  options? : NativeServeOptions = NativeServeOptions(),
) -> Unit {
  let addr = @socket.Addr::parse("0.0.0.0:\{port}")
  let server = @http.Server(addr, reuse_addr=true)
  self.serve_on(server, shutdown?, options~)
}
