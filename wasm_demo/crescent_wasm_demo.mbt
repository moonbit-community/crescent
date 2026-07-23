///|
/// Builds the demo application: a few routes and nothing else.
pub fn make_app() -> @crescent.App {
  let app = @crescent.App()
  app
  ..get("/", _ => "Hello from MoonBit on wasm!")
  ..get("/hello/:name", event => {
    let name = event.param("name").unwrap_or("World")
    "Hello, \{name}!"
  })
  .get("/json", _ => ({ "framework": "crescent", "target": "wasm" } : Json))
  app
}

///|
/// Serves the demo application on the given port.
pub async fn run(port~ : Int) -> Unit {
  make_app().serve(port~)
}
