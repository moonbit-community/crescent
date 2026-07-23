///|
async fn main {
  println("crescent_wasm_demo listening on http://localhost:8080")
  @demo.run(port=8080) catch {
    e => println("server error: \{e}")
  }
}
