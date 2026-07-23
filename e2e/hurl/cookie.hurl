# Requests in one Hurl file share a cookie store, so this covers both sides
# of Crescent's Set-Cookie and Cookie handling.

GET {{host}}/cookies/session
HTTP 200
[Asserts]
body == "new session"
cookie "session" == "hurl"
cookie "session[Max-Age]" == 600
cookie "session[Path]" == "/"
cookie "session[HttpOnly]" exists

GET {{host}}/cookies/session
HTTP 200
[Asserts]
body == "session=hurl"

# Multiple cookies must be emitted as separate Set-Cookie fields. Crescent
# also removes cookie delimiters that could be interpreted as attributes.

GET {{host}}/cookies/multiple
HTTP 200
[Asserts]
body == "multiple cookies"
cookie "manual" == "header"
cookie "first" == "one"
cookie "unsafe" == "safeevil"
