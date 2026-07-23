///|
test "custom not found handler is set" {
  let app = @crescent.App()
  app.set_not_found_handler(_ => {
    @crescent.HttpResponse(status_code=NotFound).body("Custom 404")
  })
  debug_inspect(app.has_not_found_handler(), content="true")
}

///|
test "not found handler defaults to none" {
  let app = @crescent.App()
  debug_inspect(app.has_not_found_handler(), content="false")
}

///|
test "group merges not found handler" {
  let app = @crescent.App()
  app.group("/api", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("API 404")
    })
  })
  debug_inspect(app.has_not_found_handler(), content="true")
}

///|
async test "group not_found_handler is scoped to the group prefix" {
  let app = @crescent.App()
  app.group("/api", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("API 404")
    })
  })
  let client = @test_client.TestClient(app)
  // Inside the group's prefix: the group's handler fires.
  let inside = client.get("/api/missing")
  assert_eq(inside.body_text(), "API 404")
  // Outside the prefix: the group's handler does NOT take over the whole
  // app; we fall back to the default 404 body.
  let outside = client.get("/random/path")
  assert_eq(outside.body_text(), "Not Found")
}

///|
async test "group not_found_handler chains to parent app handler outside prefix" {
  let app = @crescent.App()
  app.set_not_found_handler(_ => {
    @crescent.HttpResponse(status_code=NotFound).body("App 404")
  })
  app.group("/api", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("API 404")
    })
  })
  let client = @test_client.TestClient(app)
  let inside = client.get("/api/missing")
  assert_eq(inside.body_text(), "API 404")
  let outside = client.get("/random/path")
  assert_eq(outside.body_text(), "App 404")
}

///|
async test "group not_found_handler respects segment boundary, /apicore is not under /api" {
  let app = @crescent.App()
  app.group("/api", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("API 404")
    })
  })
  let client = @test_client.TestClient(app)
  // Confusingly-prefixed path that shares characters with /api but is a
  // different first segment: must NOT trigger the API handler.
  let confusing = client.get("/apicore/x")
  assert_eq(confusing.body_text(), "Not Found")
  // Exact-prefix request still hits the group handler.
  let exact = client.get("/api")
  assert_eq(exact.body_text(), "API 404")
}

///|
async test "group not_found_handler normalizes a trailing slash on the prefix" {
  let app = @crescent.App()
  app.group("/api/", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("API 404")
    })
  })
  let client = @test_client.TestClient(app)
  // Both /api and /api/users should match the group, despite the registered
  // prefix being declared with a trailing slash.
  let bare = client.get("/api")
  assert_eq(bare.body_text(), "API 404")
  let nested = client.get("/api/users")
  assert_eq(nested.body_text(), "API 404")
  let outside = client.get("/other")
  assert_eq(outside.body_text(), "Not Found")
}

///|
async test "overlapping nested-prefix groups: longest match wins, order-independent" {
  // Register the broader /api group before the narrower /api/v1 group.
  let app1 = @crescent.App()
  app1.group("/api", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("API 404")
    })
  })
  app1.group("/api/v1", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("V1 404")
    })
  })
  let client1 = @test_client.TestClient(app1)
  // /api/v1/x is under both prefixes — narrower /api/v1 should win.
  assert_eq(client1.get("/api/v1/x").body_text(), "V1 404")
  // /api/x is only under /api.
  assert_eq(client1.get("/api/x").body_text(), "API 404")

  // Same setup but with the registration order reversed: behavior should
  // be identical because we resolve by longest prefix match, not insertion
  // order.
  let app2 = @crescent.App()
  app2.group("/api/v1", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("V1 404")
    })
  })
  app2.group("/api", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("API 404")
    })
  })
  let client2 = @test_client.TestClient(app2)
  assert_eq(client2.get("/api/v1/x").body_text(), "V1 404")
  assert_eq(client2.get("/api/x").body_text(), "API 404")
}

///|
async test "two groups at the same prefix: later registration wins" {
  let app = @crescent.App()
  app.group("/api", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("first")
    })
  })
  app.group("/api", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("second")
    })
  })
  let client = @test_client.TestClient(app)
  assert_eq(client.get("/api/x").body_text(), "second")
}

///|
async test "sibling groups each get their own not_found_handler" {
  let app = @crescent.App()
  app.group("/api", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("API 404")
    })
  })
  app.group("/admin", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("Admin 404")
    })
  })
  let client = @test_client.TestClient(app)
  assert_eq(client.get("/api/x").body_text(), "API 404")
  assert_eq(client.get("/admin/x").body_text(), "Admin 404")
  assert_eq(client.get("/random").body_text(), "Not Found")
}
