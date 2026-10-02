///|
test "radix tree: static routes" {
  let router : @router.RadixRouter[String] = RadixRouter()
  router.insert("GET", CompiledRoute("/api/users"), "list_users")
  router.insert("GET", CompiledRoute("/api/posts"), "list_posts")
  guard router.search("GET", "/api/users") is Some(("list_users", _)) else {
    fail("expected GET /api/users")
  }
  guard router.search("GET", "/api/posts") is Some(("list_posts", _)) else {
    fail("expected GET /api/posts")
  }
  assert_true(router.search("GET", "/api/missing") is None)
  assert_true(router.search("POST", "/api/users") is None)
}

///|
test "radix tree: param routes" {
  let router : @router.RadixRouter[String] = RadixRouter()
  router.insert("GET", CompiledRoute("/users/:id"), "get_user")
  router.insert(
    "GET",
    CompiledRoute("/users/:id/posts/:postId"),
    "get_user_post",
  )
  guard router.search("GET", "/users/42")
    is Some(("get_user", { "id": "42", .. })) else {
    fail("expected GET /users/42")
  }
  guard router.search("GET", "/users/42/posts/99")
    is Some(("get_user_post", { "id": "42", "postId": "99", .. })) else {
    fail("expected GET /users/42/posts/99")
  }
}

///|
test "radix tree: wildcard routes" {
  let router : @router.RadixRouter[String] = RadixRouter()
  router.insert("GET", CompiledRoute("/files/*"), "get_file")
  guard router.search("GET", "/files/readme.txt")
    is Some(("get_file", { "_": "readme.txt", .. })) else {
    fail("expected GET /files/readme.txt")
  }
  assert_true(router.search("GET", "/files/a/b") is None)
}

///|
test "radix tree: globstar routes" {
  let router : @router.RadixRouter[String] = RadixRouter()
  router.insert("GET", CompiledRoute("/static/**"), "serve_static")
  guard router.search("GET", "/static/css/main.css")
    is Some(("serve_static", { "_": "css/main.css", .. })) else {
    fail("expected GET /static/css/main.css")
  }
}

///|
test "radix tree: mixed static and param on same level" {
  let router : @router.RadixRouter[String] = RadixRouter()
  router.insert("GET", CompiledRoute("/users/me"), "current_user")
  router.insert("GET", CompiledRoute("/users/:id"), "get_user")
  // Static should take priority
  guard router.search("GET", "/users/me") is Some(("current_user", _)) else {
    fail("expected static hit for /users/me")
  }
  // Param matches other values
  guard router.search("GET", "/users/42") is Some(("get_user", _)) else {
    fail("expected param hit for /users/42")
  }
}

///|
test "radix tree: merge routers" {
  let router1 : @router.RadixRouter[String] = RadixRouter()
  router1.insert("GET", CompiledRoute("/api/users/:id"), "get_user")
  let router2 : @router.RadixRouter[String] = RadixRouter()
  router2.insert("POST", CompiledRoute("/api/users"), "create_user")
  router1.merge(router2)
  assert_true(router1.search("GET", "/api/users/1") is Some(_))
  assert_true(router1.search("POST", "/api/users") is Some(_))
}
