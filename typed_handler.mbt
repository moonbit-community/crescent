///|
/// Error type for handlers that want automatic HTTP error responses.
pub(all) suberror HttpError {
  HttpError(StatusCode, String)
} derive(Debug)

///|
fn wrap_error_handler(handler : async (Event) -> &Responder) -> HttpHandler {
  event => {
    handler(event) catch {
      HttpError(status, message) => HttpResponse::error(status, message)
      // JSON parse errors from derive(FromJson) or @json.parse
      @json.JsonDecodeError(_) as err =>
        HttpResponse::error(BadRequest, err.to_string())
      @json.InvalidEof as err =>
        HttpResponse::error(BadRequest, err.to_string())
      @json.InvalidChar(_) as err =>
        HttpResponse::error(BadRequest, err.to_string())
      @json.InvalidNumber(_) as err =>
        HttpResponse::error(BadRequest, err.to_string())
      @json.InvalidIdentEscape(_) as err =>
        HttpResponse::error(BadRequest, err.to_string())
      @json.DepthLimitExceeded as err =>
        HttpResponse::error(BadRequest, err.to_string())
      // UTF-8 decode failures — the client sent a body that isn't valid UTF-8
      @utf8.Malformed(_) => HttpResponse::error(BadRequest, "invalid UTF-8")
      // Unknown errors: 500 — log the real error, return a generic message
      err => {
        println("[crescent] unhandled error: \{err}")
        HttpResponse::error(InternalServerError, "Internal Server Error")
      }
    }
  }
}

///|
async test "wrap_error_handler passes through success" {
  let handler = wrap_error_handler(_ => "ok")
  let event = Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let result = handler(event)
  let buf = Buffer()
  result.output(buf)
  assert_eq(buf.contents(), @utf8.encode("ok"))
}

///|
async test "wrap_error_handler catches HttpError" {
  let handler = wrap_error_handler(_event => {
    raise HttpError(BadRequest, "name is required")
  })
  let event = Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let result = handler(event)
  result.options(event.res)
  assert_eq(event.res.status_code, BadRequest)
  let buf = Buffer()
  result.output(buf)
  let body = @utf8.decode(buf.contents())
  assert_true(body.contains("name is required"))
  assert_true(body.contains("400"))
}

///|
async test "wrap_error_handler catches JsonDecodeError as 400" {
  let handler = wrap_error_handler(event => {
    let _ : Json = event.req.json()
    "ok"
  })
  let event = Event::{
    req: HttpRequest(Post, "/", {}, raw_body=b"not valid json"),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let result = handler(event)
  result.options(event.res)
  assert_eq(event.res.status_code, BadRequest)
}

///|
async test "wrap_error_handler catches unknown error as 500" {
  let handler = wrap_error_handler(_event => raise NetworkError)
  let event = Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let result = handler(event)
  result.options(event.res)
  assert_eq(event.res.status_code, InternalServerError)
}

///|
async test "wrap_error_handler catches Failure as 500 with generic message" {
  let handler = wrap_error_handler(_event => fail("secret db connection string"))
  let event = Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let result = handler(event)
  result.options(event.res)
  assert_eq(event.res.status_code, InternalServerError)
  let buf = Buffer()
  result.output(buf)
  let body = @utf8.decode(buf.contents())
  // Must NOT leak internal error details to clients
  assert_true(body.contains("Internal Server Error"))
  assert_false(body.contains("secret db connection string"))
}

///|
async test "HttpError with NotFound status" {
  let handler = wrap_error_handler(_event => {
    raise HttpError(NotFound, "user not found")
  })
  let event = Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  let result = handler(event)
  result.options(event.res)
  assert_eq(event.res.status_code, NotFound)
}

///|
/// Registers a GET handler with automatic error-to-JSON mapping.
pub fn App::get(
  self : App,
  path : String,
  handler : async (Event) -> &Responder,
) -> Unit {
  self.get_raw(path, wrap_error_handler(handler))
}

///|
/// Registers a POST handler with automatic error-to-JSON mapping.
pub fn App::post(
  self : App,
  path : String,
  handler : async (Event) -> &Responder,
) -> Unit {
  self.post_raw(path, wrap_error_handler(handler))
}

///|
/// Registers a PUT handler with automatic error-to-JSON mapping.
pub fn App::put(
  self : App,
  path : String,
  handler : async (Event) -> &Responder,
) -> Unit {
  self.put_raw(path, wrap_error_handler(handler))
}

///|
/// Registers a PATCH handler with automatic error-to-JSON mapping.
pub fn App::patch(
  self : App,
  path : String,
  handler : async (Event) -> &Responder,
) -> Unit {
  self.patch_raw(path, wrap_error_handler(handler))
}

///|
/// Registers a DELETE handler with automatic error-to-JSON mapping.
pub fn App::delete(
  self : App,
  path : String,
  handler : async (Event) -> &Responder,
) -> Unit {
  self.delete_raw(path, wrap_error_handler(handler))
}

///|
/// Registers a HEAD handler with automatic error-to-JSON mapping.
pub fn App::head(
  self : App,
  path : String,
  handler : async (Event) -> &Responder,
) -> Unit {
  self.head_raw(path, wrap_error_handler(handler))
}

///|
/// Registers an OPTIONS handler with automatic error-to-JSON mapping.
pub fn App::options(
  self : App,
  path : String,
  handler : async (Event) -> &Responder,
) -> Unit {
  self.options_raw(path, wrap_error_handler(handler))
}

///|
/// Registers a TRACE handler with automatic error-to-JSON mapping.
pub fn App::trace(
  self : App,
  path : String,
  handler : async (Event) -> &Responder,
) -> Unit {
  self.trace_raw(path, wrap_error_handler(handler))
}

///|
/// Registers a CONNECT handler with automatic error-to-JSON mapping.
pub fn App::connect(
  self : App,
  path : String,
  handler : async (Event) -> &Responder,
) -> Unit {
  self.connect_raw(path, wrap_error_handler(handler))
}

///|
/// Registers a handler matching all HTTP methods with automatic error-to-JSON mapping.
pub fn App::all(
  self : App,
  path : String,
  handler : async (Event) -> &Responder,
) -> Unit {
  self.all_raw(path, wrap_error_handler(handler))
}
