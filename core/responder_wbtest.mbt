///|
test "string responder sets content type" {
  let res = HttpResponse(status_code=OK)
  let responder : &Responder = "hello"
  responder.options(res)
  inspect(
    res.headers.get("Content-Type"),
    content="Some(\"text/plain; charset=utf-8\")",
  )
}

///|
test "string responder outputs utf8" {
  let buf = Buffer()
  let responder : &Responder = "hello"
  responder.output(buf)
  assert_eq(buf.contents(), @utf8.encode("hello"))
}

///|
test "string responder outputs utf8 with unicode" {
  let buf = Buffer()
  let responder : &Responder = "\u{4f60}\u{597d}"
  responder.output(buf)
  assert_eq(buf.contents(), @utf8.encode("\u{4f60}\u{597d}"))
}

///|
test "stringview responder sets content type" {
  let res = HttpResponse(status_code=OK)
  let s : StringView = "world"[:]
  let responder : &Responder = s
  responder.options(res)
  inspect(
    res.headers.get("Content-Type"),
    content="Some(\"text/plain; charset=utf-8\")",
  )
}

///|
test "stringview responder outputs utf8" {
  let buf = Buffer()
  let s : StringView = "world"[:]
  let responder : &Responder = s
  responder.output(buf)
  assert_eq(buf.contents(), @utf8.encode("world"))
}

///|
test "json responder sets content type" {
  let res = HttpResponse(status_code=OK)
  let j : Json = { "key": "value" }
  let responder : &Responder = j
  responder.options(res)
  inspect(
    res.headers.get("Content-Type"),
    content="Some(\"application/json; charset=utf-8\")",
  )
}

///|
test "json responder outputs json string" {
  let buf = Buffer()
  let j : Json = { "key": "value" }
  let responder : &Responder = j
  responder.output(buf)
  assert_eq(buf.contents(), @utf8.encode("{\"key\":\"value\"}"))
}

///|
test "tojson responder sets content type" {
  let res = HttpResponse(status_code=OK)
  let j : Json = { "a": 1 }
  let obj : &ToJson = j
  let responder : &Responder = obj
  responder.options(res)
  inspect(
    res.headers.get("Content-Type"),
    content="Some(\"application/json; charset=utf-8\")",
  )
}

///|
test "tojson responder outputs json string" {
  let buf = Buffer()
  let j : Json = { "a": 1 }
  let obj : &ToJson = j
  let responder : &Responder = obj
  responder.output(buf)
  assert_eq(buf.contents(), @utf8.encode("{\"a\":1}"))
}

///|
test "bytes responder sets content type" {
  let res = HttpResponse(status_code=OK)
  let responder : &Responder = b"\x01\x02\x03"
  responder.options(res)
  inspect(
    res.headers.get("Content-Type"),
    content="Some(\"application/octet-stream\")",
  )
}

///|
test "bytes responder outputs raw bytes" {
  let buf = Buffer()
  let responder : &Responder = b"\x48\x65\x6c\x6c\x6f"
  responder.output(buf)
  assert_eq(buf.contents(), b"\x48\x65\x6c\x6c\x6f")
}

///|
test "http response responder copies status code" {
  let res = HttpResponse(status_code=OK)
  let source = HttpResponse(status_code=NotFound)
  let responder : &Responder = source
  responder.options(res)
  inspect(res.status_code, content="NotFound")
}

///|
test "http response responder merges headers" {
  let res = HttpResponse(status_code=OK)
  let source = HttpResponse(status_code=OK, headers={ "X-Custom": "test-value" })
  let responder : &Responder = source
  responder.options(res)
  inspect(res.headers.get("X-Custom"), content="Some(\"test-value\")")
}

///|
test "http response responder outputs raw body" {
  let buf = Buffer()
  let source = HttpResponse(status_code=OK, raw_body=b"response body")
  let responder : &Responder = source
  responder.output(buf)
  assert_eq(buf.contents(), b"response body")
}

///|
test "http request responder merges headers" {
  let res = HttpResponse(status_code=OK)
  let req = HttpRequest(Get, "/", { "X-Forwarded": "proxy" }, raw_body=b"")
  let responder : &Responder = req
  responder.options(res)
  inspect(res.headers.get("X-Forwarded"), content="Some(\"proxy\")")
}

///|
test "http request responder outputs raw body" {
  let buf = Buffer()
  let req = HttpRequest(Post, "/data", {}, raw_body=b"request payload")
  let responder : &Responder = req
  responder.output(buf)
  assert_eq(buf.contents(), b"request payload")
}

///|
test "html helper sets content type" {
  let res = HttpResponse(status_code=OK)
  let responder = html("<h1>Hello</h1>")
  responder.options(res)
  inspect(
    res.headers.get("Content-Type"),
    content="Some(\"text/html; charset=utf-8\")",
  )
}

///|
test "html helper outputs html content" {
  let buf = Buffer()
  let responder = html("<h1>Hello</h1>")
  responder.output(buf)
  assert_eq(buf.contents(), @utf8.encode("<h1>Hello</h1>"))
}

///|
test "text helper sets content type" {
  let res = HttpResponse(status_code=OK)
  let responder = text("plain text")
  responder.options(res)
  inspect(
    res.headers.get("Content-Type"),
    content="Some(\"text/plain; charset=utf-8\")",
  )
}

///|
test "text helper outputs text content" {
  let buf = Buffer()
  let responder = text("plain text")
  responder.output(buf)
  assert_eq(buf.contents(), @utf8.encode("plain text"))
}
