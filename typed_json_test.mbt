///|
#warnings("-unnecessary_annotation")
struct TestUser {
  name : String
  age : Int
} derive(FromJson, ToJson, Eq, Debug)

///|
test "HttpRequest::json parses struct from body" {
  let req = @crescent.HttpRequest(
    Post,
    "/users",
    {},
    raw_body=b"{\"name\":\"Alice\",\"age\":30}",
  )
  let user : TestUser = req.json()
  assert_eq(user, { name: "Alice", age: 30 })
}

///|
test "HttpRequest::json fails on invalid json" {
  let req = @crescent.HttpRequest(Post, "/users", {}, raw_body=b"not json")
  @test.assert_raise(() => {
    let _ : TestUser = req.json()
  })
}

///|
test "HttpRequest::json fails on missing fields" {
  let req = @crescent.HttpRequest(
    Post,
    "/users",
    {},
    raw_body=b"{\"name\":\"Alice\"}",
  )
  @test.assert_raise(() => {
    let _ : TestUser = req.json()
  })
}

///|
test "HttpRequest::json fails on wrong field type" {
  let req = @crescent.HttpRequest(
    Post,
    "/users",
    {},
    raw_body=b"{\"name\":\"Alice\",\"age\":\"thirty\"}",
  )
  @test.assert_raise(() => {
    let _ : TestUser = req.json()
  })
}

///|
test "HttpRequest::json parses nested struct" {
  let req = @crescent.HttpRequest(
    Post,
    "/",
    {},
    raw_body=b"{\"name\":\"Bob\",\"age\":25}",
  )
  let user : TestUser = req.json()
  assert_eq(user.name, "Bob")
  assert_eq(user.age, 25)
}

///|
test "HttpRequest::json parses empty body as error" {
  let req = @crescent.HttpRequest(Post, "/", {}, raw_body=b"")
  @test.assert_raise(() => {
    let _ : TestUser = req.json()
  })
}

///|
test "HttpResponse::json_value sets content type and body" {
  let user : TestUser = { name: "Alice", age: 30 }
  let res = @crescent.HttpResponse::ok().json_value(user)
  debug_inspect(res.status_code, content="OK")
  debug_inspect(
    res.headers.get("Content-Type"),
    content="Some(\"application/json; charset=utf-8\")",
  )
  debug_inspect(
    @utf8.decode(res.raw_body),
    content=(
      #|"{\"name\":\"Alice\",\"age\":30}"
    ),
  )
}

///|
test "HttpResponse::json_value with array" {
  let users : Array[TestUser] = [
    { name: "Alice", age: 30 },
    { name: "Bob", age: 25 },
  ]
  let res = @crescent.HttpResponse::ok().json_value(users)
  debug_inspect(
    @utf8.decode(res.raw_body),
    content=(
      #|"[{\"name\":\"Alice\",\"age\":30},{\"name\":\"Bob\",\"age\":25}]"
    ),
  )
}
