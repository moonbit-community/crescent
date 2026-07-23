///|
test "redirect sets location header" {
  let res = HttpResponse::redirect("/new-path")
  debug_inspect(res.status_code, content="MovedPermanently")
  debug_inspect(res.headers.get("Location"), content="Some(\"/new-path\")")
}

///|
test "redirect_temporary sets location header" {
  let res = HttpResponse::redirect_temporary("/temp-path")
  debug_inspect(res.status_code, content="Found")
  debug_inspect(res.headers.get("Location"), content="Some(\"/temp-path\")")
}

///|
test "redirect_307 sets location header" {
  let res = HttpResponse::redirect_307("/preserve-method")
  debug_inspect(res.status_code, content="TemporaryRedirect")
  debug_inspect(
    res.headers.get("Location"),
    content="Some(\"/preserve-method\")",
  )
}

///|
test "redirect_308 sets location header" {
  let res = HttpResponse::redirect_308("/permanent-preserve")
  debug_inspect(res.status_code, content="PermanentRedirect")
  debug_inspect(
    res.headers.get("Location"),
    content="Some(\"/permanent-preserve\")",
  )
}
