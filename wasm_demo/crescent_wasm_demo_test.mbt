///|
async test "GET /" {
  let client = @test_client.TestClient(@crescent_wasm_demo.make_app())
  let res = client.get("/")
  inspect(
    res.status,
    content=(
      #|OK
    ),
  )
  inspect(res.body_text(), content="Hello from MoonBit on wasm!")
}

///|
async test "GET /hello/:name" {
  let client = @test_client.TestClient(@crescent_wasm_demo.make_app())
  let res = client.get("/hello/wasm")
  inspect(
    res.status,
    content=(
      #|OK
    ),
  )
  inspect(res.body_text(), content="Hello, wasm!")
}

///|
async test "GET /hello without name falls back to World" {
  let client = @test_client.TestClient(@crescent_wasm_demo.make_app())
  let res = client.get("/hello/")
  inspect(
    res.body_text(),
    content=(
      #|Hello, !
    ),
  )
}

///|
async test "GET /json" {
  let client = @test_client.TestClient(@crescent_wasm_demo.make_app())
  let res = client.get("/json")
  inspect(
    res.status,
    content=(
      #|OK
    ),
  )
  inspect(
    res.body_text(),
    content=(
      #|{"framework":"crescent","target":"wasm"}
    ),
  )
}
