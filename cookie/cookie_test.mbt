///|
test "CookieItem::to_string" {
  let item : CookieItem = {
    name: "session_id",
    value: "12345",
    max_age: Some(3600),
    path: Some("/"),
    domain: Some("example.com"),
    secure: Some(true),
    http_only: Some(true),
    same_site: Some(SameSiteNone),
  }
  let s = Show::to_string(item)
  debug_inspect(
    s,
    content=(
      #|"session_id=12345; Max-Age=3600; Path=/; Domain=example.com; Secure; HttpOnly; SameSite=SameSiteNone"
    ),
  )
}

///|
test "parse_cookie" {
  let cookie_str = "name=value; name2=value2; name3=value3"
  let cookies = parse_cookie(cookie_str)
  assert_eq(cookies.get("name").map(i => i.value), Some("value"))
  assert_eq(cookies.get("name2").map(i => i.value), Some("value2"))
  assert_eq(cookies.get("name3").map(i => i.value), Some("value3"))
}

///|
test "parse_cookie_with_attributes" {
  let cookie_str = "session_id=12345; Path=/; Domain=example.com; Max-Age=3600; Secure; HttpOnly; SameSite=Lax"
  let cookies = parse_cookie(cookie_str)
  guard cookies.get("session_id") is Some(item) else {
    fail("Expected session_id cookie")
  }
  assert_eq(item.value, "12345")
  assert_eq(item.path, Some("/"))
  assert_eq(item.domain, Some("example.com"))
  assert_eq(item.max_age, Some(3600))
  assert_eq(item.secure, Some(true))
  assert_eq(item.http_only, Some(true))
  assert_eq(item.same_site, Some(Lax))
}

///|
test "parse_cookie_multiple_with_attributes" {
  let cookie_str = "c1=v1; Path=/app; c2=v2; Secure; SameSite=Strict"
  let cookies = parse_cookie(cookie_str)
  guard cookies.get("c1") is Some(c1) else { fail("Expected c1") }
  assert_eq(c1.value, "v1")
  assert_eq(c1.path, Some("/app"))
  assert_eq(c1.secure, None)
  guard cookies.get("c2") is Some(c2) else { fail("Expected c2") }
  assert_eq(c2.value, "v2")
  assert_eq(c2.secure, Some(true))
  assert_eq(c2.same_site, Some(Strict))
  assert_eq(c2.path, None)
}

///|
test "parse_cookie_with_spaces" {
  let cookie_str = " name = value ; name2= value2 "
  let cookies = parse_cookie(cookie_str)
  assert_eq(cookies.get("name").map(i => i.value), Some("value"))
  assert_eq(cookies.get("name2").map(i => i.value), Some("value2"))
}

///|
test "parse_cookie_quoted" {
  let cookie_str = "name=\"value with spaces\"; name2=\"value2\""
  let cookies = parse_cookie(cookie_str)
  assert_eq(cookies.get("name").map(i => i.value), Some("value with spaces"))
  assert_eq(cookies.get("name2").map(i => i.value), Some("value2"))
}

///|
test "parse_cookie_empty_value" {
  let cookie_str = "name=; name2="
  let cookies = parse_cookie(cookie_str)
  assert_eq(cookies.get("name").map(i => i.value), Some(""))
  assert_eq(cookies.get("name2").map(i => i.value), Some(""))
}

///|
test "parse_cookie_no_value" {
  let cookie_str = "name; name2"
  let cookies = parse_cookie(cookie_str)
  assert_eq(cookies.get("name").map(i => i.value), Some(""))
  assert_eq(cookies.get("name2").map(i => i.value), Some(""))
}

///|
test "parse_complex_cookie_string" {
  let cookie_str = "__stripe_mid=4e192e8c-7c22-4923-aaf1-6b174a77a43555136e; JSESSIONID=5C63BF22946D333F1079A0150ECABBCB; session_id=12345"
  let cookies = parse_cookie(cookie_str)
  assert_eq(
    cookies.get("__stripe_mid").map(i => i.value),
    Some("4e192e8c-7c22-4923-aaf1-6b174a77a43555136e"),
  )
  assert_eq(cookies.get("session_id").map(i => i.value), Some("12345"))
  assert_eq(
    cookies.get("JSESSIONID").map(i => i.value),
    Some("5C63BF22946D333F1079A0150ECABBCB"),
  )
}

///|
test "cookie_to_string joins cookies and invalid max-age falls back to none" {
  let cookies = [
    CookieItem::{
      name: "session",
      value: "abc123",
      max_age: None,
      path: Some("/"),
      domain: None,
      secure: Some(true),
      http_only: Some(true),
      same_site: Some(Lax),
    },
    {
      name: "theme",
      value: "dark",
      max_age: None,
      path: None,
      domain: None,
      secure: None,
      http_only: None,
      same_site: None,
    },
  ]
  debug_inspect(
    cookie_to_string(cookies),
    content=(
      #|"session=abc123; Path=/; Secure; HttpOnly; SameSite=Lax;theme=dark"
    ),
  )

  let parsed = parse_cookie("session=abc123; Max-Age=oops")
  guard parsed.get("session") is Some(cookie) else {
    fail("Expected parsed session cookie")
  }
  assert_eq(cookie.value, "abc123")
  assert_eq(cookie.max_age, None)
}
