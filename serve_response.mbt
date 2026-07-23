///|
let cached_date_second : Ref[Int64] = Ref(0L)

///|
let cached_date_string : Ref[String] = Ref("")

///|
fn current_http_date() -> String {
  let now = @async.now() / 1000L
  if now != cached_date_second.val {
    cached_date_second.val = now
    cached_date_string.val = @httputil.format_http_date(now)
  }
  cached_date_string.val
}

///|
fn append_cookie_headers(
  headers : Map[String, String],
  cookies : Map[String, @cookie.CookieItem],
) -> Unit {
  if cookies.is_empty() {
    return
  }
  let cookie_lines = cookies
    .values()
    .map(cookie => cookie.to_string())
    .to_array()
  match cookie_lines {
    [] => ()
    [cookie] => headers.set("Set-Cookie", cookie)
    _ => headers.set("Set-Cookie", cookie_lines.join("\r\nSet-Cookie: "))
  }
}

///|
test "append_cookie_headers with empty cookies does nothing" {
  let headers : Map[String, String] = {}
  let cookies : Map[String, @cookie.CookieItem] = {}
  append_cookie_headers(headers, cookies)
  debug_inspect(headers.contains("Set-Cookie"), content="false")
}

///|
test "append_cookie_headers with single cookie sets header" {
  let headers : Map[String, String] = {}
  let cookies : Map[String, @cookie.CookieItem] = {}
  cookies.set("session", {
    name: "session",
    value: "abc123",
    max_age: None,
    path: None,
    domain: None,
    secure: None,
    http_only: None,
    same_site: None,
  })
  append_cookie_headers(headers, cookies)
  debug_inspect(
    headers.get("Set-Cookie"),
    content=(
      #|Some("session=abc123")
    ),
  )
}

///|
test "append_cookie_headers with multiple cookies joins with CRLF Set-Cookie" {
  let headers : Map[String, String] = {}
  let cookies : Map[String, @cookie.CookieItem] = {}
  cookies.set("a", {
    name: "a",
    value: "1",
    max_age: None,
    path: None,
    domain: None,
    secure: None,
    http_only: None,
    same_site: None,
  })
  cookies.set("b", {
    name: "b",
    value: "2",
    max_age: None,
    path: None,
    domain: None,
    secure: None,
    http_only: None,
    same_site: None,
  })
  append_cookie_headers(headers, cookies)
  debug_inspect(
    headers.get("Set-Cookie"),
    content=(
      #|Some("a=1\r\nSet-Cookie: b=2")
    ),
  )
}

///|
async fn send_raw_response_async(
  conn : @http.ServerConnection,
  response : HttpResponse,
  headers : Map[String, String],
  include_body : Bool,
) -> Unit {
  if !@httputil.has_header_case_insensitive(headers, "Date") {
    headers.set("Date", current_http_date())
  }
  if !@httputil.has_header_case_insensitive(headers, "Content-Length") {
    headers.set("Content-Length", response.raw_body.length().to_string())
  }
  if !@httputil.has_header_case_insensitive(headers, "Connection") {
    headers.set("Connection", "close")
  }
  let raw_response = Buffer()
  raw_response.write_string_utf8("HTTP/1.1 ")
  raw_response.write_string_utf8(response.status_code.to_int().to_string())
  raw_response.write_string_utf8(" ")
  raw_response.write_string_utf8(response.status_code.to_string())
  raw_response.write_string_utf8("\r\n")
  for pair in headers.to_array() {
    let (key, value) = pair
    raw_response.write_string_utf8(key)
    raw_response.write_string_utf8(": ")
    raw_response.write_string_utf8(value)
    raw_response.write_string_utf8("\r\n")
  }
  raw_response.write_string_utf8("\r\n")
  if include_body && !response.raw_body.is_empty() {
    raw_response.write_bytes(response.raw_body)
  }
  conn.enter_passthrough_mode()
  conn.write(raw_response.contents())
  conn.flush()
  conn.close()
}

///|
/// Applies a responder to a response and serializes pending cookies into
/// `Set-Cookie` headers. Shared by the live serving path
/// (`send_response_async`) and synthetic dispatch (`App::dispatch`) so the
/// two stay aligned: any bug in body materialization or cookie serialization
/// would otherwise have to be fixed twice (see commits bb22108, eb6f24b).
fn finalize_response_body(
  response : HttpResponse,
  responder : &Responder,
) -> Unit {
  responder.options(response)
  // Fast path: use output_bytes to avoid buffer allocation when possible
  match responder.output_bytes() {
    Some(bytes) => response.raw_body = bytes
    None => {
      let buffer = Buffer()
      responder.output(buffer)
      response.raw_body = buffer.to_bytes()
    }
  }
  append_cookie_headers(response.headers, response.cookies)
}

///|
async fn send_response_async(
  request : @http.Request,
  conn : @http.ServerConnection,
  response : HttpResponse,
  responder : &Responder,
) -> Unit {
  finalize_response_body(response, responder)
  let headers = response.headers
  if !@httputil.has_header_case_insensitive(headers, "Date") {
    headers.set("Date", current_http_date())
  }
  if request.meth == Head {
    send_raw_response_async(conn, response, headers, false)
    return
  }
  if @httputil.has_header_case_insensitive(headers, "Content-Encoding") {
    send_raw_response_async(conn, response, headers, true)
    return
  }
  conn.send_response(
    response.status_code.to_int(),
    response.status_code.to_string(),
    extra_headers=headers,
  )
  if !response.raw_body.is_empty() {
    conn.write(response.raw_body)
  }
  conn.end_response()
}

///|
async fn send_response_and_close_async(
  request : @http.Request,
  conn : @http.ServerConnection,
  response : HttpResponse,
) -> Unit {
  let headers = response.headers
  append_cookie_headers(headers, response.cookies)
  if !@httputil.has_header_case_insensitive(headers, "Date") {
    headers.set("Date", current_http_date())
  }
  if !@httputil.has_header_case_insensitive(headers, "Content-Length") {
    headers.set("Content-Length", response.raw_body.length().to_string())
  }
  headers.set("Connection", "close")
  if request.meth == Head {
    send_raw_response_async(conn, response, headers, false)
    return
  }
  conn.send_response(
    response.status_code.to_int(),
    response.status_code.to_string(),
    extra_headers=headers,
  )
  if !response.raw_body.is_empty() {
    conn.write(response.raw_body)
  }
  conn.end_response()
  conn.close()
}

///|
async fn send_request_entity_too_large_async(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let response = HttpResponse(status_code=RequestEntityTooLarge).body(
    "Request Entity Too Large",
  )
  response.headers.set("Content-Type", "text/plain; charset=utf-8")
  send_response_and_close_async(request, conn, response)
}

///|
async fn send_request_timeout_async(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let response = HttpResponse(status_code=RequestTimeout).body(
    "Request Timeout",
  )
  response.headers.set("Content-Type", "text/plain; charset=utf-8")
  send_response_and_close_async(request, conn, response)
}

///|
async fn send_not_found_async(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let response = HttpResponse(status_code=NotFound).body("Not Found")
  response.headers.set("Content-Type", "text/plain; charset=utf-8")
  send_response_and_close_async(request, conn, response)
}

///|
async fn send_gateway_timeout_async(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let response = HttpResponse(status_code=GatewayTimeout).body(
    "Gateway Timeout",
  )
  response.headers.set("Content-Type", "text/plain; charset=utf-8")
  send_response_and_close_async(request, conn, response)
}
