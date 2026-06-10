///|
/// Trait for types that can be sent as an HTTP response body.
pub(open) trait Responder {
  fn options(Self, res : HttpResponse) -> Unit
  fn output(Self, buf : @buffer.Buffer) -> Unit
  /// Returns pre-encoded bytes directly, bypassing the buffer allocation.
  /// Returns `None` to fall back to `output()`.
  /// Override this for types that already hold their response as bytes
  /// (e.g. HttpResponse, Bytes) to avoid a copy through the intermediate buffer.
  fn output_bytes(Self) -> Bytes?
}

///|
pub impl Responder for &ToJson with fn options(_, res) -> Unit {
  @httputil.set_missing_header_case_insensitive(
    res.headers,
    "Content-Type",
    "application/json; charset=utf-8",
  )
}

///|
pub impl Responder for &ToJson with fn output(self, buf) -> Unit {
  buf.write_string_utf8(self.to_json().stringify())
}

///|
pub impl Responder for &ToJson with fn output_bytes(_self) -> Bytes? {
  None
}

///|
pub impl Responder for HttpRequest with fn options(self, res) -> Unit {
  @httputil.merge_headers_case_insensitive(res.headers, self.headers)
}

///|
pub impl Responder for HttpRequest with fn output(self, buf) -> Unit {
  buf.write_bytes(self.raw_body)
}

///|
pub impl Responder for HttpRequest with fn output_bytes(self) -> Bytes? {
  if self.raw_body.is_empty() {
    None
  } else {
    Some(self.raw_body)
  }
}

///|
pub impl Responder for HttpResponse with fn options(self, res) -> Unit {
  res.status_code = self.status_code
  @httputil.merge_headers_case_insensitive(res.headers, self.headers)
}

///|
pub impl Responder for HttpResponse with fn output(self, buf) -> Unit {
  buf.write_bytes(self.raw_body)
}

///|
pub impl Responder for HttpResponse with fn output_bytes(self) -> Bytes? {
  if self.raw_body.is_empty() {
    None
  } else {
    Some(self.raw_body)
  }
}

///|
pub impl Responder for Json with fn options(_, res) -> Unit {
  @httputil.set_missing_header_case_insensitive(
    res.headers,
    "Content-Type",
    "application/json; charset=utf-8",
  )
}

///|
pub impl Responder for Json with fn output(self, buf) -> Unit {
  buf.write_string_utf8(self.to_json().stringify())
}

///|
pub impl Responder for Json with fn output_bytes(_self) -> Bytes? {
  None
}

///|
pub impl Responder for Bytes with fn options(_, res) -> Unit {
  @httputil.set_missing_header_case_insensitive(
    res.headers,
    "Content-Type",
    "application/octet-stream",
  )
}

///|
pub impl Responder for Bytes with fn output(self, buf) -> Unit {
  buf.write_bytes(self)
}

///|
pub impl Responder for Bytes with fn output_bytes(self) -> Bytes? {
  if self.is_empty() {
    None
  } else {
    Some(self)
  }
}

///|
pub impl Responder for String with fn options(_, res) -> Unit {
  @httputil.set_missing_header_case_insensitive(
    res.headers,
    "Content-Type",
    "text/plain; charset=utf-8",
  )
}

///|
pub impl Responder for String with fn output(self, buf) -> Unit {
  buf.write_string_utf8(self)
}

///|
pub impl Responder for String with fn output_bytes(_self) -> Bytes? {
  None
}

///|
pub impl Responder for StringView with fn options(_, res) -> Unit {
  @httputil.set_missing_header_case_insensitive(
    res.headers,
    "Content-Type",
    "text/plain; charset=utf-8",
  )
}

///|
pub impl Responder for StringView with fn output(self, buf) -> Unit {
  buf.write_string_utf8(self)
}

///|
pub impl Responder for StringView with fn output_bytes(_self) -> Bytes? {
  None
}

///|
struct Html(String)

///|
pub impl Responder for Html with fn options(_, res) -> Unit {
  @httputil.set_missing_header_case_insensitive(
    res.headers,
    "Content-Type",
    "text/html; charset=utf-8",
  )
}

///|
pub impl Responder for Html with fn output(self, buf) -> Unit {
  buf.write_string_utf8(self.0)
}

///|
pub impl Responder for Html with fn output_bytes(_self) -> Bytes? {
  None
}

///|
/// Creates an HTML responder from any `Show` value, setting the Content-Type to `text/html`.
pub fn html(html : &Show) -> &Responder {
  Html(html.to_string())
}

///|
/// Creates a plain-text responder from any `Show` value, setting the Content-Type to `text/plain`.
pub fn text(text : &Show) -> &Responder {
  text.to_string()
}
