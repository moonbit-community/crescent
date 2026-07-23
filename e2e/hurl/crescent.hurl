# Routing, JSON responders, request bodies, and the not-found handler.

GET {{host}}/health
HTTP 200
[Asserts]
body == "ready"

GET {{host}}/hello/Hurl
HTTP 200
[Asserts]
body == "Hello, Hurl!"

GET {{host}}/json
HTTP 200
[Asserts]
header "Content-Type" startsWith "application/json"
jsonpath "$.framework" == "crescent"
jsonpath "$.target" == "e2e"

POST {{host}}/echo
{
  "message": "hello from hurl"
}
HTTP 200
[Asserts]
header "Content-Type" startsWith "application/json"
jsonpath "$.message" == "hello from hurl"

GET {{host}}/missing
HTTP 404
[Asserts]
body == "crescent e2e: not found"
