///|
async test "rate_limit allows requests within limit" {
  let app = @crescent.App()
  app.use_middleware(
    @middleware.rate_limit(requests_per_window=3, window_ms=10000),
  )
  app.get("/test", _ => "ok")
  let client = @test_client.TestClient(app)
  let res1 = client.get("/test")
  let res2 = client.get("/test")
  let res3 = client.get("/test")
  assert_eq(res1.status, OK)
  assert_eq(res2.status, OK)
  assert_eq(res3.status, OK)
}

///|
async test "rate_limit returns 429 when limit exceeded" {
  let app = @crescent.App()
  app.use_middleware(
    @middleware.rate_limit(requests_per_window=2, window_ms=10000),
  )
  app.get("/test", _ => "ok")
  let client = @test_client.TestClient(app)
  let _res1 = client.get("/test")
  let _res2 = client.get("/test")
  let res3 = client.get("/test")
  assert_eq(res3.status, TooManyRequests)
  assert_true(res3.headers.get("Retry-After") is Some(_))
}

///|
async test "rate_limit resets after window expires" {
  let app = @crescent.App()
  app.use_middleware(
    @middleware.rate_limit(requests_per_window=1, window_ms=50),
  )
  app.get("/test", _ => "ok")
  let client = @test_client.TestClient(app)
  let res1 = client.get("/test")
  assert_eq(res1.status, OK)
  let res2 = client.get("/test")
  assert_eq(res2.status, TooManyRequests)
  // Wait for window to expire
  @async.sleep(60)
  let res3 = client.get("/test")
  assert_eq(res3.status, OK)
}
