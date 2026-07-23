# bobzhang/crescent_wasm_demo

A minimal web server built with [Crescent](https://github.com/moonbit-community/crescent) that targets **wasm** as well as native (`supported_targets = "-all+native+wasm"`).

Routes:

- `GET /` — plain text greeting
- `GET /hello/:name` — path parameter echo
- `GET /json` — JSON response

## Run

```sh
moon run wasm_demo/cmd/main --target wasm
moon run wasm_demo/cmd/main --target native
```

## Test

Handlers can be exercised without network I/O via `@crescent.test_client`:

```moonbit nocheck
///|
async test "hello route" {
  let client = @test_client.TestClient(@crescent_wasm_demo.make_app())
  let res = client.get("/hello/wasm")
  inspect(res.body_text(), content="Hello, wasm!")
}
```
