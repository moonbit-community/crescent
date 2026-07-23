///|
async fn main {
  let app = @crescent.App()

  app.use_middleware(
    @cors.handle_cors(
      origin="*",
      methods="GET, HEAD, POST, OPTIONS",
      allow_headers="Content-Type, X-Test",
      expose_headers="X-Crescent-Test",
      credentials=true,
      max_age=600,
    ),
  )
  app.static_assets(
    "/assets",
    @static_file.StaticFileProvider(path="static_file/testdata"),
  )

  app.get("/health", _ => "ready")
  app.get("/hello/:name", event => {
    let name = event.param("name").unwrap_or("world")
    "Hello, \{name}!"
  })
  app.get("/json", _ => ({ "framework": "crescent", "target": "e2e" } : Json))
  app.post("/echo", event => {
    let payload : Json = event.req.json()
    payload
  })

  app.get("/cookies/session", event => {
    match event.req.get_cookie("session") {
      Some(session) => "session=\{session.value}"
      None => {
        event.res.set_cookie(
          "session",
          "hurl",
          max_age=600,
          path="/",
          http_only=true,
        )
        "new session"
      }
    }
  })
  app.get("/cookies/multiple", event => {
    event.res.headers.set("Set-Cookie", "manual=header; Path=/")
    event.res.set_cookie("first", "one", path="/")
    event.res.set_cookie("unsafe", "safe;evil", path="/")
    "multiple cookies"
  })

  app.get("/cors", event => {
    event.res.headers.set("X-Crescent-Test", "cors")
    "cors response"
  })

  app.get("/_upstream/text", _ => "upstream response")
  app.post("/_upstream/echo", event => {
    let body : String = event.req.body()
    let proxy = event.req.get_header("x-proxy").unwrap_or("missing")
    "\{proxy}:\{body}"
  })
  app.head("/_upstream/head", event => {
    event.res.headers.set("X-Upstream", "head")
    @crescent.HttpResponse::no_content()
  })

  app.get("/fetch/text", event => {
    let response = @fetch.get("http://127.0.0.1:4010/_upstream/text")
    let body : String = response.read_body()
    event.res.headers.set("X-Fetch-Method", "GET")
    body
  })
  app.post("/fetch/echo", event => {
    let body : String = event.req.body()
    let response = @fetch.post(
      "http://127.0.0.1:4010/_upstream/echo",
      data=body,
      headers={ "X-Proxy": "crescent" },
    )
    let response_body : String = response.read_body()
    event.res.headers.set("X-Fetch-Method", "POST")
    response_body
  })
  app.head("/fetch/head", event => {
    let response = @fetch.head("http://127.0.0.1:4010/_upstream/head")
    event.res.headers.set(
      "X-Upstream",
      response.headers.get("x-upstream").unwrap_or("missing"),
    )
    @crescent.HttpResponse::no_content()
  })

  app.set_not_found_handler(_ => {
    @crescent.HttpResponse::not_found().body("crescent e2e: not found")
  })

  app.serve(port=4010)
}
