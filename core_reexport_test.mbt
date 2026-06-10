///|
/// Smoke tests verifying that core types are accessible through the root
/// package re-exports.  These catch accidental breakage of the
/// `pub using @core { ... }` layer.

///|
test "re-export: HttpRequest constructor" {
  let req = @crescent.HttpRequest(Get, "/", {}, raw_body=b"")
  assert_eq(req.http_method, Get)
}

///|
test "re-export: HttpResponse::ok()" {
  let res = @crescent.HttpResponse::ok()
  inspect(res.status_code, content="OK")
}

///|
test "re-export: html() helper" {
  let responder = @crescent.html("<p>hi</p>")
  let buf = Buffer()
  responder.output(buf)
  assert_eq(buf.contents(), @utf8.encode("<p>hi</p>"))
}

///|
test "re-export: text() helper" {
  let responder = @crescent.text("hello")
  let buf = Buffer()
  responder.output(buf)
  assert_eq(buf.contents(), @utf8.encode("hello"))
}

///|
test "re-export: Responder trait" {
  let res = @crescent.HttpResponse(status_code=OK)
  let r : &@crescent.Responder = "test"
  r.options(res)
  inspect(
    res.headers.get("Content-Type"),
    content="Some(\"text/plain; charset=utf-8\")",
  )
}
