///|
/// An outgoing HTTP response containing the status code, headers, cookies, and body.
pub(all) struct HttpResponse {
  /// The HTTP status code (e.g., `OK`, `NotFound`, `InternalServerError`).
  mut status_code : StatusCode
  /// Response headers as key-value pairs.
  headers : Map[String, String]
  /// Cookies to send via `Set-Cookie` headers.
  cookies : Map[String, @cookie.CookieItem]
  /// The raw response body bytes.
  mut raw_body : Bytes
  // TODO: better error message when using skip
} derive(Debug(ignore=Bytes))

///|
/// Deserializes the response body into a value of type `T` via the `BodyReader` trait.
pub fn[T : BodyReader] HttpResponse::read_body(self : HttpResponse) -> T raise {
  T::from_request(
    HttpRequest(Other(""), "", self.headers, raw_body=self.raw_body),
  )
}

///|
/// Creates a new `HttpResponse` with the given status code and optional headers, cookies, and body.
pub fn HttpResponse::HttpResponse(
  status_code~ : StatusCode,
  headers? : Map[String, String],
  cookies? : Map[String, @cookie.CookieItem],
  raw_body? : Bytes,
) -> HttpResponse {
  {
    status_code,
    headers: headers.unwrap_or({}),
    cookies: cookies.unwrap_or({}),
    raw_body: raw_body.unwrap_or(b""),
  }
}

///|
/// Sets the response body from any `Responder` and returns the response for chaining.
///
/// Applies the responder's `options()` (e.g. sets Content-Type) and uses the
/// `output_bytes()` fast path when available to avoid an intermediate buffer copy.
pub fn HttpResponse::body(
  self : HttpResponse,
  body : &Responder,
) -> HttpResponse {
  body.options(self)
  match body.output_bytes() {
    Some(bytes) => self.raw_body = bytes
    None => {
      let buf = Buffer()
      body.output(buf)
      self.raw_body = buf.to_bytes()
    }
  }
  self
}

///|
/// Sets the response body to the JSON representation of the given value.
/// Also sets `Content-Type: application/json; charset=utf-8`.
pub fn HttpResponse::json(self : HttpResponse, obj : &ToJson) -> HttpResponse {
  self.body(obj.to_json())
}

///|
/// Serializes a typed value as JSON, sets `Content-Type`, and returns the response.
///
/// Uses case-insensitive header matching: any existing `content-type` /
/// `CONTENT-TYPE` header is replaced, not duplicated.
pub fn[T : ToJson] HttpResponse::json_value(
  self : HttpResponse,
  value : T,
) -> HttpResponse {
  @httputil.set_header_case_insensitive(
    self.headers,
    "Content-Type",
    "application/json; charset=utf-8",
  )
  let json_str = value.to_json().stringify()
  self.raw_body = @utf8.encode(json_str)
  self
}

///|
/// Sets a response header and returns self for fluent chaining.
///
/// Uses case-insensitive matching: setting `Content-Type` will replace any
/// existing `content-type` or `CONTENT-TYPE` header.
pub fn HttpResponse::header(
  self : HttpResponse,
  name : String,
  value : String,
) -> HttpResponse {
  @httputil.set_header_case_insensitive(self.headers, name, value)
  self
}

///|
/// Converts this response into a `Responder` trait object for use as a handler return value.
pub fn HttpResponse::to_responder(self : HttpResponse) -> &Responder {
  self
}

///|
/// Sets a cookie on the response with the given name, value, and optional attributes.
pub fn HttpResponse::set_cookie(
  self : HttpResponse,
  name : String,
  value : String,
  max_age? : Int,
  path? : String,
  domain? : String,
  secure? : Bool,
  http_only? : Bool,
  same_site? : @cookie.SameSiteOption,
) -> Unit {
  let item = @cookie.CookieItem(
    name~,
    value~,
    max_age?,
    path?,
    domain?,
    secure?,
    http_only?,
    same_site?,
  )
  self.cookies.set(name, item)
}

///|
/// Deletes a cookie by setting its value to empty and max-age to 0.
pub fn HttpResponse::delete_cookie(self : HttpResponse, key : String) -> Unit {
  self.set_cookie(key, "", max_age=0)
}

///|
test "read_response_body" {
  let res = HttpResponse(status_code=OK, raw_body=b"{\"Hello\":\"Response\"}")
  let text : String = res.read_body()
  let json : Json = res.read_body()
  inspect(
    text,
    content=(
      #|{"Hello":"Response"}
    ),
  )
  json_inspect(json, content={ "Hello": "Response" })
}
