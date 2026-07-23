# The public routes proxy to private routes through crescent/fetch. This tests
# the package with an external client instead of Crescent's own HTTP client.

GET {{host}}/fetch/text
HTTP 200
[Asserts]
body == "upstream response"
header "X-Fetch-Method" == "GET"

POST {{host}}/fetch/echo
```
payload from hurl
```
HTTP 200
[Asserts]
body contains "crescent:payload from hurl"
header "X-Fetch-Method" == "POST"

HEAD {{host}}/fetch/head
HTTP 204
[Asserts]
bytes count == 0
header "X-Upstream" == "head"
