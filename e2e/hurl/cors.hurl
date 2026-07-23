# A regular cross-origin request receives the configured CORS response headers.

GET {{host}}/cors
Origin: https://client.example
HTTP 200
[Asserts]
body == "cors response"
header "Access-Control-Allow-Origin" == "https://client.example"
header "Access-Control-Allow-Credentials" == "true"
header "Access-Control-Expose-Headers" == "X-Crescent-Test"
header "Vary" contains "Origin"
header "X-Crescent-Test" == "cors"

# A preflight request is answered by the middleware without invoking the route.

OPTIONS {{host}}/cors
Origin: https://client.example
Access-Control-Request-Method: POST
Access-Control-Request-Headers: X-Test
HTTP 200
[Asserts]
bytes count == 0
header "Access-Control-Allow-Origin" == "https://client.example"
header "Access-Control-Allow-Credentials" == "true"
header "Access-Control-Allow-Methods" == "GET, HEAD, POST, OPTIONS"
header "Access-Control-Allow-Headers" == "Content-Type, X-Test"
header "Access-Control-Max-Age" == "600"
header "Vary" contains "Origin"
