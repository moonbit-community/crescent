///|
async test "fetch uses async client for request headers and payloads" {
  let app = @crescent.App()
  app.get("/", _ => "root")
  app.get("/fetch/hello", event => {
    let who = event.req.headers.get("x-name").unwrap_or("world").to_string()
    event.res.headers.set("X-Reply", "native")
    @crescent.HttpResponse(status_code=OK).body("hello:\{who}")
  })
  app.post("/fetch/echo", event => {
    let payload : String = event.req.body() catch { _ => "" }
    event.res.headers.set("X-Body-Len", payload.length().to_string())
    @crescent.HttpResponse(status_code=Created).body("post:\{payload}")
  })
  app.patch("/fetch/bin", event => {
    event.res.headers.set("X-Body-Len", event.req.raw_body.length().to_string())
    event.req.raw_body
  })
  with_test_server(app, port => {
    let response1 = @fetch.get(localhost_url(port, "/fetch/hello?via=async"), headers={
      "X-Name": "moon",
    })
    assert_eq(response1.status_code, OK)
    let body1 : String = response1.read_body()
    inspect(body1, content="hello:moon")
    inspect(response1.headers.get("x-reply").unwrap_or(""), content="native")

    let response2 = @fetch.fetch(
      localhost_url(port, "/fetch/echo"),
      Post,
      body="payload",
      headers={ "X-Test": "yes" },
    )
    assert_eq(response2.status_code, Created)
    let body2 : String = response2.read_body()
    inspect(body2, content="post:payload")
    inspect(response2.headers.get("x-body-len").unwrap_or(""), content="7")

    let response3 = @fetch.patch(
      localhost_url(port, "/fetch/bin"),
      data=b"\x00\x01\x02",
    )
    assert_eq(response3.status_code, OK)
    assert_eq(response3.raw_body, b"\x00\x01\x02")
    inspect(response3.headers.get("x-body-len").unwrap_or(""), content="3")

    let response4 = @fetch.get("http://127.0.0.1:\{port}?via=query")
    assert_eq(response4.status_code, OK)
    let body4 : String = response4.read_body()
    inspect(body4, content="root")
  }) catch {
    SocketBindUnavailable => return
    err => raise err
  }
}

///|
async test "fetch preserves explicit content-type without duplicate request headers" {
  let raw_headers = Ref("")
  @async.with_task_group(group => {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr.port()
    group.spawn_bg(() => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      raw_headers.val = conn.read_until("\r\n\r\n").unwrap_or("")
      conn.write(
        "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
      )
    })

    let response = @fetch.post(
      "http://127.0.0.1:\{port}/request",
      data=@crescent.text("body"),
      headers={ "content-type": "application/custom", "X-Test": "yes" },
    )
    assert_eq(response.status_code, OK)
    assert_eq(response.raw_body, b"")
  })

  assert_eq(
    raw_header_value(raw_headers.val, "content-type"),
    Some("application/custom"),
  )
  assert_eq(raw_header_count(raw_headers.val, "content-type"), 1)
  assert_eq(raw_header_value(raw_headers.val, "x-test"), Some("yes"))
}

///|
async test "fetch supports head and rejects unsupported protocols" {
  let app = @crescent.App()
  app.head("/fetch/head", event => {
    event.res.headers.set("X-Reply", "head")
    @crescent.HttpResponse(status_code=NoContent).body("ignored")
  })
  with_test_server(app, port => {
    let response = @fetch.head(localhost_url(port, "/fetch/head"))
    assert_eq(response.status_code, NoContent)
    let body : String = response.read_body()
    inspect(body, content="")
    inspect(response.headers.get("x-reply").unwrap_or(""), content="head")
  }) catch {
    SocketBindUnavailable => return
    err => raise err
  }

  try {
    let _ = @fetch.get("ftp://example.com/data")
    fail("expected fetch to reject unsupported protocol")
  } catch {
    @fetch.FetchError::RequestFailed(message) =>
      inspect(message, content="unsupported protocol: ftp")
    err => fail("unexpected error: \{err}")
  }
}
