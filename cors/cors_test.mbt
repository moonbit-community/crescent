///|
fn make_event(
  http_method : @crescent.HttpMethod,
  headers : Map[String, String],
) -> @crescent.Event {
  {
    req: @crescent.HttpRequest(http_method, "/resource", headers, raw_body=b""),
    res: @crescent.HttpResponse(status_code=OK),
    params: {},
  }
}

///|
test "origin=* with credentials=true reflects request origin" {
  let event = make_event(Get, { "origin": "https://myapp.com" })
  append_cors_headers(event, origin="*", credentials=true)
  guard event.res.headers
    is {
      "Access-Control-Allow-Origin": "https://myapp.com",
      "Access-Control-Allow-Credentials": "true",
      "Vary": "Origin",
      ..
    } else {
    fail("missing expected CORS response headers")
  }
}

///|
test "explicit origin is preserved with credentials" {
  let event = make_event(Get, { "origin": "https://myapp.com" })
  append_cors_headers(event, origin="https://allowed.com", credentials=true)
  assert_eq(
    event.res.headers.get("Access-Control-Allow-Origin"),
    Some("https://allowed.com"),
  )
}

///|
test "Vary header handles existing lowercase vary" {
  let event = make_event(Get, { "origin": "https://myapp.com" })
  // Pre-populate a lowercase Vary header with a different token
  event.res.headers["vary"] = "Accept-Encoding"
  append_cors_headers(event, origin="*", credentials=true)
  // Should append Origin to the existing (lowercase) Vary header,
  // not create a duplicate.
  let mut vary_count = 0
  event.res.headers.each((k, _v) => {
    if k.to_lower() == "vary" {
      vary_count = vary_count + 1
    }
  })
  assert_eq(vary_count, 1)
  // The existing header should now contain both tokens
  let vary = event.res.headers.get("vary").unwrap()
  assert_true(vary.contains("Accept-Encoding"))
  assert_true(vary.contains("Origin"))
}

///|
test "Vary header doesn't duplicate Origin token" {
  let event = make_event(Get, { "origin": "https://myapp.com" })
  event.res.headers["Vary"] = "Origin"
  append_cors_headers(event, origin="*", credentials=true)
  // Should not create "Origin, Origin"
  assert_eq(event.res.headers.get("Vary"), Some("Origin"))
}

///|
test "origin=* without credentials stays as *" {
  let event = make_event(Get, { "origin": "https://any.com" })
  append_cors_headers(event, origin="*", credentials=false)
  assert_eq(event.res.headers.get("Access-Control-Allow-Origin"), Some("*"))
}

///|
test "is_preflight_request requires cors headers and options" {
  debug_inspect(
    is_preflight_request(
      make_event(Options, {
        "origin": "https://example.com",
        "access-control-request-method": "PUT",
      }),
    ),
    content="true",
  )
  debug_inspect(
    is_preflight_request(
      make_event(Options, { "origin": "https://example.com" }),
    ),
    content="false",
  )
  debug_inspect(
    is_preflight_request(
      make_event(Get, {
        "origin": "https://example.com",
        "access-control-request-method": "PUT",
      }),
    ),
    content="false",
  )
}

///|
suberror ServerNotReady

///|
suberror SocketBindUnavailable

///|
async fn allocate_test_server() -> @http.Server {
  let addr = @socket.Addr::parse("127.0.0.1:0") catch {
    _ => raise SocketBindUnavailable
  }
  @http.Server(addr, reuse_addr=true) catch {
    @os_error.OSError(errno, ..) if errno == 1 => raise SocketBindUnavailable
    @os_error.OSError(_) as err if err.is_EACCES() =>
      raise SocketBindUnavailable
    err => fail("unexpected bind check failure: \{err}")
  }
}

///|
fn localhost_url(port : Int, path : String) -> String {
  "http://127.0.0.1:\{port}\{path}"
}

///|
async fn wait_until_ready(port : Int) -> Unit {
  @async.retry(FixedDelay(20), max_retry=50, () => {
    let (response, _body) = @http.get(localhost_url(port, "/__cors_ready"))
    guard response.code == 200 else { raise ServerNotReady }
  })
}

///|
async fn with_test_server(
  app : @crescent.App,
  run_test : async (Int) -> Unit,
) -> Unit {
  let server = allocate_test_server()
  let port = server.addr.port()
  app.get("/__cors_ready", _ => "ready")
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => app.serve_on(server))
    wait_until_ready(port)
    run_test(port)
  })
}

///|
async fn issue_request(
  port : Int,
  meth : @http.RequestMethod,
  path : String,
  headers? : Map[String, String],
) -> (@http.Response, Bytes) {
  let client = @http.Client("http://127.0.0.1:\{port}")
  defer client.close()
  client.request(meth, path, extra_headers=headers.unwrap_or({}))
  let response = client.end_request()
  let response_body = client.read_all().binary()
  (response, response_body)
}

///|
async fn issue_raw_request_headers(port : Int, request : String) -> String {
  let addr = @socket.Addr::parse("127.0.0.1:\{port}") catch {
    _ => fail("invalid raw request address")
  }
  let client = @socket.Tcp::connect(addr)
  defer client.close()
  client.write(request)
  client.read_until("\r\n\r\n").unwrap_or("")
}

///|
async test "handle_cors serves preflight requests through async server" {
  let handler_called = Ref(false)
  let app = @crescent.App()
  app.use_middleware(
    handle_cors(
      origin="https://frontend.example",
      methods="GET, PATCH",
      allow_headers="Content-Type, Authorization",
      credentials=true,
      max_age=7200,
    ),
  )
  app.options("/resource", _ => {
    handler_called.val = true
    @crescent.text("unexpected")
  })
  with_test_server(app, port => {
    let (response, body) = issue_request(port, Options, "/resource", headers={
      "origin": "https://frontend.example",
      "access-control-request-method": "PATCH",
    })
    assert_eq(response.code, 200)
    assert_eq(body, b"")
    guard response.headers
      is {
        "access-control-allow-origin": "https://frontend.example",
        "access-control-allow-methods": "GET, PATCH",
        "access-control-allow-headers": "Content-Type, Authorization",
        "access-control-allow-credentials": "true",
        "access-control-max-age": "7200",
        ..
      } else {
      fail("missing expected preflight CORS headers")
    }
    debug_inspect(handler_called.val, content="false")
  })
}

///|
async test "handle_cors decorates normal requests through async server" {
  let app = @crescent.App()
  app.use_middleware(
    handle_cors(
      origin="https://frontend.example",
      methods="GET, POST",
      allow_headers="Content-Type",
      expose_headers="X-Trace-Id",
      credentials=true,
    ),
  )
  app.get("/resource", _ => "ok")
  with_test_server(app, port => {
    let (response, body) = issue_request(port, Get, "/resource", headers={
      "origin": "https://frontend.example",
    })
    assert_eq(response.code, 200)
    assert_eq(@utf8.decode(body) catch { _ => "" }, "ok")
    guard response.headers
      is {
        "access-control-allow-origin": "https://frontend.example",
        "access-control-allow-methods": "GET, POST",
        "access-control-allow-headers": "Content-Type",
        "access-control-expose-headers": "X-Trace-Id",
        "access-control-allow-credentials": "true",
        ..
      } else {
      fail("missing expected CORS response headers")
    }
  })
}

///|
async test "handle_cors does not short-circuit non-preflight options" {
  let handler_called = Ref(false)
  let app = @crescent.App()
  app.use_middleware(
    handle_cors(
      origin="https://frontend.example",
      methods="GET, OPTIONS",
      allow_headers="Content-Type",
      expose_headers="X-Trace-Id",
      credentials=true,
    ),
  )
  app.options("/resource", _ => {
    handler_called.val = true
    @crescent.text("regular-options")
  })
  with_test_server(app, port => {
    let (response, body) = issue_request(port, Options, "/resource", headers={
      "origin": "https://frontend.example",
    })
    assert_eq(response.code, 200)
    assert_eq(@utf8.decode(body) catch { _ => "" }, "regular-options")
    guard response.headers
      is {
        "access-control-allow-origin": "https://frontend.example",
        "access-control-allow-methods": "GET, OPTIONS",
        "access-control-allow-headers": "Content-Type",
        "access-control-expose-headers": "X-Trace-Id",
        "access-control-allow-credentials": "true",
        ..
      } else {
      fail("missing expected CORS headers on non-preflight OPTIONS")
    }
    // non-preflight OPTIONS must NOT carry a preflight-only Max-Age
    assert_eq(response.headers.get("access-control-max-age"), None)
    debug_inspect(handler_called.val, content="true")
  })
}

///|
async test "handle_cors accepts mixed-case preflight headers" {
  let app = @crescent.App()
  app.use_middleware(
    handle_cors(
      origin="https://frontend.example",
      methods="GET, PATCH",
      allow_headers="Content-Type, Authorization",
      credentials=true,
      max_age=7200,
    ),
  )
  app.options("/resource", _ => @crescent.text("unexpected"))
  with_test_server(app, port => {
    let response_headers = issue_raw_request_headers(
      port, "OPTIONS /resource HTTP/1.1\r\nHost: localhost\r\nOrIgIn: https://frontend.example\r\nAcCeSs-CoNtRoL-ReQuEsT-MeThOd: PATCH\r\nConnection: close\r\n\r\n",
    )
    assert_true(response_headers.has_prefix("HTTP/1.1 200 "))
    assert_true(
      response_headers.contains(
        "Access-Control-Allow-Origin: https://frontend.example",
      ),
    )
    assert_true(
      response_headers.contains("Access-Control-Allow-Methods: GET, PATCH"),
    )
    assert_true(
      response_headers.contains(
        "Access-Control-Allow-Headers: Content-Type, Authorization",
      ),
    )
    assert_true(
      response_headers.contains("Access-Control-Allow-Credentials: true"),
    )
    assert_true(response_headers.contains("Access-Control-Max-Age: 7200"))
  })
}
