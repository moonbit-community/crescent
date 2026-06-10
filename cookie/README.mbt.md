# Cookie

HTTP cookie parsing and serialization for MoonBit.

Cookies are small pieces of data that web servers send to browsers via
`Set-Cookie` headers. The browser stores them and attaches them back on
subsequent requests in the `Cookie` header. They are the standard mechanism for
session management, user preferences, and tracking across HTTP requests.

## How Cookies Work

Cookies rely on a two-step exchange between server and browser:

**1. Server sets a cookie** — The server includes one or more `Set-Cookie`
headers in an HTTP response. Each header carries a name-value pair plus optional
attributes that control the cookie's lifetime, scope, and security:

```
HTTP/1.1 200 OK
Set-Cookie: session_id=abc123; Path=/; Max-Age=3600; Secure; HttpOnly; SameSite=Lax
```

**2. Browser sends it back** — On every subsequent request to the same origin
(subject to `Path`, `Domain`, and `SameSite` rules), the browser automatically
attaches all matching cookies in a single `Cookie` header:

```
GET /api/profile HTTP/1.1
Cookie: session_id=abc123; theme=dark
```

The server never sees the attributes (`Path`, `Secure`, etc.) again — the
browser uses them locally to decide *whether* to send the cookie, but only the
`name=value` pairs travel back.

### Cookie Attributes

| Attribute  | Purpose |
| ---------- | ------- |
| `Max-Age`  | Seconds until the cookie expires. `0` deletes it immediately. |
| `Path`     | URL path prefix the cookie applies to (default: current path). |
| `Domain`   | Which hosts receive the cookie (default: exact origin only). |
| `Secure`   | Only send over HTTPS. |
| `HttpOnly` | Hide from JavaScript (`document.cookie`), mitigating XSS. |
| `SameSite` | Controls cross-site sending — see [SameSite Options](#samesite-options). |

### Lifecycle

1. **Session cookies** — no `Max-Age` or `Expires`: deleted when the browser
   closes.
2. **Persistent cookies** — have a `Max-Age` (or `Expires`): survive across
   browser restarts until they expire.
3. **Deletion** — the server sends `Set-Cookie: name=; Max-Age=0` to ask the
   browser to remove a cookie.

This package provides:

- `CookieItem` — a typed representation of an HTTP cookie with attributes like
  `Path`, `Domain`, `Max-Age`, `Secure`, `HttpOnly`, and `SameSite`.
- `parse_cookie` — parses a raw cookie header string into a map of cookie items.
- `cookie_to_string` — serializes an array of cookies back into a header string.

## Install

This package is included with `bobzhang/crescent`. Import it directly:

```
import {
 "bobzhang/crescent/cookie"
 ...
}
```

## Creating Cookies

Use the `CookieItem` constructor to build a cookie with optional attributes:

```mbt check
///|
test "create a cookie with attributes" {
  let cookie = @cookie.CookieItem(
    name="session_id",
    value="abc123",
    max_age=3600,
    path="/",
    domain="example.com",
    secure=true,
    http_only=true,
    same_site=Lax,
  )
  inspect(
    cookie.to_string(),
    content="session_id=abc123; Max-Age=3600; Path=/; Domain=example.com; Secure; HttpOnly; SameSite=Lax",
  )
}
```

A minimal cookie only needs `name` and `value`:

```mbt check
///|
test "minimal cookie" {
  let cookie = @cookie.CookieItem(name="theme", value="dark")
  inspect(cookie.to_string(), content="theme=dark")
}
```

## Parsing Cookies

`parse_cookie` parses a raw `Cookie` header string into a `Map[String, CookieItem]`:

```mbt check
///|
test "parse a cookie header" {
  let cookies = @cookie.parse_cookie("name=value; session=abc123")
  inspect(cookies.get("name").map(fn(c) { c.value }) |> @debug.to_repr(), content="Some(\"value\")")
  inspect(
    cookies.get("session").map(fn(c) { c.value }) |> @debug.to_repr(),
    content="Some(\"abc123\")",
  )
}
```

It also recognizes `Set-Cookie` attributes like `Path`, `Domain`, `Max-Age`,
`Secure`, `HttpOnly`, and `SameSite`:

```mbt check
///|
test "parse cookie with attributes" {
  let cookies = @cookie.parse_cookie(
    "token=xyz; Path=/api; Secure; HttpOnly; SameSite=Strict",
  )
  guard cookies.get("token") is Some(c) else { fail("expected token cookie") }
  assert_eq(c.path, Some("/api"))
  assert_eq(c.secure, Some(true))
  assert_eq(c.http_only, Some(true))
  assert_eq(c.same_site, Some(Strict))
}
```

## Serializing Multiple Cookies

`cookie_to_string` joins an array of cookies into a semicolon-separated string:

```mbt check
///|
test "serialize multiple cookies" {
  let cookies = [
    @cookie.CookieItem(name="a", value="1"),
    CookieItem(name="b", value="2"),
  ]
  inspect(@cookie.cookie_to_string(cookies), content="a=1;b=2")
}
```

## SameSite Options

The `SameSiteOption` enum controls cross-site request behavior:

| Variant        | Meaning                                      |
| -------------- | -------------------------------------------- |
| `Lax`          | Sent on top-level navigations and GET requests |
| `Strict`       | Sent only on same-site requests              |
| `SameSiteNone` | Sent on all requests (requires `Secure`)     |
