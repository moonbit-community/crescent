///|
test "ok helper" {
  let res = HttpResponse::ok()
  inspect(res.status_code, content="OK")
}

///|
test "not_found helper" {
  let res = HttpResponse::not_found()
  inspect(res.status_code, content="NotFound")
}

///|
test "error helper creates json body" {
  let res = HttpResponse::error(BadRequest, "Invalid input")
  inspect(res.status_code, content="BadRequest")
  inspect(
    res.headers.get("Content-Type") |> @debug.to_repr,
    content="Some(\"application/json; charset=utf-8\")",
  )
}

///|
test "fluent header" {
  let res = HttpResponse::ok().header("X-Custom", "value")
  inspect(
    res.headers.get("X-Custom") |> @debug.to_repr,
    content="Some(\"value\")",
  )
}

///|
test "body() sets Content-Type from responder" {
  let res = HttpResponse::ok().body(html("<h1>Hi</h1>"))
  inspect(
    res.headers.get("Content-Type") |> @debug.to_repr,
    content="Some(\"text/html; charset=utf-8\")",
  )
}

///|
test "header() is case-insensitive" {
  let res = HttpResponse::ok()
    .header("content-type", "text/plain")
    .header("Content-Type", "text/html")
  // Only one entry should exist (replaced, not duplicated)
  let mut count = 0
  res.headers.each((k, _) => {
    if k.to_lower() == "content-type" {
      count = count + 1
    }
  })
  assert_eq(count, 1)
}

///|
test "json() sets Content-Type" {
  let res = HttpResponse::ok().json(({ "a": 1 } : Json))
  inspect(
    res.headers.get("Content-Type") |> @debug.to_repr,
    content="Some(\"application/json; charset=utf-8\")",
  )
}
