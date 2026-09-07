///|
#warnings("-unnecessary_annotation")
struct TryJsonTestUser {
  name : String
  age : Int
} derive(FromJson, ToJson, Eq, Debug)

///|
pub extend TryJsonTestUser with @json.FromJson::{from_json}

///|
pub extend TryJsonTestUser with ToJson::{to_json}

///|
pub extend TryJsonTestUser with Eq::{not_equal, equal}

///|
pub extend TryJsonTestUser with Debug::{to_repr}

///|
test "try_json returns Ok on valid json" {
  let req = HttpRequest(
    Post,
    "/",
    {},
    raw_body=@utf8.encode("{\"name\":\"Alice\",\"age\":30}"),
  )
  let result : Result[TryJsonTestUser, String] = req.try_json()
  assert_eq(result, Ok({ name: "Alice", age: 30, }))
}

///|
test "try_json returns Err on invalid json" {
  let req = HttpRequest(Post, "/", {}, raw_body=b"not valid json")
  let result : Result[TryJsonTestUser, String] = req.try_json()
  assert_true(result is Err(_))
}

///|
test "try_json returns Err on wrong schema" {
  let req = HttpRequest(
    Post,
    "/",
    {},
    raw_body=@utf8.encode("{\"wrong_field\":123}"),
  )
  let result : Result[TryJsonTestUser, String] = req.try_json()
  assert_true(result is Err(_))
}
