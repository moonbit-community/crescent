///|
test "param returns string value" {
  let event = @crescent.Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: { "id": "42" },
  }
  inspect(event.param("id"), content="Some(\"42\")")
  inspect(event.param("missing"), content="None")
}

///|
test "param_int parses integer" {
  let event = @crescent.Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: { "id": "123" },
  }
  inspect(event.param_int("id"), content="Some(123)")
  inspect(event.param_int("missing"), content="None")
}

///|
test "param_int returns none for non-integer" {
  let event = @crescent.Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: { "id": "abc" },
  }
  inspect(event.param_int("id"), content="None")
}

///|
test "require_param returns value when present" {
  let event = @crescent.Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: { "name": "alice" },
  }
  let name = event.require_param("name")
  assert_eq(name, "alice")
}

///|
test "require_param raises HttpError when missing" {
  let event = @crescent.Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  try event.require_param("id") catch {
    err => assert_true(err is @crescent.HttpError(_, _))
  } noraise {
    v => fail("Found param where none was expected \{v}")
  }
}

///|
test "require_param_int returns parsed integer" {
  let event = @crescent.Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: { "id": "42" },
  }
  let id = event.require_param_int("id")
  assert_eq(id, 42)
}

///|
test "require_param_int raises on missing param" {
  let event = @crescent.Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  try event.require_param_int("id") catch {
    err => assert_true(err is @crescent.HttpError(_, _))
  } noraise {
    v => fail("Found param where none was expected \{v}")
  }
}

///|
test "require_param_int raises on non-integer value" {
  let event = @crescent.Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: { "id": "abc" },
  }
  try event.require_param_int("id") catch {
    err => assert_true(err is @crescent.HttpError(_, _))
  } noraise {
    v => fail("Found non int param in id \{v}")
  }
}

///|
test "require_param_int64 returns parsed int64" {
  let event = @crescent.Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: { "id": "9999999999" },
  }
  let id = event.require_param_int64("id")
  assert_eq(id, 9999999999L)
}

///|
test "require_param_int64 raises on non-integer" {
  let event = @crescent.Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: { "id": "not-a-number" },
  }
  try event.require_param_int64("id") catch {
    err => assert_true(err is @crescent.HttpError(_, _))
  } noraise {
    v => fail("Found param where none was expected \{v}")
  }
}

///|
test "param_decoded URL-decodes the value" {
  let event = @crescent.Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: { "query": "hello%20world" },
  }
  assert_eq(event.param("query"), Some("hello%20world"))
  assert_eq(event.param_decoded("query"), Some("hello world"))
}

///|
test "param_decoded returns None when missing" {
  let event = @crescent.Event::{
    req: HttpRequest(Get, "/", {}, raw_body=b""),
    res: HttpResponse(status_code=OK),
    params: {},
  }
  assert_eq(event.param_decoded("missing"), None)
}
