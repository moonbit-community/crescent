/// HTTP fetch implementation shared by the native and wasm1 targets.

///|
priv enum FetchProtocol {
  Http
  Https
}

///|
fn FetchProtocol::default_port(self : FetchProtocol) -> Int {
  match self {
    Http => 80
    Https => 443
  }
}

///|
fn FetchProtocol::scheme(self : FetchProtocol) -> String {
  match self {
    Http => "http"
    Https => "https"
  }
}

///|
fn request_method_to_async(
  http_method : @core.HttpMethod,
) -> @http.RequestMethod raise {
  match http_method {
    Get => Get
    Post => Post
    Put => Put
    Patch => Patch
    Delete => Delete
    Head => Head
    Options => Options
    Trace => Trace
    Connect => Connect
    Other(m) => raise FetchError::RequestFailed("unsupported HTTP method: \{m}")
  }
}

/// Converts a BytesView (from the uri package) to a String by UTF-8 decoding.

///|
fn resolve_fetch_url(
  url : String,
) -> (FetchProtocol, String, Int, String) raise {
  // Parse the URL using the proper RFC 3986 parser from the uri package.
  let parsed = @uri.Uri(url) catch {
    _ => raise FetchError::RequestFailed("invalid URL: \{url}")
  }

  // Extract and validate scheme (must be http or https).
  let scheme = match parsed.scheme {
    Some(s) => s.to_lower()
    None => raise FetchError::RequestFailed("invalid URL: \{url} (no scheme)")
  }
  let protocol = match scheme {
    "http" => Http
    "https" => Https
    other => raise FetchError::RequestFailed("unsupported protocol: \{other}")
  }

  // Extract authority (host + port).
  let authority = match parsed.authority {
    Some(a) => a
    None => raise FetchError::RequestFailed("invalid URL: \{url} (no host)")
  }

  // Reject URLs with userinfo — we don't silently drop credentials.
  // Users should pass credentials via the `headers` param (e.g. Authorization).
  match authority.userinfo {
    Some(_) =>
      raise FetchError::RequestFailed(
        "URL userinfo (user:pass@) is not supported; use the Authorization header instead",
      )
    None => ()
  }

  // Extract host: IPv6 literals need to be wrapped in brackets for the
  // HTTP Host header and URL reconstruction.
  let host = match authority.host {
    IPv6Address(addr) => "[\{addr}]"
    RegName(name) => name.to_owned()
  }
  guard host != "" && host != "[]" else {
    raise FetchError::RequestFailed("invalid URL: \{url} (empty host)")
  }

  // Extract port, defaulting to protocol default if not specified.
  let port = match authority.port {
    Some(p) => {
      guard p is (1..<65536) else {
        raise FetchError::RequestFailed("invalid URL: \{url} (bad port)")
      }
      p
    }
    None => protocol.default_port()
  }

  // Reconstruct the request path from segments and query.
  let path_buf = StringBuilder::new()
  for seg in parsed.path {
    path_buf.write_string("/")
    path_buf.write_view(seg)
  }
  let mut path_str = path_buf.to_string()
  if path_str == "" {
    path_str = "/"
  }
  match parsed.query {
    Some(q) => path_str = path_str + "?" + q.to_owned()
    None => ()
  }
  (protocol, host, port, path_str)
}

///|
test "resolve_fetch_url basic http" {
  let (proto, host, port, path) = resolve_fetch_url("http://example.com/foo")
  assert_true(proto is Http)
  assert_eq(host, "example.com")
  assert_eq(port, 80)
  assert_eq(path, "/foo")
}

///|
test "resolve_fetch_url with port" {
  let (proto, host, port, path) = resolve_fetch_url(
    "https://api.example.com:8443/v1/users",
  )
  assert_true(proto is Https)
  assert_eq(host, "api.example.com")
  assert_eq(port, 8443)
  assert_eq(path, "/v1/users")
}

///|
test "resolve_fetch_url with query string" {
  let (_proto, _host, _port, path) = resolve_fetch_url(
    "http://example.com/search?q=hello&lang=en",
  )
  assert_eq(path, "/search?q=hello&lang=en")
}

///|
test "resolve_fetch_url default path" {
  let (_proto, _host, _port, path) = resolve_fetch_url("http://example.com/")
  assert_eq(path, "/")
}

///|
test "resolve_fetch_url https default port" {
  let (_proto, _host, port, _path) = resolve_fetch_url("https://example.com/")
  assert_eq(port, 443)
}

///|
test "resolve_fetch_url IPv6 literal" {
  let (_proto, host, _port, _path) = resolve_fetch_url(
    "http://[::1]:8080/index",
  )
  // IPv6 host should be wrapped in brackets
  assert_eq(host, "[::1]")
}

///|
test "resolve_fetch_url rejects unsupported scheme" {
  @test.assert_raise(() => resolve_fetch_url("ftp://example.com/foo"))
}

///|
test "resolve_fetch_url rejects invalid URL" {
  @test.assert_raise(() => resolve_fetch_url("not a url"))
}

///|
test "resolve_fetch_url rejects empty host" {
  @test.assert_raise(() => resolve_fetch_url("http:///foo"))
}

///|
test "resolve_fetch_url handles empty path with query" {
  // http://host?query (no path, just query) — used in some integration tests
  let (_proto, host, _port, path) = resolve_fetch_url(
    "http://127.0.0.1:4000?via=query",
  )
  assert_eq(host, "127.0.0.1")
  assert_eq(path, "/?via=query")
}

///|
test "resolve_fetch_url rejects userinfo" {
  try resolve_fetch_url("http://user:pass@example.com/api") catch {
    FetchError::RequestFailed(msg) => assert_true(msg.contains("userinfo"))
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected FetchError for URL with userinfo")
  }
}

///|
test "resolve_fetch_url rejects ftp" {
  try resolve_fetch_url("ftp://example.com/") catch {
    FetchError::RequestFailed(msg) =>
      assert_true(msg.contains("unsupported protocol"))
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected FetchError")
  }
}

///|
fn fetch_origin(protocol : FetchProtocol, host : String, port : Int) -> String {
  if port == protocol.default_port() {
    "\{protocol.scheme()}://\{host}"
  } else {
    "\{protocol.scheme()}://\{host}:\{port}"
  }
}

///|
fn prepare_fetch_payload_bytes(
  body : String?,
  data : &@core.Responder?,
  headers : Map[String, String]?,
) -> (Bytes?, Map[String, String]) {
  let req_headers = @httputil.copy_headers(headers.unwrap_or({}))
  let req_body = match body {
    Some(raw_body) => Some(@utf8.encode(raw_body))
    None =>
      match data {
        Some(responder_data) => {
          let res = @core.HttpResponse(status_code=OK)
          responder_data.options(res)
          res.headers.each((key, value) => {
            if !@httputil.has_header_case_insensitive(req_headers, key) {
              req_headers.set(key.to_string(), value.to_string())
            }
          })
          match responder_data.output_bytes() {
            Some(bytes) => Some(bytes)
            None => {
              let body_buf = Buffer()
              responder_data.output(body_buf)
              Some(body_buf.to_bytes())
            }
          }
        }
        None => None
      }
  }
  (req_body, req_headers)
}

///|
/// Sends an HTTP request to the given URL and returns the response.
pub async fn fetch(
  url : String,
  body? : String,
  http_method : @core.HttpMethod,
  data? : &@core.Responder,
  headers? : Map[String, String],
  credentials? : FetchCredentials,
  mode? : FetchMode,
) -> @core.HttpResponse {
  ignore(credentials)
  ignore(mode)
  let (req_body, req_headers) = prepare_fetch_payload_bytes(body, data, headers)
  let (protocol, host, port, path) = resolve_fetch_url(url)
  let client = @http.Client(fetch_origin(protocol, host, port)) catch {
    err => raise FetchError::RequestFailed("\{err}")
  }
  defer client.close()
  let response = try {
    client.request(
      request_method_to_async(http_method),
      path,
      extra_headers=req_headers,
    )
    match req_body {
      Some(body_bytes) => client.write(body_bytes)
      None => ()
    }
    client.end_request()
  } catch {
    err => raise FetchError::RequestFailed("\{err}")
  }
  let response_body = client.read_all().binary() catch {
      err => raise FetchError::RequestFailed("\{err}")
    }
  HttpResponse(
    status_code=@core.StatusCode::from_int(response.code),
    headers=@httputil.copy_headers(response.headers),
    raw_body=response_body,
  )
}
